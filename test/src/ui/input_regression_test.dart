import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:xterm/xterm.dart';

class _View {
  _View(this.tester, this.terminal, this.controller, this.output);

  final WidgetTester tester;
  final Terminal terminal;
  final TerminalController controller;
  final List<String> output;

  String? get selectedText {
    final selection = controller.selection;
    if (selection == null) return null;
    return terminal.buffer.getText(selection).trim();
  }

  Offset offsetOf(int column, int row) {
    final view = tester.getTopLeft(find.byType(TerminalView));
    final render = tester.renderObject(find.byType(TerminalView));
    final width = render.paintBounds.width / terminal.viewWidth;
    final height = render.paintBounds.height / terminal.viewHeight;
    return view + Offset((column + 0.5) * width, (row + 0.5) * height);
  }

  Future<void> chord(
    List<LogicalKeyboardKey> held,
    LogicalKeyboardKey key,
  ) async {
    for (final k in held) {
      await tester.sendKeyDownEvent(k);
    }
    await tester.sendKeyEvent(key);
    for (final k in held.reversed) {
      await tester.sendKeyUpEvent(k);
    }
    await tester.pump();
  }
}

Future<_View> _pump(
  WidgetTester tester, {
  String content = '',
  TerminalTargetPlatform platform = TerminalTargetPlatform.linux,
}) async {
  final output = <String>[];
  final terminal = Terminal(platform: platform, onOutput: output.add);
  final controller = TerminalController();
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: TerminalView(terminal, controller: controller, autofocus: true),
      ),
    ),
  );
  terminal.write(content);
  await tester.pump();
  return _View(tester, terminal, controller, output);
}

void main() {
  group('on Linux', () {
    testWidgets('Ctrl+A and Ctrl+X reach the shell', (tester) async {
      final view = await _pump(tester, content: 'some text');
      await view.chord([
        LogicalKeyboardKey.controlLeft,
      ], LogicalKeyboardKey.keyA);
      await view.chord([
        LogicalKeyboardKey.controlLeft,
      ], LogicalKeyboardKey.keyX);
      expect(view.output, ['\x01', '\x18']);
      expect(view.controller.selection, isNull);
    }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

    testWidgets('Ctrl+Shift+A selects everything without asserting', (
      tester,
    ) async {
      final view = await _pump(tester, content: 'some text');
      await view.chord([
        LogicalKeyboardKey.controlLeft,
        LogicalKeyboardKey.shiftLeft,
      ], LogicalKeyboardKey.keyA);
      expect(view.selectedText, 'some text');
      expect(tester.takeException(), isNull);
    }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

    testWidgets('a paste with no onPaste goes to the terminal at once', (
      tester,
    ) async {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async => call.method == 'Clipboard.getData'
            ? <String, dynamic>{'text': 'PASTED'}
            : null,
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      final view = await _pump(tester);
      await view.chord([
        LogicalKeyboardKey.controlLeft,
      ], LogicalKeyboardKey.keyV);
      await tester.pump();
      expect(view.output, ['PASTED']);
    }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

    testWidgets('Alt with a key that types a character sends ESC first', (
      tester,
    ) async {
      final view = await _pump(tester);
      await view.chord([LogicalKeyboardKey.altLeft], LogicalKeyboardKey.period);
      expect(view.output, ['\x1b.']);
    }, variant: TargetPlatformVariant.only(TargetPlatform.linux));
  });

  group('keys', () {
    test('Alt+letter is ESC and the lower case letter', () {
      final out = <String>[];
      final t = Terminal(
        platform: TerminalTargetPlatform.linux,
        onOutput: out.add,
      );
      t.keyInput(TerminalKey.keyA, alt: true);
      t.charInput('b'.codeUnitAt(0), alt: true);
      t.charInput('.'.codeUnitAt(0), alt: true);
      expect(out, ['\x1ba', '\x1bb', '\x1b.']);
    });

    test('arrows carry the modifiers held', () {
      final out = <String>[];
      final t = Terminal(
        platform: TerminalTargetPlatform.linux,
        onOutput: out.add,
      );
      t.keyInput(TerminalKey.arrowUp, shift: true);
      t.keyInput(TerminalKey.arrowUp, alt: true);
      t.keyInput(TerminalKey.arrowUp, ctrl: true);
      t.keyInput(TerminalKey.arrowDown, ctrl: true, alt: true);
      expect(out, ['\x1b[1;2A', '\x1b[1;3A', '\x1b[1;5A', '\x1b[1;7B']);
    });
  });

  testWidgets('a shift click backwards keeps the end of the selection', (
    tester,
  ) async {
    final view = await _pump(tester, content: 'alpha beta gamma');

    final drag = await tester.startGesture(
      view.offsetOf(6, 0),
      kind: PointerDeviceKind.mouse,
    );
    await drag.moveTo(view.offsetOf(10, 0));
    await tester.pump();
    await drag.up();
    await tester.pump(kDoubleTapTimeout);
    expect(view.selectedText, 'beta');

    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    final click = await tester.startGesture(
      view.offsetOf(2, 0),
      kind: PointerDeviceKind.mouse,
    );
    await click.up();
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump(kDoubleTapTimeout);

    expect(view.selectedText, 'pha beta');
  });

  testWidgets('a touch long press in a mouse mode is released', (tester) async {
    final view = await _pump(tester, content: '\x1b[?1000h\x1b[?1006hab');

    final press = await tester.startGesture(
      view.offsetOf(2, 0),
      kind: PointerDeviceKind.touch,
    );
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
    await press.up();
    await tester.pump(kDoubleTapTimeout);

    final presses = view.output.where((o) => o.endsWith('M')).length;
    final releases = view.output.where((o) => o.endsWith('m')).length;
    expect(releases, presses);
  });
}
