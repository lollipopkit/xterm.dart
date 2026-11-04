import 'package:flutter_test/flutter_test.dart';
import 'package:xterm/core.dart';
import 'package:xterm/src/ui/scroll_unit.dart';

void main() {
  group('The scroll unit of a platform', () {
    test('is the wheel that platform has', () {
      expect(
        TerminalScrollUnit.of(TerminalTargetPlatform.macos)?.pixelsPerClick,
        40.0,
      );
      expect(
        TerminalScrollUnit.of(TerminalTargetPlatform.windows)?.pixelsPerClick,
        100.0,
      );
      expect(
        TerminalScrollUnit.of(TerminalTargetPlatform.linux)?.pixelsPerClick,
        53.0,
      );
    });

    test('is nothing where there is no wheel to have one', () {
      expect(TerminalScrollUnit.of(TerminalTargetPlatform.android), isNull);
      expect(TerminalScrollUnit.of(TerminalTargetPlatform.ios), isNull);
      expect(TerminalScrollUnit.of(TerminalTargetPlatform.unknown), isNull);
    });

    test('is worth the same lines wherever the wheel was', () {
      const lineHeight = 17.0;
      final mac = TerminalScrollUnit.of(TerminalTargetPlatform.macos)!;
      final windows = TerminalScrollUnit.of(TerminalTargetPlatform.windows)!;
      final linux = TerminalScrollUnit.of(TerminalTargetPlatform.linux)!;

      expect(mac.linesFor(40.0, lineHeight), 3);
      expect(windows.linesFor(100.0, lineHeight), 3);
      expect(linux.linesFor(53.0, lineHeight), 3);
    });

    test('tells a click of the wheel from a slide of a trackpad', () {
      final mac = TerminalScrollUnit.of(TerminalTargetPlatform.macos)!;

      expect(mac.isClicks(40), isTrue);
      expect(mac.isClicks(-80), isTrue);
      expect(mac.isClicks(3.7), isFalse);
      expect(mac.isClicks(39.5), isFalse);
    });

    test('a slide of a trackpad is worth the lines it travelled', () {
      const lineHeight = 17.0;
      final mac = TerminalScrollUnit.of(TerminalTargetPlatform.macos)!;

      expect(mac.linesFor(17.0, lineHeight), 1);
      expect(mac.linesFor(8.5, lineHeight), 0.5);
    });

    test('a click of the wheel is worth the same lines as any other', () {
      const lineHeight = 17.0;
      final mac = TerminalScrollUnit.of(TerminalTargetPlatform.macos)!;

      expect(mac.linesFor(120.0, lineHeight), 9);
    });
  });
}
