import 'package:test/test.dart';
import 'package:xterm/src/core/color.dart';

void main() {
  group('NamedColor', () {
    test('basic colors have correct indices', () {
      expect(NamedColor.black, 0);
      expect(NamedColor.red, 1);
      expect(NamedColor.green, 2);
      expect(NamedColor.yellow, 3);
      expect(NamedColor.blue, 4);
      expect(NamedColor.magenta, 5);
      expect(NamedColor.cyan, 6);
      expect(NamedColor.white, 7);
    });

    test('bright colors have correct indices', () {
      expect(NamedColor.brightBlack, 8);
      expect(NamedColor.brightRed, 9);
      expect(NamedColor.brightGreen, 10);
      expect(NamedColor.brightYellow, 11);
      expect(NamedColor.brightBlue, 12);
      expect(NamedColor.brightMagenta, 13);
      expect(NamedColor.brightCyan, 14);
      expect(NamedColor.brightWhite, 15);
    });
  });
}
