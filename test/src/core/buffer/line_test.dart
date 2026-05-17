import 'package:test/test.dart';
import 'package:xterm/xterm.dart';

void main() {
  group('BufferLine.createCellData()', () {
    test('returns a snapshot without clearing the source cell', () {
      final terminal = Terminal();
      terminal.write('\x1b[31;44;1mX');
      final line = terminal.buffer.lines[0];

      final cellData = line.createCellData(0);

      expect(cellData.content, line.getContent(0));
      expect(cellData.foreground, line.getForeground(0));
      expect(cellData.background, line.getBackground(0));
      expect(cellData.flags, line.getAttributes(0));
      expect(line.getText(), 'X');
    });
  });

  group('BufferLine.getText()', () {
    test('should return the text', () {
      final terminal = Terminal();
      terminal.write('Hello World');
      expect(terminal.buffer.lines[0].getText(), 'Hello World');
    });

    test('getText() should support wide characters', () {
      final text = '😀😁😂🤣😃';
      final terminal = Terminal();
      terminal.write(text);
      expect(terminal.buffer.lines[0].getText(), equals(text));
    });

    test('can specify a range', () {
      final terminal = Terminal();
      terminal.write('Hello World');
      expect(terminal.buffer.lines[0].getText(0, 5), 'Hello');
    });

    test('can handle invalid ranges', () {
      final terminal = Terminal();
      terminal.write('Hello World');
      expect(terminal.buffer.lines[0].getText(0, 100), 'Hello World');
    });

    test('can handle negative ranges', () {
      final terminal = Terminal();
      terminal.write('Hello World');
      expect(terminal.buffer.lines[0].getText(-100, 100), 'Hello World');
    });

    test('can handle reversed ranges', () {
      final terminal = Terminal();
      terminal.write('Hello World');
      expect(terminal.buffer.lines[0].getText(5, 0), '');
    });
  });

  group('BufferLine.getTrimmedLength()', () {
    test('can get trimmed length', () {
      final line = BufferLine(10);

      final text = 'ABCDEF';

      for (var i = 0; i < text.length; i++) {
        line.setCodePoint(i, text.codeUnitAt(i));
      }

      expect(line.getTrimmedLength(), equals(text.length));
    });

    test('can get trimmed length with wide characters', () {
      final terminal = Terminal();
      final text = '😀😁😂🤣😃';

      terminal.write(text);

      expect(terminal.buffer.lines[0].getTrimmedLength(), equals(text.length));
    });

    test('can handle length larger than the line', () {
      final line = BufferLine(10);

      final text = 'ABCDEF';

      for (var i = 0; i < text.length; i++) {
        line.setCodePoint(i, text.codeUnitAt(i));
      }

      expect(line.getTrimmedLength(1000), equals(text.length));
    });

    test('can handle negative start', () {
      final line = BufferLine(10);

      final text = 'ABCDEF';

      for (var i = 0; i < text.length; i++) {
        line.setCodePoint(i, text.codeUnitAt(i));
      }

      expect(line.getTrimmedLength(-1000), equals(0));
    });

    test('does not include stale cells beyond current line length', () {
      final line = BufferLine(10);
      line.setCodePoint(8, 'X'.codeUnitAt(0));

      line.resize(4);

      expect(line.getTrimmedLength(), 0);
    });
  });

  group('BufferLine.eraseRange()', () {
    test(
      'clears both cells when erasing the first half of a wide character',
      () {
        final terminal = Terminal();
        terminal.write('\x1b[31;44;1m界\x1b[0m\r\x1b[X');
        final line = terminal.buffer.lines[0];

        expect(line.getCodePoint(0), 0);
        expect(line.getCodePoint(1), 0);
        expect(line.getForeground(0), terminal.cursor.foreground);
        expect(line.getForeground(1), terminal.cursor.foreground);
        expect(line.getBackground(0), terminal.cursor.background);
        expect(line.getBackground(1), terminal.cursor.background);
        expect(line.getAttributes(0), terminal.cursor.attrs);
        expect(line.getAttributes(1), terminal.cursor.attrs);
      },
    );
  });

  group('BufferLine.insertCells()', () {
    test('moves anchors at the insertion point', () {
      final line = BufferLine(5);
      final anchorAtStart = line.createAnchor(1);
      final anchorAfterStart = line.createAnchor(2);

      line.insertCells(1, 1);

      expect(anchorAtStart.x, 2);
      expect(anchorAfterStart.x, 3);
    });

    test('detaches all anchors pushed beyond the line end', () {
      final line = BufferLine(3);
      final firstAnchor = line.createAnchor(1);
      final secondAnchor = line.createAnchor(2);

      line.insertCells(1, 2);

      expect(firstAnchor.line, isNull);
      expect(secondAnchor.line, isNull);
    });

    test('zero count is a no-op', () {
      final terminal = Terminal();
      terminal.write('A界B');
      final line = terminal.buffer.lines[0];
      final anchor = line.createAnchor(2);
      final snapshot = line.data.toList();

      line.insertCells(2, 0, terminal.cursor);

      expect(line.data.toList(), snapshot);
      expect(anchor.line, line);
      expect(anchor.x, 2);
    });

    test('inserting at line end is a no-op', () {
      final terminal = Terminal();
      terminal.write('A界B');
      final line = terminal.buffer.lines[0];
      final anchor = line.createAnchor(line.length);
      final snapshot = line.data.toList();

      line.insertCells(line.length, 1, terminal.cursor);

      expect(line.data.toList(), snapshot);
      expect(anchor.line, line);
      expect(anchor.x, line.length);
    });
  });

  group('BufferLine.copyFrom()', () {
    test('validates source and destination bounds before mutation', () {
      final src = BufferLine(2);
      final dst = BufferLine(1);
      final snapshot = dst.data.toList();

      expect(() => dst.copyFrom(src, -1, 0, 1), throwsRangeError);
      expect(() => dst.copyFrom(src, 2, 0, 1), throwsRangeError);
      expect(() => dst.copyFrom(src, 0, -1, 1), throwsRangeError);
      expect(() => dst.copyFrom(src, 0, 0, -1), throwsRangeError);

      expect(dst.length, 1);
      expect(dst.data.toList(), snapshot);
    });

    test('clears copied wide-character head fragments without their tail', () {
      final terminal = Terminal();
      terminal.write('A界B');
      final src = terminal.buffer.lines[0];
      final dst = BufferLine(0);

      dst.copyFrom(src, 1, 0, 1);

      expect(dst.length, 1);
      expect(dst.getCodePoint(0), 0);
      expect(dst.getText(), '');
    });

    test('clears copied wide-character tail fragments without their head', () {
      final terminal = Terminal();
      terminal.write('A界B');
      final src = terminal.buffer.lines[0];
      final dst = BufferLine(0);

      dst.copyFrom(src, 2, 0, 1);

      expect(dst.length, 1);
      expect(dst.getCodePoint(0), 0);
      expect(dst.getText(), '');
    });

    test('keeps complete copied wide characters', () {
      final terminal = Terminal();
      terminal.write('A界B');
      final src = terminal.buffer.lines[0];
      final dst = BufferLine(0);

      dst.copyFrom(src, 1, 0, 2);

      expect(dst.getText(), '界');
      expect(dst.getWidth(0), 2);
      expect(dst.getWidth(1), 0);
    });
  });

  group('BufferLine.removeCells()', () {
    test('clears stale wide-character trailing fragments', () {
      final terminal = Terminal();
      terminal.write('A界B');
      final line = terminal.buffer.lines[0];

      line.removeCells(1, 1, terminal.cursor);

      expect(line.getCodePoint(0), 'A'.codeUnitAt(0));
      expect(line.getCodePoint(1), 0);
      expect(line.getCodePoint(2), 'B'.codeUnitAt(0));
      expect(line.getText(), 'AB');
    });

    test('detaches all anchors inside the removed range', () {
      final line = BufferLine(5);
      final firstAnchor = line.createAnchor(1);
      final secondAnchor = line.createAnchor(2);
      final shiftedAnchor = line.createAnchor(4);

      line.removeCells(1, 2);

      expect(firstAnchor.line, isNull);
      expect(secondAnchor.line, isNull);
      expect(shiftedAnchor.line, line);
      expect(shiftedAnchor.x, 2);
    });
  });

  group('BufferLine.resize', () {
    test('can resize', () {
      final line = BufferLine(10);

      final text = 'ABCDEF';

      for (var i = 0; i < text.length; i++) {
        line.setCodePoint(i, text.codeUnitAt(i));
      }

      line.resize(20);

      expect(line.length, equals(20));
    });

    test('clears trailing wide-character fragments when shrinking', () {
      final terminal = Terminal();
      terminal.write('A界');
      final line = terminal.buffer.lines[0];

      line.resize(2);

      expect(line.length, 2);
      expect(line.getText(), 'A');
      expect(line.getCodePoint(1), 0);
    });
  });

  group('Buffer.createAnchor', () {
    test('rejects anchors outside the line bounds', () {
      final line = BufferLine(5);

      expect(() => line.createAnchor(-1), throwsRangeError);
      expect(() => line.createAnchor(6), throwsRangeError);
      expect(line.createAnchor(5).x, 5);
    });

    test('works', () {
      final terminal = Terminal();
      final line = terminal.buffer.lines[3];
      final anchor = line.createAnchor(5);

      terminal.insertLines(5);
      expect(anchor.x, 5);
      expect(anchor.y, 8);

      terminal.buffer.clear();
      expect(line.attached, false);
      expect(anchor.attached, false);
    });

    test('line disposal detaches all anchors', () {
      final line = BufferLine(5);
      final firstAnchor = line.createAnchor(1);
      final secondAnchor = line.createAnchor(2);

      line.dispose();

      expect(firstAnchor.line, isNull);
      expect(secondAnchor.line, isNull);
      expect(line.anchors, isEmpty);
    });
  });
}
