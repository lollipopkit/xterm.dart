import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xterm/src/ui/custom_text_edit.dart';

void main() {
  _richContentAndClipboard();
  _pasteFailures();

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
