import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

  testWidgets('a triple click selects the line under it', (tester) async {
    final harness = await _pump(tester, 'alpha beta gamma');

    await harness.multiTapAt(8, 0, count: 3, kind: PointerDeviceKind.mouse);

    expect(harness.selectedText, 'alpha beta gamma');
  });

  testWidgets('a fourth click stays on the line', (tester) async {
    // Rather than cycling back to a word, which would make a run of clicks
    // depend on exactly how many got through.
    final harness = await _pump(tester, 'alpha beta gamma');

    await harness.multiTapAt(8, 0, count: 4, kind: PointerDeviceKind.mouse);

    expect(harness.selectedText, 'alpha beta gamma');
  });

  testWidgets('a triple click takes the whole of a wrapped line', (
    tester,
  ) async {
    // The rows a line wrapped over are one line of text, so all of them go.
    final harness = await _pump(tester, '');
    final width = harness.terminal.viewWidth;
    final content = 'w' * (width + 5);
    harness.terminal.write(content);
    await tester.pump();

    await harness.multiTapAt(2, 1, count: 3, kind: PointerDeviceKind.mouse);

    expect(harness.selectedText, content);
  });

  testWidgets('waiting between two clicks starts the run over', (tester) async {
    final harness = await _pump(tester, 'alpha beta gamma');

    await harness.tapAt(2, 0, kind: PointerDeviceKind.mouse);
    await harness.tapAt(2, 0, kind: PointerDeviceKind.mouse);

    // `tapAt` waits out kDoubleTapTimeout, so these are two first clicks.
    expect(harness.selectedText, anyOf(isNull, isEmpty));
  });

  testWidgets('clicking somewhere else starts the run over', (tester) async {
    final harness = await _pump(tester, 'alpha beta gamma');

    await harness.tapAt(2, 0, kind: PointerDeviceKind.mouse, settle: false);
    await harness.tapAt(14, 0, kind: PointerDeviceKind.mouse, settle: false);

    // Close in time but far apart, which is two clicks and not a double one.
    expect(harness.selectedText, anyOf(isNull, isEmpty));
  });

  testWidgets('shift clicking after the selection extends forwards', (
    tester,
  ) async {
    // Whole words, because the double click asked for words and shift
    // clicking goes on in whatever the run was taking. That is what a text
    // field on this platform does, and an editor, and it is the reason the
    // granularity is remembered past the gesture that set it.
    final harness = await _pump(tester, 'alpha beta gamma delta');

    await harness.doubleTapAt(8, 0, kind: PointerDeviceKind.mouse);
    expect(harness.selectedText, 'beta');

    await harness.shiftTapAt(19, 0);

    expect(harness.selectedText, 'beta gamma delta');
  });

  testWidgets('shift clicking before the selection extends backwards', (
    tester,
  ) async {
    final harness = await _pump(tester, 'alpha beta gamma delta');

    await harness.doubleTapAt(8, 0, kind: PointerDeviceKind.mouse);
    expect(harness.selectedText, 'beta');

    await harness.shiftTapAt(2, 0);

    expect(harness.selectedText, 'alpha beta');
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

  /// One click. [settle] waits out [kDoubleTapTimeout] afterwards, so the next
  /// one counts as a first click again; pass false to keep the run going.
  Future<void> tapAt(
    int column,
    int row, {
    required PointerDeviceKind kind,
    bool settle = true,
  }) async {
    final gesture = await tester.startGesture(offsetOf(column, row), kind: kind);
    await gesture.up();
    await tester.pump(
      settle
          ? kDoubleTapTimeout + const Duration(milliseconds: 1)
          : kDoubleTapMinTime,
    );
  }

  Future<void> doubleTapAt(
    int column,
    int row, {
    required PointerDeviceKind kind,
  }) {
    return multiTapAt(column, row, count: 2, kind: kind);
  }

  /// [count] clicks in the same place, close enough together in time to be one
  /// run of them.
  Future<void> multiTapAt(
    int column,
    int row, {
    required int count,
    required PointerDeviceKind kind,
  }) async {
    final position = offsetOf(column, row);

    for (var i = 0; i < count; i++) {
      final gesture = await tester.startGesture(position, kind: kind);
      await gesture.up();
      await tester.pump(
        i == count - 1
            ? kDoubleTapTimeout + const Duration(milliseconds: 1)
            : kDoubleTapMinTime,
      );
    }
  }

  Future<void> shiftTapAt(int column, int row) async {
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tapAt(column, row, kind: PointerDeviceKind.mouse);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump();
  }
}
