import 'package:test/test.dart';
import 'package:xterm/src/core/escape/emitter.dart';

void main() {
  group('EscapeEmitter', () {
    final emitter = const EscapeEmitter();

    test('primaryDeviceAttributes', () {
      expect(emitter.primaryDeviceAttributes(), '\x1b[?1;2c');
    });

    test('secondaryDeviceAttributes', () {
      expect(emitter.secondaryDeviceAttributes(), '\x1b[>0;0;0c');
    });

    test('tertiaryDeviceAttributes', () {
      expect(emitter.tertiaryDeviceAttributes(), '\x1bP!|00000000\x1b\\');
    });

    test('operatingStatus', () {
      expect(emitter.operatingStatus(), '\x1b[0n');
    });

    test('cursorPosition reports 1-based coordinates', () {
      expect(emitter.cursorPosition(0, 0), '\x1b[1;1R');
      expect(emitter.cursorPosition(4, 7), '\x1b[8;5R');
    });

    test('extendedCursorPosition reports 1-based with ? prefix', () {
      expect(emitter.extendedCursorPosition(0, 0), '\x1b[?1;1R');
      expect(emitter.extendedCursorPosition(9, 24), '\x1b[?25;10R');
    });

    test('bracketedPaste wraps text in markers', () {
      expect(emitter.bracketedPaste('hello'), '\x1b[200~hello\x1b[201~');
    });

    test('bracketedPaste handles empty string', () {
      expect(emitter.bracketedPaste(''), '\x1b[200~\x1b[201~');
    });

    test('size reports rows and cols', () {
      expect(emitter.size(24, 80), '\x1b[8;24;80t');
    });
  });
}
