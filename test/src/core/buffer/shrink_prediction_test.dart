import 'package:test/test.dart';
import 'package:xterm/core.dart';

void main() {
  test('the screen top a shrink is predicted at is where resize puts it', () {
    for (final cursorRow in [0, 5, 12, 23]) {
      for (final scrolled in [0, 30]) {
        final terminal = Terminal()..resize(80, 24);
        terminal.write('x\r\n' * (24 + scrolled - 1));
        terminal.setCursor(0, cursorRow);
        final predicted = terminal.buffer.screenTopAfterShrink(10);
        terminal.resize(80, 10);
        expect(
          terminal.buffer.scrollBack,
          predicted,
          reason: 'cursor row $cursorRow, $scrolled lines scrolled off',
        );
      }
    }
  });
}
