import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xterm/src/ui/custom_text_edit.dart';

void main() {
  _richContentAndClipboard();
  _pasteFailures();
  _imeReplacesPlaceholder();
  _imeEdits();
  _toolbarBuilderContract();

  testWidgets('IME delete command emits a single backspace', (tester) async {
    final focusNode = FocusNode();
    var deleteCount = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Material(
          child: CustomTextEdit(
            focusNode: focusNode,
            onInsert: (_) {},
            onDelete: () => deleteCount++,
            onComposing: (_) {},
            onAction: (_) {},
            onKeyEvent: (_, _) => KeyEventResult.ignored,
            child: const SizedBox.shrink(),
          ),
        ),
      ),
    );

    focusNode.requestFocus();
    await tester.pump();

    final state = tester.state<CustomTextEditState>(
      find.byType(CustomTextEdit),
    );

    state.performPrivateCommand('deleteSurroundingText', {'beforeLength': 128});
    await tester.pump();

    expect(deleteCount, 1);

    focusNode.dispose();
  });

  testWidgets('deleteDetection placeholder ignores follow-up IME updates', (
    tester,
  ) async {
    final focusNode = FocusNode();
    var deleteCount = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Material(
          child: CustomTextEdit(
            focusNode: focusNode,
            deleteDetection: true,
            onInsert: (_) {},
            onDelete: () => deleteCount++,
            onComposing: (_) {},
            onAction: (_) {},
            onKeyEvent: (_, _) => KeyEventResult.ignored,
            child: const SizedBox.shrink(),
          ),
        ),
      ),
    );

    focusNode.requestFocus();
    await tester.pump();

    final state = tester.state<CustomTextEditState>(
      find.byType(CustomTextEdit),
    );

    state.performPrivateCommand('deleteSurroundingText', {'beforeLength': 64});
    await tester.pump();

    // Simulate the IME reporting that one of the placeholder characters was removed.
    state.updateEditingValue(
      const TextEditingValue(
        text: ' ',
        selection: TextSelection.collapsed(offset: 1),
      ),
    );

    expect(deleteCount, 1);

    focusNode.dispose();
  });

  testWidgets('IME commit inserts text when composition length changes', (
    tester,
  ) async {
    final focusNode = FocusNode();
    final insertedText = <String>[];

    await tester.pumpWidget(
      MaterialApp(
        home: Material(
          child: CustomTextEdit(
            focusNode: focusNode,
            onInsert: insertedText.add,
            onDelete: () {},
            onComposing: (_) {},
            onAction: (_) {},
            onKeyEvent: (_, _) => KeyEventResult.ignored,
            child: const SizedBox.shrink(),
          ),
        ),
      ),
    );

    focusNode.requestFocus();
    await tester.pump();

    final state = tester.state<CustomTextEditState>(
      find.byType(CustomTextEdit),
    );

    state.updateEditingValue(
      const TextEditingValue(
        text: 'nihongo',
        selection: TextSelection.collapsed(offset: 7),
        composing: TextRange(start: 0, end: 7),
      ),
    );
    state.updateEditingValue(
      const TextEditingValue(
        text: '日本語',
        selection: TextSelection.collapsed(offset: 3),
      ),
    );

    state.updateEditingValue(
      const TextEditingValue(
        text: 'ka',
        selection: TextSelection.collapsed(offset: 2),
        composing: TextRange(start: 0, end: 2),
      ),
    );
    state.updateEditingValue(
      const TextEditingValue(
        text: 'かきく',
        selection: TextSelection.collapsed(offset: 3),
      ),
    );

    expect(insertedText, ['日本語', 'かきく']);

    focusNode.dispose();
  });
}

Future<CustomTextEditState> _pumpEdit(
  WidgetTester tester, {
  required void Function(String) onInsert,
  void Function()? onCopied,
  String Function()? getSelectedText,
  bool Function()? hasSelection,
}) async {
  final focusNode = FocusNode();
  addTearDown(focusNode.dispose);
  await tester.pumpWidget(
    MaterialApp(
      home: Material(
        child: CustomTextEdit(
          focusNode: focusNode,
          onInsert: onInsert,
          onDelete: () {},
          onComposing: (_) {},
          onAction: (_) {},
          onKeyEvent: (_, _) => KeyEventResult.ignored,
          onCopied: onCopied,
          getSelectedText: getSelectedText,
          hasSelection: hasSelection,
          child: const SizedBox.shrink(),
        ),
      ),
    ),
  );
  focusNode.requestFocus();
  await tester.pump();
  return tester.state<CustomTextEditState>(find.byType(CustomTextEdit));
}

