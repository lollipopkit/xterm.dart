import 'package:test/test.dart';
import 'package:xterm/src/utils/unicode_width.dart';

// The tables are generated (script/gen_unicode_width.dart), so what is worth
// asserting is not their contents but that the generated file is the version
// it claims and that the lookup reads it correctly.
//
// The width cases below are the ones that *changed* between 12.1, which is
// what this package carried while the file was named `unicode_v11.dart`, and
// 16.0. A regeneration that quietly dropped a block would leave these at their
// old answers, which is exactly what a table nobody checks does.

void main() {
  test('the tables are the version the file names', () {
    expect(unicodeWidth.version, '16.0.0');
  });

  group('widths that did not change, as a control', () {
    const cases = {
      0x41: 1, // A
      0x20: 1, // space
      0x00: 0, // NUL
      0x1B: 0, // ESC
      0x0301: 0, // combining acute
      0x4E00: 2, // CJK ideograph
      0xFF21: 2, // fullwidth A
      0x3000: 2, // ideographic space
      0x00AD: 1, // soft hyphen: Cf, but printed
      0x1160: 0, // Hangul Jamo medial: Lo, but composes
      0x1F600: 2, // grinning face
    };

    cases.forEach((codePoint, width) {
      test('U+${codePoint.toRadixString(16).toUpperCase()} is $width', () {
        expect(unicodeWidth.wcwidth(codePoint), width);
      });
    });
  });

  group('widths that 12.1 got wrong', () {
    // Most of these were 1 under 12.1 because the code point was unassigned
    // then. Two were not: U+4DC0 and U+1D300 have been assigned since Unicode
    // 4.0, and East_Asian_Width called them Neutral until they were corrected
    // to Wide. Either way a terminal that still believes 12.1 puts the rest of
    // the line one or two columns off from where the program writing it
    // believes the cursor is.
    const nowWide = {
      0x4DC0: 'hexagram for the creative heaven, N in 12.1 and W in 16',
      0x1D300: 'monogram for earth, N in 12.1 and W in 16',
      0x1FA96: 'military helmet (Unicode 13 emoji)',
      0x1FAE0: 'melting face (Unicode 14 emoji)',
      0x1FADF: 'splatter (Unicode 16 emoji)',
      0x18AF3: 'Tangut component-756',
    };
    const nowZero = {
      0x1AC0: 'combining latin small letter turned w below (Unicode 15)',
      0x1CF00: 'Znamenny combining mark gorazdo nizko s kryzhem on left',
      0x13447: 'Egyptian hieroglyph modifier damaged at top start',
      0x1611E: 'Gurung Khema vowel sign AA',
    };

    nowWide.forEach((codePoint, name) {
      test('$name is two columns', () {
        expect(unicodeWidth.wcwidth(codePoint), 2);
      });
    });

    nowZero.forEach((codePoint, name) {
      test('$name takes no column', () {
        expect(unicodeWidth.wcwidth(codePoint), 0);
      });
    });
  });

  group('emoji presentation', () {
    // The renderer rasterises a glyph once without a colour and tints it when
    // it draws, so a code point a font draws in colour has to stay off that
    // path or it comes out as a solid silhouette.
    const colour = {
      0x1F600: 'grinning face',
      0x231A: 'watch, which is Emoji_Presentation and below U+2500',
      0x2B50: 'star',
      0x1F3FD: 'medium skin tone modifier',
      0x1F1E8: 'regional indicator C',
    };
    const notColour = {
      0x41: 'A',
      0x4E00: 'a CJK ideograph',
      0x2500: 'a box drawing character',
      0x2764: 'heavy black heart, which needs U+FE0F to be an emoji',
      0x0301: 'a combining acute',
      0x2122: 'the trade mark sign',
    };

    colour.forEach((codePoint, name) {
      test('$name is drawn in colour', () {
        expect(unicodeWidth.hasEmojiPresentation(codePoint), isTrue);
      });
    });

    notColour.forEach((codePoint, name) {
      test('$name is not', () {
        expect(unicodeWidth.hasEmojiPresentation(codePoint), isFalse);
      });
    });
  });

  group('the tables agree with each other', () {
    test('every code point reads back the width its table claims', () {
      // A code point in both tables would take whichever `buildTable` filled
      // last, silently. The generator subtracts one set from the other so the
      // question cannot arise, and reading every entry of both back is what
      // says it still does: an overlap shows up as one of them answering the
      // other's width.
      //
      // Collected and asserted once rather than per code point, because there
      // are a quarter of a million of them and a matcher call each is the
      // difference between a fast test and a slow one.
      final wrong = <String>[];

      void check(List<List<int>> table, int width) {
        for (final range in table) {
          for (var cp = range[0]; cp <= range[1]; cp++) {
            if (unicodeWidth.wcwidth(cp) != width) {
              wrong.add('U+${cp.toRadixString(16).toUpperCase()}');
            }
          }
        }
      }

      check(BMP_WIDE, 2);
      check(HIGH_WIDE, 2);
      // The control characters are zero by rule rather than by table, and the
      // tables do not claim them, so this is only the ranges themselves.
      check(BMP_COMBINING, 0);
      check(HIGH_COMBINING, 0);

      expect(wrong, isEmpty, reason: 'code points that read back another '
          "table's width");
    });

    test('every range is ascending and disjoint from the next', () {
      for (final table in [
        BMP_COMBINING,
        HIGH_COMBINING,
        BMP_WIDE,
        HIGH_WIDE,
        BMP_EMOJI_PRESENTATION,
        HIGH_EMOJI_PRESENTATION,
      ]) {
        for (var i = 0; i < table.length; i++) {
          expect(table[i][0], lessThanOrEqualTo(table[i][1]));
          if (i > 0) {
            // Strictly greater than the previous end plus one: adjacent ranges
            // would mean the generator failed to merge them, and `bisearch`
            // stays correct but the table is longer than it needs to be.
            expect(table[i][0], greaterThan(table[i - 1][1] + 1));
          }
        }
      }
    });
  });
}
