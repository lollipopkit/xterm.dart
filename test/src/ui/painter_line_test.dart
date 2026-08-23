import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xterm/src/terminal.dart';
import 'package:xterm/src/ui/glyph_atlas.dart';
import 'package:xterm/src/ui/painter.dart';
import 'package:xterm/src/ui/terminal_text_style.dart';
import 'package:xterm/src/ui/themes.dart';

// These assert on the draw calls TerminalPainter.paintLine issues, since that
// is what run coalescing changes: which cells share a draw and which share a
// background rect.
//
// A cell reaches the canvas one of two ways. Cells that coalesce are drawn as
// one paragraph; a cell that could not join a run is a sprite in the line's
// single `drawRawAtlas` batch. [_Painted.glyphs] covers both, so a test says
// which cells shared a draw without naming the primitive.
//
// The order there is by column, not by draw order: the atlas batch is issued
// once at the end of the line, so its sprites reach the canvas after the
// paragraphs that sit between them.
//
// How wide a draw is: a paragraph's text is not readable back, so a run is
// identified by how wide it laid out. Under `flutter test` every glyph is an
// identical box of exactly one cell, so a run of n cells measures n * cellWidth.

void main() {
  group('foreground runs', () {
    test('cells sharing a style are drawn as one paragraph', () {
      final painted = _paintLine('hello');

      expect(painted.glyphs, hasLength(1));
      expect(painted.glyphs.single.x, closeTo(0, 0.5));
      expect(painted.cellsIn(0), 5);
    });

    test('a colour change starts a new run', () {
      final painted = _paintLine('\x1b[31mabc\x1b[32mdef');

      expect(painted.glyphs, hasLength(2));
      expect(painted.cellsIn(0), 3);
      expect(painted.glyphs[1].x, closeTo(painted.columns(3), 0.5));
      expect(painted.cellsIn(1), 3);
    });

    test('bold starts a new run', () {
      final painted = _paintLine('ab\x1b[1mcd');

      expect(painted.glyphs, hasLength(2));
      expect(painted.cellsIn(0), 2);
      expect(painted.cellsIn(1), 2);
    });

    test('an untouched cell ends the run', () {
      // Write ab, jump to column 6, write cd. Columns 2..4 were never written.
      final painted = _paintLine('ab\x1b[6Gcd');

      expect(painted.glyphs, hasLength(2));
      expect(painted.glyphs[1].x, closeTo(painted.columns(5), 0.5));
    });

    test('an invisible cell ends the run and paints nothing', () {
      final painted = _paintLine('ab\x1b[8mcd\x1b[28mef');

      expect(painted.glyphs, hasLength(2));
      expect(painted.cellsIn(0), 2);
      expect(painted.glyphs[1].x, closeTo(painted.columns(4), 0.5));
      expect(painted.cellsIn(1), 2);
    });

    test('a wide character is drawn on its own', () {
      final painted = _paintLine('a中b');

      // The wide character cannot join a run, and it separates the two ASCII
      // cells, so each is drawn alone. Its trailing half paints nothing.
      expect(painted.glyphs, hasLength(3));
      expect(painted.glyphs[0].x, closeTo(painted.columns(0), 0.5));
      expect(painted.glyphs[1].x, closeTo(painted.columns(1), 0.5));
      expect(painted.glyphs[2].x, closeTo(painted.columns(3), 0.5));
      // The wide character claims both of its columns.
      expect(painted.cellsIn(1), 2);
    });

    test('box drawing characters form a run', () {
      final painted = _paintLine('────');

      expect(painted.glyphs, hasLength(1));
      expect(painted.cellsIn(0), 4);
    });

    test('box drawing does not join an ASCII run', () {
      // A font boundary must not land inside a paragraph: box drawing usually
      // comes from a different fallback font than ASCII does.
      final painted = _paintLine('ab──');

      expect(painted.glyphs, hasLength(2));
      expect(painted.cellsIn(0), 2);
      expect(painted.cellsIn(1), 2);
    });

    test('a space does not break an underlined run', () {
      // An underlined space is swapped for a non-breaking space, which has to
      // happen inside the run rather than by ending it.
      final painted = _paintLine('\x1b[4ma b');

      expect(painted.glyphs, hasLength(1));
      expect(painted.cellsIn(0), 3);
    });

    test('a cell holding combining marks is drawn on its own', () {
      // The cluster's glyph is composed from more than one code point and need
      // not advance by one cell, so it cannot sit inside a run. It also has to
      // break the run either side of it rather than be skipped.
      final painted = _paintLine('ab́c');

      expect(painted.glyphs, hasLength(3));
      expect(painted.glyphs[0].x, closeTo(painted.columns(0), 0.5));
      expect(painted.glyphs[1].x, closeTo(painted.columns(1), 0.5));
      expect(painted.glyphs[2].x, closeTo(painted.columns(2), 0.5));
    });

    test('a cluster paints its marks rather than the base alone', () {
      final painted = _paintLine('á');

      // Width says nothing here: the mark advances by zero, so a cluster and
      // its bare base lay out the same. What the paragraph was built from is
      // the claim, and its length is the way to read that back.
      expect(painted.glyphs, hasLength(1));
      expect(painted.codeUnitsIn(0), 2);
    });

    test('a zero width joiner sequence is laid out as one paragraph', () {
      final painted = _paintLine('\u{1F468}‍\u{1F469}‍\u{1F467}');

      expect(painted.glyphs, hasLength(1));
      expect(painted.glyphs.single.x, closeTo(painted.columns(0), 0.5));
      // Three surrogate pairs and two joiners.
      expect(painted.codeUnitsIn(0), 8);
    });
  });

  group('background spans', () {
    test('cells sharing a background fill one rect', () {
      final painted = _paintLine('\x1b[41mabcd');

      expect(painted.rects, hasLength(1));
      expect(painted.rects.single.left, 0);
      expect(painted.rects.single.width, closeTo(painted.columns(4) + 1, 0.01));
    });

    test('a background change splits the rect', () {
      final painted = _paintLine('\x1b[41mab\x1b[42mcd');

      expect(painted.rects, hasLength(2));
      expect(painted.rects[1].left, closeTo(painted.columns(2), 0.01));
    });

    test('cells with no background of their own fill nothing', () {
      expect(_paintLine('abcd').rects, isEmpty);
    });

    test('a wide character fills both of its columns', () {
      final painted = _paintLine('\x1b[41m中');

      expect(painted.rects, hasLength(1));
      expect(painted.rects.single.width, closeTo(painted.columns(2) + 1, 0.01));
    });

    test('an inverse cell fills with its foreground colour', () {
      // Inverse fills even where the cell has no background of its own, so
      // this is one span where the plain equivalent would be none.
      final painted = _paintLine('\x1b[7mab');

      expect(painted.rects, hasLength(1));
      expect(painted.rects.single.width, closeTo(painted.columns(2) + 1, 0.01));
    });
  });

  test('every sprite lands on a whole device pixel', () {
    // What keeps a sprite a copy of its texels rather than a resample of them,
    // and so what keeps the text sharp. At the default scale the test font's
    // cell is exactly 13 logical pixels and every column is already whole, so
    // this has to be asked at a scale where it is not: 14.3, over a ratio of 2.
    const dpr = 2.0;
    final painted = _paintLine(
      '\x1b[38;2;255;0;0ma\x1b[38;2;0;255;0mb\x1b[38;2;0;0;255mc',
      scale: 1.1,
      dpr: dpr,
    );

    expect(painted.spriteOffsets, hasLength(3));

    for (final offset in painted.spriteOffsets) {
      expect(
        offset * dpr,
        closeTo((offset * dpr).roundToDouble(), 1e-6),
        reason: '$offset is not a whole number of device pixels',
      );
    }
  });

  test('every background is painted before any glyph', () {
    // Painting a cell at a time used to interleave them, so a glyph wider than
    // its cell was clipped by the next cell's background.
    final painted = _paintLine('\x1b[41mab\x1b[42mcd');

    final lastRect = painted.ops.lastIndexWhere((op) => op is _RectOp);
    final firstGlyph = painted.ops.indexWhere((op) => op is! _RectOp);

    // Both have to exist, or the ordering below holds vacuously: with no rects
    // lastRect is -1, which is less than any glyph index.
    expect(lastRect, isNonNegative, reason: 'no background was painted');
    expect(firstGlyph, isNonNegative, reason: 'no glyph was painted');
    expect(lastRect, lessThan(firstGlyph));
  });
}

