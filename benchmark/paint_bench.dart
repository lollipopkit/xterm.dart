// Paint-path benchmark. See https://github.com/lollipopkit/xterm.dart/issues/17
//
// Run with:
//
//   flutter test benchmark/paint_bench.dart
//
// This does not live in `bin/xterm_bench.dart` because that file runs under
// `dart run`, and the paint path needs `dart:ui`, which only exists inside a
// Flutter engine.
//
// What is measured: the time to *record* a screenful of paint operations, and
// how many draws that recording issues. `glyphs` counts cells, whether each
// reached the canvas inside a coalesced paragraph or as a sprite in the line's
// atlas batch; `calls` counts the draws themselves. The ratio between them is
// how much of the screen each draw carried, which is what coalescing and the
// atlas are each for.
// GPU rasterisation is deliberately not measured: forcing it from a test
// needs an async `toByteData` round trip whose cost is dominated by the
// readback rather than by the drawing. Draw-call count is the quantity the
// rendering issues are about, and it is exact rather than sampled.
//
// The numbers are comparable between runs on one machine and one Flutter
// version. They are not comparable to a real app: `flutter test` lays text out
// in the FlutterTest font, where every glyph is an identical box. Read the
// ratio between a change and its baseline, not the absolute milliseconds.

import 'dart:math';
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xterm/src/terminal.dart';
import 'package:xterm/src/ui/painter.dart';
import 'package:xterm/src/ui/terminal_text_style.dart';
import 'package:xterm/src/ui/themes.dart';

/// Number of frames recorded per measurement, after [_warmupFrames].
const _measuredFrames = 30;

/// Frames recorded and discarded before measuring, so the JIT has settled and
/// the paragraph cache holds whatever it is going to hold.
const _warmupFrames = 10;

/// Grid sizes to report. 80x24 is a phone or a small pane, 120x40 a typical
/// desktop window, 240x70 a maximised one on a large display.
const _grids = [(80, 24), (120, 40), (240, 70)];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('paint benchmark', () {
    for (final (cols, rows) in _grids) {
      // ignore: avoid_print
      print('\n=== ${cols}x$rows ===');
      // ignore: avoid_print
      print(
        '${'profile'.padRight(14)}'
        '${'glyphs'.padLeft(8)}'
        '${'calls'.padLeft(8)}'
        '${'rects'.padLeft(8)}'
        '${'ms/frame'.padLeft(10)}',
      );

      for (final profile in _profiles) {
        final result = _run(profile, cols, rows);
        // ignore: avoid_print
        print(
          '${profile.name.padRight(14)}'
          '${result.glyphs.toString().padLeft(8)}'
          '${result.calls.toString().padLeft(8)}'
          '${result.rects.toString().padLeft(8)}'
          '${result.msPerFrame.toStringAsFixed(3).padLeft(10)}',
        );
      }
    }
  });
}

class _Result {
  const _Result({
    required this.glyphs,
    required this.calls,
    required this.rects,
    required this.msPerFrame,
  });

  /// Cells that reached the canvas, however they got there.
  final int glyphs;

  /// Draw calls that carried them.
  final int calls;

  final int rects;
  final double msPerFrame;
}

_Result _run(_Profile profile, int cols, int rows) {
  final terminal = Terminal(maxLines: rows);
  terminal.resize(cols, rows);
  profile.write(terminal, cols, rows);

  final painter = TerminalPainter(
    theme: TerminalThemes.defaultTheme,
    textStyle: const TerminalStyle(),
    textScaler: TextScaler.noScaling,
  );

  // Count on a throwaway pass, so the counting wrapper's own overhead stays
  // out of the timed pass below.
  final countingRecorder = PictureRecorder();
  final counting = _CountingCanvas(Canvas(countingRecorder), painter.cellSize.width);
  _paintFrame(painter, terminal, counting, rows);
  countingRecorder.endRecording().dispose();

  for (var i = 0; i < _warmupFrames; i++) {
    _recordFrame(painter, terminal, rows);
  }

  final sw = Stopwatch()..start();
  for (var i = 0; i < _measuredFrames; i++) {
    _recordFrame(painter, terminal, rows);
  }
  sw.stop();

  return _Result(
    glyphs: counting.glyphs,
    calls: counting.calls,
    rects: counting.rects,
    msPerFrame: sw.elapsedMicroseconds / _measuredFrames / 1000,
  );
}

