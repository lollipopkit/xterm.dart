import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xterm/xterm.dart';

// What a pointer does to the selection, asserted through the widget rather
// than through the gesture handler's internals: which cells end up selected is
// the whole observable, and it is what a change to the gesture wiring is
// allowed to move.

void main() {
  testWidgets('a double click selects the word under it', (tester) async {
    final harness = await _pump(tester, 'alpha beta gamma');

    await harness.doubleTapAt(2, 0, kind: PointerDeviceKind.mouse);

    expect(harness.selectedText, 'alpha');
  });

  testWidgets('a double tap selects the word under it', (tester) async {
    // The touch path already did this. It is here so that the two stay the
    // same thing rather than two implementations that agree today.
    final harness = await _pump(tester, 'alpha beta gamma');

    await harness.doubleTapAt(8, 0, kind: PointerDeviceKind.touch);

    expect(harness.selectedText, 'beta');
  });

  testWidgets('a single click selects nothing', (tester) async {
    final harness = await _pump(tester, 'alpha beta gamma');

    await harness.tapAt(2, 0, kind: PointerDeviceKind.mouse);

    expect(harness.selectedText, anyOf(isNull, isEmpty));
  });
}

Future<_Harness> _pump(WidgetTester tester, String content) async {
  final terminal = Terminal(maxLines: 32);
  final controller = TerminalController();

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: TerminalView(terminal, controller: controller),
      ),
    ),
  );
  await tester.pump();

  terminal.write(content);
  await tester.pump();

  return _Harness(tester, terminal, controller);
}

class _Harness {
  _Harness(this.tester, this.terminal, this.controller);

  final WidgetTester tester;
  final Terminal terminal;
  final TerminalController controller;

  String? get selectedText {
    final selection = controller.selection;
    if (selection == null) return null;
    return terminal.buffer.getText(selection).trim();
  }

  /// The centre of cell [column], [row] in global coordinates.
  Offset offsetOf(int column, int row) {
    final view = tester.getTopLeft(find.byType(TerminalView));
    final size = _cellSize;
    return view + Offset((column + 0.5) * size.width, (row + 0.5) * size.height);
  }

  /// Under `flutter test` every glyph is one identical box, so the cell is the
  /// character size of the default terminal style.
  Size get _cellSize {
    final render = tester.renderObject(find.byType(TerminalView));
    final width = render.paintBounds.width / terminal.viewWidth;
    final height = render.paintBounds.height / terminal.viewHeight;
    return Size(width, height);
  }

  Future<void> tapAt(int column, int row, {required PointerDeviceKind kind}) async {
    final gesture = await tester.startGesture(offsetOf(column, row), kind: kind);
    await gesture.up();
    await tester.pump(kDoubleTapTimeout + const Duration(milliseconds: 1));
  }

  Future<void> doubleTapAt(
    int column,
    int row, {
    required PointerDeviceKind kind,
  }) async {
    final position = offsetOf(column, row);

    var gesture = await tester.startGesture(position, kind: kind);
    await gesture.up();
    await tester.pump(kDoubleTapMinTime);

    gesture = await tester.startGesture(position, kind: kind);
    await gesture.up();
    await tester.pump(kDoubleTapTimeout + const Duration(milliseconds: 1));
  }
}
