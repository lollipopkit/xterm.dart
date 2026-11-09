import 'package:flutter/widgets.dart';

class TerminalTheme {
  const TerminalTheme({
    required this.cursor,
    required this.selectionCursor,
    required this.selection,
    required this.foreground,
    required this.background,
    required this.black,
    required this.white,
    required this.red,
    required this.green,
    required this.yellow,
    required this.blue,
    required this.magenta,
    required this.cyan,
    required this.brightBlack,
    required this.brightRed,
    required this.brightGreen,
    required this.brightYellow,
    required this.brightBlue,
    required this.brightMagenta,
    required this.brightCyan,
    required this.brightWhite,
    required this.searchHitBackground,
    required this.searchHitBackgroundCurrent,
    required this.searchHitForeground,
  });

  final Color cursor;
  final Color selectionCursor;
  final Color selection;

  final Color foreground;
  final Color background;

  final Color black;
  final Color red;
  final Color green;
  final Color yellow;
  final Color blue;
  final Color magenta;
  final Color cyan;
  final Color white;

  final Color brightBlack;
  final Color brightRed;
  final Color brightGreen;
  final Color brightYellow;
  final Color brightBlue;
  final Color brightMagenta;
  final Color brightCyan;
  final Color brightWhite;

  final Color searchHitBackground;
  final Color searchHitBackgroundCurrent;
  final Color searchHitForeground;

  // By value, for the same reason as `TerminalStyle`: a theme copied into a
  // new instance with nothing changed must not empty the paint caches.
  @override
  bool operator ==(Object other) =>
      other is TerminalTheme &&
      other.cursor == cursor &&
      other.selectionCursor == selectionCursor &&
      other.selection == selection &&
      other.foreground == foreground &&
      other.background == background &&
      other.black == black &&
      other.red == red &&
      other.green == green &&
      other.yellow == yellow &&
      other.blue == blue &&
      other.magenta == magenta &&
      other.cyan == cyan &&
      other.white == white &&
      other.brightBlack == brightBlack &&
      other.brightRed == brightRed &&
      other.brightGreen == brightGreen &&
      other.brightYellow == brightYellow &&
      other.brightBlue == brightBlue &&
      other.brightMagenta == brightMagenta &&
      other.brightCyan == brightCyan &&
      other.brightWhite == brightWhite &&
      other.searchHitBackground == searchHitBackground &&
      other.searchHitBackgroundCurrent == searchHitBackgroundCurrent &&
      other.searchHitForeground == searchHitForeground;

  @override
  int get hashCode => Object.hashAll([
    cursor,
    selectionCursor,
    selection,
    foreground,
    background,
    black,
    red,
    green,
    yellow,
    blue,
    magenta,
    cyan,
    white,
    brightBlack,
    brightRed,
    brightGreen,
    brightYellow,
    brightBlue,
    brightMagenta,
    brightCyan,
    brightWhite,
    searchHitBackground,
    searchHitBackgroundCurrent,
    searchHitForeground,
  ]);
}
