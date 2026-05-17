import 'package:test/test.dart';
import 'package:xterm/src/core/mouse/mode.dart';

void main() {
  group('MouseMode', () {
    test('none is the default mode', () {
      expect(MouseMode.none.index, 0);
    });

    test('all modes are distinct', () {
      final modes = MouseMode.values.toSet();
      expect(modes.length, 5);
    });
  });

  group('MouseReportMode', () {
    test('normal is the default mode', () {
      expect(MouseReportMode.normal.index, 0);
    });

    test('all modes are distinct', () {
      final modes = MouseReportMode.values.toSet();
      expect(modes.length, 4);
    });
  });
}