void _recordFrame(TerminalPainter painter, Terminal terminal, int rows) {
  final recorder = PictureRecorder();
  _paintFrame(painter, terminal, Canvas(recorder), rows);
  recorder.endRecording().dispose();
}

/// Paints the visible region the way [RenderTerminal] does: every line from the
/// top of the viewport to the bottom, one [TerminalPainter.paintLine] each.
void _paintFrame(
  TerminalPainter painter,
  Terminal terminal,
  Canvas canvas,
  int rows,
) {
  final lines = terminal.buffer.lines;
  final cellHeight = painter.cellSize.height;
  final first = max(0, lines.length - rows);

  for (var i = first; i < lines.length; i++) {
    painter.paintLine(canvas, Offset(0, (i - first) * cellHeight), lines[i]);
  }
}

/// Counts the draw calls the painter issues, forwarding each to a real canvas
/// so the recorded picture stays representative.
///
/// [paintLine] only reaches `drawRect`, `drawParagraph` and `drawRawAtlas`;
/// everything else on [Canvas] goes to [noSuchMethod] and would throw, which is
/// the intent. A painter that starts using another primitive should fail here
/// rather than silently go uncounted.
class _CountingCanvas implements Canvas {
  _CountingCanvas(this._inner, this._cellWidth);

  final Canvas _inner;

  /// Needed because a coalesced paragraph carries a whole run, and the number
  /// of cells in it is not otherwise recoverable from a [Paragraph]. Under
  /// `flutter test` every glyph is exactly one cell wide, so its laid out width
  /// divided by this is how many cells it drew.
  final double _cellWidth;

  var glyphs = 0;
  var calls = 0;
  var rects = 0;

  @override
  void drawParagraph(Paragraph paragraph, Offset offset) {
    glyphs += max(1, (paragraph.maxIntrinsicWidth / _cellWidth).round());
    calls++;
    _inner.drawParagraph(paragraph, offset);
  }

  @override
  void drawRawAtlas(
    Image atlas,
    Float32List rstTransforms,
    Float32List rects,
    Int32List? colors,
    BlendMode? blendMode,
    Rect? cullRect,
    Paint paint,
  ) {
    glyphs += rects.length ~/ 4;
    calls++;
    _inner.drawRawAtlas(
      atlas,
      rstTransforms,
      rects,
      colors,
      blendMode,
      cullRect,
      paint,
    );
  }

  @override
  void drawRect(Rect rect, Paint paint) {
    rects++;
    _inner.drawRect(rect, paint);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) {
    throw UnsupportedError(
      'paint benchmark: uncounted canvas call '
      '${invocation.memberName}; add it to _CountingCanvas',
    );
  }
}

class _Profile {
  const _Profile(this.name, this.write);

  final String name;
  final void Function(Terminal terminal, int cols, int rows) write;
}

const _profiles = [
  _Profile('ascii', _writeAscii),
  _Profile('colored', _writeColored),
  _Profile('tui', _writeTui),
  _Profile('cjk', _writeCjk),
  _Profile('unique', _writeUnique),
];

/// Plain text in the default colours. The best case for run coalescing: one
/// run per line.
void _writeAscii(Terminal terminal, int cols, int rows) {
  final rng = Random(1);
  for (var y = 0; y < rows; y++) {
    final buf = StringBuffer();
    while (buf.length < cols) {
      buf.write(_words[rng.nextInt(_words.length)]);
      buf.write(' ');
    }
    terminal.write(buf.toString().substring(0, cols));
    if (y < rows - 1) terminal.write('\r\n');
  }
}

