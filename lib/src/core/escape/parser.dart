import 'package:xterm/src/core/color.dart';
import 'package:xterm/src/core/mouse/mode.dart';
import 'package:xterm/src/core/escape/handler.dart';
import 'package:xterm/src/utils/ascii.dart';
import 'package:xterm/src/utils/byte_consumer.dart';
import 'package:xterm/src/utils/char_code.dart';
import 'package:xterm/src/utils/lookup_table.dart';

/// [EscapeParser] translates control characters and escape sequences into
/// function calls that the terminal can handle.
///
/// Design goals:
///  * Zero object allocation during processing.
///  * No internal state. Same input will always produce same output.
class EscapeParser {
  final EscapeHandler handler;

  EscapeParser(this.handler);

  final _queue = ByteConsumer();

  /// Start of sequence or character being processed. Useful for debugging.
  var tokenBegin = 0;

  /// End of sequence or character being processed. Useful for debugging.
  int get tokenEnd => _queue.totalConsumed;

  void write(String chunk) {
    _queue.unrefConsumedBlocks();
    _queue.add(chunk);
    _process();
  }

  void _process() {
    while (_queue.isNotEmpty) {
      tokenBegin = _queue.totalConsumed;
      final char = _queue.consume();

      if (char == Ascii.ESC) {
        final processed = _processEscape();
        if (!processed) {
          _queue.rollback(tokenEnd - tokenBegin);
          return;
        }
      } else if (char == _c1ControlSequenceIntroducer) {
        final processed = _escHandleCSI();
        if (!processed) {
          _queue.rollback(tokenEnd - tokenBegin);
          return;
        }
      } else if (char == _c1OperatingSystemCommand) {
        final processed = _escHandleOSC();
        if (!processed) {
          _queue.rollback(tokenEnd - tokenBegin);
          return;
        }
      } else if (_processC1Control(char)) {
        // Handled above.
      } else if (char == _c1SingleShift2) {
        handler.singleShift(2);
      } else if (char == _c1SingleShift3) {
        handler.singleShift(3);
      } else if (_isC1StringControl(char)) {
        final processed = _consumeStringControl();
        if (!processed) {
          _queue.rollback(tokenEnd - tokenBegin);
          return;
        }
      } else {
        _processChar(char);
      }
    }
  }

  bool _processC1Control(int char) {
    switch (char) {
      case _c1Index:
        handler.index();
        return true;
      case _c1NextLine:
        handler.nextLine();
        return true;
      case _c1HorizontalTabSet:
        handler.setTapStop();
        return true;
      case _c1ReverseIndex:
        handler.reverseIndex();
        return true;
      default:
        return false;
    }
  }

  void _processChar(int char) {
    if (char == Ascii.NULL || _isCancelControl(char) || char == Ascii.DEL) {
      return;
    }

    if (_isC1Control(char)) {
      handler.unknownSBC(char);
      return;
    }

    if (char > _sbcHandlers.maxIndex) {
      handler.writeChar(char);
      return;
    }

    final sbcHandler = _sbcHandlers[char];
    if (sbcHandler == null) {
      handler.unknownSBC(char);
      return;
    }

    sbcHandler();
  }

  /// Processes a sequence of characters that starts with an escape character.
  /// Returns [true] if the sequence was processed, [false] if it was not.
  bool _processEscape() {
    while (true) {
      if (_queue.isEmpty) return false;

      final escapeChar = _queue.consume();

      if (_isCancelControl(escapeChar)) {
        return true;
      }

      if (escapeChar == Ascii.NULL || escapeChar == Ascii.DEL) {
        continue;
      }

      if (escapeChar == Ascii.ESC) {
        continue;
      }

      if (escapeChar > Ascii.NULL && escapeChar < Ascii.space) {
        _processChar(escapeChar);
        continue;
      }

      final escapeHandler = _escHandlers[escapeChar];

      if (escapeHandler == null) {
        handler.unkownEscape(escapeChar);
        return true;
      }

      return escapeHandler();
    }
  }

  late final _sbcHandlers = FastLookupTable<_SbcHandler>({
    0x07: handler.bell,
    0x08: handler.backspaceReturn,
    0x09: handler.tab,
    0x0a: handler.lineFeed,
    0x0b: handler.lineFeed,
    0x0c: handler.lineFeed,
    0x0d: handler.carriageReturn,
    0x0e: handler.shiftOut,
    0x0f: handler.shiftIn,
  });

  late final _escHandlers = FastLookupTable<_EscHandler>({
    '['.charCode: _escHandleCSI,
    ']'.charCode: _escHandleOSC,
    ' '.charCode: _escHandleSpace,
    '6'.charCode: _escHandleBackIndex,
    '7'.charCode: _escHandleSaveCursor,
    '8'.charCode: _escHandleRestoreCursor,
    '9'.charCode: _escHandleForwardIndex,
    'D'.charCode: _escHandleIndex,
    'E'.charCode: _escHandleNextLine,
    'H'.charCode: _escHandleTabSet,
    'M'.charCode: _escHandleReverseIndex,
    'N'.charCode: _escHandleSingleShift2,
    'O'.charCode: _escHandleSingleShift3,
    'P'.charCode: _escHandleStringControl, // DCS
    'X'.charCode: _escHandleStringControl, // SOS
    'Z'.charCode: _escHandleIdentifyTerminal,
    '^'.charCode: _escHandleStringControl, // PM
    '_'.charCode: _escHandleStringControl, // APC
    'c'.charCode: _escHandleResetTerminal,
    '#'.charCode: _escHandleHash,
    '%'.charCode: _escHandleDesignateCodingSystem,
    '('.charCode: _escHandleDesignateCharset0, //  SCS - G0
    ')'.charCode: _escHandleDesignateCharset1, //  SCS - G1
    '*'.charCode: _escHandleDesignateCharset2,
    '+'.charCode: _escHandleDesignateCharset3,
    '-'.charCode: _escHandleDesignateCharset1,
    '.'.charCode: _escHandleDesignateCharset2,
    '/'.charCode: _escHandleDesignateCharset3,
    '<'.charCode: _escHandleEnterAnsiMode,
    '='.charCode: _escHandleSetAppKeypadMode,
    '>'.charCode: _escHandleResetAppKeypadMode,
  });

