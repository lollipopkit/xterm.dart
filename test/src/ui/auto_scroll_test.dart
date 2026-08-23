import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xterm/xterm.dart';

// A selection dragged to the edge of the view and held there.
//
// The pointer stops sending events the moment it stops moving, so anything
// driven by them scrolls once and stops - which is what this used to do, and
// what made selecting more than a screenful mean dragging out and back in over
// and over. A ticker keeps going while the pointer is held, and these are the
// two halves of that: it goes on without further events, and it stops on
// release rather than running on.
//
// Driven through the long press. A mouse drag is deliverable in a widget test
// and test/src/ui/selection_gesture_test.dart does deliver one, but only along
// a row: this needs a drag to the top edge, and a vertical one is taken by the
// scrollable inside the view before the selection ever sees it.

void main() {
  testWidgets('a drag held at the top edge goes on scrolling', (tester) async {
    final harness = await _pump(tester);

    final gesture = await harness.longPressAtRow(4);
    final started = harness.selectionTop;

    await harness.dragToTopEdge(gesture);
    final afterFirstMove = harness.selectionTop;

    // Nothing moves the pointer from here on. Only the ticker is running.
    //
    // The first tick is the clock the rest are measured against and moves
    // nothing, so it is spent before anything is read.
    await tester.pump(const Duration(milliseconds: 16));
    final beforeWaiting = harness.selectionTop;

    await tester.pump(const Duration(milliseconds: 100));
    final afterWaiting = harness.selectionTop;

    await tester.pump(const Duration(milliseconds: 100));
    final afterWaitingLonger = harness.selectionTop;

    await gesture.up();
    await tester.pump();

    expect(afterFirstMove, lessThan(started));
    expect(afterWaiting, lessThan(beforeWaiting));
    expect(afterWaitingLonger, lessThan(afterWaiting));
  });

  testWidgets('the scrolling stops when the pointer goes up', (tester) async {
    final harness = await _pump(tester);

    final gesture = await harness.longPressAtRow(4);
    await harness.dragToTopEdge(gesture);

    await tester.pump(const Duration(milliseconds: 16));
    final beforeWaiting = harness.selectionTop;
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));

    // Or the rest of this would hold however dead the ticker was.
    expect(harness.selectionTop, lessThan(beforeWaiting));

    await gesture.up();
    await tester.pump();

    final atRelease = harness.selectionTop;
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));

    expect(harness.selectionTop, atRelease);
  });

  testWidgets('a drag that stays inside the view does not scroll', (
    tester,
  ) async {
    // The band that starts it is a few lines deep at the edge, not the whole
    // view, or a selection could not be dragged across one without running.
    final harness = await _pump(tester);

    final gesture = await harness.longPressAtRow(10);
    final started = harness.selectionTop;

    await gesture.moveTo(harness.offsetOfRow(8));
    await tester.pump();
    final afterMove = harness.selectionTop;

    await tester.pump(const Duration(milliseconds: 200));

    expect(harness.selectionTop, afterMove);
    expect(afterMove, lessThan(started));

    await gesture.up();
    await tester.pump();
  });
}

Future<_Harness> _pump(WidgetTester tester) async {
  final terminal = Terminal(maxLines: 400);
  final controller = TerminalController();

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(body: TerminalView(terminal, controller: controller)),
    ),
  );
  await tester.pump();

  // Enough scrollback that there is somewhere to go. The view sits at the
  // bottom of it, so the room is above.
  for (var i = 0; i < 300; i++) {
    terminal.write('line $i\r\n');
  }
  await tester.pump();

  return _Harness(tester, terminal, controller);
}

class _Harness {
  _Harness(this.tester, this.terminal, this.controller);

  final WidgetTester tester;
  final Terminal terminal;
  final TerminalController controller;

  /// The first buffer row the selection covers. It rises as the view scrolls
  /// up under a pointer that is not moving.
  int get selectionTop => controller.selection!.normalized.begin.y;

  Rect get _viewRect => tester.getRect(find.byType(TerminalView));

  double get _lineHeight => _viewRect.height / terminal.viewHeight;

  Offset offsetOfRow(int row) {
    return Offset(_viewRect.center.dx, _viewRect.top + (row + 0.5) * _lineHeight);
  }

  Future<TestGesture> longPressAtRow(int row) async {
    final gesture = await tester.startGesture(
      offsetOfRow(row),
      kind: PointerDeviceKind.touch,
    );
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 1));
    return gesture;
  }

  /// Moves onto the top edge and leaves the pointer there.
  Future<void> dragToTopEdge(TestGesture gesture) async {
    await gesture.moveTo(Offset(_viewRect.center.dx, _viewRect.top + 1));
    await tester.pump();
  }
}
