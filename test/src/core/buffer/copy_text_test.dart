import 'package:flutter_test/flutter_test.dart';
import 'package:xterm/xterm.dart';

// What ends up on the clipboard. Every case here was wrong before the test
// existed, and each was wrong silently: the text came out shorter, which reads
// as a selection that was off by a bit rather than as a defect.

void main() {
  /// Writes [input] to a terminal [width] columns wide and copies [range],
  /// defaulting to the whole of the first three rows.
  String copy(String input, {BufferRange? range, int width = 20}) {
    final terminal = Terminal(maxLines: 20);
    terminal.resize(width, 6);
    terminal.write(input);
    return terminal.buffer.getText(
      range ?? BufferRangeLine(CellOffset(0, 0), CellOffset(width - 1, 2)),
    );
  }

  group('blanks a line was left with', () {
    test('a cursor move leaves the columns it skipped', () {
      // CHA to column 10. The cells between were never written, and closing
      // them up would move everything to their right nine columns left.
      expect(copy('a\x1b[10Gb'), 'a        b\n\n');
    });

    test('a tab leaves the columns it skipped', () {
      expect(copy('a\tb'), 'a       b\n\n');
    });

    test('an erased cell stays a cell', () {
      // ECH at column 3, over the c.
      expect(copy('abcdef\x1b[3G\x1b[X'), 'ab def\n\n');
    });

    test('the blanks a line ends with are dropped', () {
      expect(copy('ab   \r\ncd\r\nef'), 'ab\ncd\nef');
    });

    test('a line of nothing is a line', () {
      expect(copy('a\r\n\r\nb'), 'a\n\nb');
    });
  });

  group('a wide character', () {
    test('is copied once, not once per column', () {
      expect(copy('中文'), '中文\n\n');
    });

    test('comes along when only its left column is selected', () {
      // A drag that stopped on the character's first column. It is drawn
      // selected, so it has to be copied; it used to come back empty.
      expect(
        copy(
          '中文',
          range: BufferRangeLine(CellOffset(0, 0), CellOffset(1, 0)),
        ),
        '中',
      );
    });

    test('comes along when only its right column is selected', () {
      expect(
        copy(
          '中文',
          range: BufferRangeLine(CellOffset(1, 0), CellOffset(2, 0)),
        ),
        '中',
      );
    });
  });

  group('a grapheme cluster', () {
    test('keeps its marks', () {
      expect(copy('éö'), 'éö\n\n');
    });

    test('is not mistaken for padding when it ends in a space', () {
      // The cluster is a space and a combining mark, which is a cell with
      // something in it however much it looks like an empty one.
      expect(copy('a ́'), 'a ́\n\n');
    });
  });

  group('line endings', () {
    test('a wrapped line is one line', () {
      expect(copy('aaaaaaaaaaaaaaaaaaaabbbb'), 'aaaaaaaaaaaaaaaaaaaabbbb\n');
    });

    test('a line that wrapped on a space keeps it', () {
      // The trim runs at the end of the logical line, not at the end of each
      // row, or this would come back as one word.
      expect(
        copy('aaaaaaaaaaaaaaaaaaa bbb'),
        'aaaaaaaaaaaaaaaaaaa bbb\n',
      );
    });
  });

  group('a block range', () {
    test('keeps the blanks up to the column it names', () {
      // The right edge is the caller's, not the end of what was written, so
      // there is nothing here to call padding.
      expect(
        copy(
          'Hello World\r\nNice to meet you',
          range: BufferRangeBlock(CellOffset(2, 0), CellOffset(6, 1)),
        ),
        'llo \nce t',
      );
    });
  });
}
