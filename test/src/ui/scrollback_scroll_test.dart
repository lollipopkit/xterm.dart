import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xterm/core.dart';
import 'package:xterm/xterm.dart';

/// A terminal with scrollback, and the scroll controller that shows it.
Future<(ScrollController, double)> pumpTerminal(
  WidgetTester tester, {
  required TerminalTargetPlatform platform,
}) async {
  final terminal = Terminal(platform: platform, maxLines: 1000);
  final scroll = ScrollController();

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: TerminalView(
          terminal,
          controller: TerminalController(),
          scrollController: scroll,
        ),
      ),
    ),
  );
  terminal.write('line\n' * 50);
  await tester.pump();

  final state = tester.state<TerminalViewState>(find.byType(TerminalView));
  return (scroll, state.renderTerminal.lineHeight);
}

void main() {
  testWidgets('a click of the wheel scrolls three lines on macOS', (
    tester,
  ) async {
    final (scroll, lineHeight) = await pumpTerminal(
      tester,
      platform: TerminalTargetPlatform.macos,
    );
    final before = scroll.position.pixels;

    await tester.sendEventToBinding(
      const PointerScrollEvent(
        position: Offset(100, 300),
        scrollDelta: Offset(0, -40),
      ),
    );
    await tester.pump();

    expect(before - scroll.position.pixels, closeTo(3 * lineHeight, 0.001));
  });

  testWidgets('a click of the wheel scrolls three lines on Windows', (
    tester,
  ) async {
    final (scroll, lineHeight) = await pumpTerminal(
      tester,
      platform: TerminalTargetPlatform.windows,
    );
    final before = scroll.position.pixels;

    await tester.sendEventToBinding(
      const PointerScrollEvent(
        position: Offset(100, 300),
        scrollDelta: Offset(0, -100),
      ),
    );
    await tester.pump();

    expect(before - scroll.position.pixels, closeTo(3 * lineHeight, 0.001));
  });

  testWidgets('a click of the wheel scrolls three lines on Linux', (
    tester,
  ) async {
    final (scroll, lineHeight) = await pumpTerminal(
      tester,
      platform: TerminalTargetPlatform.linux,
    );
    final before = scroll.position.pixels;

    await tester.sendEventToBinding(
      const PointerScrollEvent(
        position: Offset(100, 300),
        scrollDelta: Offset(0, -53),
      ),
    );
    await tester.pump();

    expect(before - scroll.position.pixels, closeTo(3 * lineHeight, 0.001));
  });

  testWidgets('a slide of a trackpad moves a line at a time', (tester) async {
    final (scroll, lineHeight) = await pumpTerminal(
      tester,
      platform: TerminalTargetPlatform.macos,
    );
    final before = scroll.position.pixels;

    await tester.sendEventToBinding(
      PointerScrollEvent(
        position: const Offset(100, 300),
        scrollDelta: Offset(0, -lineHeight),
      ),
    );
    await tester.pump();

    expect(before - scroll.position.pixels, closeTo(lineHeight, 0.001));
  });

  testWidgets('the scrollback is scrolled by whole lines', (tester) async {
    final (scroll, lineHeight) = await pumpTerminal(
      tester,
      platform: TerminalTargetPlatform.macos,
    );
    final before = scroll.position.pixels;

    // A third of a line is not a line, and a line is not three.
    await tester.sendEventToBinding(
      const PointerScrollEvent(
        position: Offset(100, 300),
        scrollDelta: Offset(0, -5),
      ),
    );
    await tester.pump();
    expect(scroll.position.pixels, before);

    await tester.sendEventToBinding(
      PointerScrollEvent(
        position: const Offset(100, 300),
        scrollDelta: Offset(0, -lineHeight / 2),
      ),
    );
    await tester.pump();
    expect(scroll.position.pixels, before);
  });
}