  /// `ESC SP F`/`ESC SP G` select 7-bit/8-bit C1 controls (S7C1T/S8C1T).
  ///
  /// Both forms of C1 controls are accepted by this parser, so the sequence is
  /// consumed without changing runtime state.
  bool _escHandleSpace() {
    return _consumeEscapeFinalByte() != null;
  }

  /// `ESC 6` Back Index (DECBI)
  bool _escHandleBackIndex() {
    handler.backIndex();
    return true;
  }

  /// `ESC 9` Forward Index (DECFI)
  bool _escHandleForwardIndex() {
    handler.forwardIndex();
    return true;
  }

  /// `ESC 7` Save Cursor (DECSC)
  ///
  /// https://terminalguide.namepad.de/seq/a_esc_a7/
  bool _escHandleSaveCursor() {
    handler.saveCursor();
    return true;
  }

  /// `ESC 8` Restore Cursor (DECRC)
  ///
  /// https://terminalguide.namepad.de/seq/a_esc_a8/
  bool _escHandleRestoreCursor() {
    handler.restoreCursor();
    return true;
  }

  /// `ESC D` Index (IND)
  ///
  /// https://terminalguide.namepad.de/seq/a_esc_cd/
  bool _escHandleIndex() {
    handler.index();
    return true;
  }

  /// `ESC E` Next Line (NEL)
  ///
  /// https://terminalguide.namepad.de/seq/a_esc_ce/
  bool _escHandleNextLine() {
    handler.nextLine();
    return true;
  }

  /// `ESC H` Horizontal Tab Set (HTS)
  ///
  /// https://terminalguide.namepad.de/seq/a_esc_ch/
  bool _escHandleTabSet() {
    handler.setTapStop();
    return true;
  }

  /// `ESC M` Reverse Index (RI)
  ///
  /// https://terminalguide.namepad.de/seq/a_esc_cm/
  bool _escHandleReverseIndex() {
    handler.reverseIndex();
    return true;
  }

  bool _escHandleDesignateCodingSystem() {
    final code = _consumeEscapeFinalByte();
    if (code == null) return false;
    return true;
  }

  int? _consumeEscapeFinalByte() {
    while (true) {
      if (_queue.isEmpty) return null;
      final char = _queue.consume();

      if (_isCancelControl(char)) {
        return _escapeSequenceCanceled;
      }

      if (char == Ascii.ESC) {
        _queue.rollback();
        return _escapeSequenceCanceled;
      }

      if (char == Ascii.NULL || char == Ascii.DEL) {
        continue;
      }

      if (char > Ascii.NULL && char < Ascii.space) {
        _processChar(char);
        continue;
      }

      return char;
    }
  }

  bool _escHandleSingleShift2() {
    handler.singleShift(2);
    return true;
  }

  bool _escHandleSingleShift3() {
    handler.singleShift(3);
    return true;
  }

  bool _escHandleDesignateCharset0() {
    return _escHandleDesignateCharset(0);
  }

  bool _escHandleDesignateCharset1() {
    return _escHandleDesignateCharset(1);
  }

  bool _escHandleDesignateCharset2() {
    return _escHandleDesignateCharset(2);
  }

  bool _escHandleDesignateCharset3() {
    return _escHandleDesignateCharset(3);
  }

  bool _escHandleDesignateCharset(int charset) {
    final name = _consumeEscapeFinalByte();
    if (name == null) return false;
    if (name != _escapeSequenceCanceled) {
      handler.designateCharset(charset, name);
    }
    return true;
  }

  /// `ESC =` Set Application Keypad Mode (DECKPAM)
  ///
  /// https://terminalguide.namepad.de/seq/a_esc_x3d_equals/
  bool _escHandleStringControl() {
    return _consumeStringControl();
  }

  /// `ESC <` Exit VT52 mode and enter ANSI mode.
  bool _escHandleEnterAnsiMode() {
    handler.setAnsiMode(true);
    return true;
  }

  /// `ESC Z` Identify Terminal (DECID), obsolete alias for primary DA.
  bool _escHandleIdentifyTerminal() {
    handler.sendPrimaryDeviceAttributes();
    return true;
  }

  /// `ESC c` Reset to Initial State (RIS)
  bool _escHandleResetTerminal() {
    handler.resetTerminal();
    return true;
  }

  bool _escHandleHash() {
    final code = _consumeEscapeFinalByte();
    if (code == null) return false;
    if (code == Ascii.num8) {
      handler.screenAlignmentPattern();
    }
    return true;
  }

  bool _escHandleSetAppKeypadMode() {
    handler.setAppKeypadMode(true);
    return true;
  }

  /// `ESC >` Reset Application Keypad Mode (DECKPNM)
  ///
  /// https://terminalguide.namepad.de/seq/a_esc_x3c_greater_than/
  bool _escHandleResetAppKeypadMode() {
    handler.setAppKeypadMode(false);
    return true;
  }

  bool _escHandleCSI() {
    final consumed = _consumeCsi();
    if (!consumed) return false;

    if (_csi.finalByte == 0) {
      return true;
    }

    if (_csi.intermediates.isNotEmpty &&
        _csi.finalByte != Ascii.p &&
        _csi.finalByte != Ascii.q) {
      handler.unknownCSI(_csi.finalByte);
      return true;
    }

    if (_csi.prefix != null && !_isSupportedPrefixedCsi()) {
      handler.unknownCSI(_csi.finalByte);
      return true;
    }

    final csiHandler = _csiHandlers[_csi.finalByte];

    if (csiHandler == null) {
      handler.unknownCSI(_csi.finalByte);
    } else {
      csiHandler();
    }

    return true;
  }

