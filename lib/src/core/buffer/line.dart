import 'dart:math' show min;
import 'dart:typed_data';

import 'package:xterm/src/core/buffer/cell_offset.dart';
import 'package:xterm/src/core/cell.dart';
import 'package:xterm/src/core/cursor.dart';
import 'package:xterm/src/utils/circular_buffer.dart';
import 'package:xterm/src/utils/unicode_width.dart';

const _cellSize = 4;

const _cellForeground = 0;

const _cellBackground = 1;

const _cellAttributes = 2;

const _cellContent = 3;

class BufferLine with IndexedItem {
  BufferLine(this._length, {this.isWrapped = false})
    : _data = Uint32List(_calcCapacity(_length) * _cellSize);

  int _length;

  Uint32List _data;

  Uint32List get data => _data;

  var isWrapped = false;

  int get length => _length;

  final _anchors = <CellAnchor>[];

  List<CellAnchor> get anchors => _anchors;

  /// The whole text of the cells that hold more than the one code point [_data]
  /// has room for, keyed by column. Null until the line has one, which for most
  /// lines is never: a map per line would cost more than the feature.
  ///
  /// A column appears here exactly when its content has
  /// [CellContent.clusterFlag], in both directions, which is what lets a
  /// reader use the flag as a cheap gate and then take the entry. The string
  /// always starts with that cell's own code point.
  ///
  /// Every mutation below either routes through a setter that drops the entry
  /// or moves it explicitly; a stale entry would put one cell's marks on
  /// whatever text replaced it.
  Map<int, String>? _clusters;

  int getForeground(int index) {
    return _data[index * _cellSize + _cellForeground];
  }

  int getBackground(int index) {
    return _data[index * _cellSize + _cellBackground];
  }

  int getAttributes(int index) {
    return _data[index * _cellSize + _cellAttributes];
  }

  int getContent(int index) {
    return _data[index * _cellSize + _cellContent];
  }

  int getCodePoint(int index) {
    return _data[index * _cellSize + _cellContent] & CellContent.codepointMask;
  }

  int getWidth(int index) {
    return _data[index * _cellSize + _cellContent] >> CellContent.widthShift;
  }

  /// The whole text of the cell at [index]: its base character followed by the
  /// combining marks or joined code points that belong to it. Null when the
  /// cell is the single code point [getCodePoint] returns.
  String? getCluster(int index) {
    return _clusters?[index];
  }

  /// Gives the cell at [index] the text [cluster], which must begin with the
  /// code point already in the cell: [getCodePoint], [getWidth] and everything
  /// that lays out the grid keep reading that, and only the drawn and copied
  /// text changes.
  void setCluster(int index, String cluster) {
    (_clusters ??= <int, String>{})[index] = cluster;
    _data[index * _cellSize + _cellContent] |= CellContent.clusterFlag;
  }

  void getCellData(int index, CellData cellData) {
    final offset = index * _cellSize;
    cellData.foreground = _data[offset + _cellForeground];
    cellData.background = _data[offset + _cellBackground];
    cellData.flags = _data[offset + _cellAttributes];
    cellData.content = _data[offset + _cellContent];
    cellData.cluster = _clusters?[index];
  }

  CellData createCellData(int index) {
    final cellData = CellData.empty();
    getCellData(index, cellData);
    return cellData;
  }

  void setForeground(int index, int value) {
    _data[index * _cellSize + _cellForeground] = value;
  }

  void setBackground(int index, int value) {
    _data[index * _cellSize + _cellBackground] = value;
  }

  void setAttributes(int index, int value) {
    _data[index * _cellSize + _cellAttributes] = value;
  }

  void setContent(int index, int value) {
    // The flag is taken off [value] rather than trusted. It says this line
    // holds text for the cell, and this call is what replaces that text; a
    // caller passing a content word read from another cell would otherwise
    // leave the cell claiming a cluster the line does not have.
    _data[index * _cellSize + _cellContent] = value & ~CellContent.clusterFlag;
    _clusters?.remove(index);
  }

  void setCodePoint(int index, int char) {
    final width = unicodeWidth.wcwidth(char);
    setContent(index, char | (width << CellContent.widthShift));
  }

  void setCell(int index, int char, int witdh, CursorStyle style) {
    final offset = index * _cellSize;
    _data[offset + _cellForeground] = style.foreground;
    _data[offset + _cellBackground] = style.background;
    _data[offset + _cellAttributes] = style.attrs;
    _data[offset + _cellContent] = char | (witdh << CellContent.widthShift);
    _clusters?.remove(index);
  }

