import 'package:test/test.dart';
import 'package:xterm/src/core/input/keytab/keytab.dart';
import 'package:xterm/xterm.dart';

void main() {
  group('defaultInputHandler', () {
    test('supports numpad enter', () {
      final output = <String>[];
      final terminal = Terminal(onOutput: output.add);
      terminal.keyInput(TerminalKey.numpadEnter);
      expect(output, ['\r']);
    });
  });

  group('KeytabInputHandler', () {
    test('can insert modifier code', () {
      final handler = KeytabInputHandler(
        Keytab.parse(r'key Home +AnyMod : "\E[1;*H"'),
      );

      final terminal = Terminal(inputHandler: handler);

      late String output;

      terminal.onOutput = (data) {
        output = data;
      };

      terminal.keyInput(TerminalKey.home, ctrl: true);

      expect(output, '\x1b[1;5H');

      terminal.keyInput(TerminalKey.home, shift: true);

      expect(output, '\x1b[1;2H');
    });

    test('uses VT52 mappings when ANSI mode is disabled', () {
      final outputs = <String>[];
      final terminal = Terminal(onOutput: outputs.add);

      terminal.keyInput(TerminalKey.arrowUp);
      expect(outputs.removeLast(), '\x1b[A');

      terminal.write('\x1b[?2l'); // DECANM reset -> enter VT52 mode.

      terminal.keyInput(TerminalKey.arrowUp);
      expect(outputs.removeLast(), '\x1bA');

      terminal.write('\x1b[?2h'); // DECANM set -> return to ANSI.

      terminal.keyInput(TerminalKey.arrowUp);
      expect(outputs.removeLast(), '\x1b[A');
    });
  });
}
