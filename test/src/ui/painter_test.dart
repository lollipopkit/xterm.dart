import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xterm/src/core/buffer/cell_flags.dart';
import 'package:xterm/src/core/cell.dart';
import 'package:xterm/src/ui/painter.dart';
import 'package:xterm/src/ui/terminal_text_style.dart';
import 'package:xterm/src/ui/themes.dart';

// A cell that is not part of a run is drawn out of the glyph atlas: one sprite,
// rasterised without a colour and tinted as it is drawn. So the two things
// worth asserting about a cell are which atlas entry it used and what colour it
// was tinted. The source rect names the entry: two cells share one exactly
// when they share a rect. Neither needs an API the package does not already
// have.
//
// Which of those two a property belongs to is the whole design. A style flag
// changes the entry; a colour does not, and that is what stops a screen of
// uniquely coloured cells from missing the cache on every cell.

void main() {
  late TerminalPainter painter;

  setUp(() {
    painter = TerminalPainter(
      theme: TerminalThemes.defaultTheme,
      textStyle: const TerminalStyle(),
      textScaler: TextScaler.noScaling,
    );
  });

  group('atlas entries', () {
    test('the same cell twice reuses one entry', () {
      final first = _paint(painter, _cell());
      final second = _paint(painter, _cell());

      expect(first, isNotNull);
      expect(second!.source, first!.source);
    });

    test('a different character is a different entry', () {
      final a = _paint(painter, _cell(char: 0x41));
      final b = _paint(painter, _cell(char: 0x42));

      expect(b!.source, isNot(a!.source));
    });

    for (final (name, flag) in const [
      ('bold', CellFlags.bold),
      ('italic', CellFlags.italic),
    ]) {
      test('$name is a different entry from plain', () {
        final plain = _paint(painter, _cell());
        final styled = _paint(painter, _cell(flags: flag));

        expect(styled!.source, isNot(plain!.source));
      });
    }

    test('a different colour is the same entry, tinted differently', () {
      // The point of the atlas. Under the paragraph cache these were two
      // entries, and a screen of distinct colours could not be held.
      final red = _paint(painter, _cell(foreground: _rgb(0xFF0000)));
      final blue = _paint(painter, _cell(foreground: _rgb(0x0000FF)));

      expect(blue!.source, red!.source);
      expect(red.color, 0xFFFF0000);
      expect(blue.color, 0xFF0000FF);
    });
  });

  // Everything below is a claim the atlas key makes by leaving something out.
  // Each is wrong if the flag mask picks up a flag it should not, or drops one
  // it should keep.
  group('what does not reach the entry', () {
    test('blink neither splits the entry nor changes the colour', () {
      // Blink never reaches TerminalStyle.toTextStyle, so a blinking cell and
      // a steady one are the same glyph.
      final steady = _paint(painter, _cell());
      final blinking = _paint(painter, _cell(flags: CellFlags.blink));

      expect(blinking!.source, steady!.source);
      expect(blinking.color, steady.color);
    });

    test('inverse resolves into the colour rather than the entry', () {
      // An inverse cell paints its background colour as the foreground, so it
      // is the same glyph as a plain cell whose foreground is that colour.
      final inverted = _paint(
        painter,
        _cell(
          foreground: _rgb(0xFF0000),
          background: _rgb(0x0000FF),
          flags: CellFlags.inverse,
        ),
      );
      final plain = _paint(painter, _cell(foreground: _rgb(0x0000FF)));

      expect(inverted, isNotNull);
      expect(inverted!.source, plain!.source);
      expect(inverted.color, plain.color);
    });

    test('reverseDisplay resolves into the colour rather than the entry', () {
      final reversed = _paint(
        painter,
        _cell(foreground: _rgb(0xFF0000), background: _rgb(0x0000FF)),
        reverseDisplay: true,
      );
      final plain = _paint(painter, _cell(foreground: _rgb(0x0000FF)));

      expect(reversed, isNotNull);
      expect(reversed!.color, plain!.color);
    });

    test('inverse twice over cancels back to the plain colour', () {
      final doubled = _paint(
        painter,
        _cell(
          foreground: _rgb(0xFF0000),
          background: _rgb(0x0000FF),
          flags: CellFlags.inverse,
        ),
        reverseDisplay: true,
      );
      final plain = _paint(painter, _cell(foreground: _rgb(0xFF0000)));

      expect(doubled!.color, plain!.color);
    });

    test('faint halves the alpha and keeps the entry', () {
      // Unlike blink, faint does change the colour, but not the glyph.
      final plain = _paint(painter, _cell(foreground: _rgb(0xFF0000)));
      final faint = _paint(
        painter,
        _cell(foreground: _rgb(0xFF0000), flags: CellFlags.faint),
      );

      expect(faint!.source, plain!.source);
      expect(faint.color, 0x80FF0000);
    });
  });

  group('cells the atlas does not take', () {
    for (final (name, flag) in const [
      ('underline', CellFlags.underline),
      ('strikethrough', CellFlags.strikethrough),
      ('overline', CellFlags.overline),
    ]) {
      test('$name is drawn as a paragraph', () {
        // A decoration spans the character's advance, and two neighbours' out
        // of an atlas can leave a gap where they meet.
        final canvas = _paintWith(painter, _cell(flags: flag));

        expect(canvas.sprites, isEmpty);
        expect(canvas.paragraphs, hasLength(1));
      });
    }

    test('an emoji is drawn as a paragraph', () {
      // Tinting a glyph the font draws in colour would leave a silhouette.
      final canvas = _paintWith(painter, _cell(char: 0x1F600));

      expect(canvas.sprites, isEmpty);
      expect(canvas.paragraphs, hasLength(1));
    });
  });

  group('cells that paint nothing', () {
    test('an invisible cell paints nothing', () {
      final canvas = _paintWith(painter, _cell(flags: CellFlags.invisible));

      expect(canvas.sprites, isEmpty);
      expect(canvas.paragraphs, isEmpty);
    });

    test('an empty cell paints nothing', () {
      final canvas = _paintWith(painter, _cell(char: 0));

      expect(canvas.sprites, isEmpty);
      expect(canvas.paragraphs, isEmpty);
    });
  });
}