  /// The last parsed [_Csi]. This is a mutable singletion by design to reduce
  /// object allocations.
  final _csi = _Csi(
    finalByte: 0,
    params: [],
    separators: [],
    intermediates: [],
  );

  /// Parse a CSI from the head of the queue. Return false if the CSI isn't
  /// complete. After a CSI is successfully parsed, [_csi] is updated.
  bool _consumeCsi() {
    if (_queue.isEmpty) {
      return false;
    }

    _csi.params.clear();
    _csi.separators.clear();
    _csi.intermediates.clear();

    // test whether the csi is a `CSI ? Ps ...` or `CSI Ps ...`
    final prefix = _queue.peek();
    if (prefix >= Ascii.lessThan && prefix <= Ascii.questionMark) {
      _csi.prefix = prefix;
      _queue.consume();
    } else {
      _csi.prefix = null;
    }

    var param = 0;
    var hasParam = false;
    while (true) {
      // The sequence isn't completed, just ignore it.
      if (_queue.isEmpty) {
        return false;
      }

      final char = _queue.consume();

      if (_isCancelControl(char)) {
        _csi.finalByte = 0;
        return true;
      }

      if (char == Ascii.ESC) {
        _queue.rollback();
        _csi.finalByte = 0;
        return true;
      }

      if (char > Ascii.NULL && char < Ascii.space) {
        _processChar(char);
        continue;
      }

      if (char == Ascii.semicolon || char == Ascii.colon) {
        _csi.separators.add(char);
        _csi.params.add(hasParam ? param : 0);
        param = 0;
        hasParam = false;
        continue;
      }

      if (char >= Ascii.num0 && char <= Ascii.num9) {
        hasParam = true;
        param *= 10;
        param += char - Ascii.num0;
        continue;
      }

      if (char > Ascii.NULL && char < Ascii.num0) {
        _csi.intermediates.add(char);
        continue;
      }

      if (char >= Ascii.atSign && char <= Ascii.tilde) {
        if (hasParam || _csi.params.isNotEmpty) {
          _csi.params.add(hasParam ? param : 0);
        }

        _csi.finalByte = char;
        return true;
      }
    }
  }

  bool _isSupportedPrefixedCsi() {
    switch (_csi.finalByte) {
      case Ascii.c:
        return _csi.prefix == Ascii.greaterThan || _csi.prefix == Ascii.equal;
      case Ascii.h:
      case Ascii.l:
      case Ascii.n:
      case Ascii.J:
      case Ascii.K:
        return _csi.prefix == Ascii.questionMark;
      default:
        return false;
    }
  }

  late final _csiHandlers = FastLookupTable<_CsiHandler>({
    '`'.codeUnitAt(0): _csiHandleCursorHorizontalAbsolute,
    'a'.codeUnitAt(0): _csiHandleCursorForward,
    'b'.codeUnitAt(0): _csiHandleRepeatPreviousCharacter,
    'c'.codeUnitAt(0): _csiHandleSendDeviceAttributes,
    'd'.codeUnitAt(0): _csiHandleLinePositionAbsolute,
    'e'.codeUnitAt(0): _csiHandleCursorDown,
    'f'.codeUnitAt(0): _csiHandleCursorPosition,
    'g'.codeUnitAt(0): _csiHandelClearTabStop,
    'h'.codeUnitAt(0): _csiHandleMode,
    'l'.codeUnitAt(0): _csiHandleMode,
    'm'.codeUnitAt(0): _csiHandleSgr,
    'n'.codeUnitAt(0): _csiHandleDeviceStatusReport,
    'p'.codeUnitAt(0): _csiHandleSoftReset,
    'q'.codeUnitAt(0): _csiHandleSetCursorShape,
    'r'.codeUnitAt(0): _csiHandleSetMargins,
    's'.codeUnitAt(0): _csiHandleSaveCursor,
    't'.codeUnitAt(0): _csiWindowManipulation,
    'u'.codeUnitAt(0): _csiHandleRestoreCursor,
    'A'.codeUnitAt(0): _csiHandleCursorUp,
    'B'.codeUnitAt(0): _csiHandleCursorDown,
    'C'.codeUnitAt(0): _csiHandleCursorForward,
    'D'.codeUnitAt(0): _csiHandleCursorBackward,
    'E'.codeUnitAt(0): _csiHandleCursorNextLine,
    'F'.codeUnitAt(0): _csiHandleCursorPrecedingLine,
    'G'.codeUnitAt(0): _csiHandleCursorHorizontalAbsolute,
    'H'.codeUnitAt(0): _csiHandleCursorPosition,
    'I'.codeUnitAt(0): _csiHandleCursorForwardTab,
    'J'.codeUnitAt(0): _csiHandleEraseDisplay,
    'K'.codeUnitAt(0): _csiHandleEraseLine,
    'L'.codeUnitAt(0): _csiHandleInsertLines,
    'M'.codeUnitAt(0): _csiHandleDeleteLines,
    'P'.codeUnitAt(0): _csiHandleDelete,
    'S'.codeUnitAt(0): _csiHandleScrollUp,
    'T'.codeUnitAt(0): _csiHandleScrollDown,
    'X'.codeUnitAt(0): _csiHandleEraseCharacters,
    'Z'.codeUnitAt(0): _csiHandleCursorBackwardTab,
    '@'.codeUnitAt(0): _csiHandleInsertBlankCharacters,
  });

