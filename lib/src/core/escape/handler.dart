import 'package:xterm/src/core/mouse/mode.dart';

abstract class EscapeHandler {
  void writeChar(int char);

  /* SBC */

  void bell();

  void backspaceReturn();

  void tab();

  /// Handles CBT / cursor backward tabulation.
  ///
  /// [amount] is the number of tab stops to move left; parser defaults omitted
  /// or zero parameters to 1. Implementers should move to previous tab stops,
  /// not erase cells or change tab-stop state.
  void backTab(int amount);

  void lineFeed();

  void carriageReturn();

  void shiftOut();

  void shiftIn();

  /// Handles SS2/SS3 single-shift controls.
  ///
  /// [charset] is the one-shot G-set number, currently 2 or 3. It affects only
  /// the next printable character and should not permanently designate a set.
  void singleShift(int charset);

  void unknownSBC(int char);

  /* ANSI sequence */

  void saveCursor();

  void restoreCursor();

  void index();

  void nextLine();

  void setTapStop();

  void reverseIndex();

  /// Handles DECBI / backward index.
  ///
  /// Moves the active line content one column to the right at the cursor line,
  /// with scrolling behavior defined by the terminal state. This is separate
  /// from [backTab], which moves the cursor between tab stops.
  void backIndex();

  /// Handles DECFI / forward index.
  ///
  /// Moves the active line content one column to the left at the cursor line,
  /// with scrolling behavior defined by the terminal state. This is separate
  /// from cursor-forward movement, which only changes cursor position.
  void forwardIndex();

  void designateCharset(int charset, int name);

  void unkownEscape(int char);

  void resetTerminal();

  /// Handles DECSTR / soft terminal reset.
  ///
  /// Resets modes and cursor state to DECSTR defaults without clearing buffer
  /// contents. This is narrower than [resetTerminal], which handles RIS.
  void softResetTerminal();

  /// Handles DECALN / screen alignment pattern.
  ///
  /// Fills the display with the alignment test character and moves the cursor
  /// according to DECALN semantics. It should not be treated as regular input.
  void screenAlignmentPattern();

  /* CSI */

  /// Handles REP / repeat preceding character.
  ///
  /// [n] is the repeat count in cells; parser defaults omitted or zero values
  /// to 1. Implementers repeat the previous printable character at the cursor.
  void repeatPreviousCharacter(int n);

  void setCursor(int x, int y);

  void setCursorX(int x);

  void setCursorY(int y);

  void sendPrimaryDeviceAttributes();

  /// Handles TBC 0 / clear tab stop at the cursor column.
  ///
  /// Clears only the tab stop under the current cursor and does not move the
  /// cursor. Use [clearAllTabStops] for TBC 3.
  void clearTabStopUnderCursor();

  /// Handles TBC 3 / clear all tab stops.
  ///
  /// Removes all configured tab stops without moving the cursor or resetting
  /// them to defaults. Use [clearTabStopUnderCursor] for TBC 0.
  void clearAllTabStops();

  void moveCursorX(int offset);

  void moveCursorY(int n);

  void sendSecondaryDeviceAttributes();

  void sendTertiaryDeviceAttributes();

  void sendOperatingStatus();

  void sendCursorPosition();

  /// Handles DEC private DSR 6 / extended cursor position report.
  ///
  /// Sends the DEC-style cursor position response to the host. This differs
  /// from [sendCursorPosition], which handles the non-private DSR 6 response.
  void sendExtendedCursorPosition();

  void setMargins(int i, [int? bottom]);

  /// Handles CNL / cursor next line.
  ///
  /// [amount] is the number of rows to move down; parser defaults omitted or
  /// zero values to 1. Implementers also move the cursor to column 0.
  void cursorNextLine(int amount);

  /// Handles CPL / cursor preceding line.
  ///
  /// [amount] is the number of rows to move up; parser defaults omitted or zero
  /// values to 1. Implementers also move the cursor to column 0.
  void cursorPrecedingLine(int amount);

  void eraseDisplayBelow();

  void eraseDisplayAbove();

  void eraseDisplay();

  /// Handles ED 3 / erase scrollback.
  ///
  /// Clears scrollback history without erasing visible display cells. This is
  /// separate from [eraseDisplay], [eraseDisplayBelow], and [eraseDisplayAbove].
  void eraseScrollbackOnly();

