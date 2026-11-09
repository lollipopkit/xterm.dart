import 'package:flutter_test/flutter_test.dart';
import 'package:xterm/xterm.dart';

void main() {
  group('TerminalTheme', () {
    test('compares by value', () {
      final theme = TerminalThemes.defaultTheme;
      final copy = TerminalTheme(
        cursor: theme.cursor,
        selectionCursor: theme.selectionCursor,
        selection: theme.selection,
        foreground: theme.foreground,
        background: theme.background,
        black: theme.black,
        white: theme.white,
        red: theme.red,
        green: theme.green,
        yellow: theme.yellow,
        blue: theme.blue,
        magenta: theme.magenta,
        cyan: theme.cyan,
        brightBlack: theme.brightBlack,
        brightRed: theme.brightRed,
        brightGreen: theme.brightGreen,
        brightYellow: theme.brightYellow,
        brightBlue: theme.brightBlue,
        brightMagenta: theme.brightMagenta,
        brightCyan: theme.brightCyan,
        brightWhite: theme.brightWhite,
        searchHitBackground: theme.searchHitBackground,
        searchHitBackgroundCurrent: theme.searchHitBackgroundCurrent,
        searchHitForeground: theme.searchHitForeground,
      );
      expect(copy, theme);
      expect(copy.hashCode, theme.hashCode);
    });
  });
}