  /// `ESC [ Ps b` Repeat Previous Character (REP)
  ///
  /// https://terminalguide.namepad.de/seq/csi_sb/
  void _csiHandleRepeatPreviousCharacter() {
    var amount = 1;

    if (_csi.params.isNotEmpty) {
      amount = _csi.params[0];
      if (amount == 0) amount = 1;
    }

    handler.repeatPreviousCharacter(amount);
  }

  /// `ESC [ Ps c` Device Attributes (DA)
  ///
  /// https://terminalguide.namepad.de/seq/csi_sc/
  void _csiHandleSendDeviceAttributes() {
    for (final request in _csi.params) {
      if (request != 0) {
        return;
      }
    }

    switch (_csi.prefix) {
      case null:
        return handler.sendPrimaryDeviceAttributes();
      case Ascii.greaterThan:
        return handler.sendSecondaryDeviceAttributes();
      case Ascii.equal:
        return handler.sendTertiaryDeviceAttributes();
    }
  }

  /// `ESC [ Ps d` Cursor Vertical Position Absolute (VPA)
  ///
  /// https://terminalguide.namepad.de/seq/csi_sd/
  void _csiHandleLinePositionAbsolute() {
    final y = _paramOrDefault(0, 1);

    handler.setCursorY(y - 1);
  }

  /// `ESC [ Ps ; Ps f` Alias: Set Cursor Position
  ///
  /// https://terminalguide.namepad.de/seq/csi_sf/
  void _csiHandleCursorPosition() {
    final row = _paramOrDefault(0, 1);
    final col = _paramOrDefault(1, 1);

    handler.setCursor(col - 1, row - 1);
  }

  /// `ESC [ Ps g` Tab Clear (TBC)
  ///
  /// https://terminalguide.namepad.de/seq/csi_sg/
  void _csiHandelClearTabStop() {
    var cmd = 0;

    if (_csi.params.isNotEmpty) {
      cmd = _csi.params[0];
    }

    switch (cmd) {
      case 0:
        return handler.clearTabStopUnderCursor();
      case 3:
        return handler.clearAllTabStops();
    }
  }

  /// - `ESC [ [ Pm ] h Set Mode (SM)` https://terminalguide.namepad.de/seq/csi_sm/
  /// - `ESC [ ? [ Pm ] h` Set Mode (?) (SM) https://terminalguide.namepad.de/seq/csi_sh__p/
  /// - `ESC [ [ Pm ] l` Reset Mode (RM) https://terminalguide.namepad.de/seq/csi_rm/
  /// - `ESC [ ? [ Pm ] l` Reset Mode (?) (RM) https://terminalguide.namepad.de/seq/csi_sl__p/
  void _csiHandleMode() {
    final isEnabled = _csi.finalByte == Ascii.h;

    final isDecModes = _csi.prefix == Ascii.questionMark;

    if (isDecModes) {
      for (var mode in _csi.params) {
        _setDecMode(mode, isEnabled);
      }
    } else {
      for (var mode in _csi.params) {
        _setMode(mode, isEnabled);
      }
    }
  }

