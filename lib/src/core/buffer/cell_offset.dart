import 'package:xterm/src/core/buffer/range.dart';

class CellOffset {
  final int x;

  final int y;

  const CellOffset(this.x, this.y);

  bool isEqual(CellOffset other) {
    return other.x == x && other.y == y;
  }

  bool isBefore(CellOffset other) {
    return y < other.y || (y == other.y && x < other.x);
  }

  bool isAfter(CellOffset other) {
    return y > other.y || (y == other.y && x > other.x);
  }

  bool isBeforeOrSame(CellOffset other) {
    return y < other.y || (y == other.y && x <= other.x);
  }

  bool isAfterOrSame(CellOffset other) {
    return y > other.y || (y == other.y && x >= other.x);
  }

  bool isAtSameRow(CellOffset other) {
    return y == other.y;
  }

  bool isAtSameColumn(CellOffset other) {
    return x == other.x;
  }

  bool isWithin(BufferRange range) {
    return range.contains(this);
  }

  bool isAfterWithTolerance(CellOffset other) {
    return y > other.y || (y == other.y && x > other.x + 2);
  }

  CellOffset moveRelative(CellOffset offset, {int? maxX, int? maxY}) {
    if (maxX == null && maxY == null) {
      return CellOffset(x + offset.x, y + offset.y);
    }
    final xx = switch (x + offset.x) {
      final val when maxX == null => val,
      final val when val > maxX => maxX,
      final val when val < 0 => 0,
      final val => val,
    };
    final yy = switch (y + offset.y) {
      final val when maxY == null => val,
      final val when val > maxY => maxY,
      final val when val < 0 => 0,
      final val => val,
    };
    return CellOffset(xx, yy);
  }

  @override
  String toString() => 'CellOffset($x, $y)';

  @override
  int get hashCode => x.hashCode ^ y.hashCode;

  CellOffset operator +(CellOffset other) {
    return CellOffset(x + other.x, y + other.y);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CellOffset &&
          runtimeType == other.runtimeType &&
          x == other.x &&
          y == other.y;
}