/// One sprite of a `drawRawAtlas` batch.
class _Sprite {
  const _Sprite(this.source, this.color);

  /// The sprite's rect in the atlas, which is what identifies its entry.
  final Rect source;

  /// The ARGB the sprite was tinted with, read back unsigned: the painter
  /// hands Skia an [Int32List], where an opaque colour is a negative number.
  final int color;
}

/// Paints one cell's foreground and returns the sprite it drew, or null if it
/// drew none.
_Sprite? _paint(
  TerminalPainter painter,
  CellData cell, {
  bool reverseDisplay = false,
}) {
  final sprites = _paintWith(
    painter,
    cell,
    reverseDisplay: reverseDisplay,
  ).sprites;

  return sprites.isEmpty ? null : sprites.single;
}

_CapturingCanvas _paintWith(
  TerminalPainter painter,
  CellData cell, {
  bool reverseDisplay = false,
}) {
  final recorder = PictureRecorder();
  final canvas = _CapturingCanvas(Canvas(recorder));

  painter.paintCellForeground(
    canvas,
    Offset.zero,
    cell,
    reverseDisplay: reverseDisplay,
  );
  recorder.endRecording().dispose();

  return canvas;
}

CellData _cell({
  int char = 0x41,
  int foreground = CellColor.normal,
  int background = CellColor.normal,
  int flags = 0,
}) {
  return CellData(
    foreground: foreground,
    background: background,
    flags: flags,
    content: char | (1 << CellContent.widthShift),
  );
}

/// A cell colour holding a literal RGB value, as an SGR 38;2 sequence produces.
///
/// The tests use these rather than palette or default colours because
/// [TerminalPainter.resolveForegroundColor] and `resolveBackgroundColor` agree
/// on every colour type except [CellColor.normal], where one answers the
/// theme's foreground and the other its background.
int _rgb(int value) => CellColor.rgb | value;

/// Captures what a painter draws, forwarding it to a real canvas.
///
/// Anything other than the two primitives a foreground painter uses reaches
/// [noSuchMethod] and throws, which is intended: one that starts drawing
/// something else should fail here rather than have it go unseen.
class _CapturingCanvas implements Canvas {
  _CapturingCanvas(this._inner);

  final Canvas _inner;

  final paragraphs = <Paragraph>[];
  final sprites = <_Sprite>[];

  @override
  void drawParagraph(Paragraph paragraph, Offset offset) {
    paragraphs.add(paragraph);
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
    for (var i = 0; i < colors!.length; i++) {
      sprites.add(
        _Sprite(
          Rect.fromLTRB(
            rects[i * 4],
            rects[i * 4 + 1],
            rects[i * 4 + 2],
            rects[i * 4 + 3],
          ),
          colors[i].toUnsigned(32),
        ),
      );
    }
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
