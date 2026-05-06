import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:test/test.dart';
import 'package:xterm/xterm.dart';

@GenerateNiceMocks([MockSpec<EscapeHandler>()])
import 'parser_test.mocks.dart';

void main() {
  group('EscapeParser', () {
    test('can parse window manipulation', () {
      final parser = EscapeParser(MockEscapeHandler());
      parser.write('\x1b[8;24;80t');
      verify(parser.handler.resize(80, 24));
    });

    test('maps DA requests by prefix', () {
      final handler = MockEscapeHandler();
      final parser = EscapeParser(handler);

      parser.write('\x1b[c\x1b[>c\x1b[=c\x1b[0c\x1b[>0c\x1b[=0c');

      verifyInOrder([
        handler.sendPrimaryDeviceAttributes(),
        handler.sendSecondaryDeviceAttributes(),
        handler.sendTertiaryDeviceAttributes(),
        handler.sendPrimaryDeviceAttributes(),
        handler.sendSecondaryDeviceAttributes(),
        handler.sendTertiaryDeviceAttributes(),
      ]);
    });

    test('does not answer non-zero DA requests', () {
      final handler = MockEscapeHandler();
      final parser = EscapeParser(handler);

      parser.write('\x1b[1c\x1b[>1c\x1b[=1c\x1b[0;1c\x1b[>0;1c\x1b[=0;1c');

      verifyNever(handler.sendPrimaryDeviceAttributes());
      verifyNever(handler.sendSecondaryDeviceAttributes());
      verifyNever(handler.sendTertiaryDeviceAttributes());
    });

    test('does not answer private DA as primary DA', () {
      final handler = MockEscapeHandler();
      final parser = EscapeParser(handler);

      parser.write('\x1b[?c');

      verifyNever(handler.sendPrimaryDeviceAttributes());
    });

    test('does not print ignored control characters', () {
      final handler = MockEscapeHandler();
      final parser = EscapeParser(handler);

      parser.write('\x00\x7f\u0081X');

      verifyNever(handler.writeChar(0));
      verifyNever(handler.writeChar(0x7f));
      verifyNever(handler.writeChar(0x81));
      verifyNever(handler.unknownSBC(0));
      verify(handler.unknownSBC(0x81));
      verify(handler.writeChar('X'.codeUnitAt(0))).called(1);
    });

    test('uses the first parameter for TBC ED and EL', () {
      final handler = MockEscapeHandler();
      final parser = EscapeParser(handler);

      parser.write('\x1b[3;0g\x1b[2;0J\x1b[1;0K');

      verify(handler.clearAllTabStops());
      verify(handler.eraseDisplay());
      verify(handler.eraseLineLeft());
    });

    test('maps selective erase to erase when protection is unsupported', () {
      final handler = MockEscapeHandler();
      final parser = EscapeParser(handler);

      parser.write('\x1b[?2J\x1b[?1K');

      verify(handler.eraseDisplay());
      verify(handler.eraseLineLeft());
    });

    test('maps DECBI and DECFI', () {
      final handler = MockEscapeHandler();
      final parser = EscapeParser(handler);

      parser.write('\x1b6\x1b9');

      verifyInOrder([handler.backIndex(), handler.forwardIndex()]);
    });

    test('handles C1 control mode selection without printing it', () {
      final handler = MockEscapeHandler();
      final parser = EscapeParser(handler);

      parser.write('\x1b F\x1b GZ');

      verifyNever(handler.writeChar('F'.codeUnitAt(0)));
      verifyNever(handler.writeChar('G'.codeUnitAt(0)));
      verify(handler.writeChar('Z'.codeUnitAt(0))).called(1);
    });

    test('handles coding system designation without printing it', () {
      final handler = MockEscapeHandler();
      final parser = EscapeParser(handler);

      parser.write('\x1b%');
      verifyNever(handler.writeChar(any));
      parser.write('GZ');

      verifyNever(handler.writeChar('G'.codeUnitAt(0)));
      verify(handler.writeChar('Z'.codeUnitAt(0))).called(1);
    });

    test('executes C0 controls inside charset designation', () {
      final handler = MockEscapeHandler();
      final parser = EscapeParser(handler);

      parser.write('\x1b(\x070');

      verify(handler.bell());
      verify(handler.designateCharset(0, '0'.codeUnitAt(0)));
    });

    test('executes C0 controls inside ESC state', () {
      final handler = MockEscapeHandler();
      final parser = EscapeParser(handler);

      parser.write('\x1b\x00\x7f\x07c');

      verify(handler.bell());
      verify(handler.resetTerminal());
    });

    test('ESC aborts ESC state and starts a new escape sequence', () {
      final handler = MockEscapeHandler();
      final parser = EscapeParser(handler);

      parser.write('\x1b\x1bc');

      verify(handler.resetTerminal());
      verifyNever(handler.unkownEscape(0x1b));
    });

    test('CAN and SUB cancel ESC state', () {
      final handler = MockEscapeHandler();
      final parser = EscapeParser(handler);

      parser.write('\x1b\x18c\x1b\x1aZ');

      verify(handler.writeChar('c'.codeUnitAt(0))).called(1);
      verify(handler.writeChar('Z'.codeUnitAt(0))).called(1);
      verifyNever(handler.resetTerminal());
      verifyNever(handler.sendPrimaryDeviceAttributes());
    });

    test('ESC aborts charset designation', () {
      final handler = MockEscapeHandler();
      final parser = EscapeParser(handler);

      parser.write('\x1b(\x1b)0');

      verifyNever(handler.designateCharset(0, any));
      verify(handler.designateCharset(1, '0'.codeUnitAt(0)));
    });

    test('supports alternate charset designation prefixes', () {
      final handler = MockEscapeHandler();
      final parser = EscapeParser(handler);

      parser.write('\x1b-0\x1b.0\x1b/0');

      verifyInOrder([
        handler.designateCharset(1, '0'.codeUnitAt(0)),
        handler.designateCharset(2, '0'.codeUnitAt(0)),
        handler.designateCharset(3, '0'.codeUnitAt(0)),
      ]);
    });

    test('maps single shift controls', () {
      final handler = MockEscapeHandler();
      final parser = EscapeParser(handler);

      parser.write('\x1bN\x1bO\u008e\u008f');

      verifyInOrder([
        handler.singleShift(2),
        handler.singleShift(3),
        handler.singleShift(2),
        handler.singleShift(3),
      ]);
    });

    test('supports 8-bit C1 non-string controls', () {
      final handler = MockEscapeHandler();
      final parser = EscapeParser(handler);

      parser.write('\u0084\u0085\u0088\u008d');

      verifyInOrder([
        handler.index(),
        handler.nextLine(),
        handler.setTapStop(),
        handler.reverseIndex(),
      ]);
    });

    test('maps DECALN screen alignment pattern', () {
      final handler = MockEscapeHandler();
      final parser = EscapeParser(handler);

      parser.write('\x1b#8');

      verify(handler.screenAlignmentPattern());
    });

    test('keeps split DECALN pending until final byte', () {
      final handler = MockEscapeHandler();
      final parser = EscapeParser(handler);

      parser.write('\x1b#');
      verifyNever(handler.screenAlignmentPattern());
      parser.write('8');

      verify(handler.screenAlignmentPattern());
    });

    test('maps DECSTR soft terminal reset', () {
      final handler = MockEscapeHandler();
      final parser = EscapeParser(handler);

      parser.write('\x1b[!p');

      verify(handler.softResetTerminal());
      verifyNever(handler.unknownCSI('p'.codeUnitAt(0)));
    });

    test('maps DECSCUSR cursor style', () {
      final handler = MockEscapeHandler();
      final parser = EscapeParser(handler);

      parser.write('\x1b[5 q');

      verify(handler.setCursorShape(5));
      verifyNever(handler.unknownCSI('q'.codeUnitAt(0)));
    });

    test('does not dispatch unsupported intermediate CSI as normal CSI', () {
      final handler = MockEscapeHandler();
      final parser = EscapeParser(handler);

      parser.write('\x1b[!31m');

      verifyNever(handler.setForegroundColor16(NamedColor.red));
      verify(handler.unknownCSI('m'.codeUnitAt(0)));
    });

    test('does not dispatch unsupported prefixed CSI as normal CSI', () {
      final handler = MockEscapeHandler();
      final parser = EscapeParser(handler);

      parser.write('\x1b[?10A');

      verifyNever(handler.moveCursorY(any));
      verify(handler.unknownCSI('A'.codeUnitAt(0)));
    });

    test('does not treat plain CSI p as DECSTR', () {
      final handler = MockEscapeHandler();
      final parser = EscapeParser(handler);

      parser.write('\x1b[p');

      verifyNever(handler.softResetTerminal());
      verify(handler.unknownCSI('p'.codeUnitAt(0)));
    });

    test('maps ESC c to terminal reset', () {
      final handler = MockEscapeHandler();
      final parser = EscapeParser(handler);

      parser.write('\x1bc');

      verify(handler.resetTerminal());
    });

    test('ESC aborts CSI and starts a new escape sequence', () {
      final handler = MockEscapeHandler();
      final parser = EscapeParser(handler);

      parser.write('\x1b[31\x1b[32mX');

      verifyNever(handler.setForegroundColor16(NamedColor.red));
      verify(handler.setForegroundColor16(NamedColor.green));
      verify(handler.writeChar('X'.codeUnitAt(0))).called(1);
    });

    test('executes C0 controls inside CSI sequences', () {
      final handler = MockEscapeHandler();
      final parser = EscapeParser(handler);

      parser.write('\x1b[31\x07m');

      verify(handler.bell());
      verify(handler.setForegroundColor16(NamedColor.red));
    });

    test('CAN and SUB cancel control sequences', () {
      final handler = MockEscapeHandler();
      final parser = EscapeParser(handler);

      parser.write('\x1b[31\x18X');
      parser.write('\x1b]2;ignored\x1aY');
      parser.write('\x1bPignored\x18Z');

      verifyNever(handler.setForegroundColor16(any));
      verifyNever(handler.unknownCSI(any));
      verifyNever(handler.setTitle(any));
      verify(handler.writeChar('X'.codeUnitAt(0))).called(1);
      verify(handler.writeChar('Y'.codeUnitAt(0))).called(1);
      verify(handler.writeChar('Z'.codeUnitAt(0))).called(1);
    });

    test('maps CSI s and u to save and restore cursor', () {
      final handler = MockEscapeHandler();
      final parser = EscapeParser(handler);

      parser.write('\x1b[s\x1b[u');

      verifyInOrder([handler.saveCursor(), handler.restoreCursor()]);
    });

    test('maps private DSR 6 to extended cursor report', () {
      final handler = MockEscapeHandler();
      final parser = EscapeParser(handler);

      parser.write('\x1b[6n\x1b[?6n');

      verifyInOrder([
        handler.sendCursorPosition(),
        handler.sendExtendedCursorPosition(),
      ]);
    });

    test('does not answer unsupported private DSR requests as plain DSR', () {
      final handler = MockEscapeHandler();
      final parser = EscapeParser(handler);

      parser.write('\x1b[?5n');

      verifyNever(handler.sendOperatingStatus());
      verifyNever(handler.sendExtendedCursorPosition());
    });

    test('does not answer multi-parameter DSR requests', () {
      final handler = MockEscapeHandler();
      final parser = EscapeParser(handler);

      parser.write('\x1b[6;1n\x1b[?6;1n\x1b[5;0n');

      verifyNever(handler.sendCursorPosition());
      verifyNever(handler.sendExtendedCursorPosition());
      verifyNever(handler.sendOperatingStatus());
    });

    test('supports cursor forward tabulation', () {
      final handler = MockEscapeHandler();
      final parser = EscapeParser(handler);

      parser.write('\x1b[I\x1b[0I\x1b[2I\x1b[3Z');

      verify(handler.tab()).called(4);
      verify(handler.backTab(3));
    });

    test('supports xterm cursor movement aliases', () {
      final handler = MockEscapeHandler();
      final parser = EscapeParser(handler);

      parser.write('\x1b[3a\x1b[4e\x1b[5`');

      verifyInOrder([
        handler.moveCursorX(3),
        handler.moveCursorY(4),
        handler.setCursorX(4),
      ]);
    });

    test('handles omitted cursor-position parameters as defaults', () {
      final handler = MockEscapeHandler();
      final parser = EscapeParser(handler);

      parser.write('\x1b[5H');
      parser.write('\x1b[;10H');
      parser.write('\x1b[0;0H');
      parser.write('\x1b[0d');

      verifyInOrder([
        handler.setCursor(0, 4),
        handler.setCursor(9, 0),
        handler.setCursor(0, 0),
        handler.setCursorY(0),
      ]);
    });

    test('does not treat multi-parameter CSI T as scroll down', () {
      final handler = MockEscapeHandler();
      final parser = EscapeParser(handler);

      parser.write('\x1b[1;2;3T');

      verifyNever(handler.scrollDown(any));
      verify(handler.unknownCSI('T'.codeUnitAt(0))).called(1);
    });

    test('handles zero counts as one for editing CSI commands', () {
      final handler = MockEscapeHandler();
      final parser = EscapeParser(handler);

      parser.write('\x1b[0P\x1b[0@\x1b[0L\x1b[0M\x1b[0S\x1b[0T\x1b[0X');

      verifyInOrder([
        handler.deleteChars(1),
        handler.insertBlankChars(1),
        handler.insertLines(1),
        handler.deleteLines(1),
        handler.scrollUp(1),
        handler.scrollDown(1),
        handler.eraseChars(1),
      ]);
    });

    test('SGR 6 maps rapid blink to blink style', () {
      final handler = MockEscapeHandler();
      final parser = EscapeParser(handler);

      parser.write('\x1b[6m');

      verify(handler.setCursorBlink()).called(1);
      verifyNever(handler.unsupportedStyle(6));
    });

    test('SGR 21 maps to underline rather than normal intensity', () {
      final handler = MockEscapeHandler();
      final parser = EscapeParser(handler);

      parser.write('\x1b[21m');

      verify(handler.setCursorUnderline());
      verifyNever(handler.unsetCursorBold());
    });

    test('SGR 22 resets both bold and faint intensity', () {
      final handler = MockEscapeHandler();
      final parser = EscapeParser(handler);

      parser.write('\x1b[1;2;22m');

      verifyInOrder([
        handler.setCursorBold(),
        handler.setCursorFaint(),
        handler.unsetCursorBold(),
        handler.unsetCursorFaint(),
      ]);
    });

    test('SGR 53 and 55 set and reset overline', () {
      final handler = MockEscapeHandler();
      final parser = EscapeParser(handler);

      parser.write('\x1b[53;55m');

      verifyInOrder([
        handler.setCursorOverline(),
        handler.unsetCursorOverline(),
      ]);
      verifyNever(handler.unsupportedStyle(53));
      verifyNever(handler.unsupportedStyle(55));
    });

    test('keeps colon SGR subparameters grouped', () {
      final handler = MockEscapeHandler();
      final parser = EscapeParser(handler);

      parser.write('\x1b[4:3m');

      verify(handler.setCursorUnderline());
      verifyNever(handler.setCursorItalic());
    });

    test('SGR 4:0 clears underline', () {
      final handler = MockEscapeHandler();
      final parser = EscapeParser(handler);

      parser.write('\x1b[4:0m');

      verify(handler.unsetCursorUnderline());
      verifyNever(handler.setCursorUnderline());
    });

    test('supports colon-delimited SGR colors', () {
      final handler = MockEscapeHandler();
      final parser = EscapeParser(handler);

      parser.write(
        '\x1b[38:2:1:2:3m\x1b[48:2::4:5:6m\x1b[38:2:1:7:8:9m\x1b[48:5:42m',
      );

      verify(handler.setForegroundColorRgb(1, 2, 3));
      verify(handler.setBackgroundColorRgb(4, 5, 6));
      verify(handler.setForegroundColorRgb(7, 8, 9));
      verify(handler.setBackgroundColor256(42));
    });

    test('ignores incomplete extended SGR colors', () {
      final handler = MockEscapeHandler();
      final parser = EscapeParser(handler);

      expect(() => parser.write('\x1b[38;2;1m\x1b[48;5m'), returnsNormally);
      verifyNever(handler.setForegroundColorRgb(any, any, any));
      verifyNever(handler.setBackgroundColor256(any));
      verifyNever(handler.setCursorBold());
      verifyNever(handler.setCursorFaint());
      verifyNever(handler.setCursorBlink());
    });

    test(
      'ignores unsupported underline color SGR without applying subparams',
      () {
        final handler = MockEscapeHandler();
        final parser = EscapeParser(handler);

        parser.write('\x1b[58;5;1m\x1b[58:2::1:2:3m\x1b[59m');

        verifyNever(handler.setCursorBold());
        verifyNever(handler.setCursorFaint());
        verifyNever(handler.setCursorBlink());
        verifyNever(handler.unsupportedStyle(58));
        verifyNever(handler.unsupportedStyle(59));
      },
    );

    test('continues SGR parsing after unsupported underline color', () {
      final handler = MockEscapeHandler();
      final parser = EscapeParser(handler);

      parser.write('\x1b[58;2;1;2;3;31m\x1b[58:2::4:5:6;32m');

      verifyInOrder([
        handler.setForegroundColor16(NamedColor.red),
        handler.setForegroundColor16(NamedColor.green),
      ]);
      verifyNever(handler.setCursorBold());
      verifyNever(handler.setCursorFaint());
      verifyNever(handler.setCursorItalic());
    });

    test('ignores DCS SOS PM and APC string controls', () {
      final handler = MockEscapeHandler();
      final parser = EscapeParser(handler);

      parser.write('\x1bPignored\x1b\\');
      parser.write('\x1bXignored\x1b\\');
      parser.write('\x1b^ignored\x1b\\');
      parser.write('\x1b_ignored\x1b\\Z');

      verifyNever(handler.writeChar('i'.codeUnitAt(0)));
      verify(handler.writeChar('Z'.codeUnitAt(0))).called(1);
    });

    test('supports split DCS strings', () {
      final handler = MockEscapeHandler();
      final parser = EscapeParser(handler);

      parser.write('\x1bPignored');
      verifyNever(handler.writeChar(any));
      parser.write('\x1b\\Z');

      verify(handler.writeChar('Z'.codeUnitAt(0))).called(1);
    });

    test('supports 8-bit C1 CSI OSC and string controls', () {
      final handler = MockEscapeHandler();
      final parser = EscapeParser(handler);

      parser.write('\u009b8;24;80t');
      parser.write('\u009d2;title\u009c');
      parser.write('\u0090ignored\u009cZ');

      verify(handler.resize(80, 24));
      verify(handler.setTitle('title'));
      verifyNever(handler.writeChar('i'.codeUnitAt(0)));
      verify(handler.writeChar('Z'.codeUnitAt(0))).called(1);
    });

    test('supports split 8-bit C1 sequences', () {
      final handler = MockEscapeHandler();
      final parser = EscapeParser(handler);

      parser.write('\u009b8;24');
      verifyNever(handler.resize(any, any));
      parser.write(';80t');

      verify(handler.resize(80, 24));
    });

    test('handles multiple DEC private modes separately', () {
      final handler = MockEscapeHandler();
      final parser = EscapeParser(handler);

      parser.write('\x1b[?1006;1000h');

      verifyInOrder([
        handler.setMouseReportMode(MouseReportMode.sgr),
        handler.setMouseMode(MouseMode.upDownScroll),
      ]);
    });

    test('DECSET 1049 restores cursor when leaving alternate buffer', () {
      final handler = MockEscapeHandler();
      final parser = EscapeParser(handler);

      parser.write('\x1b[?1049h\x1b[?1049l');

      verifyInOrder([
        handler.saveCursor(),
        handler.clearAltBuffer(),
        handler.useAltBuffer(),
        handler.useMainBuffer(),
        handler.restoreCursor(),
      ]);
    });

    test('maps ESC = to application keypad mode', () {
      final handler = MockEscapeHandler();
      final parser = EscapeParser(handler);

      parser.write('\x1b=');

      verify(handler.setAppKeypadMode(true));
    });

    test('maps ESC > to normal keypad mode', () {
      final handler = MockEscapeHandler();
      final parser = EscapeParser(handler);

      parser.write('\x1b>');

      verify(handler.setAppKeypadMode(false));
    });

    test('maps ESC < to ANSI mode', () {
      final handler = MockEscapeHandler();
      final parser = EscapeParser(handler);

      parser.write('\x1b<');

      verify(handler.setAnsiMode(true));
    });

    test('maps ESC Z DECID to primary DA', () {
      final handler = MockEscapeHandler();
      final parser = EscapeParser(handler);

      parser.write('\x1bZ');

      verify(handler.sendPrimaryDeviceAttributes());
    });

    test('designates G2 charset via ESC *', () {
      final handler = MockEscapeHandler();
      final parser = EscapeParser(handler);

      parser.write('\x1b*B');

      verify(handler.designateCharset(2, 'B'.codeUnitAt(0)));
    });

    test('designates G3 charset via ESC +', () {
      final handler = MockEscapeHandler();
      final parser = EscapeParser(handler);

      parser.write('\x1b+B');

      verify(handler.designateCharset(3, 'B'.codeUnitAt(0)));
    });
  });
}
