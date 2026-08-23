import 'dart:ui';

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xterm/src/core/buffer/cell_flags.dart';
import 'package:xterm/src/core/cell.dart';
import 'package:xterm/src/ui/painter.dart';
import 'package:xterm/src/ui/terminal_text_style.dart';
import 'package:xterm/src/ui/themes.dart';

void main() {
  late TerminalPainter painter;

  setUp(() {
    painter = TerminalPainter(
      theme: TerminalThemes.defaultTheme,
      textStyle: const TerminalStyle(),
      textScaler: TextScaler.noScaling,
    );
  });

  // A cache hit hands back the same [Paragraph] object, so identity is what
  // says whether two cells shared an entry. That is the whole surface of the
  // glyph key: which cells are the same glyph, and which are not.
  group('glyph cache identity', () {
    test('the same cell twice reuses one paragraph', () {
      final first = _paint(painter, _cell());
      final second = _paint(painter, _cell());

      expect(first, isNotNull);
      expect(identical(first, second), isTrue);
    });

    test('a different character is a different paragraph', () {
      final a = _paint(painter, _cell(char: 0x41));
      final b = _paint(painter, _cell(char: 0x42));

      expect(identical(a, b), isFalse);
    });

    test('a different colour is a different paragraph', () {
      final red = _paint(painter, _cell(foreground: _rgb(0xFF0000)));
      final blue = _paint(painter, _cell(foreground: _rgb(0x0000FF)));

      expect(identical(red, blue), isFalse);
    });

    for (final (name, flag) in const [
      ('bold', CellFlags.bold),
      ('italic', CellFlags.italic),
      ('underline', CellFlags.underline),
      ('strikethrough', CellFlags.strikethrough),
      ('overline', CellFlags.overline),
    ]) {
      test('$name is a different paragraph from plain', () {
        final plain = _paint(painter, _cell());
        final styled = _paint(painter, _cell(flags: flag));

        expect(identical(plain, styled), isFalse);
      });
    }
  });

  // Everything below is a claim the key makes by leaving something out. Each
  // one is wrong if the flag mask picks up a flag it should not, or drops one
  // it should keep.
  group('glyph cache key narrowing', () {
    test('blink does not split the cache', () {
      // Blink never reaches TerminalStyle.toTextStyle, so a blinking cell and
      // a steady one are the same glyph.
      final steady = _paint(painter, _cell());
      final blinking = _paint(painter, _cell(flags: CellFlags.blink));

      expect(identical(steady, blinking), isTrue);
    });

    test('inverse resolves into the colour rather than the key', () {
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
      expect(identical(inverted, plain), isTrue);
    });

    test('reverseDisplay resolves into the colour rather than the key', () {
      final reversed = _paint(
        painter,
        _cell(foreground: _rgb(0xFF0000), background: _rgb(0x0000FF)),
        reverseDisplay: true,
      );
      final plain = _paint(painter, _cell(foreground: _rgb(0x0000FF)));

      expect(reversed, isNotNull);
      expect(identical(reversed, plain), isTrue);
    });

    test('inverse twice over cancels back to the plain glyph', () {
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

      expect(identical(doubled, plain), isTrue);
    });

    test('faint is a different paragraph from plain', () {
      // Unlike blink, faint does change the colour, so it must split.
      final plain = _paint(painter, _cell(foreground: _rgb(0xFF0000)));
      final faint = _paint(
        painter,
        _cell(foreground: _rgb(0xFF0000), flags: CellFlags.faint),
      );

      expect(identical(plain, faint), isFalse);
    });
  });

  group('cells that paint no glyph', () {
    test('an invisible cell paints nothing', () {
      expect(_paint(painter, _cell(flags: CellFlags.invisible)), isNull);
    });

    test('an empty cell paints nothing', () {
      expect(_paint(painter, _cell(char: 0)), isNull);
    });
  });
}

/// Paints one cell's foreground and returns the [Paragraph] it drew, or null
/// if it drew none.
Paragraph? _paint(
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

  return canvas.paragraphs.isEmpty ? null : canvas.paragraphs.single;
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

/// Captures the paragraphs a painter draws, forwarding them to a real canvas.
///
/// Anything other than `drawParagraph` reaches [noSuchMethod] and throws, which
/// is intended: a foreground painter that starts drawing something else should
/// fail here rather than have it go unseen.
class _CapturingCanvas implements Canvas {
  _CapturingCanvas(this._inner);

  final Canvas _inner;

  final paragraphs = <Paragraph>[];

  @override
  void drawParagraph(Paragraph paragraph, Offset offset) {
    paragraphs.add(paragraph);
    _inner.drawParagraph(paragraph, offset);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) {
    throw UnsupportedError(
      'painter test: unexpected canvas call ${invocation.memberName}',
    );
  }
}
