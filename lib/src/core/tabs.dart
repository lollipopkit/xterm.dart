const _kInitialColumns = 1024;
const _kTabInterval = 8;

/// Manages the tab stop state for a terminal.
class TabStops {
  final _stops = List<bool>.filled(_kInitialColumns, false, growable: true);

  var _defaultTabsEnabled = true;

  TabStops() {
    _initializeRange(0, _stops.length);
  }

  /// Initializes tab stops in [start, end) to the default 8 column intervals.
  void _initializeRange(int start, int end) {
    final first =
        start + (_kTabInterval - start % _kTabInterval) % _kTabInterval;
    for (var i = first; i < end; i += _kTabInterval) {
      _stops[i] = true;
    }
  }

  void _ensureLength(int length) {
    if (length <= _stops.length) {
      return;
    }
    final oldLength = _stops.length;
    _stops.addAll(List<bool>.filled(length - oldLength, false));
    if (_defaultTabsEnabled) {
      _initializeRange(oldLength, length);
    }
  }

  /// Finds the next tab stop index, which satisfies [start] <= index < [end].
  int? find(int start, int end) {
    if (start >= end) {
      return null;
    }
    _ensureLength(end);
    for (var i = start; i < end; i++) {
      if (_stops[i]) {
        return i;
      }
    }
    return null;
  }

  /// Finds the previous tab stop index, which satisfies [start] > index >= [end].
  int? findPrevious(int start, int end) {
    if (start <= end) {
      return null;
    }
    _ensureLength(start);
    for (var i = start - 1; i >= end; i--) {
      if (_stops[i]) {
        return i;
      }
    }
    return null;
  }

  /// Sets the tab stop at [index]. If there is already a tab stop at [index],
  /// this method does nothing.
  ///
  /// See also:
  /// * [clearAt] which does the opposite.
  void setAt(int index) {
    if (index < 0) {
      return;
    }
    _ensureLength(index + 1);
    _stops[index] = true;
  }

  /// Clears the tab stop at [index]. If there is no tab stop at [index], this
  /// method does nothing.
  void clearAt(int index) {
    if (index < 0) {
      return;
    }
    _ensureLength(index + 1);
    _stops[index] = false;
  }

  /// Clears all tab stops without resetting them to the default 8 column
  /// intervals.
  void clearAll() {
    _defaultTabsEnabled = false;
    _stops.fillRange(0, _stops.length, false);
  }

  /// Returns true if there is a tab stop at [index].
  bool isSetAt(int index) {
    if (index < 0) {
      return false;
    }
    _ensureLength(index + 1);
    return _stops[index];
  }

  /// Resets the tab stops to the default 8 column intervals.
  void reset() {
    _defaultTabsEnabled = true;
    _stops.fillRange(0, _stops.length, false);
    _initializeRange(0, _stops.length);
  }
}
