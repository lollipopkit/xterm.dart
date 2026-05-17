import 'package:test/test.dart';
import 'package:xterm/src/core/mouse/button.dart';

void main() {
  group('TerminalMouseButton', () {
    test('left button has id 0', () {
      expect(TerminalMouseButton.left.id, 0);
      expect(TerminalMouseButton.left.isWheel, isFalse);
    });

    test('middle button has id 1', () {
      expect(TerminalMouseButton.middle.id, 1);
      expect(TerminalMouseButton.middle.isWheel, isFalse);
    });

    test('right button has id 2', () {
      expect(TerminalMouseButton.right.id, 2);
      expect(TerminalMouseButton.right.isWheel, isFalse);
    });

    test('wheelUp has id 64', () {
      expect(TerminalMouseButton.wheelUp.id, 64);
      expect(TerminalMouseButton.wheelUp.isWheel, isTrue);
    });

    test('wheelDown has id 65', () {
      expect(TerminalMouseButton.wheelDown.id, 65);
      expect(TerminalMouseButton.wheelDown.isWheel, isTrue);
    });

    test('wheelLeft has id 66', () {
      expect(TerminalMouseButton.wheelLeft.id, 66);
      expect(TerminalMouseButton.wheelLeft.isWheel, isTrue);
    });

    test('wheelRight has id 67', () {
      expect(TerminalMouseButton.wheelRight.id, 67);
      expect(TerminalMouseButton.wheelRight.isWheel, isTrue);
    });
  });
}
