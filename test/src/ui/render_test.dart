import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xterm/src/core/buffer/cell_offset.dart';
import 'package:xterm/src/core/buffer/range_line.dart';
import 'package:xterm/src/terminal.dart';
import 'package:xterm/src/ui/controller.dart';
import 'package:xterm/src/ui/cursor_type.dart';
import 'package:xterm/src/ui/pointer_input.dart';
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

  test('TerminalStyle combines underline strikethrough and overline', () {
    const style = TerminalStyle();

    final textStyle = style.toTextStyle(
      underline: true,
      strikethrough: true,
      overline: true,
    );

    expect(
      textStyle.decoration,
      TextDecoration.combine(const [
        TextDecoration.underline,
        TextDecoration.lineThrough,
        TextDecoration.overline,
      ]),
    );
  });

  test('TerminalController.setSelection can reuse existing anchors', () {
    final terminal = Terminal();
    terminal.write('abcdef');

    const vsync = TestVSync();
    final controller = TerminalController(vsync: vsync);
    final base = terminal.buffer.createAnchor(0, 0);
    final oldExtent = terminal.buffer.createAnchor(2, 0);
    final newExtent = terminal.buffer.createAnchor(4, 0);

    controller.setSelection(base, oldExtent);
    controller.setSelection(base, newExtent);

    expect(base.attached, isTrue);
    expect(oldExtent.attached, isFalse);
    expect(newExtent.attached, isTrue);
    expect(controller.selection, isNotNull);

    controller.dispose();
  });

  test('TerminalController.setSelection works without vsync', () {
    final terminal = Terminal();
    terminal.write('abcdef');

    final controller = TerminalController();
    final base = terminal.buffer.createAnchor(0, 0);
    final extent = terminal.buffer.createAnchor(2, 0);

    controller.setSelection(base, extent);

    expect(controller.selection, isNotNull);
    expect(controller.selectionAnimation, isNull);

    controller.dispose();
  });

  test('TerminalController.setSelection ignores detached anchors', () {
    final terminal = Terminal();
    terminal.write('abcdef');

    const vsync = TestVSync();
    final controller = TerminalController(vsync: vsync);
    final base = terminal.buffer.createAnchor(0, 0);
    final extent = terminal.buffer.createAnchor(2, 0);
    controller.setSelection(base, extent);
    expect(controller.selection, isNotNull);

    final detachedBase = terminal.buffer.createAnchor(1, 0)..dispose();
    final detachedExtent = terminal.buffer.createAnchor(3, 0);

    controller.setSelection(detachedBase, detachedExtent);

    expect(controller.selection, isNull);
    expect(base.attached, isFalse);
    expect(extent.attached, isFalse);
    expect(detachedExtent.attached, isTrue);

    detachedExtent.dispose();
    controller.dispose();
  });

  test('TerminalController.clearSelection handles shared anchor', () {
    final terminal = Terminal();
    terminal.write('abcdef');

    const vsync = TestVSync();
    final controller = TerminalController(vsync: vsync);
    final anchor = terminal.buffer.createAnchor(2, 0);

    controller.setSelection(anchor, anchor);
    controller.clearSelection();

    expect(anchor.line, isNull);
    expect(controller.selection, isNull);

    controller.dispose();
  });

  test(
    'TerminalController.dispose detaches selection and highlight anchors',
    () {
      final terminal = Terminal();
      terminal.write('abcdef');

      const vsync = TestVSync();
      final controller = TerminalController(
        vsync: vsync,
        pointerInputs: const PointerInputs({}),
      );

      final selectionBase = terminal.buffer.createAnchor(0, 0);
      final selectionExtent = terminal.buffer.createAnchor(2, 0);
      final highlightStart = terminal.buffer.createAnchor(3, 0);
      final highlightEnd = terminal.buffer.createAnchor(5, 0);

      controller.setSelection(selectionBase, selectionExtent);
      final highlight = controller.highlight(
        p1: highlightStart,
        p2: highlightEnd,
        color: const Color(0xFFFF0000),
      );

      controller.dispose();

      expect(selectionBase.line, isNull);
      expect(selectionExtent.line, isNull);
      expect(highlightStart.line, isNull);
      expect(highlightEnd.line, isNull);
      expect(highlight.disposed, isTrue);
    },
  );

  test(
    'TerminalController.dispose handles shared selection and highlight anchors',
    () {
      final terminal = Terminal();
      terminal.write('abcdef');

      const vsync = TestVSync();
      final controller = TerminalController(
        vsync: vsync,
        pointerInputs: const PointerInputs({}),
      );

      final selectionAnchor = terminal.buffer.createAnchor(1, 0);
      final highlightAnchor = terminal.buffer.createAnchor(3, 0);

      controller.setSelection(selectionAnchor, selectionAnchor);
      final highlight = controller.highlight(
        p1: highlightAnchor,
        p2: highlightAnchor,
        color: const Color(0xFFFF0000),
      );

      controller.dispose();

      expect(selectionAnchor.line, isNull);
      expect(highlightAnchor.line, isNull);
      expect(highlight.disposed, isTrue);
    },
  );
}
