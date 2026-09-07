// The editable rect goes to the engine as JSON, and JSON has no NaN.
//
// A non-finite one throws `JsonUnsupportedObjectError` inside the platform
// channel, from a timer callback with nothing above it to catch it. It has been
// seen on a device, arriving through `Terminal.write` on a session flush, so
// `RenderTerminal._notifyEditableRect` refuses to send one.
//
// **Why the geometry goes non-finite is not known**, and this file is where
// that is recorded rather than guessed at. The three shapes that looked likely
// are checked below and every one of them stays finite, so none of them is the
// cause — which is worth knowing next time it is chased. The guard is a
// mitigation: it turns an uncatchable throw into one skipped update.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xterm/src/ui/render.dart';
import 'package:xterm/xterm.dart';

Widget _plain(Widget child) => child;
Widget _offstage(Widget child) => Offstage(offstage: true, child: child);
Widget _zeroBox(Widget child) => SizedBox.shrink(child: child);
Widget _scaledAway(Widget child) => Transform.scale(scale: 0, child: child);

void main() {
  /// Every `RenderTerminal` in the tree, of which `TerminalView` builds more
  /// than one — its own render object is the scroll view's, not the terminal's.
  Future<(Terminal, List<RenderTerminal>)> pump(
    WidgetTester tester,
    Widget Function(Widget child) wrap,
  ) async {
    final terminal = Terminal(maxLines: 100);
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: wrap(TerminalView(terminal)))),
    );
    await tester.pump();
    final renders = tester.allRenderObjects.whereType<RenderTerminal>().toList();
    expect(renders, isNotEmpty);
    addTearDown(() => tester.pumpWidget(const SizedBox.shrink()));
    return (terminal, renders);
  }

  /// What the guard is for. None of these reproduces it — recorded so the next
  /// attempt does not start here — but a write must not throw in any of them
  /// either, which is what this asserts.
  const shapes = <String, Widget Function(Widget)>{
    'on screen': _plain,
    'offstage': _offstage,
    'a zero-size box': _zeroBox,
    'an ancestor at scale zero': _scaledAway,
  };

  shapes.forEach((name, wrap) {
    testWidgets('$name: the geometry stays finite and a write does not throw', (
      tester,
    ) async {
      final (terminal, renders) = await pump(tester, wrap);

      for (final render in renders) {
        expect(
          render.localToGlobal(Offset.zero).isFinite,
          isTrue,
          reason: '$name produced a non-finite origin — it may be the cause',
        );
        expect(render.cellSize.isFinite, isTrue, reason: name);
      }

      terminal.write('hello\r\n');
      await tester.pump();

      expect(tester.takeException(), isNull, reason: name);
    });
  });
}
