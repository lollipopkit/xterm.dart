import 'package:flutter/gestures.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xterm/xterm.dart';

// What a mouse sends to a program that turned a mouse mode on, and what it
// still does to the selection here.

void main() {
  testWidgets('a drag in mode 1002 is reported to the program', (tester) async {
    final harness = await _pump(tester, '\x1b[?1049h\x1b[?1002h\x1b[?1006h');

    final gesture = await harness.press(1, 1);
    await gesture.moveTo(harness.offsetOf(4, 2));
    await tester.pump();
    await gesture.up();
    await tester.pump(kDoubleTapTimeout);

    expect(harness.output, ['\x1b[<0;2;2M', '\x1b[<32;5;3M', '\x1b[<0;5;3m']);
    expect(harness.controller.selection, isNull);
  });

  testWidgets('a move within one cell is not reported', (tester) async {
    final harness = await _pump(tester, '\x1b[?1049h\x1b[?1002h\x1b[?1006h');

    final gesture = await harness.press(1, 1);
    await gesture.moveBy(const Offset(1, 0));
    await tester.pump();
    await gesture.up();
    await tester.pump(kDoubleTapTimeout);

    expect(harness.output, ['\x1b[<0;2;2M', '\x1b[<0;2;2m']);
  });

  testWidgets('a hover is reported in mode 1003 only', (tester) async {
    final harness = await _pump(tester, '\x1b[?1049h\x1b[?1002h\x1b[?1006h');
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: harness.offsetOf(0, 0));
    await mouse.moveTo(harness.offsetOf(3, 0));
    await tester.pump();
    expect(harness.output, isEmpty);

    harness.terminal.write('\x1b[?1003h');
    await mouse.moveTo(harness.offsetOf(6, 1));
    await tester.pump();
    expect(harness.output, ['\x1b[<35;7;2M']);
    await mouse.removePointer();
  });

  testWidgets('a right click goes to the program', (tester) async {
    final harness = await _pump(tester, '\x1b[?1049h\x1b[?1000h\x1b[?1006h');

    final gesture = await harness.press(2, 0, buttons: kSecondaryMouseButton);
    await gesture.up();
    await tester.pump(kDoubleTapTimeout);

    expect(harness.output, ['\x1b[<2;3;1M', '\x1b[<2;3;1m']);
  });

  testWidgets('a click is reported once', (tester) async {
    final harness = await _pump(tester, '\x1b[?1049h\x1b[?1000h');

    final gesture = await harness.press(0, 0);
    await gesture.up();
    await tester.pump(kDoubleTapTimeout);

    expect(harness.output, ['\x1b[M !!', '\x1b[M#!!']);
  });

  testWidgets('a touch tap is reported once', (tester) async {
    final harness = await _pump(tester, '\x1b[?1049h\x1b[?1000h\x1b[?1006h');

    final gesture = await harness.press(0, 0, kind: PointerDeviceKind.touch);
    await gesture.up();
    await tester.pump(kDoubleTapTimeout);

    expect(harness.output, ['\x1b[<0;1;1M', '\x1b[<0;1;1m']);
  });

  testWidgets('shift keeps the drag here, as a selection', (tester) async {
    final harness = await _pump(tester, '\x1b[?1002h\x1b[?1006halpha beta');

    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    final gesture = await harness.press(0, 0);
    await gesture.moveTo(harness.offsetOf(5, 0));
    await tester.pump();
    await gesture.up();
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump(kDoubleTapTimeout);

    expect(harness.output, isEmpty);
    expect(harness.selectedText, 'alpha');
  });

  testWidgets('a row below the scrollback is counted from the screen', (
    tester,
  ) async {
    final harness = await _pump(tester, '');
    harness.terminal.write('line\r\n' * (harness.terminal.viewHeight * 2));
    harness.terminal.write('\x1b[?1000h\x1b[?1006h');
    await tester.pump();

    final row = harness.terminal.viewHeight - 1;
    final gesture = await harness.press(0, row);
    await gesture.up();
    await tester.pump(kDoubleTapTimeout);

    expect(harness.output.first, '\x1b[<0;1;${row + 1}M');
  });

  testWidgets('a shift click is not reported', (tester) async {
    final harness = await _pump(tester, '\x1b[?1049h\x1b[?1000h\x1b[?1006h');

    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    final gesture = await harness.press(2, 1);
    await tester.pump(const Duration(milliseconds: 100));
    await gesture.up();
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump(kDoubleTapTimeout);

    expect(harness.output, isEmpty);
  });

  testWidgets('a right click on the selection stays with the host', (
    tester,
  ) async {
    var secondaryTaps = 0;
    final harness = await _pump(
      tester,
      '\x1b[?1000h\x1b[?1006halpha beta',
      onSecondaryTapUp: () => secondaryTaps++,
    );

    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    final drag = await harness.press(0, 0);
    await drag.moveTo(harness.offsetOf(5, 0));
    await tester.pump();
    await drag.up();
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump(kDoubleTapTimeout);
    expect(harness.selectedText, 'alpha');

    final click = await harness.press(2, 0, buttons: kSecondaryMouseButton);
    await click.up();
    await tester.pump(kDoubleTapTimeout);

    expect(harness.output, isEmpty);
    expect(secondaryTaps, 1);
    expect(harness.selectedText, 'alpha');
  });

  testWidgets('a right click on a selection handle does not grab it', (
    tester,
  ) async {
    var secondaryTaps = 0;
    final harness = await _pump(
      tester,
      'alpha beta',
      onSecondaryTapUp: () => secondaryTaps++,
    );

    final drag = await harness.press(0, 0);
    await drag.moveTo(harness.offsetOf(5, 0));
    await tester.pump();
    await drag.up();
    await tester.pump(kDoubleTapTimeout);

    final handle = find.descendant(
      of: find.byType(TerminalView),
      matching: find.byType(Positioned),
    );
    expect(handle, findsNWidgets(2));
    final click = await tester.startGesture(
      tester.getCenter(handle.last),
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryMouseButton,
    );
    await click.up();
    await tester.pump(kDoubleTapTimeout);

    expect(secondaryTaps, 1);
    expect(harness.selectedText, 'alpha');
  });

  testWidgets('ctrl is carried in the report', (tester) async {
    final harness = await _pump(tester, '\x1b[?1049h\x1b[?1000h\x1b[?1006h');

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    final gesture = await harness.press(0, 0);
    await gesture.up();
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump(kDoubleTapTimeout);

    expect(harness.output, ['\x1b[<16;1;1M', '\x1b[<16;1;1m']);
  });

  testWidgets('a drag released above the screen is still released', (
    tester,
  ) async {
    final harness = await _pump(tester, '');
    harness.terminal.write('line\r\n' * (harness.terminal.viewHeight * 2));
    harness.terminal.write('\x1b[?1002h\x1b[?1006h');
    await tester.pump();

    final gesture = await harness.press(3, 2);
    await gesture.moveTo(harness.offsetOf(3, 0) - const Offset(0, 40));
    await tester.pump();
    await gesture.up();
    await tester.pump(kDoubleTapTimeout);

    expect(harness.output, ['\x1b[<0;4;3M', '\x1b[<32;4;1M', '\x1b[<0;4;1m']);
  });

  testWidgets('a touch double tap sends no release without its press', (
    tester,
  ) async {
    final harness = await _pump(tester, '\x1b[?1000h\x1b[?1006halpha beta');

    for (var i = 0; i < 2; i++) {
      final tap = await harness.press(1, 0, kind: PointerDeviceKind.touch);
      await tap.up();
      await tester.pump(kDoubleTapMinTime);
    }
    await tester.pump(kDoubleTapTimeout);

    final presses = harness.output.where((o) => o.endsWith('M')).length;
    final releases = harness.output.where((o) => o.endsWith('m')).length;
    expect(releases, presses);
  });

  testWidgets('a touch while the button is held does not lose the release', (
    tester,
  ) async {
    final harness = await _pump(tester, '\x1b[?1049h\x1b[?1002h\x1b[?1006h');

    final mouse = await harness.press(1, 1);
    final finger = await harness.press(8, 4, kind: PointerDeviceKind.touch);
    await finger.up();
    await mouse.up();
    await tester.pump(kDoubleTapTimeout);

    expect(harness.output.first, '\x1b[<0;2;2M');
    expect(harness.output.last, '\x1b[<0;2;2m');
  });

  testWidgets('alt drags out a rectangle', (tester) async {
    final harness = await _pump(tester, 'abcdef\r\nghijkl\r\nmnopqr');

    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    final gesture = await harness.press(4, 0);
    await gesture.moveTo(harness.offsetOf(1, 2));
    await tester.pump();
    await gesture.up();
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    await tester.pump(kDoubleTapTimeout);

    expect(harness.controller.selectionMode, SelectionMode.block);
    expect(harness.selectedText, 'bcd\nhij\nnop');

    // And without alt, a run of text again.
    final next = await harness.press(0, 0);
    await next.moveTo(harness.offsetOf(2, 1));
    await tester.pump();
    await next.up();
    await tester.pump(kDoubleTapTimeout);

    expect(harness.controller.selectionMode, SelectionMode.line);
  });
}

