import 'package:flutter_test/flutter_test.dart';
import 'package:xterm/src/core/cursor.dart';

void main() {
  test('CursorStyle.isItalic reflects italic attribute', () {
    final style = CursorStyle();

    expect(style.isItalic, isFalse);

    style.setItalic();
    expect(style.isItalic, isTrue);

    style.unsetItalic();
    expect(style.isItalic, isFalse);
  });
}
