import 'dart:ui';

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xterm/src/terminal.dart';
import 'package:xterm/src/ui/painter.dart';
import 'package:xterm/src/ui/terminal_text_style.dart';
import 'package:xterm/src/ui/themes.dart';

// These assert on the draw calls TerminalPainter.paintLine issues, since that
// is what run coalescing changes: which cells share a paragraph and which
// share a background rect.
//
// A paragraph's text is not readable back, so a run is identified by how wide
// it laid out. Under `flutter test` every glyph is an identical box of exactly
// one cell, so a run of n cells measures n * cellWidth.

void main() {
  group('foreground runs', () {
    test('cells sharing a style are drawn as one paragraph', () {
      final painted = _paintLine('hello');

      expect(painted.paragraphs, hasLength(1));
      expect(painted.paragraphs.single.offset.dx, 0);
      expect(painted.cellsIn(0), 5);
    });

    test('a colour change starts a new run', () {
      final painted = _paintLine('\x1b[31mabc\x1b[32mdef');

      expect(painted.paragraphs, hasLength(2));
      expect(painted.cellsIn(0), 3);
      expect(painted.paragraphs[1].offset.dx, painted.columns(3));
      expect(painted.cellsIn(1), 3);
    });

    test('bold starts a new run', () {
      final painted = _paintLine('ab\x1b[1mcd');

      expect(painted.paragraphs, hasLength(2));
      expect(painted.cellsIn(0), 2);
      expect(painted.cellsIn(1), 2);
    });

    test('an untouched cell ends the run', () {
      // Write ab, jump to column 6, write cd. Columns 2..4 were never written.
      final painted = _paintLine('ab\x1b[6Gcd');

      expect(painted.paragraphs, hasLength(2));
      expect(painted.paragraphs[1].offset.dx, painted.columns(5));
    });

    test('an invisible cell ends the run and paints nothing', () {
      final painted = _paintLine('ab\x1b[8mcd\x1b[28mef');

      expect(painted.paragraphs, hasLength(2));
      expect(painted.cellsIn(0), 2);
      expect(painted.paragraphs[1].offset.dx, painted.columns(4));
      expect(painted.cellsIn(1), 2);
    });

    test('a wide character is drawn on its own', () {
      final painted = _paintLine('a中b');

      // The wide character cannot join a run, and it separates the two ASCII
      // cells, so each is drawn alone. Its trailing half paints nothing.
      expect(painted.paragraphs, hasLength(3));
      expect(painted.paragraphs[0].offset.dx, painted.columns(0));
      expect(painted.paragraphs[1].offset.dx, painted.columns(1));
      expect(painted.paragraphs[2].offset.dx, painted.columns(3));
    });

    test('box drawing characters form a run', () {
      final painted = _paintLine('────');

      expect(painted.paragraphs, hasLength(1));
      expect(painted.cellsIn(0), 4);
    });

    test('box drawing does not join an ASCII run', () {
      // A font boundary must not land inside a paragraph: box drawing usually
      // comes from a different fallback font than ASCII does.
      final painted = _paintLine('ab──');

      expect(painted.paragraphs, hasLength(2));
      expect(painted.cellsIn(0), 2);
      expect(painted.cellsIn(1), 2);
    });

    test('a space does not break an underlined run', () {
      // An underlined space is swapped for a non-breaking space, which has to
      // happen inside the run rather than by ending it.
      final painted = _paintLine('\x1b[4ma b');

      expect(painted.paragraphs, hasLength(1));
      expect(painted.cellsIn(0), 3);
    });

    test('a cell holding combining marks is drawn on its own', () {
      // The cluster's glyph is composed from more than one code point and need
      // not advance by one cell, so it cannot sit inside a run. It also has to
      // break the run either side of it rather than be skipped.
      final painted = _paintLine('ab́c');

      expect(painted.paragraphs, hasLength(3));
      expect(painted.paragraphs[0].offset.dx, painted.columns(0));
      expect(painted.paragraphs[1].offset.dx, painted.columns(1));
      expect(painted.paragraphs[2].offset.dx, painted.columns(2));
    });

    test('a cluster paints its marks rather than the base alone', () {
      final painted = _paintLine('á');

      // Width says nothing here: the mark advances by zero, so a cluster and
      // its bare base lay out the same. What the paragraph was built from is
      // the claim, and its length is the way to read that back.
      expect(painted.paragraphs, hasLength(1));
      expect(painted.codeUnitsIn(0), 2);
      expect(_paintLine('a').codeUnitsIn(0), 1);
    });

    test('a zero width joiner sequence is laid out as one paragraph', () {
      final painted = _paintLine('\u{1F468}‍\u{1F469}‍\u{1F467}');

      expect(painted.paragraphs, hasLength(1));
      expect(painted.paragraphs.single.offset.dx, painted.columns(0));
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

  test('every background is painted before any glyph', () {
    // Painting a cell at a time used to interleave them, so a glyph wider than
    // its cell was clipped by the next cell's background.
    final painted = _paintLine('\x1b[41mab\x1b[42mcd');

    final lastRect = painted.ops.lastIndexWhere((op) => op.isRect);
    final firstGlyph = painted.ops.indexWhere((op) => !op.isRect);

    // Both have to exist, or the ordering below holds vacuously: with no rects
    // lastRect is -1, which is less than any glyph index.
    expect(lastRect, isNonNegative, reason: 'no background was painted');
    expect(firstGlyph, isNonNegative, reason: 'no glyph was painted');
    expect(lastRect, lessThan(firstGlyph));
  });
}

_Painted _paintLine(String input, {int width = 20}) {
  final terminal = Terminal(maxLines: 4);
  terminal.resize(width, 2);
  terminal.write(input);

  final painter = TerminalPainter(
    theme: TerminalThemes.defaultTheme,
    textStyle: const TerminalStyle(),
    textScaler: TextScaler.noScaling,
  );

  final recorder = PictureRecorder();
  final canvas = _RecordingCanvas(Canvas(recorder));
  painter.paintLine(canvas, Offset.zero, terminal.buffer.lines[0]);
  recorder.endRecording().dispose();

  return _Painted(canvas.ops, painter.cellSize.width);
}

class _Painted {
  _Painted(this.ops, this.cellWidth);

  final List<_Op> ops;
  final double cellWidth;

  List<_Op> get paragraphs => ops.where((op) => !op.isRect).toList();

  List<Rect> get rects =>
      ops.where((op) => op.isRect).map((op) => op.rect!).toList();

  /// The x offset of column [n].
  double columns(int n) => n * cellWidth;

  /// How many cells wide the paragraph at [index] laid out as.
  int cellsIn(int index) {
    return (paragraphs[index].paragraph!.maxIntrinsicWidth / cellWidth).round();
  }

  /// How many UTF-16 code units the paragraph at [index] was built from.
  ///
  /// A [Paragraph] does not hand its text back, but the caret position past its
  /// right edge is the offset of the end of that text.
  int codeUnitsIn(int index) {
    return paragraphs[index].paragraph!
        .getPositionForOffset(const Offset(double.maxFinite, 1))
        .offset;
  }
}

class _Op {
  _Op.rect(this.rect) : paragraph = null, offset = Offset.zero;
  _Op.paragraph(this.paragraph, this.offset) : rect = null;

  final Rect? rect;
  final Paragraph? paragraph;
  final Offset offset;

  bool get isRect => rect != null;
}

/// Records the draw calls a painter makes, in order, forwarding each to a real
/// canvas.
///
/// Anything other than `drawRect` and `drawParagraph` reaches [noSuchMethod]
/// and throws: a line painter that starts drawing something else should fail
/// here rather than have it go unrecorded.
class _RecordingCanvas implements Canvas {
  _RecordingCanvas(this._inner);

  final Canvas _inner;

  final ops = <_Op>[];

  @override
  void drawRect(Rect rect, Paint paint) {
    ops.add(_Op.rect(rect));
    _inner.drawRect(rect, paint);
  }

  @override
  void drawParagraph(Paragraph paragraph, Offset offset) {
    ops.add(_Op.paragraph(paragraph, offset));
    _inner.drawParagraph(paragraph, offset);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) {
    throw UnsupportedError(
      'painter test: unexpected canvas call ${invocation.memberName}',
    );
  }
}