_Painted _paintLine(
  String input, {
  int width = 20,
  double scale = 1,
  double dpr = 1,
}) {
  final terminal = Terminal(maxLines: 4);
  terminal.resize(width, 2);
  terminal.write(input);

  final painter = TerminalPainter(
    theme: TerminalThemes.defaultTheme,
    textStyle: const TerminalStyle(),
    textScaler: TextScaler.linear(scale),
    devicePixelRatio: dpr,
  );

  final recorder = PictureRecorder();
  final canvas = _RecordingCanvas(Canvas(recorder), dpr);
  painter.paintLine(canvas, Offset.zero, terminal.buffer.lines[0]);
  recorder.endRecording().dispose();

  return _Painted(canvas.ops, painter.cellSize.width);
}

class _Painted {
  _Painted(this.ops, this.cellWidth);

  final List<_Op> ops;
  final double cellWidth;

  /// Every glyph the line drew, paragraphs and sprites alike, ordered by the
  /// column each sits in.
  late final List<_Glyph> glyphs =
      [for (final op in ops) ...op.glyphs(cellWidth)]
        ..sort((a, b) => a.x.compareTo(b.x));

  List<Rect> get rects =>
      ops.whereType<_RectOp>().map((op) => op.rect).toList();

  /// Where each sprite was placed, before the padding is taken back off.
  List<double> get spriteOffsets => [
    for (final op in ops.whereType<_AtlasOp>())
      for (var i = 0; i < op.rects.length ~/ 4; i++) op.transforms[i * 4 + 2],
  ];

