import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xterm/xterm.dart';

void main() {
  testWidgets('a trackpad scrolls a program that has the alternate screen', (
    tester,
  ) async {
    final outputs = <String>[];
    final terminal = Terminal(
      platform: TerminalTargetPlatform.macos,
      onOutput: outputs.add,
    );
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: TerminalView(terminal))),
    );
    terminal.write('\x1b[?1049h');
    await tester.pump();

    final state = tester.state<TerminalViewState>(find.byType(TerminalView));
    final lineHeight = state.renderTerminal.lineHeight;
    final pointer = TestPointer(1, PointerDeviceKind.trackpad);
    const at = Offset(100, 300);
    await tester.sendEventToBinding(pointer.panZoomStart(at));
    // Fingers down by two lines and a half: the content follows them, so the
    // program is scrolled up two lines.
    await tester.sendEventToBinding(
      pointer.panZoomUpdate(at, pan: Offset(0, lineHeight * 2.5)),
    );
    await tester.sendEventToBinding(pointer.panZoomEnd());
    await tester.pump();

    expect(outputs.join(), '\x1b[A\x1b[A');
  });
}