  /// Writes [cellData] to the cell at [index], including its cluster.
  ///
  /// The flag is taken from `cellData.cluster` rather than from its content, so
  /// that a caller that built a [CellData] by hand cannot leave the cell
  /// claiming a cluster the line does not have.
  void setCellData(int index, CellData cellData) {
    final offset = index * _cellSize;
    _data[offset + _cellForeground] = cellData.foreground;
    _data[offset + _cellBackground] = cellData.background;
    _data[offset + _cellAttributes] = cellData.flags;

    final cluster = cellData.cluster;
    if (cluster == null) {
      _data[offset + _cellContent] =
          cellData.content & ~CellContent.clusterFlag;
      _clusters?.remove(index);
    } else {
      _data[offset + _cellContent] = cellData.content | CellContent.clusterFlag;
      (_clusters ??= <int, String>{})[index] = cluster;
    }
  }

  void eraseCell(int index, CursorStyle style) {
    final offset = index * _cellSize;
    _data[offset + _cellForeground] = style.foreground;
    _data[offset + _cellBackground] = style.background;
    _data[offset + _cellAttributes] = style.attrs;
    _data[offset + _cellContent] = 0;
    _clusters?.remove(index);
  }

  void resetCell(int index) {
    final offset = index * _cellSize;
    _data[offset + _cellForeground] = 0;
    _data[offset + _cellBackground] = 0;
    _data[offset + _cellAttributes] = 0;
    _data[offset + _cellContent] = 0;
    _clusters?.remove(index);
  }

  /// Erase cells whose index satisfies [start] <= index < [end]. Erased cells
  /// are filled with [style].
  void eraseRange(int start, int end, CursorStyle style) {
    if (start < 0) {
      start = 0;
    }
    end = min(end, _length);

    if (start >= end) {
      return;
    }

    // Reset cell one to the left if start is the second cell of a wide char.
    if (start > 0 && getWidth(start - 1) == 2) {
      eraseCell(start - 1, style);
    }

    // Reset cell one to the right if end splits a wide char.
    if (end < _length && getWidth(end - 1) == 2) {
      eraseCell(end, style);
    }

    for (var i = start; i < end; i++) {
      eraseCell(i, style);
    }
  }

  /// Remove [count] cells starting at [start]. Cells that are empty after the
  /// removal are filled with [style].
  void removeCells(int start, int count, [CursorStyle? style]) {
    assert(start >= 0 && start <= _length);
    assert(count >= 0 && start + count <= _length);

    if (count == 0) {
      return;
    }

    style ??= CursorStyle.empty;

    if (start + count < _length) {
      final moveStart = start * _cellSize;
      final moveEnd = (_length - count) * _cellSize;
      final moveOffset = count * _cellSize;
      for (var i = moveStart; i < moveEnd; i++) {
        _data[i] = _data[i + moveOffset];
      }

      // The cells moved as raw words, so the clusters keyed off their old
      // columns have to follow. When the branch is not taken there is nothing
      // to move: everything from [start] on is erased below, and erasing drops
      // the entry.
      _shiftClusters(start, -count);
    }

    for (var i = _length - count; i < _length; i++) {
      eraseCell(i, style);
    }

    if (start > 0 && getWidth(start - 1) == 2) {
      eraseCell(start - 1, style);
    }

    if (start < _length && getWidth(start) == 0) {
      eraseCell(start, style);
    }

    // Update anchors, remove anchors that are inside the removed range.
    for (var i = _anchors.length - 1; i >= 0; i--) {
      final anchor = _anchors[i];
      if (anchor.x >= start) {
        if (anchor.x < start + count) {
          anchor.dispose();
        } else {
          anchor.reposition(anchor.x - count);
        }
      }
    }
  }

  /// Inserts [count] cells at [start]. New cells are initialized with [style].
  void insertCells(int start, int count, [CursorStyle? style]) {
    assert(start >= 0 && start <= _length);
    assert(count >= 0);

    if (count == 0 || start == _length) {
      return;
    }

    style ??= CursorStyle.empty;

    if (start > 0 && getWidth(start - 1) == 2) {
      eraseCell(start - 1, style);
    }

    if (start + count < _length) {
      final moveStart = start * _cellSize;
      final moveEnd = (_length - count) * _cellSize;
      final moveOffset = count * _cellSize;
      for (var i = moveEnd - 1; i >= moveStart; i--) {
        _data[i + moveOffset] = _data[i];
      }

      // As in [removeCells]: the words moved, so their clusters move with them.
      _shiftClusters(start, count);
    }

    final end = min(start + count, _length);
    for (var i = start; i < end; i++) {
      eraseCell(i, style);
    }

    if (getWidth(_length - 1) == 2) {
      eraseCell(_length - 1, style);
    }

    // Update anchors, move anchors that are at or after the insertion point.
    for (var i = _anchors.length - 1; i >= 0; i--) {
      final anchor = _anchors[i];
      if (anchor.x >= start) {
        anchor.reposition(anchor.x + count);

        // Remove anchors that are now outside the buffer.
        if (anchor.x >= _length) {
          anchor.dispose();
        }
      }
    }
  }

