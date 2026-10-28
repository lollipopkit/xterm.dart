import 'package:test/test.dart';
import 'package:xterm/xterm.dart';

String _row(Terminal t, int y) => t.buffer.lines[y].getText().trimRight();

void main() {
  group('reflow', () {
    test('the cursor follows its text when the width grows', () {
      final t = Terminal()..resize(10, 5);
      t.write('abcdefghijklmnopqrstuvwxy');
      t.resize(30, 5);
      t.write('Z');
      expect(_row(t, 0), 'abcdefghijklmnopqrstuvwxyZ');
    });

    test('the cursor follows its text when the width shrinks', () {
      final t = Terminal()..resize(30, 5);
      t.write('abcdefghijklmnopqrstuvwxy');
      t.resize(10, 5);
      t.write('Z');
      expect(_row(t, 2), 'uvwxyZ');
    });

    test('an empty continuation stays after the text it continues', () {
      final t = Terminal()..resize(10, 5);
      t.write('aaaaaaaaaab\b\x1b[X');
      t.resize(20, 5);
      expect(_row(t, 0), 'aaaaaaaaaa');
      expect(t.buffer.lines[0].isWrapped, isFalse);
    });

    test('an empty continuation adds no row when narrowing', () {
      final t = Terminal()..resize(20, 5);
      t.write('${'a' * 20}b\b\x1b[X');
      t.resize(15, 5);
      expect([_row(t, 0), _row(t, 1)], ['a' * 15, 'a' * 5]);
    });
  });

  group('a line that grows again', () {
    for (final reflow in [true, false]) {
      test('does not bring back what was cleared (reflow: $reflow)', () {
        final t = Terminal(reflowEnabled: reflow)..resize(20, 5);
        t.write('${'A' * 10}${'B' * 10}');
        t.resize(10, 5);
        t.write('\x1b[H\x1b[2J');
        t.resize(20, 5);
        // The A row may have gone to the scrollback, which 2J keeps.
        expect(t.buffer.getText(), isNot(contains('B')));
      });
    }
  });

  group('a pending wrap', () {
    for (final (name, seq, row) in [
      ('EL', '\x1b[K', 'abcd'),
      ('ECH', '\x1b[X', 'abcd'),
      ('DCH', '\x1b[P', 'abcd'),
      ('ICH', '\x1b[@', 'abcd'),
    ]) {
      test('$name works from the last column', () {
        final t = Terminal()..resize(5, 3);
        t.write('abcde$seq');
        expect(_row(t, 0), row);
      });
    }

    test('is cleared by EL, so the next character stays on the line', () {
      final t = Terminal()..resize(5, 3);
      t.write('abcde\x1b[KX');
      expect(_row(t, 0), 'abcdX');
    });
  });

  group('getText', () {
    test('keeps the last column by default', () {
      final t = Terminal()..resize(5, 2);
      t.write('\x1b[2;1Habcde');
      expect(t.buffer.getText(), '\nabcde');
    });

    test('puts each row of a block on its own line across a wrap', () {
      final t = Terminal()..resize(5, 3);
      t.write('aaaaabbbbb');
      expect(
        t.buffer.getText(
          BufferRangeBlock(const CellOffset(0, 0), const CellOffset(3, 1)),
        ),
        'aaa\nbbb',
      );
    });
  });

  test('a double click takes a whole run of wide characters', () {
    final t = Terminal();
    t.write('ab 中文字 cd');
    final range = t.buffer.getWordBoundary(const CellOffset(5, 0))!;
    expect(t.buffer.getText(range), '中文字');
  });

  test('a block given by its other diagonal is the same block', () {
    final range = BufferRangeBlock(
      const CellOffset(5, 0),
      const CellOffset(2, 3),
    );
    expect(range.toSegments(), hasLength(4));
    expect(range.contains(const CellOffset(3, 1)), isTrue);
  });
}