/// SGR-heavy output: a 256-colour foreground per word and a background on some
/// of them. Models `ls --color` and a build log. The worst case for
/// per-cell background rects.
void _writeColored(Terminal terminal, int cols, int rows) {
  final rng = Random(2);
  for (var y = 0; y < rows; y++) {
    var written = 0;
    while (written < cols) {
      final word = _words[rng.nextInt(_words.length)];
      final take = min(word.length, cols - written);
      terminal.write('\x1b[38;5;${rng.nextInt(256)}m');
      if (rng.nextInt(4) == 0) {
        terminal.write('\x1b[48;5;${rng.nextInt(256)}m');
      }
      terminal.write(word.substring(0, take));
      terminal.write('\x1b[0m');
      written += take;
      if (written < cols) {
        terminal.write(' ');
        written++;
      }
    }
    if (y < rows - 1) terminal.write('\r\n');
  }
}

/// A full-screen TUI: box drawing, a coloured header, and meter bars. Models
/// htop. Mixed runs, and every cell is painted.
void _writeTui(Terminal terminal, int cols, int rows) {
  final rng = Random(3);
  terminal.write('\x1b[48;5;24m\x1b[38;5;255m');
  terminal.write(' xterm.dart paint benchmark'.padRight(cols));
  terminal.write('\x1b[0m\r\n');

  for (var y = 1; y < rows; y++) {
    if (y % 8 == 0) {
      terminal.write('\x1b[38;5;240m${'─' * cols}\x1b[0m');
    } else {
      final label = ' ${_words[rng.nextInt(_words.length)].padRight(10)}';
      terminal.write('\x1b[38;5;250m$label\x1b[0m');
      final barWidth = max(0, cols - label.length - 8);
      final filled = rng.nextInt(barWidth + 1);
      terminal.write('\x1b[38;5;46m${'│' * filled}');
      terminal.write('\x1b[38;5;238m${'│' * (barWidth - filled)}\x1b[0m');
      terminal.write('\x1b[38;5;250m${(filled * 100 ~/ max(1, barWidth))}%');
      terminal.write('\x1b[0m');
    }
    if (y < rows - 1) terminal.write('\r\n');
  }
}

/// CJK text, every cell double width. Exercises the wide-character path, which
/// run coalescing must leave alone.
void _writeCjk(Terminal terminal, int cols, int rows) {
  final rng = Random(4);
  for (var y = 0; y < rows; y++) {
    final buf = StringBuffer();
    for (var x = 0; x < cols ~/ 2; x++) {
      buf.writeCharCode(0x4E00 + rng.nextInt(0x1000));
    }
    terminal.write(buf.toString());
    if (y < rows - 1) terminal.write('\r\n');
  }
}

/// Every cell a distinct foreground colour, so no two adjacent cells can be
/// coalesced and the paragraph cache cannot hold a screen. The pathological
/// case: a change that helps here helps everywhere.
void _writeUnique(Terminal terminal, int cols, int rows) {
  final rng = Random(5);
  for (var y = 0; y < rows; y++) {
    for (var x = 0; x < cols; x++) {
      terminal.write('\x1b[38;2;${rng.nextInt(256)};');
      terminal.write('${rng.nextInt(256)};${rng.nextInt(256)}m');
      terminal.write(String.fromCharCode(0x21 + rng.nextInt(0x5E)));
    }
    terminal.write('\x1b[0m');
    if (y < rows - 1) terminal.write('\r\n');
  }
}

const _words = [
  'terminal',
  'buffer',
  'paint',
  'cell',
  'line',
  'render',
  'escape',
  'cursor',
  'scroll',
  'select',
  'attribute',
  'glyph',
  'column',
  'width',
  'flush',
];