Future<_Harness> _pump(
  WidgetTester tester,
  String content, {
  VoidCallback? onSecondaryTapUp,
}) async {
  final output = <String>[];
  final terminal = Terminal(maxLines: 64, onOutput: output.add);
  final controller = TerminalController();

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: TerminalView(
          terminal,
          controller: controller,
          onSecondaryTapUp: onSecondaryTapUp == null
              ? null
              : (_, _) => onSecondaryTapUp(),
        ),
      ),
    ),
  );
  await tester.pump();

  terminal.write(content);
  await tester.pump();

  return _Harness(tester, terminal, controller, output);
}

class _Harness {
  _Harness(this.tester, this.terminal, this.controller, this.output);

  final WidgetTester tester;
  final Terminal terminal;
  final TerminalController controller;
  final List<String> output;

  String? get selectedText {
    final selection = controller.selection;
    if (selection == null) return null;
    return terminal.buffer.getText(selection).trim();
  }

  Offset offsetOf(int column, int row) {
    final view = tester.getTopLeft(find.byType(TerminalView));
    final render = tester.renderObject(find.byType(TerminalView));
    final width = render.paintBounds.width / terminal.viewWidth;
    final height = render.paintBounds.height / terminal.viewHeight;
    return view + Offset((column + 0.5) * width, (row + 0.5) * height);
  }

  Future<TestGesture> press(
    int column,
    int row, {
    PointerDeviceKind kind = PointerDeviceKind.mouse,
    int buttons = kPrimaryMouseButton,
  }) {
    return tester.startGesture(
      offsetOf(column, row),
      kind: kind,
      buttons: buttons,
    );
  }
}
