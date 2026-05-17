import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xterm/src/terminal.dart';
import 'package:xterm/src/terminal_view.dart';
import 'package:xterm/src/ui/render.dart';

void main() {
  testWidgets('DEC cursor blink mode updates the render cursor blink state', (
    tester,
  ) async {
    final terminal = Terminal();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: TerminalView(terminal, autofocus: true)),
      ),
    );
    await tester.pump();

    final terminalViewRenderObject = find.byWidgetPredicate(
      (widget) => widget.runtimeType.toString() == '_TerminalView',
    );
    var render = tester.renderObject<RenderTerminal>(terminalViewRenderObject);
    expect(render.cursorBlinkEnabled, isFalse);

    terminal.write('\x1b[?12h');
    await tester.pump();

    render = tester.renderObject<RenderTerminal>(terminalViewRenderObject);
    expect(render.cursorBlinkEnabled, isTrue);

    terminal.write('\x1b[?12l');
    await tester.pump();

    render = tester.renderObject<RenderTerminal>(terminalViewRenderObject);
    expect(render.cursorBlinkEnabled, isFalse);
  });

  testWidgets('backspace repeats when holding key', (tester) async {
    final outputs = <String>[];
    final terminal = Terminal(onOutput: outputs.add);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TerminalView(
            terminal,
            autofocus: true,
            hardwareKeyboardOnly: true,
          ),
        ),
      ),
    );

    await tester.pump();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.backspace);
    await tester.pump();
    expect(outputs.length, 1);

    await tester.sendKeyRepeatEvent(LogicalKeyboardKey.backspace);
    await tester.pump();
    expect(outputs.length, 2);

    final repeatsBeforeRelease = outputs.length;

    await tester.sendKeyUpEvent(LogicalKeyboardKey.backspace);
    await tester.pump(const Duration(milliseconds: 100));
    expect(outputs.length, repeatsBeforeRelease);
  });
}