  /// `ESC [ [ Ps ] m` Select Graphic Rendition (SGR)
  ///
  /// https://terminalguide.namepad.de/seq/csi_sm/
  void _csiHandleSgr() {
    final params = _csi.params;

    if (params.isEmpty) {
      return handler.resetCursorStyle();
    }

    // This is a workaround for a bug in the analyzer.
    // ignore: dead_code
    for (var i = 0; i < _csi.params.length; i++) {
      final param = params[i];
      switch (param) {
        case 0:
          handler.resetCursorStyle();
          continue;
        case 1:
          handler.setCursorBold();
          continue;
        case 2:
          handler.setCursorFaint();
          continue;
        case 3:
          handler.setCursorItalic();
          continue;
        case 4:
          if (_isColonSubParam(i, 0)) {
            handler.unsetCursorUnderline();
          } else {
            handler.setCursorUnderline();
          }
          i = _skipColonSubParams(i);
          continue;
        case 5:
        case 6:
          handler.setCursorBlink();
          continue;
        case 7:
          handler.setCursorInverse();
          continue;
        case 8:
          handler.setCursorInvisible();
          continue;
        case 9:
          handler.setCursorStrikethrough();
          continue;

        case 21:
          handler.setCursorUnderline();
          continue;
        case 22:
          handler.unsetCursorBold();
          handler.unsetCursorFaint();
          continue;
        case 23:
          handler.unsetCursorItalic();
          continue;
        case 24:
          handler.unsetCursorUnderline();
          continue;
        case 25:
          handler.unsetCursorBlink();
          continue;
        case 27:
          handler.unsetCursorInverse();
          continue;
        case 28:
          handler.unsetCursorInvisible();
          continue;
        case 29:
          handler.unsetCursorStrikethrough();
          continue;

        case 30:
          handler.setForegroundColor16(NamedColor.black);
          continue;
        case 31:
          handler.setForegroundColor16(NamedColor.red);
          continue;
        case 32:
          handler.setForegroundColor16(NamedColor.green);
          continue;
        case 33:
          handler.setForegroundColor16(NamedColor.yellow);
          continue;
        case 34:
          handler.setForegroundColor16(NamedColor.blue);
          continue;
        case 35:
          handler.setForegroundColor16(NamedColor.magenta);
          continue;
        case 36:
          handler.setForegroundColor16(NamedColor.cyan);
          continue;
        case 37:
          handler.setForegroundColor16(NamedColor.white);
          continue;
        case 38:
          if (i + 1 >= params.length) continue;
          final mode = params[i + 1];
          switch (mode) {
            case 2:
              if (_hasColonColorSpace(i)) {
                final r = params[i + 3];
                final g = params[i + 4];
                final b = params[i + 5];
                handler.setForegroundColorRgb(r, g, b);
                i += 5;
                break;
              }
              if (i + 4 >= params.length) {
                i = params.length;
                break;
              }
              final r = params[i + 2];
              final g = params[i + 3];
              final b = params[i + 4];
              handler.setForegroundColorRgb(r, g, b);
              i += 4;
              break;
            case 5:
              if (i + 2 >= params.length) {
                i += 1;
                break;
              }
              final index = params[i + 2];
              handler.setForegroundColor256(index);
              i += 2;
              break;
            default:
              i += 1;
              break;
          }
          continue;
        case 39:
          handler.resetForeground();
          continue;

        case 40:
          handler.setBackgroundColor16(NamedColor.black);
          continue;
        case 41:
          handler.setBackgroundColor16(NamedColor.red);
          continue;
        case 42:
          handler.setBackgroundColor16(NamedColor.green);
          continue;
        case 43:
          handler.setBackgroundColor16(NamedColor.yellow);
          continue;
        case 44:
          handler.setBackgroundColor16(NamedColor.blue);
          continue;
        case 45:
          handler.setBackgroundColor16(NamedColor.magenta);
          continue;
        case 46:
          handler.setBackgroundColor16(NamedColor.cyan);
          continue;
        case 47:
          handler.setBackgroundColor16(NamedColor.white);
          continue;
        case 48:
          if (i + 1 >= params.length) continue;
          final mode = params[i + 1];
          switch (mode) {
            case 2:
              if (_hasColonColorSpace(i)) {
                final r = params[i + 3];
                final g = params[i + 4];
                final b = params[i + 5];
                handler.setBackgroundColorRgb(r, g, b);
                i += 5;
                break;
              }
              if (i + 4 >= params.length) {
                i = params.length;
                break;
              }
              final r = params[i + 2];
              final g = params[i + 3];
              final b = params[i + 4];
              handler.setBackgroundColorRgb(r, g, b);
              i += 4;
              break;
            case 5:
              if (i + 2 >= params.length) {
                i += 1;
                break;
              }
              final index = params[i + 2];
              handler.setBackgroundColor256(index);
              i += 2;
              break;
            default:
              i += 1;
              break;
          }
          continue;
        case 49:
          handler.resetBackground();
          continue;

        case 53:
          handler.setCursorOverline();
          continue;
        case 58:
          i = _skipUnsupportedExtendedColor(i);
          continue;
        case 59:
          continue;
        case 55:
          handler.unsetCursorOverline();
          continue;

        case 90:
          handler.setForegroundColor16(NamedColor.brightBlack);
          continue;
        case 91:
          handler.setForegroundColor16(NamedColor.brightRed);
          continue;
        case 92:
          handler.setForegroundColor16(NamedColor.brightGreen);
          continue;
        case 93:
          handler.setForegroundColor16(NamedColor.brightYellow);
          continue;
        case 94:
          handler.setForegroundColor16(NamedColor.brightBlue);
          continue;
        case 95:
          handler.setForegroundColor16(NamedColor.brightMagenta);
          continue;
        case 96:
          handler.setForegroundColor16(NamedColor.brightCyan);
          continue;
        case 97:
          handler.setForegroundColor16(NamedColor.brightWhite);
          continue;

        case 100:
          handler.setBackgroundColor16(NamedColor.brightBlack);
          continue;
        case 101:
          handler.setBackgroundColor16(NamedColor.brightRed);
          continue;
        case 102:
          handler.setBackgroundColor16(NamedColor.brightGreen);
          continue;
        case 103:
          handler.setBackgroundColor16(NamedColor.brightYellow);
          continue;
        case 104:
          handler.setBackgroundColor16(NamedColor.brightBlue);
          continue;
        case 105:
          handler.setBackgroundColor16(NamedColor.brightMagenta);
          continue;
        case 106:
          handler.setBackgroundColor16(NamedColor.brightCyan);
          continue;
        case 107:
          handler.setBackgroundColor16(NamedColor.brightWhite);
          continue;

        default:
          handler.unsupportedStyle(param);
          continue;
      }
    }
  }

  /// `ESC [ Ps n` Device Status Report [Dispatch] (DSR)
  ///
  /// https://terminalguide.namepad.de/seq/csi_sn/
  void _csiHandleDeviceStatusReport() {
    if (_csi.params.length != 1) return;

    switch (_csi.params[0]) {
      case 5:
        if (_csi.prefix == null) {
          return handler.sendOperatingStatus();
        }
        return;
      case 6:
        if (_csi.prefix == Ascii.questionMark) {
          return handler.sendExtendedCursorPosition();
        }
        if (_csi.prefix == null) {
          return handler.sendCursorPosition();
        }
        return;
    }
  }

  /// `ESC [ Ps SP q` Set Cursor Style (DECSCUSR)
  void _csiHandleSetCursorShape() {
    if (_csi.intermediates.length == 1 &&
        _csi.intermediates[0] == Ascii.space) {
      handler.setCursorShape(_paramOrDefault(0, 0));
    } else {
      handler.unknownCSI(_csi.finalByte);
    }
  }

  /// `ESC [ ! p` Soft Terminal Reset (DECSTR)
  void _csiHandleSoftReset() {
    if (_csi.intermediates.length == 1 &&
        _csi.intermediates[0] == Ascii.exclamationMark) {
      handler.softResetTerminal();
    } else {
      handler.unknownCSI(_csi.finalByte);
    }
  }

  /// `ESC [ Ps ; Ps r` Set Top and Bottom Margins (DECSTBM)
  ///
  /// https://terminalguide.namepad.de/seq/csi_sr/
  void _csiHandleSetMargins() {
    var top = 1;
    int? bottom;

    if (_csi.params.length > 2) return;

    if (_csi.params.isNotEmpty) {
      top = _paramOrDefault(0, 1);

      if (_csi.params.length == 2 && _csi.params[1] != 0) {
        bottom = _csi.params[1] - 1;
      }
    }

    handler.setMargins(top - 1, bottom);
  }