  void resize(int length) {
    assert(length >= 0);

    if (length == _length) {
      return;
    }

    if (length > _length) {
      final newBufferSize = _calcCapacity(length) * _cellSize;

      if (newBufferSize > _data.length) {
        final newBuffer = Uint32List(newBufferSize);
        newBuffer.setRange(0, _data.length, _data);
        _data = newBuffer;
      }
    }

    _length = length;

    // Shrinking leaves the words of the cells that fell off the end in place,
    // so growing again can bring them back. Their clusters do not, since by
    // then the column may hold something else. The flag goes with the entry,
    // because a cell claiming a cluster the line does not have is a state the
    // readers are entitled to assume cannot happen.
    _clusters?.removeWhere((index, _) {
      if (index < _length) return false;
      _data[index * _cellSize + _cellContent] &= ~CellContent.clusterFlag;
      return true;
    });

    if (_length > 0 && getWidth(_length - 1) == 2) {
      resetCell(_length - 1);
    }

    for (var i = 0; i < _anchors.length; i++) {
      final anchor = _anchors[i];
      if (anchor.x > _length) {
        anchor.reposition(_length);
      }
    }
  }

  /// Returns the offset of the last cell that has content from the start of
  /// the line.
  int getTrimmedLength([int? cols]) {
    if (cols == null || cols > _length) {
      cols = _length;
    }

    if (cols <= 0) {
      return 0;
    }

    for (var i = cols - 1; i >= 0; i--) {
      var codePoint = getCodePoint(i);

      if (codePoint != 0) {
        // we are at the last cell in this line that has content.
        // the length of this line is the index of this cell + 1
        // the only exception is that if that last cell is wider
        // than 1 then we have to add the diff
        final lastCellWidth = getWidth(i);
        return i + lastCellWidth;
      }
    }
    return 0;
  }

  /// Copies [len] cells from [src] starting at [srcCol] to [dstCol] at this
  /// line.
  void copyFrom(BufferLine src, int srcCol, int dstCol, int len) {
    RangeError.checkNotNegative(len, 'len');
    RangeError.checkNotNegative(dstCol, 'dstCol');
    RangeError.checkValueInInterval(srcCol, 0, src._length - len, 'srcCol');

    if (len == 0) {
      return;
    }

    resize(dstCol + len);

    // data.setRange(
    //   dstCol * _cellSize,
    //   (dstCol + len) * _cellSize,
    //   Uint32List.sublistView(src.data, srcCol * _cellSize, len * _cellSize),
    // );

    var srcOffset = srcCol * _cellSize;
    var dstOffset = dstCol * _cellSize;

    for (var i = 0; i < len * _cellSize; i++) {
      _data[dstOffset++] = src._data[srcOffset++];
    }

    _copyClusters(src, srcCol, dstCol, len);

    _cleanupWideFragmentsAroundRange(dstCol, dstCol + len);
  }

  /// Replaces the clusters of `[dstCol, dstCol + len)` with [src]'s, so the
  /// destination range holds what the copied words say it holds and nothing of
  /// what was there before.
  void _copyClusters(BufferLine src, int srcCol, int dstCol, int len) {
    final theirs = src._clusters;
    final mine = _clusters;

    if (mine != null && mine.isNotEmpty) {
      mine.removeWhere((index, _) => index >= dstCol && index < dstCol + len);
    }

    if (theirs == null || theirs.isEmpty) {
      return;
    }

    for (var i = 0; i < len; i++) {
      final cluster = theirs[srcCol + i];
      if (cluster != null) {
        (_clusters ??= <int, String>{})[dstCol + i] = cluster;
      }
    }
  }

  /// Moves every cluster at or after [from] by [delta] columns, to follow cells
  /// that moved as raw words. An entry that lands before [from] was overwritten
  /// by the move, and one that lands past the end of the line left it; both are
  /// dropped.
  void _shiftClusters(int from, int delta) {
    final clusters = _clusters;
    if (clusters == null || clusters.isEmpty) {
      return;
    }

    final moved = <int, String>{};
    clusters.forEach((index, cluster) {
      if (index < from) {
        moved[index] = cluster;
        return;
      }
      final to = index + delta;
      if (to < from || to >= _length) {
        return;
      }
      moved[to] = cluster;
    });

    _clusters = moved;
  }

  void _cleanupWideFragmentsAroundRange(int start, int end) {
    if (start > 0 && getWidth(start - 1) == 2) {
      resetCell(start - 1);
    }

    if (start < _length && getWidth(start) == 0) {
      resetCell(start);
    }

    if (end <= 0 || end > _length) {
      return;
    }

    if (getWidth(end - 1) == 2) {
      if (end == _length || getWidth(end) != 0) {
        resetCell(end - 1);
      }
    } else if (end < _length && getWidth(end) == 0) {
      resetCell(end);
    }
  }

