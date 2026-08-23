import 'package:flutter/material.dart';
import 'package:meta/meta.dart';
import 'package:xterm/src/base/disposable.dart';
import 'package:xterm/src/core/buffer/cell_offset.dart';
import 'package:xterm/src/core/buffer/line.dart';
import 'package:xterm/src/core/buffer/range.dart';
import 'package:xterm/src/core/buffer/range_block.dart';
import 'package:xterm/src/core/buffer/range_line.dart';
import 'package:xterm/src/ui/pointer_input.dart';
import 'package:xterm/src/ui/selection_mode.dart';

class TerminalController with ChangeNotifier {
  TerminalController({
    SelectionMode selectionMode = SelectionMode.line,
    PointerInputs pointerInputs = const PointerInputs({PointerInput.tap}),
    bool suspendPointerInput = false,
  }) : _selectionMode = selectionMode,
       _pointerInputs = pointerInputs,
       _suspendPointerInputs = suspendPointerInput;

  CellAnchor? _selectionBase;
  CellAnchor? _selectionExtent;

  SelectionMode get selectionMode => _selectionMode;
  SelectionMode _selectionMode;

  PointerInputs get pointerInput => _pointerInputs;
  PointerInputs _pointerInputs;

  bool get suspendedPointerInputs => _suspendPointerInputs;
  bool _suspendPointerInputs;

  List<TerminalHighlight> get highlights => _highlights;
  final _highlights = <TerminalHighlight>[];

  bool _isDisposing = false;

  BufferRange? get selection {
    final base = _selectionBase;
    final extent = _selectionExtent;

    if (base == null || extent == null) {
      return null;
    }

    if (!base.attached || !extent.attached) {
      return null;
    }

    return _createRange(base.offset, extent.offset);
  }

  void setSelection(CellAnchor base, CellAnchor extent, {SelectionMode? mode}) {
    if (!base.attached || !extent.attached) {
      clearSelection();
      return;
    }

    final oldBase = _selectionBase;
    final oldExtent = _selectionExtent;

    if (oldBase != null && oldBase != base && oldBase != extent) {
      oldBase.dispose();
    }
    if (oldExtent != null &&
        oldExtent != oldBase &&
        oldExtent != base &&
        oldExtent != extent) {
      oldExtent.dispose();
    }

    _selectionBase = base;
    _selectionExtent = extent;

    if (mode != null) {
      _selectionMode = mode;
    }

    notifyListeners();
  }

  BufferRange _createRange(CellOffset begin, CellOffset end) {
    switch (selectionMode) {
      case SelectionMode.line:
        return BufferRangeLine(begin, end);
      case SelectionMode.block:
        return BufferRangeBlock(begin, end);
    }
  }

  void setSelectionMode(SelectionMode newSelectionMode) {
    if (_selectionMode == newSelectionMode) {
      return;
    }
    _selectionMode = newSelectionMode;
    notifyListeners();
  }

  void clearSelection() {
    _disposeSelectionAnchors();
    notifyListeners();
  }

  void setPointerInputs(PointerInputs pointerInput) {
    _pointerInputs = pointerInput;
    notifyListeners();
  }

  void setSuspendPointerInput(bool suspend) {
    _suspendPointerInputs = suspend;
    notifyListeners();
  }

  @internal
  bool shouldSendPointerInput(PointerInput pointerInput) {
    return _suspendPointerInputs
        ? false
        : _pointerInputs.inputs.contains(pointerInput);
  }

  TerminalHighlight highlight({
    required CellAnchor p1,
    required CellAnchor p2,
    required Color color,
  }) {
    final highlight = TerminalHighlight(this, p1: p1, p2: p2, color: color);

    _highlights.add(highlight);
    notifyListeners();

    highlight.registerCallback(() {
      _highlights.remove(highlight);
      if (!_isDisposing) {
        notifyListeners();
      }
    });

    return highlight;
  }

  @override
  void dispose() {
    _isDisposing = true;

    _disposeSelectionAnchors();

    for (final highlight in _highlights.toList()) {
      highlight.dispose();
    }
    _highlights.clear();

    super.dispose();
  }

  void _disposeSelectionAnchors() {
    final base = _selectionBase;
    final extent = _selectionExtent;

    base?.dispose();
    if (extent != null && !identical(extent, base)) {
      extent.dispose();
    }

    _selectionBase = null;
    _selectionExtent = null;
  }
}

class TerminalHighlight with Disposable {
  final TerminalController owner;
  final CellAnchor p1;
  final CellAnchor p2;
  final Color color;

  TerminalHighlight(
    this.owner, {
    required this.p1,
    required this.p2,
    required this.color,
  });

  BufferRange? get range {
    if (!p1.attached || !p2.attached) {
      return null;
    }
    return BufferRangeLine(p1.offset, p2.offset);
  }

  @override
  void dispose() {
    if (disposed) {
      return;
    }

    p1.dispose();
    if (!identical(p2, p1)) {
      p2.dispose();
    }
    super.dispose();
  }
}
