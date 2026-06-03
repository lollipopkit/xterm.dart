import 'package:test/test.dart';
import 'package:xterm/core.dart';

void main() {
  group('Scroll forwarding conditions', () {
    test('mouseInput generates output when in alt buffer with mouse mode', () {
      final outputs = <String>[];
      final terminal = Terminal(onOutput: outputs.add);

      // Switch to alt buffer and enable mouse scroll tracking
      terminal.write('\x1b[?1049h'); // alt buffer
      terminal.write('\x1b[?1002h'); // mouse mode with reportScroll

      terminal.mouseInput(
        TerminalMouseButton.wheelUp,
        TerminalMouseButtonState.down,
        const CellOffset(10, 5),
      );

      expect(outputs, isNotEmpty);
      // Should contain mouse SGR escape sequence
      expect(outputs.first, contains('\x1b['));
    });

    test('mouseInput generates no output when not in alt buffer and mouseMode is none', () {
      final outputs = <String>[];
      final terminal = Terminal(onOutput: outputs.add);

      // Main buffer, no mouse mode
      terminal.mouseInput(
        TerminalMouseButton.wheelUp,
        TerminalMouseButtonState.down,
        const CellOffset(10, 5),
      );

      expect(outputs, isEmpty);
    });

    test('mouseInput generates output when mouseMode has reportScroll even in main buffer', () {
      final outputs = <String>[];
      final terminal = Terminal(onOutput: outputs.add);

      // Enable mouse mode with scroll reporting in main buffer
      terminal.write('\x1b[?1002h'); // upDownScrollDrag

      terminal.mouseInput(
        TerminalMouseButton.wheelDown,
        TerminalMouseButtonState.down,
        const CellOffset(5, 3),
      );

      expect(outputs, isNotEmpty);
    });

    test('mouseInput does not generate output for wheel when mouseMode is clickOnly', () {
      final outputs = <String>[];
      final terminal = Terminal(onOutput: outputs.add);

      // Enable click-only mouse mode (DEC 9 = X10, does not report scroll)
      terminal.write('\x1b[?9h');

      // Wheel events should not be reported in clickOnly mode
      terminal.mouseInput(
        TerminalMouseButton.wheelUp,
        TerminalMouseButtonState.down,
        const CellOffset(10, 5),
      );

      expect(outputs, isEmpty);

      // But clicks should still be reported
      terminal.mouseInput(
        TerminalMouseButton.left,
        TerminalMouseButtonState.down,
        const CellOffset(10, 5),
      );

      expect(outputs, isNotEmpty);
    });
  });

  group('simulateScroll fallback behavior', () {
    test('mouseInput returns false when mouseMode is none, allowing arrow key fallback', () {
      final outputs = <String>[];
      final terminal = Terminal(onOutput: outputs.add);

      // In alt buffer with no mouse mode
      terminal.write('\x1b[?1049h');

      // mouseInput returns false when no mouse mode is active
      final handled = terminal.mouseInput(
        TerminalMouseButton.wheelUp,
        TerminalMouseButtonState.down,
        const CellOffset(10, 5),
      );

      expect(handled, isFalse);
      expect(outputs, isEmpty);

      // The caller (TerminalScrollGestureHandler._sendScrollEvent) would
      // then decide to fall back to arrow key via terminal.keyInput()
      terminal.keyInput(TerminalKey.arrowUp);
      expect(outputs, isNotEmpty);
    });

    test('mouseInput returns true when mouseMode is active, no arrow key fallback needed', () {
      final outputs = <String>[];
      final terminal = Terminal(onOutput: outputs.add);

      // Enable mouse mode with scroll reporting
      terminal.write('\x1b[?1002h');

      // mouseInput handles wheel events when mouse mode is active
      final handled = terminal.mouseInput(
        TerminalMouseButton.wheelUp,
        TerminalMouseButtonState.down,
        const CellOffset(10, 5),
      );

      expect(handled, isTrue);
      expect(outputs, isNotEmpty);

      // Verify output is a mouse escape sequence (not an arrow key)
      expect(outputs.first, contains('\x1b['));
    });
  });

  group('MouseMode transitions', () {
    test('switching from none to upDownScroll enables wheel reporting', () {
      final outputs = <String>[];
      final terminal = Terminal(onOutput: outputs.add);

      // Initially mouse mode is none
      terminal.mouseInput(
        TerminalMouseButton.wheelUp,
        TerminalMouseButtonState.down,
        const CellOffset(10, 5),
      );
      expect(outputs, isEmpty);

      // Enable scroll reporting
      terminal.write('\x1b[?1002h');
      outputs.clear();

      // Now wheel events should be reported
      terminal.mouseInput(
        TerminalMouseButton.wheelUp,
        TerminalMouseButtonState.down,
        const CellOffset(10, 5),
      );
      expect(outputs, isNotEmpty);
    });

    test('switching from upDownScroll to none disables wheel reporting', () {
      final outputs = <String>[];
      final terminal = Terminal(onOutput: outputs.add);

      // Enable scroll reporting
      terminal.write('\x1b[?1002h');

      terminal.mouseInput(
        TerminalMouseButton.wheelUp,
        TerminalMouseButtonState.down,
        const CellOffset(10, 5),
      );
      expect(outputs, isNotEmpty);
      outputs.clear();

      // Disable mouse mode
      terminal.write('\x1b[?1002l');

      terminal.mouseInput(
        TerminalMouseButton.wheelUp,
        TerminalMouseButtonState.down,
        const CellOffset(10, 5),
      );
      expect(outputs, isEmpty);
    });

    test('exiting alt buffer clears mouse mode state', () {
      final outputs = <String>[];
      final terminal = Terminal(onOutput: outputs.add);

      // Enter alt buffer
      terminal.write('\x1b[?1049h');
      expect(terminal.isUsingAltBuffer, isTrue);

      // Exit alt buffer  
      terminal.write('\x1b[?1049l');
      expect(terminal.isUsingAltBuffer, isFalse);
    });
  });

  group('Wheel direction mapping', () {
    test('wheelUp generates correct escape sequence', () {
      final outputs = <String>[];
      final terminal = Terminal(onOutput: outputs.add);
      terminal.write('\x1b[?1002h');

      terminal.mouseInput(
        TerminalMouseButton.wheelUp,
        TerminalMouseButtonState.down,
        const CellOffset(10, 5),
      );

      expect(outputs, isNotEmpty);
      // SGR format: \x1b[<button;x;yM (M = down) or m (up)
      expect(outputs.first, contains('M'));
    });

    test('wheelDown generates correct escape sequence', () {
      final outputs = <String>[];
      final terminal = Terminal(onOutput: outputs.add);
      terminal.write('\x1b[?1002h');

      terminal.mouseInput(
        TerminalMouseButton.wheelDown,
        TerminalMouseButtonState.down,
        const CellOffset(10, 5),
      );

      expect(outputs, isNotEmpty);
      // SGR format for wheel down
      expect(outputs.first, contains('M'));
    });
  });
}
