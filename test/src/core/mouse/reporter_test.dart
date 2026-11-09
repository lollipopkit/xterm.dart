import 'package:test/test.dart';
import 'package:xterm/src/core/mouse/reporter.dart';
import 'package:xterm/xterm.dart';

void main() {
  group('MouseReporter', () {
    test('report() supports normal mode', () {
      final output = MouseReporter.report(
        TerminalMouseButton.left,
        TerminalMouseButtonState.down,
        CellOffset(0, 0),
        MouseReportMode.normal,
      );

      expect(output, equals('\x1B[M !!'));
    });

    test('report() supports utf mode', () {
      final output = MouseReporter.report(
        TerminalMouseButton.left,
        TerminalMouseButtonState.down,
        CellOffset(0, 0),
        MouseReportMode.utf,
      );

      expect(output, equals('\x1B[M !!'));
    });

    test('report() supports sgr mode', () {
      final output = MouseReporter.report(
        TerminalMouseButton.left,
        TerminalMouseButtonState.down,
        CellOffset(0, 0),
        MouseReportMode.sgr,
      );

      expect(output, equals('\x1B[<0;1;1M'));
    });

    test('report() uses xterm wheel button codes', () {
      final output = MouseReporter.report(
        TerminalMouseButton.wheelUp,
        TerminalMouseButtonState.down,
        CellOffset(0, 0),
        MouseReportMode.sgr,
      );

      expect(output, equals('\x1B[<64;1;1M'));
    });

    test('report() supports urxvt mode', () {
      final output = MouseReporter.report(
        TerminalMouseButton.left,
        TerminalMouseButtonState.down,
        CellOffset(0, 0),
        MouseReportMode.urxvt,
      );

      expect(output, equals('\x1B[32;1;1M'));
    });

    test('report() sets bit 5 for a move in every mode', () {
      String motion(TerminalMouseButton button, MouseReportMode mode) {
        return MouseReporter.report(
          button,
          TerminalMouseButtonState.motion,
          CellOffset(0, 0),
          mode,
        );
      }

      expect(
        motion(TerminalMouseButton.left, MouseReportMode.normal),
        '\x1B[M@!!',
      );
      expect(
        motion(TerminalMouseButton.left, MouseReportMode.utf),
        '\x1B[M@!!',
      );
      expect(
        motion(TerminalMouseButton.left, MouseReportMode.sgr),
        '\x1B[<32;1;1M',
      );
      expect(
        motion(TerminalMouseButton.right, MouseReportMode.sgr),
        '\x1B[<34;1;1M',
      );
      expect(
        motion(TerminalMouseButton.none, MouseReportMode.sgr),
        '\x1B[<35;1;1M',
      );
      expect(
        motion(TerminalMouseButton.left, MouseReportMode.urxvt),
        '\x1B[64;1;1M',
      );
    });
  });
}