  /// The x offset of column [n].
  double columns(int n) => n * cellWidth;

  /// How many cells wide the glyph at [index] was drawn.
  int cellsIn(int index) => (glyphs[index].width / cellWidth).round();

  /// How many UTF-16 code units the paragraph at [index] was built from.
  ///
  /// A [Paragraph] does not hand its text back, but the caret position past its
  /// right edge is the offset of the end of that text. Sprites have no text to
  /// ask about, so this only applies to a glyph that took the paragraph path.
  int codeUnitsIn(int index) {
    return glyphs[index].paragraph!
        .getPositionForOffset(const Offset(double.maxFinite, 1))
        .offset;
  }
}

/// One glyph on the canvas: where it starts, how wide it drew, and its
/// paragraph if it took that path.
class _Glyph {
  const _Glyph(this.x, this.width, this.paragraph);

  final double x;
  final double width;
  final Paragraph? paragraph;
}

sealed class _Op {
  List<_Glyph> glyphs(double cellWidth) => const [];
}

class _RectOp extends _Op {
  _RectOp(this.rect);

  final Rect rect;
}

class _ParagraphOp extends _Op {
  _ParagraphOp(this.paragraph, this.offset);

  final Paragraph paragraph;
  final Offset offset;

  @override
  List<_Glyph> glyphs(double cellWidth) => [
    _Glyph(offset.dx, paragraph.maxIntrinsicWidth, paragraph),
  ];
}

/// One `drawRawAtlas` batch, which is how a line draws every cell that could
/// not join a run.
class _AtlasOp extends _Op {
  _AtlasOp(this.transforms, this.rects, this.devicePixelRatio);

  final Float32List transforms;
  final Float32List rects;

  /// The source rects are in device pixels where the transforms and the cell
  /// grid are logical, so taking the margin off needs both in one unit.
  final double devicePixelRatio;

  @override
  List<_Glyph> glyphs(double cellWidth) {
    final margin = GlyphAtlas.padding * cellWidth;

    return [
      for (var i = 0; i < rects.length ~/ 4; i++)
        // A sprite carries a margin on every side and is placed by its own left
        // edge, on a whole device pixel. Undoing the first two gives the column
        // it is in, to within the rounding the third does.
        _Glyph(
          transforms[i * 4 + 2] + margin,
          (rects[i * 4 + 2] - rects[i * 4]) / devicePixelRatio - 2 * margin,
          null,
        ),
    ];
  }
}

/// Records the draw calls a painter makes, in order, forwarding each to a real
/// canvas.
///
/// Anything other than the three primitives [TerminalPainter.paintLine] uses
/// reaches [noSuchMethod] and throws: a line painter that starts drawing
/// something else should fail here rather than have it go unrecorded.
class _RecordingCanvas implements Canvas {
  _RecordingCanvas(this._inner, this.devicePixelRatio);

  final Canvas _inner;
  final double devicePixelRatio;

  final ops = <_Op>[];

  @override
  void drawRect(Rect rect, Paint paint) {
    ops.add(_RectOp(rect));
    _inner.drawRect(rect, paint);
  }

  @override
  void drawParagraph(Paragraph paragraph, Offset offset) {
    ops.add(_ParagraphOp(paragraph, offset));
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
    ops.add(_AtlasOp(rstTransforms, rects, devicePixelRatio));
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
  dynamic noSuchMethod(Invocation invocation) {
    throw UnsupportedError(
      'painter test: unexpected canvas call ${invocation.memberName}',
    );
  }
}