  /// `ESC [ s` Save Cursor (SCOSC)
  void _csiHandleSaveCursor() {
    handler.saveCursor();
  }

  /// `ESC [ u` Restore Cursor (SCORC)
  void _csiHandleRestoreCursor() {
    handler.restoreCursor();
  }

  /// `ESC [ Ps t` Window operations [DISPATCH]
  ///
  /// https://terminalguide.namepad.de/seq/csi_st/
  void _csiWindowManipulation() {
    // The sequence needs at least one parameter.
    if (_csi.params.isEmpty) {
      return;
    }
    // Most the commands in this group are either of the scope of this package,
    // or should be disabled for security risks.
    switch (_csi.params.first) {
      // Window handling is currently not in the scope of the package.
      case 1: // Restore Terminal Window (show window if minimized)
      case 2: // Minimize Terminal Window
      case 3: // Set Terminal Window Position
      case 4: // Set Terminal Window Size in Pixels
      case 5: // Raise Terminal Window
      case 6: // Lower Terminal Window
      case 7: // Refresh/Redraw Terminal Window
        return;
      case 8: // Set Terminal Window Size (in characters)
        // This CSI contains 2 more parameters: width and height.
        if (_csi.params.length != 3) {
          return;
        }
        final rows = _csi.params[1];
        final cols = _csi.params[2];
        handler.resize(cols, rows);
        return;
      // Window handling is currently no in the scope of the package.
      case 9: // Maximize Terminal Window
      case 10: // Alias: Maximize Terminal Window
      case 11: // Report Terminal Window State
      case 13: // Report Terminal Window Position
      case 14: // Report Terminal Window Size in Pixels
      case 15: // Report Screen Size in Pixels
      case 16: // Report Cell Size in Pixels
        return;
      case 18: // Report Terminal Size (in characters)
        handler.sendSize();
        return;
      // Screen handling is currently no in the scope of the package.
      case 19: // Report Screen Size (in characters)
      // Disabled as these can a security risk.
      case 20: // Get Icon Title
      case 21: // Get Terminal Title
      // Not implemented.
      case 22: // Push Terminal Title
      case 23: // Pop Terminal Title
        return;
      // Unknown CSI.
      default:
        return;
    }
  }

  /// `ESC [ Ps A` Cursor Up (CUU)
  ///
  /// https://terminalguide.namepad.de/seq/csi_ca/
  void _csiHandleCursorUp() {
    var amount = 1;

    if (_csi.params.isNotEmpty) {
      amount = _csi.params[0];
      if (amount == 0) amount = 1;
    }

    handler.moveCursorY(-amount);
  }

  /// `ESC [ Ps B` Cursor Down (CUD)
  ///
  /// https://terminalguide.namepad.de/seq/csi_cb/
  void _csiHandleCursorDown() {
    var amount = 1;

    if (_csi.params.isNotEmpty) {
      amount = _csi.params[0];
      if (amount == 0) amount = 1;
    }

    handler.moveCursorY(amount);
  }

  /// `ESC [ Ps C` Cursor Right (CUF)
  ///
  /// Cursor Right (CUF)
  void _csiHandleCursorForward() {
    var amount = 1;

    if (_csi.params.isNotEmpty) {
      amount = _csi.params[0];
      if (amount == 0) amount = 1;
    }

    handler.moveCursorX(amount);
  }

  /// `ESC [ Ps D` Cursor Left (CUB)
  ///
  /// https://terminalguide.namepad.de/seq/csi_cd/
  void _csiHandleCursorBackward() {
    var amount = 1;

    if (_csi.params.isNotEmpty) {
      amount = _csi.params[0];
      if (amount == 0) amount = 1;
    }

    handler.moveCursorX(-amount);
  }

  /// `ESC [ Ps E` Cursor Next Line (CNL)
  ///
  /// https://terminalguide.namepad.de/seq/csi_ce/
  void _csiHandleCursorNextLine() {
    var amount = 1;

    if (_csi.params.isNotEmpty) {
      amount = _csi.params[0];
      if (amount == 0) amount = 1;
    }

    handler.cursorNextLine(amount);
  }

  /// `ESC [ Ps F` Cursor Previous Line (CPL)
  ///
  /// https://terminalguide.namepad.de/seq/csi_cf/
  void _csiHandleCursorPrecedingLine() {
    var amount = 1;

    if (_csi.params.isNotEmpty) {
      amount = _csi.params[0];
      if (amount == 0) amount = 1;
    }

    handler.cursorPrecedingLine(amount);
  }

  void _csiHandleCursorHorizontalAbsolute() {
    var x = 1;

    if (_csi.params.isNotEmpty) {
      x = _csi.params[0];
      if (x == 0) x = 1;
    }

    handler.setCursorX(x - 1);
  }

  /// `ESC [ Ps I` Cursor Forward Tabulation (CHT)
  ///
  /// Moves the cursor to the next tab stop [amount] times.
  void _csiHandleCursorForwardTab() {
    final amount = _paramOrDefault(0, 1);
    for (var i = 0; i < amount; i++) {
      handler.tab();
    }
  }

  /// `ESC [ Ps Z` Cursor Backward Tabulation (CBT)
  ///
  /// Moves the cursor to the previous tab stop [amount] times.
  void _csiHandleCursorBackwardTab() {
    handler.backTab(_paramOrDefault(0, 1));
  }

  /// ESC [ Ps J Erase Display [Dispatch] (ED)
  ///
  /// https://terminalguide.namepad.de/seq/csi_cj/
  void _csiHandleEraseDisplay() {
    var cmd = 0;

    if (_csi.params.isNotEmpty) {
      cmd = _csi.params[0];
    }

    switch (cmd) {
      case 0:
        return handler.eraseDisplayBelow();
      case 1:
        return handler.eraseDisplayAbove();
      case 2:
        return handler.eraseDisplay();
      case 3:
        return handler.eraseScrollbackOnly();
    }
  }

