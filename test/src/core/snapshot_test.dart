import 'package:test/test.dart';
import 'package:xterm/core.dart';

void main() {
  group('TerminalSnapshot', () {
    test('can be created from terminal', () {
      final terminal = Terminal();
      terminal.write('Hello World');

      final snapshot = TerminalSnapshot(terminal.buffer);
      expect(snapshot.buffer, terminal.buffer);
    });

    test('trimScrollback removes lines above viewport', () {
      final terminal = Terminal(maxLines: 10);
      terminal.resize(4, 2);

      // Write enough lines to fill scrollback
      for (var i = 0; i < 5; i++) {
        terminal.write('Line $i\r\n');
      }

      final initialHeight = terminal.buffer.height;
      expect(initialHeight, greaterThan(terminal.viewHeight));

      final snapshot = TerminalSnapshot(terminal.buffer);
      snapshot.trimScrollback();

      expect(terminal.buffer.height, terminal.viewHeight);
      expect(terminal.buffer.scrollBack, 0);
    });

    test('trimScrollback is a no-op when there is no scrollback', () {
      final terminal = Terminal(maxLines: 10);
      terminal.resize(10, 5);
      terminal.write('Hello');

      final snapshot = TerminalSnapshot(terminal.buffer);
      snapshot.trimScrollback();

      expect(terminal.buffer.height, terminal.viewHeight);
      expect(terminal.buffer.lines[0].getText(), 'Hello');
    });
  });
}
