import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xterm/xterm.dart';

/// A terminal whose height is [height], as a page over a sliding keyboard.
Future<(Terminal, ScrollController)> pumpTerminal(
  WidgetTester tester,
  ValueNotifier<double> height, {
  bool autoResize = true,
}) async {
  final terminal = Terminal();
  final scroll = ScrollController();
  addTearDown(scroll.dispose);
  await tester.pumpWidget(
    MaterialApp(
      home: Align(
        alignment: Alignment.topCenter,
        child: ValueListenableBuilder(
          valueListenable: height,
          builder: (_, h, _) => SizedBox(
            width: 400,
            height: h,
            child: TerminalView(
              terminal,
              scrollController: scroll,
              autoResize: autoResize,
            ),
          ),
        ),
      ),
    ),
  );
  return (terminal, scroll);
}

/// The height sliding down to [to] a frame at a time, then left to settle.
Future<void> slide(
  WidgetTester tester,
  ValueNotifier<double> height,
  double to,
  void Function() eachFrame, {
  void Function()? sliding,
}) async {
  final from = height.value;
  for (var i = 1; i <= 8; i++) {
    height.value = from + (to - from) * i / 8;
    await tester.pump(const Duration(milliseconds: 16));
    eachFrame();
    sliding?.call();
  }
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 16));
    eachFrame();
  }
}

void main() {
  testWidgets('a prompt at the top stays there while the keyboard slides up', (
    tester,
  ) async {
    final height = ValueNotifier(600.0);
    addTearDown(height.dispose);
    final (terminal, scroll) = await pumpTerminal(tester, height);
    terminal.write('/ # ');
    await tester.pump();
    final rows = terminal.viewHeight;

    await slide(tester, height, 300, () {
      expect(scroll.position.pixels, 0, reason: 'the prompt left the top');
    });
    expect(terminal.viewHeight, lessThan(rows), reason: 'resized at the end');
  });

  testWidgets('a cursor at the bottom stays in sight while the keyboard slides up', (
    tester,
  ) async {
    final height = ValueNotifier(600.0);
    addTearDown(height.dispose);
    final (terminal, scroll) = await pumpTerminal(tester, height);
    terminal.write('line\r\n' * 200);
    await tester.pump();
    final state = tester.state<TerminalViewState>(find.byType(TerminalView));
    final render = state.renderTerminal;

    await slide(tester, height, 300, () {
      final cursorBottom = render.cursorOffset.dy + render.lineHeight;
      expect(cursorBottom, lessThanOrEqualTo(height.value + 0.001));
      expect(render.cursorOffset.dy, greaterThanOrEqualTo(-0.001));
    });
  });

  testWidgets('the view still follows the output once the keyboard is up', (
    tester,
  ) async {
    final height = ValueNotifier(600.0);
    addTearDown(height.dispose);
    final (terminal, scroll) = await pumpTerminal(tester, height);
    terminal.write('/ # ');
    await tester.pump();

    await slide(
      tester,
      height,
      300,
      () {},
      // A scroll notification while the keyboard slides, as a programmatic
      // jump sends.
      sliding: () => scroll.jumpTo(scroll.position.pixels + 1),
    );
    terminal.write('line\r\n' * 100);
    await tester.pump();
    expect(scroll.position.pixels, scroll.position.maxScrollExtent);
  });

  testWidgets('without autoResize the view shows the last rows', (
    tester,
  ) async {
    final height = ValueNotifier(300.0);
    addTearDown(height.dispose);
    final (terminal, scroll) = await pumpTerminal(
      tester,
      height,
      autoResize: false,
    );
    terminal.resize(80, 40);
    terminal.write('/ # ');
    await tester.pump();
    expect(scroll.position.pixels, scroll.position.maxScrollExtent);
    expect(scroll.position.maxScrollExtent, greaterThan(0));
  });
}