  /// `ESC [ Ps K` Erase Line [Dispatch] (EL)
  ///
  /// https://terminalguide.namepad.de/seq/csi_ck/
  void _csiHandleEraseLine() {
    var cmd = 0;

    if (_csi.params.isNotEmpty) {
      cmd = _csi.params[0];
    }

    switch (cmd) {
      case 0:
        return handler.eraseLineRight();
      case 1:
        return handler.eraseLineLeft();
      case 2:
        return handler.eraseLine();
    }
  }

  /// `ESC [ Ps L` Insert Line (IL)
  ///
  /// https://terminalguide.namepad.de/seq/csi_cl/
  void _csiHandleInsertLines() {
    var amount = 1;

    amount = _paramOrDefault(0, amount);

    handler.insertLines(amount);
  }

  /// ESC [ Ps M Delete Line (DL)
  ///
  /// https://terminalguide.namepad.de/seq/csi_cm/
  void _csiHandleDeleteLines() {
    var amount = 1;

    amount = _paramOrDefault(0, amount);

    handler.deleteLines(amount);
  }

  /// ESC [ Ps P Delete Character (DCH)
  ///
  /// https://terminalguide.namepad.de/seq/csi_cp/
  void _csiHandleDelete() {
    var amount = 1;

    amount = _paramOrDefault(0, amount);

    handler.deleteChars(amount);
  }

  /// `ESC [ Ps S` Scroll Up (SU)
  ///
  /// https://terminalguide.namepad.de/seq/csi_cs/
  void _csiHandleScrollUp() {
    var amount = 1;

    amount = _paramOrDefault(0, amount);

    handler.scrollUp(amount);
  }

  /// `ESC [ Ps T `Scroll Down (SD)
  ///
  /// https://terminalguide.namepad.de/seq/csi_ct_1param/
  void _csiHandleScrollDown() {
    if (_csi.params.length > 1) {
      handler.unknownCSI(_csi.finalByte);
      return;
    }

    var amount = 1;

    amount = _paramOrDefault(0, amount);

    handler.scrollDown(amount);
  }

  /// `ESC [ Ps X` Erase Character (ECH)
  ///
  /// https://terminalguide.namepad.de/seq/csi_cx/
  void _csiHandleEraseCharacters() {
    var amount = 1;

    amount = _paramOrDefault(0, amount);

    handler.eraseChars(amount);
  }

  /// `ESC [ Ps @` Insert Blanks (ICH)
  ///
  /// https://terminalguide.namepad.de/seq/csi_x40_at/
  ///
  /// Inserts amount spaces at current cursor position moving existing cell
  /// contents to the right. The contents of the amount right-most columns in
  /// the scroll region are lost. The cursor position is not changed.
  void _csiHandleInsertBlankCharacters() {
    var amount = 1;

    amount = _paramOrDefault(0, amount);

    handler.insertBlankChars(amount);
  }

  bool _hasColonColorSpace(int index) {
    return index + 5 < _csi.params.length &&
        index + 4 < _csi.separators.length &&
        _csi.separators[index] == Ascii.colon &&
        _csi.separators[index + 1] == Ascii.colon &&
        _csi.separators[index + 2] == Ascii.colon &&
        _csi.separators[index + 3] == Ascii.colon &&
        _csi.separators[index + 4] == Ascii.colon;
  }

  int _skipUnsupportedExtendedColor(int index) {
    if (index + 1 >= _csi.params.length) {
      return index;
    }

    switch (_csi.params[index + 1]) {
      case 2:
        if (_hasColonColorSpace(index)) {
          return index + 5;
        }
        if (index + 4 < _csi.params.length) {
          return index + 4;
        }
        return _csi.params.length;
      case 5:
        final end = index + 2;
        return end < _csi.params.length ? end : _csi.params.length;
      default:
        return index + 1;
    }
  }

  int _skipColonSubParams(int index) {
    while (index < _csi.separators.length &&
        _csi.separators[index] == Ascii.colon) {
      index++;
    }
    return index;
  }

  bool _isColonSubParam(int index, int value) {
    return index < _csi.separators.length &&
        _csi.separators[index] == Ascii.colon &&
        index + 1 < _csi.params.length &&
        _csi.params[index + 1] == value;
  }

  int _paramOrDefault(int index, int defaultValue) {
    if (index >= _csi.params.length || _csi.params[index] == 0) {
      return defaultValue;
    }
    return _csi.params[index];
  }

  void _setMode(int mode, bool enabled) {
    switch (mode) {
      case 4:
        return handler.setInsertMode(enabled);
      case 20:
        return handler.setLineFeedMode(enabled);
      default:
        return handler.setUnknownMode(mode, enabled);
    }
  }