void _richContentAndClipboard() {
  testWidgets('inserted content that is not text is ignored', (tester) async {
    // A sticker or GIF from the keyboard is image bytes (SERVERBOX-146).
    final inserted = <String>[];
    final state = await _pumpEdit(tester, onInsert: inserted.add);

    state.insertContent(
      KeyboardInsertedContent(
        mimeType: 'image/png',
        uri: 'content://sticker',
        data: Uint8List.fromList([0x89, 0x50, 0x4e, 0x47, 0xff]),
      ),
    );
    state.insertContent(
      KeyboardInsertedContent(
        mimeType: 'text/plain',
        uri: 'content://text',
        data: Uint8List.fromList(utf8.encode('ls -la')),
      ),
    );

    expect(inserted, ['ls -la']);
  });

  testWidgets('a paste with no selection goes at the end', (tester) async {
    // SERVERBOX-1AL: offsets of -1 have nothing to split at.
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async => call.method == 'Clipboard.getData'
          ? <String, dynamic>{'text': 'pwd'}
          : null,
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    final state = await _pumpEdit(tester, onInsert: (_) {});
    state.textEditingValue = const TextEditingValue(
      text: 'ab',
      selection: TextSelection.collapsed(offset: -1),
    );

    await state.pasteText(SelectionChangedCause.keyboard);

    expect(state.textEditingValue.text, endsWith('pwd'));
  });

  testWidgets('a clipboard that refuses a copy is not reported', (
    tester,
  ) async {
    // SERVERBOX-1N7: Windows answers "Unable to open clipboard".
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async => call.method == 'Clipboard.setData'
          ? throw PlatformException(code: 'Clipboard error')
          : null,
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    var copied = false;
    final state = await _pumpEdit(
      tester,
      onInsert: (_) {},
      onCopied: () => copied = true,
      getSelectedText: () => 'secret',
      hasSelection: () => true,
    );

    final errors = <Object>[];
    await runZonedGuarded(() async {
      state.copySelection(SelectionChangedCause.keyboard);
      await tester.pump();
    }, (e, _) => errors.add(e));

    expect(errors, isEmpty);
    expect(copied, isFalse);
  });
}

void _pasteFailures() {
  testWidgets('a clipboard that refuses a read is not an error', (tester) async {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async => call.method == 'Clipboard.getData'
          ? throw PlatformException(code: 'Clipboard error')
          : null,
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    final state = await _pumpEdit(tester, onInsert: (_) {});

    final errors = <Object>[];
    await runZonedGuarded(
      () => state.pasteText(SelectionChangedCause.keyboard),
      (e, _) => errors.add(e),
    );

    expect(errors, isEmpty);
  });

  testWidgets('a clipboard answer after the edit is gone sets nothing', (
    tester,
  ) async {
    final answer = Completer<Object?>();
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) => call.method == 'Clipboard.getData'
          ? answer.future
          : Future.value(),
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    final state = await _pumpEdit(tester, onInsert: (_) {});

    final paste = state.pasteText(SelectionChangedCause.keyboard);
    await tester.pumpWidget(const SizedBox.shrink());
    answer.complete(<String, dynamic>{'text': 'late'});
    await paste;

    expect(tester.takeException(), isNull);
    // Without the guard this waits on a setState that never comes back.
  }, timeout: const Timeout(Duration(seconds: 10)));
}

void _imeReplacesPlaceholder() {
  testWidgets('an IME replacing the placeholder inserts all it wrote', (
    tester,
  ) async {
    // With delete detection the buffer is two placeholder spaces, reset after
    // every commit. An IME that writes over them rather than after them must
    // not lose what stood where they were.
    final inserted = <String>[];
    final focusNode = FocusNode();
    addTearDown(focusNode.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Material(
          child: CustomTextEdit(
            focusNode: focusNode,
            deleteDetection: true,
            onInsert: inserted.add,
            onDelete: () {},
            onComposing: (_) {},
            onAction: (_) {},
            onKeyEvent: (_, _) => KeyEventResult.ignored,
            child: const SizedBox.shrink(),
          ),
        ),
      ),
    );
    focusNode.requestFocus();
    await tester.pump();
    final state = tester.state<CustomTextEditState>(
      find.byType(CustomTextEdit),
    );

    state.updateEditingValue(
      const TextEditingValue(
        text: 'hello',
        selection: TextSelection.collapsed(offset: 5),
      ),
    );
    state.updateEditingValue(
      const TextEditingValue(
        text: '  ls',
        selection: TextSelection.collapsed(offset: 4),
      ),
    );

    expect(inserted, ['hello', 'ls']);
  });
}

Future<CustomTextEditState> _pumpDetecting(
  WidgetTester tester, {
  required List<String> inserted,
  required void Function() onDelete,
  bool deleteDetection = true,
}) async {
  final focusNode = FocusNode();
  addTearDown(focusNode.dispose);
  await tester.pumpWidget(
    MaterialApp(
      home: Material(
        child: CustomTextEdit(
          focusNode: focusNode,
          deleteDetection: deleteDetection,
          onInsert: inserted.add,
          onDelete: onDelete,
          onComposing: (_) {},
          onAction: (_) {},
          onKeyEvent: (_, _) => KeyEventResult.ignored,
          child: const SizedBox.shrink(),
        ),
      ),
    ),
  );
  focusNode.requestFocus();
  await tester.pump();
  return tester.state<CustomTextEditState>(find.byType(CustomTextEdit));
}

