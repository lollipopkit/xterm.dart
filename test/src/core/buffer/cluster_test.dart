import 'package:test/test.dart';
import 'package:xterm/xterm.dart';

// A cluster lives beside the line's Uint32List, keyed by column, so every
// mutation that moves cells as raw words has to move it too. A missed one does
// not throw: the marks stay on a column whose text has been replaced, and the
// terminal draws them on the wrong character. Each mutation therefore gets its
// own case here.
//
// The marks are named as escapes rather than written literally. A combining
// character in a source literal is invisible, so one that got mangled in an
// edit would read as a passing test asserting nothing.

/// COMBINING ACUTE ACCENT.
const acute = '\u0301';

/// COMBINING DIAERESIS.
const diaeresis = '\u0308';

/// ZERO WIDTH JOINER.
const zwj = '\u200D';

/// VARIATION SELECTOR-16, which asks for the emoji rendering of what precedes.
const vs16 = '\uFE0F';

void main() {
  group('Buffer.writeChar', () {
    test('a combining mark joins the character before it', () {
      final terminal = Terminal(maxLines: 20);
      terminal.write('e$acute');

      expect(terminal.buffer.lines[0].getCluster(0), 'e$acute');
      expect(terminal.buffer.lines[0].getCodePoint(0), 'e'.codeUnitAt(0));
      expect(terminal.buffer.lines[0].getWidth(0), 1);
      expect(terminal.buffer.cursorX, 1);
    });

    test('several marks accumulate on one cell', () {
      final terminal = Terminal(maxLines: 20);
      terminal.write('e$acute$diaeresis');

      expect(terminal.buffer.lines[0].getCluster(0), 'e$acute$diaeresis');
      expect(terminal.buffer.cursorX, 1);
    });

    test('a mark with nothing before it is dropped', () {
      final terminal = Terminal(maxLines: 20);
      terminal.write('${acute}a');

      expect(terminal.buffer.lines[0].getText(), 'a');
      expect(terminal.buffer.lines[0].getCluster(0), isNull);
    });

    test('a mark after a wide character joins its first column', () {
      final terminal = Terminal(maxLines: 20);
      terminal.write('中$acute');

      // The cursor sits past both columns of the wide character, so the cell
      // immediately to its left is the empty right half.
      expect(terminal.buffer.lines[0].getCluster(0), '中$acute');
      expect(terminal.buffer.lines[0].getCluster(1), isNull);
      expect(terminal.buffer.cursorX, 2);
    });

    test('a mark after a space stays on the space', () {
      final terminal = Terminal(maxLines: 20);
      terminal.write(' $acute');

      expect(terminal.buffer.lines[0].getCluster(0), ' $acute');
    });

    test('a variation selector joins rather than taking a cell', () {
      final terminal = Terminal(maxLines: 20);
      terminal.write('❤$vs16');

      expect(terminal.buffer.lines[0].getCluster(0), '❤$vs16');
      expect(terminal.buffer.cursorX, 1);
    });

    test('a zero width joiner pulls the emoji after it into the cluster', () {
      final terminal = Terminal(maxLines: 20);
      terminal.write('\u{1F468}$zwj\u{1F469}$zwj\u{1F467}');

      // Three emoji and two joiners, in the two columns the first emoji
      // claimed.
      expect(
        terminal.buffer.lines[0].getCluster(0),
        '\u{1F468}$zwj\u{1F469}$zwj\u{1F467}',
      );
      expect(terminal.buffer.lines[0].getWidth(0), 2);
      expect(terminal.buffer.cursorX, 2);
    });

    test('an emoji after a cluster that has no joiner starts a new cell', () {
      final terminal = Terminal(maxLines: 20);
      terminal.write('\u{1F468}$vs16\u{1F469}');

      expect(terminal.buffer.lines[0].getCluster(0), '\u{1F468}$vs16');
      expect(terminal.buffer.lines[0].getCluster(2), isNull);
      expect(terminal.buffer.lines[0].getText(), '\u{1F468}$vs16\u{1F469}');
      expect(terminal.buffer.cursorX, 4);
    });

    test('a skin tone modifier joins the emoji before it', () {
      // U+1F3FD is East Asian Wide, so the width table alone would give it two
      // columns of its own.
      final terminal = Terminal(maxLines: 20);
      terminal.write('\u{1F44D}\u{1F3FD}');

      expect(terminal.buffer.lines[0].getCluster(0), '\u{1F44D}\u{1F3FD}');
      expect(terminal.buffer.cursorX, 2);
    });

    test('a regional indicator pair stays two cells', () {
      // Deliberate: the width table gives each one column, so joining them
      // would leave a two-column flag glyph in a one-column cell.
      final terminal = Terminal(maxLines: 20);
      terminal.write('\u{1F1E8}\u{1F1F3}');

      expect(terminal.buffer.lines[0].getCluster(0), isNull);
      expect(terminal.buffer.lines[0].getCluster(1), isNull);
      expect(terminal.buffer.cursorX, 2);
    });

    test('a mark in the first column of a wrapped line reaches back', () {
      final terminal = Terminal(maxLines: 20);
      terminal.resize(3, 5);
      terminal.write('abc$acute');

      expect(terminal.buffer.lines[0].getCluster(2), 'c$acute');
      expect(terminal.buffer.lines[1].getCluster(0), isNull);
    });

    test('a mark at the start of an unwrapped line is dropped', () {
      final terminal = Terminal(maxLines: 20);
      terminal.resize(3, 5);
      terminal.write('abc\r\n$acute');

      expect(terminal.buffer.lines[1].getCluster(0), isNull);
      expect(terminal.buffer.lines[0].getCluster(2), isNull);
    });

    test('a cell stops growing before a mark stream can run away', () {
      final terminal = Terminal(maxLines: 20);
      terminal.write('e${acute * 200}');

      expect(terminal.buffer.lines[0].getCluster(0)!.length, lessThan(64));
      expect(terminal.buffer.cursorX, 1);
    });

    test('REP repeats the base character, not the mark', () {
      final terminal = Terminal(maxLines: 20);
      terminal.write('e$acute\x1b[2b');

      expect(terminal.buffer.lines[0].getText(), 'e${acute}ee');
    });

    test('overwriting a cell drops the cluster it held', () {
      final terminal = Terminal(maxLines: 20);
      terminal.write('e$acute\rX');

      expect(terminal.buffer.lines[0].getCluster(0), isNull);
      expect(terminal.buffer.lines[0].getText(), 'X');
    });
  });

  group('BufferLine.getText', () {
    test('emits the whole cluster', () {
      final line = _lineWith({0: 'e$acute', 2: 'o$diaeresis'});

      expect(line.getText(), 'e${acute}xo${diaeresis}xxx');
    });

    test('a cluster outside the requested range is not emitted', () {
      final line = _lineWith({0: 'e$acute', 2: 'o$diaeresis'});

      expect(line.getText(0, 2), 'e${acute}x');
    });
  });

  group('mutations that move cells', () {
    test('setContent drops the cluster', () {
      final line = _lineWith({1: 'e$acute'});

      line.setContent(1, 'Z'.codeUnitAt(0) | (1 << CellContent.widthShift));

      expect(line.getCluster(1), isNull);
      expect(line.getContent(1) & CellContent.clusterFlag, 0);
    });

    test('setCodePoint drops the cluster', () {
      final line = _lineWith({1: 'e$acute'});

      line.setCodePoint(1, 'Z'.codeUnitAt(0));

      expect(line.getCluster(1), isNull);
    });

    test('setCell drops the cluster', () {
      final line = _lineWith({1: 'e$acute'});

      line.setCell(1, 'Z'.codeUnitAt(0), 1, CursorStyle.empty);

      expect(line.getCluster(1), isNull);
    });

    test('eraseCell drops the cluster', () {
      final line = _lineWith({1: 'e$acute'});

      line.eraseCell(1, CursorStyle.empty);

      expect(line.getCluster(1), isNull);
    });

    test('resetCell drops the cluster', () {
      final line = _lineWith({1: 'e$acute'});

      line.resetCell(1);

      expect(line.getCluster(1), isNull);
    });

    test('eraseRange drops the clusters inside it', () {
      final line = _lineWith({0: 'a$acute', 2: 'c$acute', 4: 'e$acute'});

      line.eraseRange(1, 4, CursorStyle.empty);

      expect(line.getCluster(0), 'a$acute');
      expect(line.getCluster(2), isNull);
      expect(line.getCluster(4), 'e$acute');
    });

    test('removeCells moves the clusters after it left', () {
      final line = _lineWith({1: 'b$acute', 4: 'e$acute'});

      line.removeCells(0, 1);

      expect(line.getCluster(0), 'b$acute');
      expect(line.getCluster(3), 'e$acute');
      expect(line.getCluster(1), isNull);
      expect(line.getCluster(4), isNull);
    });

    test('removeCells drops the clusters it removed', () {
      final line = _lineWith({1: 'b$acute', 4: 'e$acute'});

      line.removeCells(1, 2);

      expect(line.getCluster(1), isNull);
      expect(line.getCluster(2), 'e$acute');
    });

    test('insertCells moves the clusters after it right', () {
      final line = _lineWith({1: 'b$acute', 4: 'e$acute'});

      line.insertCells(0, 1);

      expect(line.getCluster(2), 'b$acute');
      expect(line.getCluster(1), isNull);
      // The line is six cells wide, so `e` lands in the last one and stays.
      expect(line.getCluster(5), 'e$acute');
    });

    test('insertCells drops the clusters it pushes off the end', () {
      final line = _lineWith({1: 'b$acute', 5: 'f$acute'});

      line.insertCells(0, 1);

      expect(line.getCluster(2), 'b$acute');
      expect(line.getCluster(5), isNull);
    });

    test('shrinking drops the clusters that left the line', () {
      final line = _lineWith({1: 'b$acute', 4: 'e$acute'});

      line.resize(3);
      line.resize(6);

      expect(line.getCluster(1), 'b$acute');
      expect(line.getCluster(4), isNull);
    });

    test('copyFrom brings the clusters with the cells', () {
      final src = _lineWith({1: 'b$acute', 3: 'd$acute'});
      final dst = BufferLine(6);

      dst.copyFrom(src, 1, 0, 3);

      expect(dst.getCluster(0), 'b$acute');
      expect(dst.getCluster(2), 'd$acute');
      expect(dst.getText(), 'b${acute}xd$acute');
    });

    test('copyFrom clears the clusters it overwrote', () {
      final src = BufferLine(6);
      for (var i = 0; i < 6; i++) {
        src.setCodePoint(i, 'x'.codeUnitAt(0));
      }
      final dst = _lineWith({0: 'a$acute', 2: 'c$acute'});

      dst.copyFrom(src, 0, 0, 3);

      expect(dst.getCluster(0), isNull);
      expect(dst.getCluster(2), isNull);
    });

    test('a cell copied through CellData keeps its cluster', () {
      final src = _lineWith({1: 'b$acute'});
      final dst = BufferLine(6);

      dst.setCellData(0, src.createCellData(1));

      expect(dst.getCluster(0), 'b$acute');
      expect(dst.getContent(0) & CellContent.clusterFlag, isNot(0));
    });

    test('setContent will not leave the flag on without an entry', () {
      // The two are one fact, and a reader is entitled to take the entry once
      // it has seen the flag. Copying a content word from a cell that has a
      // cluster is the natural way to break that.
      final line = _lineWith({0: 'e$acute'});

      line.setContent(1, line.getContent(0));

      expect(line.getCluster(1), isNull);
      expect(line.getContent(1) & CellContent.clusterFlag, 0);
    });

    test('shrinking takes the flag off with the entry', () {
      final line = _lineWith({4: 'e$acute'});

      line.resize(3);
      line.resize(6);

      expect(line.getCluster(4), isNull);
      expect(line.getContent(4) & CellContent.clusterFlag, 0);
    });

    test('a CellData with no cluster clears both the entry and the flag', () {
      final src = _lineWith({1: 'b$acute'});
      final dst = _lineWith({0: 'a$acute'});

      final cell = src.createCellData(1);
      cell.cluster = null;
      dst.setCellData(0, cell);

      expect(dst.getCluster(0), isNull);
      expect(dst.getContent(0) & CellContent.clusterFlag, 0);
    });
  });

  group('through the terminal', () {
    test('a cluster survives being scrolled into the scrollback', () {
      final terminal = Terminal(maxLines: 20);
      terminal.resize(10, 3);
      terminal.write('e$acute\r\n\r\n\r\n\r\n');

      expect(terminal.buffer.lines[0].getCluster(0), 'e$acute');
    });

    test('a cluster survives a reflow that narrows the terminal', () {
      final terminal = Terminal(maxLines: 20);
      terminal.resize(6, 3);
      terminal.write('abcde$acute');
      terminal.resize(3, 3);

      // Wrapped lines are one logical line, so the text comes back unbroken;
      // what moved is which physical line holds the marked cell.
      expect(terminal.buffer.getText().trimRight(), 'abcde$acute');
      expect(terminal.buffer.lines[1].isWrapped, isTrue);
      expect(terminal.buffer.lines[1].getCluster(1), 'e$acute');
    });

    test('a cluster survives a reflow that widens the terminal', () {
      final terminal = Terminal(maxLines: 20);
      terminal.resize(3, 3);
      terminal.write('abcde$acute');
      terminal.resize(6, 3);

      expect(terminal.buffer.getText().trimRight(), 'abcde$acute');
    });

    test('a cluster is not left behind on the column it moved off', () {
      final terminal = Terminal(maxLines: 20);
      terminal.resize(6, 3);
      terminal.write('abcde$acute');
      terminal.resize(3, 3);

      // `e` moved from column 4 to column 1 of the wrapped line. Column 1 of
      // the first line holds a plain `b`, and must not have inherited a mark.
      expect(terminal.buffer.lines[0].getCluster(1), isNull);
    });

    test('insert mode moves a cluster along with its cell', () {
      final terminal = Terminal(maxLines: 20);
      terminal.write('e$acute\r\x1b[4hZ');

      expect(terminal.buffer.lines[0].getText(), 'Ze$acute');
      expect(terminal.buffer.lines[0].getCluster(1), 'e$acute');
      expect(terminal.buffer.lines[0].getCluster(0), isNull);
    });

    test('delete character moves a cluster along with its cell', () {
      final terminal = Terminal(maxLines: 20);
      terminal.write('Ze$acute\r\x1b[1P');

      expect(terminal.buffer.lines[0].getText(), 'e$acute');
      expect(terminal.buffer.lines[0].getCluster(0), 'e$acute');
    });

    test('selection copies the marks with the text', () {
      final terminal = Terminal(maxLines: 20);
      terminal.write('e${acute}X');

      expect(
        terminal.buffer.getText(
          BufferRangeLine(CellOffset(0, 0), CellOffset(2, 0)),
        ),
        'e${acute}X',
      );
    });
  });
}

/// A six-cell line reading `xxxxxx`, with [clusters] applied to the columns
/// that name them. Each cluster's first code point replaces that column's `x`,
/// so the cell and its cluster agree on the base as the invariant requires.
BufferLine _lineWith(Map<int, String> clusters) {
  final line = BufferLine(6);

  for (var i = 0; i < 6; i++) {
    line.setCodePoint(i, 'x'.codeUnitAt(0));
  }

  clusters.forEach((index, cluster) {
    line.setCodePoint(index, cluster.runes.first);
    line.setCluster(index, cluster);
  });

  return line;
}
