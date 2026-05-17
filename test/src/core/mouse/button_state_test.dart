import 'package:test/test.dart';
import 'package:xterm/src/core/mouse/button_state.dart';

void main() {
  group('TerminalMouseButtonState', () {
    test('has down and up states', () {
      expect(TerminalMouseButtonState.down, isNot(TerminalMouseButtonState.up));
    });

    test('up state has index 0', () {
      expect(TerminalMouseButtonState.up.index, 0);
    });

    test('down state has index 1', () {
      expect(TerminalMouseButtonState.down.index, 1);
    });
  });
}
