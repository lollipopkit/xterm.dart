import 'package:flutter_test/flutter_test.dart';
import 'package:xterm/core.dart';
import 'package:xterm/src/ui/scroll_unit.dart';

void main() {
  test('a notch of the wheel is three lines on every desktop', () {
    // What each engine reports for one notch, in logical pixels.
    const notch = {
      TerminalTargetPlatform.macos: 40.0,
      TerminalTargetPlatform.windows: 100.0,
      TerminalTargetPlatform.linux: 53.0,
    };
    for (final MapEntry(key: platform, value: pixels) in notch.entries) {
      final perLine = TerminalScrollUnit.pixelsPerLine(platform)!;
      expect(TerminalScrollLines().add(pixels, perLine), 3, reason: '$platform');
    }
  });

  test('a phone has no wheel unit', () {
    expect(TerminalScrollUnit.pixelsPerLine(TerminalTargetPlatform.android), isNull);
    expect(TerminalScrollUnit.pixelsPerLine(TerminalTargetPlatform.ios), isNull);
  });

  test('Windows scrolls the lines the system is set to', () {
    // Five lines per notch: the engine sends 5 * 100 / 3 pixels.
    final perLine = TerminalScrollUnit.pixelsPerLine(TerminalTargetPlatform.windows)!;
    expect(TerminalScrollLines().add(5 * 100 / 3, perLine), 5);
  });

  test('an accelerated wheel scrolls in proportion, the rest kept', () {
    final perLine = TerminalScrollUnit.pixelsPerLine(TerminalTargetPlatform.macos)!;
    final lines = TerminalScrollLines();
    // Two and a half notches: seven lines and a half.
    expect(lines.add(100, perLine), 7);
    expect(lines.add(20, perLine), 2, reason: 'the half line kept');
  });

  test('less than a line waits, in either direction', () {
    final lines = TerminalScrollLines();
    expect(lines.add(-5, 10), 0);
    expect(lines.add(-5, 10), -1);
    expect(lines.add(4, 10), 0);
    lines.reset();
    expect(lines.add(6, 10), 0);
  });
}
