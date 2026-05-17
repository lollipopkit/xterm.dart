import 'package:test/test.dart';
import 'package:xterm/src/core/charset.dart';

void main() {
  group('asciiTranslator', () {
    test('returns the input code point unchanged', () {
      for (final cp in [0x41, 0x61, 0x30, 0x20, 0x7e]) {
        expect(asciiTranslator(cp), cp);
      }
    });
  });

  group('ukTranslator', () {
    test('maps number sign to pound sign', () {
      expect(ukTranslator(0x23), 0x00a3);
    });

    test('leaves other characters unchanged', () {
      expect(ukTranslator(0x41), 0x41);
      expect(ukTranslator(0x30), 0x30);
    });
  });

  group('decSpecGraphicsTranslator', () {
    test('maps DEC special graphics characters', () {
      expect(decSpecGraphicsTranslator(0x6a), 0x2518); // ┘
      expect(decSpecGraphicsTranslator(0x71), 0x2500); // ─
      expect(decSpecGraphicsTranslator(0x78), 0x2502); // │
    });

    test('passes through characters >= 127', () {
      expect(decSpecGraphicsTranslator(0x7f), 0x7f);
    });

    test('passes through non-DEC mapping characters', () {
      expect(decSpecGraphicsTranslator(0x41), 0x41);
    });
  });

  group('Charset', () {
    test('default translator is ASCII', () {
      final charset = Charset();
      expect(charset.translate(0x41), 0x41);
    });

    test('designate and use G0 charset', () {
      final charset = Charset();
      charset.designate(0, '0'.codeUnitAt(0));
      charset.use(0);
      expect(charset.translate(0x6a), 0x2518);
    });

    test('designate and use G1 charset', () {
      final charset = Charset();
      charset.designate(1, '0'.codeUnitAt(0));
      charset.use(1);
      expect(charset.translate(0x6a), 0x2518);
    });

    test('unknown charset designation is ignored', () {
      final charset = Charset();
      charset.designate(0, 'X'.codeUnitAt(0));
      charset.use(0);
      // Falls back to ASCII
      expect(charset.translate(0x41), 0x41);
    });

    test('single shift applies charset for one character only', () {
      final charset = Charset();
      charset.designate(2, '0'.codeUnitAt(0));
      charset.useOnce(2);
      // G2 special graphics: 0x6a -> ┘
      expect(charset.translate(0x6a), 0x2518);
      // Next character is back to default
      expect(charset.translate(0x41), 0x41);
    });

    test('designation to non-existent charset index does not crash', () {
      final charset = Charset();
      charset.designate(4, 'B'.codeUnitAt(0));
      charset.use(4);
      expect(charset.translate(0x41), 0x41);
    });

    test('save and restore charset state', () {
      final charset = Charset();
      charset.designate(0, '0'.codeUnitAt(0));
      charset.use(0);
      charset.save();

      // Switch to a different charset
      charset.designate(1, 'A'.codeUnitAt(0));
      charset.use(1);

      // Restore
      charset.restore();
      charset.use(0);
      expect(charset.translate(0x6a), 0x2518);
    });

    test('reset clears all charset assignments', () {
      final charset = Charset();
      charset.designate(0, '0'.codeUnitAt(0));
      charset.use(0);
      charset.reset();
      expect(charset.translate(0x6a), 0x6a); // No longer translated
    });

    test('shift in selects G0', () {
      final charset = Charset();
      charset.designate(0, '0'.codeUnitAt(0));
      charset.use(1);
      charset.use(0);
      expect(charset.translate(0x6a), 0x2518);
    });

    test('shift out selects G1', () {
      final charset = Charset();
      charset.designate(1, '0'.codeUnitAt(0));
      charset.use(1);
      expect(charset.translate(0x6a), 0x2518);
    });

    test('UK charset maps number sign to pound', () {
      final charset = Charset();
      charset.designate(0, 'A'.codeUnitAt(0));
      charset.use(0);
      expect(charset.translate(0x23), 0x00a3);
    });
  });
}
