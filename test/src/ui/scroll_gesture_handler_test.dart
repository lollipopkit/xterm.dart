import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xterm/core.dart';
import 'package:xterm/src/ui/scroll_handler.dart';

void main() {
  group('TerminalScrollGestureHandler', () {
    testWidgets('reports SGR wheel up with button 64', (tester) async {
      final outputs = <String>[];
      final terminal = Terminal(onOutput: outputs.add);
      terminal.resize(20, 10);
      terminal.write('\x1b[?1049h');
      terminal.write('\x1b[?1002h');
      terminal.write('\x1b[?1006h');

      await tester.pumpWidget(_ScrollHarness(terminal: terminal));

      await tester.sendEventToBinding(
        const PointerScrollEvent(
          position: Offset(50, 50),
          scrollDelta: Offset(0, -20),
        ),
      );

      expect(outputs, contains('\x1b[<64;6;6M'));
    });

    testWidgets('click-only mouse mode falls back to simulated scroll', (
      tester,
    ) async {
      final outputs = <String>[];
      final terminal = Terminal(onOutput: outputs.add);
      terminal.resize(20, 10);
      terminal.write('\x1b[?1049h');
      terminal.write('\x1b[?9h');

      await tester.pumpWidget(_ScrollHarness(terminal: terminal));

      await tester.sendEventToBinding(
        const PointerScrollEvent(
          position: Offset(50, 50),
          scrollDelta: Offset(0, -20),
        ),
      );

      expect(outputs, contains('\x1b[A'));
    });

    testWidgets('touch drag up reports wheel down for natural scrolling', (
      tester,
    ) async {
      final outputs = <String>[];
      final terminal = Terminal(onOutput: outputs.add);
      terminal.resize(20, 10);
      terminal.write('\x1b[?1049h');
      terminal.write('\x1b[?1002h');
      terminal.write('\x1b[?1006h');

      await tester.pumpWidget(_ScrollHarness(terminal: terminal));

      final gesture = await tester.startGesture(
        const Offset(50, 50),
        kind: PointerDeviceKind.touch,
      );
      await gesture.moveTo(const Offset(50, 10));
      await gesture.up();

      expect(outputs, contains('\x1b[<65;6;2M'));
    });
  });
}

class _ScrollHarness extends StatelessWidget {
  const _ScrollHarness({required this.terminal});

  final Terminal terminal;

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.ltr,
      child: TerminalScrollGestureHandler(
        terminal: terminal,
        getCellOffset: (offset) => CellOffset(offset.dx ~/ 10, offset.dy ~/ 10),
        getLineHeight: () => 10,
        child: const ColoredBox(
          color: Color(0xff000000),
          child: SizedBox(width: 100, height: 100),
        ),
      ),
    );
  }
}