void _imeEdits() {
  testWidgets('a shorter commit over the placeholder is still input', (
    tester,
  ) async {
    final inserted = <String>[];
    var deletes = 0;
    final state = await _pumpDetecting(
      tester,
      inserted: inserted,
      onDelete: () => deletes++,
    );

    state.updateEditingValue(
      const TextEditingValue(
        text: 'a',
        selection: TextSelection.collapsed(offset: 1),
      ),
    );
    expect(inserted, ['a']);
    expect(deletes, 0);

    // One placeholder space gone and nothing written: a backspace.
    state.updateEditingValue(
      const TextEditingValue(
        text: ' ',
        selection: TextSelection.collapsed(offset: 1),
      ),
    );
    expect(deletes, 1);
    expect(inserted, ['a']);
  });

  testWidgets('a composition committed as different text inserts the commit', (
    tester,
  ) async {
    // Pinyin composed, then committed as the characters it spelled: nothing
    // of the composition reached the terminal, so the commit is all of it.
    final inserted = <String>[];
    final state = await _pumpDetecting(
      tester,
      inserted: inserted,
      onDelete: () {},
      deleteDetection: false,
    );

    state.updateEditingValue(
      const TextEditingValue(
        text: 'nihao',
        selection: TextSelection.collapsed(offset: 5),
        composing: TextRange(start: 0, end: 5),
      ),
    );
    state.updateEditingValue(
      const TextEditingValue(
        text: '你好',
        selection: TextSelection.collapsed(offset: 2),
      ),
    );

    expect(inserted, ['你好']);
  });

  testWidgets('a copy that lands after the edit is gone is not reported', (
    tester,
  ) async {
    final written = Completer<Object?>();
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) =>
          call.method == 'Clipboard.setData' ? written.future : Future.value(),
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    var copied = false;
    final state = await _pumpEdit(
      tester,
      onInsert: (_) {},
      onCopied: () => copied = true,
      getSelectedText: () => 'secret',
      hasSelection: () => true,
    );

    state.copySelection(SelectionChangedCause.keyboard);
    await tester.pumpWidget(const SizedBox.shrink());
    written.complete(null);
    await tester.pump();

    expect(copied, isFalse);
  });

  testWidgets('a private-command selection outside the text is ignored', (
    tester,
  ) async {
    final inserted = <String>[];
    final state = await _pumpDetecting(
      tester,
      inserted: inserted,
      onDelete: () {},
    );
    final before = state.textEditingValue.selection;

    state.performPrivateCommand('setSelection', {
      'selectionBase': 999,
      'selectionExtent': 1000,
    });

    expect(state.textEditingValue.selection, before);
    expect(inserted, isEmpty);
  });
}

void _toolbarBuilderContract() {
  Future<CustomTextEditState> pump(
    WidgetTester tester,
    CustomTextEditToolbarBuilder builder,
  ) async {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async => call.method == 'Clipboard.hasStrings'
          ? <String, bool>{'value': true}
          : null,
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    final focusNode = FocusNode();
    addTearDown(focusNode.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Material(
          child: CustomTextEdit(
            focusNode: focusNode,
            onInsert: (_) {},
            onDelete: () {},
            onComposing: (_) {},
            onAction: (_) {},
            onKeyEvent: (_, _) => KeyEventResult.ignored,
            hasSelection: () => true,
            getSelectedText: () => 'x',
            toolbarBuilder: builder,
            child: const SizedBox.shrink(),
          ),
        ),
      ),
    );
    final state = tester.state<CustomTextEditState>(
      find.byType(CustomTextEdit),
    );
    // Once to learn the clipboard state, then for real.
    state.showToolbar(globalSelectionRect: const Rect.fromLTWH(100, 200, 10, 10));
    await tester.pumpAndSettle();
    state.hideToolbar();
    state.showToolbar(globalSelectionRect: const Rect.fromLTWH(100, 200, 10, 10));
    await tester.pump();
    return state;
  }

  testWidgets('a toolbar builder returning nothing shows no toolbar', (
    tester,
  ) async {
    // Its result is the complete list: empty is not "the defaults, please".
    final state = await pump(tester, (_, _, _) => const []);
    expect(state.isToolbarShown, isFalse);
    state.hideToolbar();
  });

  testWidgets('a toolbar builder returning the defaults shows them', (
    tester,
  ) async {
    final state = await pump(tester, (_, _, defaults) => defaults);
    expect(state.isToolbarShown, isTrue);
    state.hideToolbar();
    await tester.pump();
  });
}
