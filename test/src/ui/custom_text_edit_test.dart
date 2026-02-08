import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xterm/src/ui/custom_text_edit.dart';

void main() {
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
}
