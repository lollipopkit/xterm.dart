import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

Map<ShortcutActivator, Intent> get defaultTerminalShortcuts {
  switch (defaultTargetPlatform) {
    case TargetPlatform.android:
    case TargetPlatform.fuchsia:
    case TargetPlatform.linux:
    case TargetPlatform.windows:
      return _defaultShortcuts;
    case TargetPlatform.iOS:
    case TargetPlatform.macOS:
      return _defaultAppleShortcuts;
  }
}

final Map<ShortcutActivator, Intent> _defaultShortcuts = {
  SingleActivator(LogicalKeyboardKey.keyC, control: true, shift: true):
      CopySelectionTextIntent.copy,
  SingleActivator(LogicalKeyboardKey.keyV, control: true):
      const PasteTextIntent(SelectionChangedCause.keyboard),
  SingleActivator(LogicalKeyboardKey.keyV, control: true, shift: true):
      const PasteTextIntent(SelectionChangedCause.keyboard),
  // With shift: Ctrl+A and Ctrl+X are the shell's, readline's start of line
  // and nano's exit, tmux and screen's prefix.
  SingleActivator(LogicalKeyboardKey.keyA, control: true, shift: true):
      const SelectAllTextIntent(SelectionChangedCause.keyboard),
  SingleActivator(LogicalKeyboardKey.insert, control: true):
      CopySelectionTextIntent.copy,
  SingleActivator(LogicalKeyboardKey.insert, shift: true):
      const PasteTextIntent(SelectionChangedCause.keyboard),
  SingleActivator(LogicalKeyboardKey.delete, shift: true):
      CopySelectionTextIntent.cut(SelectionChangedCause.keyboard),
};

final Map<ShortcutActivator, Intent> _defaultAppleShortcuts = {
  SingleActivator(LogicalKeyboardKey.keyC, meta: true):
      CopySelectionTextIntent.copy,
  SingleActivator(LogicalKeyboardKey.keyV, meta: true): const PasteTextIntent(
    SelectionChangedCause.keyboard,
  ),
  SingleActivator(LogicalKeyboardKey.keyA, meta: true):
      const SelectAllTextIntent(SelectionChangedCause.keyboard),
  SingleActivator(LogicalKeyboardKey.keyX, meta: true):
      CopySelectionTextIntent.cut(SelectionChangedCause.keyboard),
};
