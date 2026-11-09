import 'package:flutter_test/flutter_test.dart';
import 'package:xterm/xterm.dart';

void main() {
  group('TerminalStyle', () {
    test('compares by value', () {
      expect(
        const TerminalStyle(fontSize: 14).copyWith(),
        const TerminalStyle(fontSize: 14),
      );
      expect(
        const TerminalStyle(fontFamilyFallback: ['a']),
        TerminalStyle(fontFamilyFallback: ['a'].toList()),
      );
      expect(
        const TerminalStyle(fontSize: 14),
        isNot(const TerminalStyle(fontSize: 15)),
      );
    });
  });
}
