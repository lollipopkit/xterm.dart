import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xterm/core.dart';
import 'package:xterm/src/ui/scroll_handler.dart';

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

    test(
      'mouseInput generates no output when not in alt buffer and mouseMode is none',
      () {
        final outputs = <String>[];
        final terminal = Terminal(onOutput: outputs.add);

        // Main buffer, no mouse mode
        terminal.mouseInput(
          TerminalMouseButton.wheelUp,
          TerminalMouseButtonState.down,
          const CellOffset(10, 5),
        );

        expect(outputs, isEmpty);
      },
    );

    test(
      'mouseInput generates output when mouseMode has reportScroll even in main buffer',
      () {
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
      },
    );

    test(
      'mouseInput does not generate output for wheel when mouseMode is clickOnly',
      () {
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
      },
    );
  });

  group('simulateScroll fallback behavior', () {
    test(
      'mouseInput returns false when mouseMode is none, allowing arrow key fallback',
      () {
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
      },
    );

    test(
      'mouseInput returns true when mouseMode is active, no arrow key fallback needed',
      () {
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
      },
    );
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

  group('TerminalScrollGestureHandler listener forwarding', () {
    testWidgets('returns child unchanged when scroll should not be forwarded', (
      tester,
    ) async {
      final terminal = Terminal()..resize(20, 10);

      await tester.pumpWidget(_ScrollHarness(terminal: terminal));

      expect(find.byType(Listener), findsNothing);
      expect(find.byType(ColoredBox), findsOneWidget);
    });

    testWidgets('main buffer reportScroll mode forwards listener scroll', (
      tester,
    ) async {
      final outputs = <String>[];
      final terminal = Terminal(onOutput: outputs.add)..resize(20, 10);
      terminal.write('\x1b[?1002h');
      terminal.write('\x1b[?1006h');

      await tester.pumpWidget(_ScrollHarness(terminal: terminal));

      await tester.sendEventToBinding(
        const PointerScrollEvent(
          position: Offset(50, 50),
          scrollDelta: Offset(0, -10),
        ),
      );

      expect(outputs, contains('\x1b[<64;6;6M'));
    });

    testWidgets('pointer scroll emits same SGR wheel buttons as mouseInput', (
      tester,
    ) async {
      final outputs = <String>[];
      final terminal = _sgrScrollTerminal(outputs);

      await tester.pumpWidget(_ScrollHarness(terminal: terminal));

      await tester.sendEventToBinding(
        const PointerScrollEvent(
          position: Offset(50, 50),
          scrollDelta: Offset(0, -10),
        ),
      );

      expect(outputs, contains('\x1b[<64;6;6M'));
      outputs.clear();

      await tester.sendEventToBinding(
        const PointerScrollEvent(
          position: Offset(50, 50),
          scrollDelta: Offset(0, 10),
        ),
      );

      expect(outputs, contains('\x1b[<65;6;6M'));
    });

    testWidgets('simulateScroll falls back to arrow keys from pointer scroll', (
      tester,
    ) async {
      final outputs = <String>[];
      final terminal = Terminal(onOutput: outputs.add)..resize(20, 10);
      terminal.write('\x1b[?1049h');

      await tester.pumpWidget(_ScrollHarness(terminal: terminal));

      await tester.sendEventToBinding(
        const PointerScrollEvent(
          position: Offset(50, 50),
          scrollDelta: Offset(0, -10),
        ),
      );

      expect(outputs, contains('\x1b[A'));
    });

    testWidgets('terminal state updates rebuild the forwarding listener', (
      tester,
    ) async {
      final outputs = <String>[];
      final terminal = Terminal(onOutput: outputs.add)..resize(20, 10);

      await tester.pumpWidget(_ScrollHarness(terminal: terminal));
      expect(find.byType(Listener), findsNothing);

      terminal.write('\x1b[?1049h');
      await tester.pump();

      expect(find.byType(Listener), findsOneWidget);

      await tester.sendEventToBinding(
        const PointerScrollEvent(
          position: Offset(50, 50),
          scrollDelta: Offset(0, -10),
        ),
      );

      expect(outputs, contains('\x1b[A'));
    });

    testWidgets('didUpdateWidget listens to the replacement terminal', (
      tester,
    ) async {
      final firstOutputs = <String>[];
      final secondOutputs = <String>[];
      final firstTerminal = Terminal(onOutput: firstOutputs.add)
        ..resize(20, 10);
      final secondTerminal = Terminal(onOutput: secondOutputs.add)
        ..resize(20, 10);

      await tester.pumpWidget(_ScrollHarness(terminal: firstTerminal));
      await tester.pumpWidget(_ScrollHarness(terminal: secondTerminal));

      firstTerminal.write('\x1b[?1049h');
      await tester.pump();
      expect(find.byType(Listener), findsNothing);

      secondTerminal.write('\x1b[?1049h');
      await tester.pump();
      expect(find.byType(Listener), findsOneWidget);

      await tester.sendEventToBinding(
        const PointerScrollEvent(
          position: Offset(50, 50),
          scrollDelta: Offset(0, -10),
        ),
      );

      expect(firstOutputs, isEmpty);
      expect(secondOutputs, contains('\x1b[A'));
    });

    testWidgets('simulateScroll false suppresses pointer scroll fallback', (
      tester,
    ) async {
      final outputs = <String>[];
      final terminal = Terminal(onOutput: outputs.add)..resize(20, 10);
      terminal.write('\x1b[?1049h');

      await tester.pumpWidget(
        _ScrollHarness(terminal: terminal, simulateScroll: false),
      );

      await tester.sendEventToBinding(
        const PointerScrollEvent(
          position: Offset(50, 50),
          scrollDelta: Offset(0, -10),
        ),
      );

      expect(outputs, isEmpty);
    });

    testWidgets('touch drag scrolls but mouse drag does not', (tester) async {
      final outputs = <String>[];
      final terminal = _sgrScrollTerminal(outputs);

      await tester.pumpWidget(_ScrollHarness(terminal: terminal));

      final mouseGesture = await tester.startGesture(
        const Offset(50, 50),
        kind: PointerDeviceKind.mouse,
      );
      await mouseGesture.moveTo(const Offset(50, 10));
      await mouseGesture.up();

      expect(outputs, isEmpty);

      final touchGesture = await tester.startGesture(
        const Offset(50, 50),
        kind: PointerDeviceKind.touch,
      );
      await touchGesture.moveTo(const Offset(50, 10));
      await touchGesture.up();

      expect(outputs, contains('\x1b[<65;6;2M'));
    });

    testWidgets('pointer cancel clears pending touch drag', (tester) async {
      final outputs = <String>[];
      final terminal = _sgrScrollTerminal(outputs);

      await tester.pumpWidget(_ScrollHarness(terminal: terminal));

      final gesture = await tester.startGesture(
        const Offset(50, 50),
        kind: PointerDeviceKind.touch,
      );
      await gesture.cancel();
      await tester.sendEventToBinding(
        const PointerMoveEvent(
          pointer: 1,
          position: Offset(50, 10),
          kind: PointerDeviceKind.touch,
        ),
      );

      expect(outputs, isEmpty);
    });
  });
}

Terminal _sgrScrollTerminal(List<String> outputs) {
  final terminal = Terminal(onOutput: outputs.add)..resize(20, 10);
  terminal.write('\x1b[?1049h');
  terminal.write('\x1b[?1002h');
  terminal.write('\x1b[?1006h');
  return terminal;
}

class _ScrollHarness extends StatelessWidget {
  const _ScrollHarness({required this.terminal, this.simulateScroll = true});

  final Terminal terminal;
  final bool simulateScroll;

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.ltr,
      child: TerminalScrollGestureHandler(
        terminal: terminal,
        getCellOffset: (offset) => CellOffset(offset.dx ~/ 10, offset.dy ~/ 10),
        getLineHeight: () => 10,
        simulateScroll: simulateScroll,
        child: const ColoredBox(
          color: Color(0xff000000),
          child: SizedBox(width: 100, height: 100),
        ),
      ),
    );
  }
}
