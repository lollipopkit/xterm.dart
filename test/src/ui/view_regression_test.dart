import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:xterm/src/ui/render.dart';
import 'package:xterm/xterm.dart';

RenderTerminal _render(WidgetTester tester) =>
    tester.renderObject<RenderTerminal>(
      find.descendant(
        of: find.byType(TerminalView),
        matching: find.byWidgetPredicate(
          (w) => w.runtimeType.toString() == '_TerminalView',
        ),
      ),
    );

void main() {
  testWidgets('a side inset moves the text and the hit test together', (
    tester,
  ) async {
    final terminal = Terminal();
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(padding: EdgeInsets.only(left: 40)),
          child: TerminalView(terminal),
        ),
      ),
    );
    terminal.write('abcdefgh');
    await tester.pump();

    final render = _render(tester);
    final cell = render.cellSize;
    expect(render.cursorOffset.dx, render.getOffset(const CellOffset(8, 0)).dx);
    expect(
      render.getCellOffset(Offset(40 + cell.width * 5.5, cell.height / 2)),
      const CellOffset(5, 0),
    );
    expect(terminal.viewWidth, (render.size.width - 40) ~/ cell.width);
  });

  testWidgets('rebuilding with the same style keeps the glyph atlas', (
    tester,
  ) async {
    final terminal = Terminal();
    late StateSetter setState;
    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, set) {
            setState = set;
            return TerminalView(
              terminal,
              textStyle: const TerminalStyle(fontSize: 14),
              theme: TerminalThemes.defaultTheme,
            );
          },
        ),
      ),
    );
    terminal.write('中文 x');
    await tester.pump();

    var images = 0;
    void count(ui.Image _) => images++;
    ui.Image.onCreate = count;
    addTearDown(() => ui.Image.onCreate = null);

    for (var i = 0; i < 3; i++) {
      setState(() {});
      await tester.pump();
    }

    expect(images, 0);
  });

  test('a style and a theme compare by value', () {
    expect(
      const TerminalStyle(fontSize: 14).copyWith(),
      const TerminalStyle(fontSize: 14),
    );
    expect(
      const TerminalStyle(fontFamilyFallback: ['a']),
      TerminalStyle(fontFamilyFallback: ['a'].toList()),
    );
    expect(
      const TerminalStyle(fontSize: 14),
      isNot(const TerminalStyle(fontSize: 15)),
    );
    final theme = TerminalThemes.defaultTheme;
    final copy = TerminalTheme(
      cursor: theme.cursor,
      selectionCursor: theme.selectionCursor,
      selection: theme.selection,
      foreground: theme.foreground,
      background: theme.background,
      black: theme.black,
      white: theme.white,
      red: theme.red,
      green: theme.green,
      yellow: theme.yellow,
      blue: theme.blue,
      magenta: theme.magenta,
      cyan: theme.cyan,
      brightBlack: theme.brightBlack,
      brightRed: theme.brightRed,
      brightGreen: theme.brightGreen,
      brightYellow: theme.brightYellow,
      brightBlue: theme.brightBlue,
      brightMagenta: theme.brightMagenta,
      brightCyan: theme.brightCyan,
      brightWhite: theme.brightWhite,
      searchHitBackground: theme.searchHitBackground,
      searchHitBackgroundCurrent: theme.searchHitBackgroundCurrent,
      searchHitForeground: theme.searchHitForeground,
    );
    expect(copy, theme);
    expect(copy.hashCode, theme.hashCode);
  });

  testWidgets('scrolling to the bottom catches up with output during it', (
    tester,
  ) async {
    final terminal = Terminal();
    final scroll = ScrollController();
    await tester.pumpWidget(
      MaterialApp(
        home: TerminalView(
          terminal,
          scrollController: scroll,
          autofocus: true,
          hardwareKeyboardOnly: true,
        ),
      ),
    );
    terminal.write('line\r\n' * 100);
    await tester.pump();
    scroll.jumpTo(0);
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump(const Duration(milliseconds: 50));
    terminal.write('more\r\n' * 20);
    await tester.pump(const Duration(milliseconds: 500));

    expect(scroll.position.pixels, scroll.position.maxScrollExtent);

    terminal.write('more\r\n' * 20);
    await tester.pump();
    expect(scroll.position.pixels, scroll.position.maxScrollExtent);
  });

  testWidgets('a view scrolled up stays on its text as scrollback trims', (
    tester,
  ) async {
    final terminal = Terminal(maxLines: 100);
    final scroll = ScrollController();
    await tester.pumpWidget(
      MaterialApp(home: TerminalView(terminal, scrollController: scroll)),
    );
    for (var i = 0; i < 150; i++) {
      terminal.write('line$i\r\n');
    }
    await tester.pump();

    final render = _render(tester);
    final lineHeight = render.lineHeight;
    scroll.jumpTo(lineHeight * 10);
    await tester.pump();
    String topLine() => terminal
        .buffer
        .lines[render.getCellOffset(Offset(1, lineHeight / 2)).y]
        .getText()
        .trim();
    final before = topLine();

    for (var i = 150; i < 160; i++) {
      terminal.write('line$i\r\n');
    }
    await tester.pump();

    expect(topLine(), before);
  });

  testWidgets('a new terminal does not keep the old one\'s selection', (
    tester,
  ) async {
    final a = Terminal();
    final b = Terminal();
    final controller = TerminalController();
    a.write('alpha');
    await tester.pumpWidget(
      MaterialApp(home: TerminalView(a, controller: controller)),
    );
    controller.setSelection(
      a.buffer.createAnchor(0, 0),
      a.buffer.createAnchor(3, 0),
    );
    await tester.pump();

    await tester.pumpWidget(
      MaterialApp(home: TerminalView(b, controller: controller)),
    );
    await tester.pump();

    expect(controller.selection, isNull);
  });
}