  void _setDecMode(int mode, bool enabled) {
    switch (mode) {
      case 1:
        return handler.setCursorKeysMode(enabled);
      case 2:
        return handler.setAnsiMode(enabled);
      case 3:
        return handler.setColumnMode(enabled);
      case 5:
        return handler.setReverseDisplayMode(enabled);
      case 6:
        return handler.setOriginMode(enabled);
      case 7:
        return handler.setAutoWrapMode(enabled);
      case 9:
        return enabled
            ? handler.setMouseMode(MouseMode.clickOnly)
            : handler.setMouseMode(MouseMode.none);
      case 12:
      case 13:
        return handler.setCursorBlinkMode(enabled);
      case 25:
        return handler.setCursorVisibleMode(enabled);
      case 47:
        if (enabled) {
          return handler.useAltBuffer();
        } else {
          return handler.useMainBuffer();
        }
      case 66:
        return handler.setAppKeypadMode(enabled);
      case 1000:
        return enabled
            ? handler.setMouseMode(MouseMode.upDownScroll)
            : handler.setMouseMode(MouseMode.none);
      case 1001:
        return enabled
            ? handler.setMouseMode(MouseMode.upDownScroll)
            : handler.setMouseMode(MouseMode.none);
      case 1002:
        return enabled
            ? handler.setMouseMode(MouseMode.upDownScrollDrag)
            : handler.setMouseMode(MouseMode.none);
      case 1003:
        return enabled
            ? handler.setMouseMode(MouseMode.upDownScrollMove)
            : handler.setMouseMode(MouseMode.none);
      case 1004:
        return handler.setReportFocusMode(enabled);
      case 1005:
        return enabled
            ? handler.setMouseReportMode(MouseReportMode.utf)
            : handler.setMouseReportMode(MouseReportMode.normal);
      case 1006:
        return enabled
            ? handler.setMouseReportMode(MouseReportMode.sgr)
            : handler.setMouseReportMode(MouseReportMode.normal);
      case 1007:
        return handler.setAltBufferMouseScrollMode(enabled);
      case 1015:
        return enabled
            ? handler.setMouseReportMode(MouseReportMode.urxvt)
            : handler.setMouseReportMode(MouseReportMode.normal);
      case 1047:
        if (enabled) {
          handler.useAltBuffer();
        } else {
          handler.clearAltBuffer();
          handler.useMainBuffer();
        }
        return;
      case 1048:
        if (enabled) {
          return handler.saveCursor();
        } else {
          return handler.restoreCursor();
        }
      case 1049:
        if (enabled) {
          handler.saveCursor();
          handler.clearAltBuffer();
          handler.useAltBuffer();
        } else {
          handler.useMainBuffer();
          handler.restoreCursor();
        }
        return;
      case 2004:
        return handler.setBracketedPasteMode(enabled);
      default:
        return handler.setUnknownDecMode(mode, enabled);
    }
  }

  /// Parse a OSC sequence from the queue. Returns true if a sequence was
  /// found and handled.
  bool _escHandleOSC() {
    final consumed = _consumeOsc();
    if (!consumed) {
      return false;
    }

    if (_osc.isEmpty || (_osc.length == 1 && _osc[0].isEmpty)) {
      return true;
    }

    // Common OSCs
    if (_osc.length >= 2) {
      final ps = _osc[0];
      final pt = _osc.sublist(1).join(';');

      switch (ps) {
        case '0':
          handler.setTitle(pt);
          handler.setIconName(pt);
          return true;
        case '1':
          handler.setIconName(pt);
          return true;
        case '2':
          handler.setTitle(pt);
          return true;
      }
    }

    // Private extensions
    handler.unknownOSC(_osc[0], _osc.sublist(1));

    return true;
  }

  final _osc = <String>[];

  bool _consumeStringControl() {
    while (true) {
      if (_queue.isEmpty) {
        return false;
      }

      final char = _queue.consume();
      if (_isCancelControl(char)) {
        return true;
      }
      if (char == _c1StringTerminator) {
        return true;
      }

      if (char == Ascii.ESC) {
        if (_queue.isEmpty) {
          return false;
        }
        if (_queue.consume() == Ascii.backslash) {
          return true;
        }
      }
    }
  }

  bool _consumeOsc() {
    _osc.clear();
    final param = StringBuffer();

    while (true) {
      if (_queue.isEmpty) {
        return false;
      }

      final char = _queue.consume();

      if (_isCancelControl(char)) {
        _osc.clear();
        return true;
      }

      // OSC terminates with BEL or 8-bit ST.
      if (char == Ascii.BEL || char == _c1StringTerminator) {
        _osc.add(param.toString());
        return true;
      }

      /// OSC terminates with ST
      if (char == Ascii.ESC) {
        if (_queue.isEmpty) {
          return false;
        }

        final next = _queue.consume();
        if (next == Ascii.backslash) {
          _osc.add(param.toString());
          return true;
        }

        param.writeCharCode(char);
        param.writeCharCode(next);
        continue;
      }

      /// Parse next parameter
      if (char == Ascii.semicolon) {
        _osc.add(param.toString());
        param.clear();
        continue;
      }

      param.writeCharCode(char);
    }
  }
}

class _Csi {
  _Csi({
    required this.params,
    required this.separators,
    required this.intermediates,
    required this.finalByte,
  });

  int? prefix;

  List<int> params;

  /// Separators between adjacent [params]. Each entry is either `;` or `:`.
  List<int> separators;

  final List<int> intermediates;

  int finalByte;

  @override
  String toString() {
    return params.join(';') + String.fromCharCode(finalByte);
  }
}

/// Function that handles a sequence of characters that starts with an escape.
/// Returns [true] if the sequence was processed, [false] if it was not.
const _escapeSequenceCanceled = -1;

const _c1Index = 0x84;
const _c1SingleShift2 = 0x8e;
const _c1SingleShift3 = 0x8f;
const _c1NextLine = 0x85;
const _c1HorizontalTabSet = 0x88;
const _c1ReverseIndex = 0x8d;
const _c1DeviceControlString = 0x90;
const _c1StartOfString = 0x98;
const _c1ControlSequenceIntroducer = 0x9b;
const _c1StringTerminator = 0x9c;
const _c1OperatingSystemCommand = 0x9d;
const _c1PrivacyMessage = 0x9e;
const _c1ApplicationProgramCommand = 0x9f;

bool _isCancelControl(int char) {
  return char == Ascii.CAN || char == Ascii.SUB;
}

bool _isC1Control(int char) {
  return char >= 0x80 && char <= 0x9f;
}

bool _isC1StringControl(int char) {
  return char == _c1DeviceControlString ||
      char == _c1StartOfString ||
      char == _c1PrivacyMessage ||
      char == _c1ApplicationProgramCommand;
}

typedef _EscHandler = bool Function();

typedef _SbcHandler = void Function();

typedef _CsiHandler = void Function();
