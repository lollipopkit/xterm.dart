import 'package:test/test.dart';
import 'package:xterm/src/core/state.dart';
import 'package:xterm/src/core/mouse/mode.dart';
import 'package:xterm/src/core/cursor.dart';

class _TestTerminalState implements TerminalState {
  @override
  int get viewWidth => 80;

  @override
  int get viewHeight => 24;

  @override
  CursorStyle get cursor => CursorStyle();

  @override
  bool get reflowEnabled => true;

  @override
  bool get insertMode => false;

  @override
  bool get lineFeedMode => false;

  @override
  bool get cursorKeysMode => false;

  @override
  bool get reverseDisplayMode => false;

  @override
  bool get originMode => false;

  @override
  bool get autoWrapMode => true;

  @override
  bool get ansiMode => true;

  @override
  MouseMode get mouseMode => MouseMode.none;

  @override
  MouseReportMode get mouseReportMode => MouseReportMode.normal;

  @override
  bool get cursorBlinkMode => false;

  @override
  bool get cursorVisibleMode => true;

  @override
  bool get appKeypadMode => false;

  @override
  bool get reportFocusMode => false;

  @override
  bool get altBufferMouseScrollMode => false;

  @override
  bool get bracketedPasteMode => false;
}

void main() {
  group('TerminalState', () {
    test('interface can be implemented', () {
      final state = _TestTerminalState();
      expect(state.viewWidth, 80);
      expect(state.viewHeight, 24);
      expect(state.autoWrapMode, isTrue);
      expect(state.ansiMode, isTrue);
      expect(state.mouseMode, MouseMode.none);
      expect(state.mouseReportMode, MouseReportMode.normal);
      expect(state.reflowEnabled, isTrue);
    });
  });
}
