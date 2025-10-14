import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xterm/src/core/buffer/cell_offset.dart';
import 'package:xterm/src/core/buffer/range_line.dart';
import 'package:xterm/src/terminal.dart';
import 'package:xterm/src/ui/controller.dart';
import 'package:xterm/src/ui/cursor_type.dart';
import 'package:xterm/src/ui/render.dart';
import 'package:xterm/src/ui/terminal_text_style.dart';
import 'package:xterm/src/ui/themes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('RenderTerminal.selectBufferRange keeps exclusive end', () {
    final terminal = Terminal();
    terminal.write('foo bar');

    const vsync = TestVSync();
    final controller = TerminalController(vsync: vsync);
    final focusNode = FocusNode();

    final render = RenderTerminal(
      terminal: terminal,
      controller: controller,
      offset: ViewportOffset.zero(),
      padding: EdgeInsets.zero,
      autoResize: false,
      textStyle: const TerminalStyle(),
      textScaler: TextScaler.noScaling,
      theme: TerminalThemes.defaultTheme,
      focusNode: focusNode,
      cursorType: TerminalCursorType.block,
      cursorBlinkEnabled: false,
      cursorBlinkVisible: true,
      alwaysShowCursor: false,
    );

    final owner = PipelineOwner();
    render.attach(owner);

    final range = BufferRangeLine(
      const CellOffset(0, 0),
      const CellOffset(3, 0),
    );
    render.selectBufferRange(range);

    final selection = controller.selection;
    expect(selection, isA<BufferRangeLine>());
    expect(selection, equals(range));

    render.detach();
    controller.dispose();
    focusNode.dispose();
  });
}