  void eraseLineRight();

  void eraseLineLeft();

  void eraseLine();

  void insertLines(int amount);

  void deleteLines(int amount);

  void deleteChars(int amount);

  void scrollUp(int amount);

  void scrollDown(int amount);

  void eraseChars(int amount);

  /// Handles ICH / insert blank characters.
  ///
  /// [amount] is the number of blank cells to insert at the cursor; parser
  /// defaults omitted or zero values to 1. Existing cells shift right and cells
  /// pushed past the line end are discarded.
  void insertBlankChars(int amount);

  void unknownCSI(int finalByte);

  /* Modes */

  void setInsertMode(bool enabled);

  void setLineFeedMode(bool enabled);

  void setUnknownMode(int mode, bool enabled);

  /* DEC Private modes */

  void setCursorKeysMode(bool enabled);

  void setReverseDisplayMode(bool enabled);

  void setOriginMode(bool enabled);

  void setColumnMode(bool enabled);

  void setAutoWrapMode(bool enabled);

  void setAnsiMode(bool enabled);

  void setMouseMode(MouseMode mode);

  void setCursorBlinkMode(bool enabled);

  void setCursorVisibleMode(bool enabled);

  /// Handles DECSCUSR / set cursor style.
  ///
  /// [shape] is the numeric DECSCUSR parameter; 0 clears any override and other
  /// supported values select block, underline, or bar shapes. Implementers
  /// should update cursor rendering state, not move the cursor.
  void setCursorShape(int shape);

  void useAltBuffer();

  void useMainBuffer();

  void clearAltBuffer();

  void setAppKeypadMode(bool enabled);

  /// Handles DECSET/DECRST 1004 / focus event reporting.
  ///
  /// [enabled] reflects whether the mode is being set or reset. When enabled,
  /// focus changes should later be reported by the input/focus path.
  void setReportFocusMode(bool enabled);

  void setMouseReportMode(MouseReportMode mode);

  /// Handles DECSET/DECRST 1007 / alternate-scroll mouse mode.
  ///
  /// [enabled] reflects whether the mode is being set or reset. This affects
  /// mouse-wheel behavior in the alternate buffer and should not switch buffers.
  void setAltBufferMouseScrollMode(bool enabled);

  /// Handles DECSET/DECRST 2004 / bracketed paste mode.
  ///
  /// [enabled] reflects whether paste bracketing is active. When enabled,
  /// paste input should be wrapped by the input path, not emitted here.
  void setBracketedPasteMode(bool enabled);

  void setUnknownDecMode(int mode, bool enabled);

  /// Handles window manipulation resize requests.
  ///
  /// [cols] and [rows] are requested terminal dimensions in cells and are
  /// positive values parsed from the sequence. Implementers resize the viewport
  /// as if requested externally.
  void resize(int cols, int rows);

  /// Handles window manipulation size reports.
  ///
  /// Sends the terminal size in characters to the host. This reports state only
  /// and must not resize the terminal.
  void sendSize();

  /* Select Graphic Rendition (SGR) */

  void resetCursorStyle();

  void setCursorBold();

  void setCursorFaint();

  void setCursorItalic();

  void setCursorUnderline();

  void setCursorBlink();

  void setCursorInverse();

  void setCursorInvisible();

  void setCursorStrikethrough();

  void setCursorOverline();

  void unsetCursorBold();

  void unsetCursorFaint();

  void unsetCursorItalic();

  void unsetCursorUnderline();

  void unsetCursorBlink();

  void unsetCursorInverse();

  void unsetCursorInvisible();

  void unsetCursorStrikethrough();

  void unsetCursorOverline();

  void setForegroundColor16(int color);

  void setForegroundColor256(int index);

  void setForegroundColorRgb(int r, int g, int b);

  void resetForeground();

  void setBackgroundColor16(int color);

  void setBackgroundColor256(int index);

  void setBackgroundColorRgb(int r, int g, int b);

  void resetBackground();

  void unsupportedStyle(int param);

  /* OSC */

  void setTitle(String name);

  void setIconName(String name);

  void unknownOSC(String code, List<String> args);
}
