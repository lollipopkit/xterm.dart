import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
// The render object is not on the package's export surface, and should not be
// put on it to satisfy a test.
// ignore: implementation_imports
import 'package:xterm/src/ui/render.dart';
import 'package:xterm/xterm.dart';

// The selection highlight slides from where it was to where it is, instead of
// stepping a whole cell at a time as a dragged selection grows.
//
// Asserted through the tween rather than through pixels: what is drawn from it
// is one lerp, and reading a rect back out of a recorded picture would test
// the recorder more than the terminal.

void main() {
  testWidgets('growing a selection slides the highlight after it', (
    tester,
  ) async {
    final harness = await _pump(tester);

    final gesture = await tester.startGesture(
      harness.offsetOf(0),
      kind: PointerDeviceKind.mouse,
    );

    // The first move makes the selection; the second grows it, and that is
    // the one with somewhere to slide from.
    await gesture.moveTo(harness.offsetOf(3));
    await tester.pump();
    await gesture.moveTo(harness.offsetOf(6));
    await tester.pump();

    expect(
      harness.render.selectionFrom,
      isNotNull,
      reason: 'there is a selection to slide from',
    );
    expect(harness.render.selectionT, lessThan(1));

    // Long enough for the tween, which is 70ms.
    await tester.pump(const Duration(milliseconds: 100));
    expect(harness.render.selectionT, 1);

    await gesture.up();
    await tester.pump();
  });

  testWidgets('a selection made from nothing does not slide', (tester) async {
    // There is nowhere to come from, and sliding out of the last selection -
    // which may be a screen away - would be a streak across the terminal
    // rather than a selection appearing.
    final harness = await _pump(tester);

    final gesture = await tester.startGesture(
      harness.offsetOf(0),
      kind: PointerDeviceKind.mouse,
    );
    await gesture.moveTo(harness.offsetOf(3));
    await tester.pump();

    expect(harness.controller.selection, isNotNull);
    expect(harness.render.selectionFrom, isNull);
    expect(harness.render.selectionT, 1);

    await gesture.up();
    await tester.pump();
  });
}

Future<_Harness> _pump(WidgetTester tester) async {
  final terminal = Terminal(maxLines: 32);
  final controller = TerminalController();

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(body: TerminalView(terminal, controller: controller)),
    ),
  );
  await tester.pump();

  terminal.write('alpha beta gamma delta');
  await tester.pump();

  return _Harness(tester, terminal, controller);
}

class _Harness {
  _Harness(this.tester, this.terminal, this.controller);

  final WidgetTester tester;
  final Terminal terminal;
  final TerminalController controller;

  /// Through a set: `allRenderObjects` walks elements, and every element in
  /// the chain down to the terminal reports the same render object, so it
  /// comes back several times over.
  RenderTerminal get render =>
      tester.allRenderObjects.whereType<RenderTerminal>().toSet().single;

  Offset offsetOf(int column) {
    final topLeft = tester.getTopLeft(find.byType(TerminalView));
    final box = tester.renderObject(find.byType(TerminalView));
    final cellWidth = box.paintBounds.width / terminal.viewWidth;
    final cellHeight = box.paintBounds.height / terminal.viewHeight;
    return topLeft + Offset((column + 0.5) * cellWidth, 0.5 * cellHeight);
  }
}