  static int _calcCapacity(int length) {
    assert(length >= 0);

    var capacity = 64;

    if (length < 256) {
      while (capacity < length) {
        capacity *= 2;
      }
    } else {
      capacity = 256;
      while (capacity < length) {
        capacity += 32;
      }
    }

    return capacity;
  }

  /// The text of the cells in `[from, to)`.
  ///
  /// A cell nothing was written to is a space, so that the columns of what
  /// was written are the columns it is read back in. The run of them every
  /// line ends with is dropped instead, unless [trimRight] says not to —
  /// which is what a caller joining this to the next row passes, since the
  /// end of a wrapped line is the middle of the text.
  String getText([int? from, int? to, bool trimRight = true]) {
    final start = (from == null || from < 0) ? 0 : from;
    var end = (to == null || to > _length) ? _length : to;

    if (trimRight) {
      // Walked back over the cells rather than over the string they produce:
      // one cell is any number of code units, and a cluster ending in a space
      // is text rather than padding.
      while (end > start && _isBlank(end - 1)) {
        end--;
      }
    }

    final builder = StringBuffer();

    for (var i = start; i < end; i++) {
      if (getCodePoint(i) != 0) {
        _writeCell(builder, i);
        continue;
      }

      // An empty cell is one of two things, told apart by the cell to its
      // left, which is how the rest of the buffer tells them apart too.
      if (i > 0 && getWidth(i - 1) == 2) {
        // The second column of a wide character. Its text lives in the first
        // column and was written when that column came up — unless the range
        // starts here, which is a selection that took half a character, and
        // then this column is the only chance to write it.
        if (i == start) {
          _writeCell(builder, i - 1);
        }
        continue;
      }

      // Otherwise a cell nothing was written to, or one that was erased. It
      // is a blank the reader has to see: a tab, a cursor move and ECH each
      // leave one behind, and dropping it slides the rest of the line left,
      // which takes the columns out of anything laid out in them.
      builder.write(' ');
    }

    return builder.toString();
  }

  /// Whether the cell at [index] reads as nothing: never written, the second
  /// column of a wide character, or a space. A space someone typed and one
  /// left over from a line that was never that long are the same cell, so
  /// trimming cannot tell them apart and does not try.
  bool _isBlank(int index) {
    final codePoint = getCodePoint(index);

    if (codePoint == 0) {
      // The second column of a wide character is not padding. Trimming past
      // it would leave the range ending on the character's first column, and
      // a range that ends where a character starts holds none of it.
      return !(index > 0 && getWidth(index - 1) == 2);
    }

    return codePoint == 0x20 && _clusters?[index] == null;
  }

  void _writeCell(StringBuffer builder, int index) {
    // The cluster already starts with the cell's code point, so it replaces
    // it rather than following it.
    final cluster = _clusters?[index];
    if (cluster != null) {
      builder.write(cluster);
    } else {
      builder.writeCharCode(getCodePoint(index));
    }
  }

  CellAnchor createAnchor(int offset) {
    RangeError.checkValueInInterval(offset, 0, _length, 'offset');

    final anchor = CellAnchor(offset, owner: this);
    _anchors.add(anchor);
    return anchor;
  }

  void dispose() {
    for (var i = _anchors.length - 1; i >= 0; i--) {
      _anchors[i].dispose();
    }
  }

  @override
  String toString() {
    return getText();
  }
}

/// A handle to a cell in a [BufferLine] that can be used to track the location
/// of the cell. Anchors are guaranteed to be stable, retaining their relative
/// position to each other after mutations to the buffer.
class CellAnchor {
  CellAnchor(int offset, {BufferLine? owner})
    : _offset = offset,
      _owner = owner;

  int _offset;

  int get x {
    return _offset;
  }

  int get y {
    assert(attached);
    return _owner!.index;
  }

  CellOffset get offset {
    assert(attached);
    return CellOffset(_offset, _owner!.index);
  }

  BufferLine? _owner;

  BufferLine? get line => _owner;

  bool get attached => _owner?.attached ?? false;

  void reparent(BufferLine owner, int offset) {
    _owner?._anchors.remove(this);
    _owner = owner;
    _owner?._anchors.add(this);
    _offset = offset;
  }

  void reposition(int offset) {
    _offset = offset;
  }

  void dispose() {
    _owner?._anchors.remove(this);
    _owner = null;
  }

  @override
  String toString() {
    if (attached) {
      return 'CellAnchor($x, $y)';
    } else {
      return 'CellAnchor($x, detached)';
    }
  }
}
