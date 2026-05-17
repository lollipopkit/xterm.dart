import 'package:test/test.dart';
import 'package:xterm/src/core/cursor.dart';
import 'package:xterm/src/core/cell.dart';
import 'package:xterm/src/core/color.dart';

void main() {
  group('CursorStyle', () {
    test('initial state is empty', () {
      final style = CursorStyle();
      expect(style.foreground, 0);
      expect(style.background, 0);
      expect(style.attrs, 0);
    });

    test('isItalic reflects italic attribute', () {
      final style = CursorStyle();

      expect(style.isItalic, isFalse);

      style.setItalic();
      expect(style.isItalic, isTrue);

      style.unsetItalic();
      expect(style.isItalic, isFalse);
    });

    test('isBold reflects bold attribute', () {
      final style = CursorStyle();
      style.setBold();
      expect(style.isBold, isTrue);
      style.unsetBold();
      expect(style.isBold, isFalse);
    });

    test('isFaint reflects faint attribute', () {
      final style = CursorStyle();
      style.setFaint();
      expect(style.isFaint, isTrue);
      style.unsetFaint();
      expect(style.isFaint, isFalse);
    });

    test('isUnderline reflects underline attribute', () {
      final style = CursorStyle();
      style.setUnderline();
      expect(style.isUnderline, isTrue);
      style.unsetUnderline();
      expect(style.isUnderline, isFalse);
    });

    test('isBlink reflects blink attribute', () {
      final style = CursorStyle();
      style.setBlink();
      expect(style.isBlink, isTrue);
      style.unsetBlink();
      expect(style.isBlink, isFalse);
    });

    test('isInverse reflects inverse attribute', () {
      final style = CursorStyle();
      style.setInverse();
      expect(style.isInverse, isTrue);
      style.unsetInverse();
      expect(style.isInverse, isFalse);
    });

    test('isInvisible reflects invisible attribute', () {
      final style = CursorStyle();
      style.setInvisible();
      expect(style.isInvisible, isTrue);
      style.unsetInvisible();
      expect(style.isInvisible, isFalse);
    });

    test('isOverline reflects overline attribute', () {
      final style = CursorStyle();
      style.setOverline();
      expect(style.isOverline, isTrue);
      style.unsetOverline();
      expect(style.isOverline, isFalse);
    });

    test('isStrikethrough reflects strikethrough attribute', () {
      final style = CursorStyle();
      style.setStrikethrough();
      expect(style.isStrikethrough, isTrue);
      style.unsetStrikethrough();
      expect(style.isStrikethrough, isFalse);
    });

    test('setForegroundColor16 stores color with named type', () {
      final style = CursorStyle();
      style.setForegroundColor16(NamedColor.red);
      expect(style.foreground, NamedColor.red | CellColor.named);
    });

    test('setForegroundColor256 stores color with palette type', () {
      final style = CursorStyle();
      style.setForegroundColor256(42);
      expect(style.foreground, 42 | CellColor.palette);
    });

    test('setForegroundColor256 clamps value', () {
      final style = CursorStyle();
      style.setForegroundColor256(300);
      expect(style.foreground, 255 | CellColor.palette);
    });

    test('setForegroundColorRgb stores RGB with rgb type', () {
      final style = CursorStyle();
      style.setForegroundColorRgb(10, 20, 30);
      expect(style.foreground, (10 << 16) | (20 << 8) | 30 | CellColor.rgb);
    });

    test('setForegroundColorRgb clamps each channel', () {
      final style = CursorStyle();
      style.setForegroundColorRgb(300, -1, 128);
      expect(style.foreground, (255 << 16) | (0 << 8) | 128 | CellColor.rgb);
    });

    test('resetForegroundColor clears foreground', () {
      final style = CursorStyle();
      style.setForegroundColor16(NamedColor.red);
      style.resetForegroundColor();
      expect(style.foreground, 0);
    });

    test('setBackgroundColor16 stores color with named type', () {
      final style = CursorStyle();
      style.setBackgroundColor16(NamedColor.blue);
      expect(style.background, NamedColor.blue | CellColor.named);
    });

    test('setBackgroundColor256 stores color with palette type', () {
      final style = CursorStyle();
      style.setBackgroundColor256(99);
      expect(style.background, 99 | CellColor.palette);
    });

    test('setBackgroundColorRgb stores RGB with rgb type', () {
      final style = CursorStyle();
      style.setBackgroundColorRgb(100, 200, 50);
      expect(
        style.background,
        (100 << 16) | (200 << 8) | 50 | CellColor.rgb,
      );
    });

    test('resetBackgroundColor clears background', () {
      final style = CursorStyle();
      style.setBackgroundColor16(NamedColor.green);
      style.resetBackgroundColor();
      expect(style.background, 0);
    });

    test('reset clears all fields', () {
      final style = CursorStyle();
      style.setBold();
      style.setUnderline();
      style.setForegroundColor16(NamedColor.red);
      style.setBackgroundColor256(42);
      style.reset();
      expect(style.foreground, 0);
      expect(style.background, 0);
      expect(style.attrs, 0);
    });

    test('multiple attributes can be combined', () {
      final style = CursorStyle();
      style.setBold();
      style.setItalic();
      style.setUnderline();
      expect(style.isBold, isTrue);
      expect(style.isItalic, isTrue);
      expect(style.isUnderline, isTrue);
      expect(style.isFaint, isFalse);
      expect(style.isBlink, isFalse);
    });
  });
}
