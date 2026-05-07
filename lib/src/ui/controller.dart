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

enum SelectionAnimationType {
  insert, // New selection.
  update, // Existing selection changed.
}

class SelectionAnimation {
  final AnimationController controller;
  final Animation<double> scaleAnimation;
  final Animation<Offset> positionAnimation;
  final SelectionAnimationType type;

  SelectionAnimation({
    required this.controller,
    required this.scaleAnimation,
    required this.positionAnimation,
    required this.type,
  });

  void dispose() {
    controller.dispose();
  }
}

class TerminalController with ChangeNotifier {
  TerminalController({
    SelectionMode selectionMode = SelectionMode.line,
    PointerInputs pointerInputs = const PointerInputs({PointerInput.tap}),
    bool suspendPointerInput = false,
    required TickerProvider vsync,
  }) : _selectionMode = selectionMode,
       _pointerInputs = pointerInputs,
       _suspendPointerInputs = suspendPointerInput,
       _vsync = vsync;

  final TickerProvider _vsync;

  CellAnchor? _selectionBase;
  CellAnchor? _selectionExtent;

  SelectionAnimation? _selectionAnimation;
  CellOffset? _lastSelectionBegin;
  CellOffset? _lastSelectionEnd;

  SelectionMode get selectionMode => _selectionMode;
  SelectionMode _selectionMode;

  PointerInputs get pointerInput => _pointerInputs;
  PointerInputs _pointerInputs;

  bool get suspendedPointerInputs => _suspendPointerInputs;
  bool _suspendPointerInputs;

  List<TerminalHighlight> get highlights => _highlights;
  final _highlights = <TerminalHighlight>[];

  SelectionAnimation? get selectionAnimation => _selectionAnimation;

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

    final newBegin = base.offset;
    final newEnd = extent.offset;

    final isNewSelection = _selectionBase == null || _selectionExtent == null;
    final animationType = isNewSelection
        ? SelectionAnimationType.insert
        : SelectionAnimationType.update;

    _selectionAnimation?.dispose();

    _selectionAnimation = _createSelectionAnimation(
      type: animationType,
      oldBegin: _lastSelectionBegin,
      oldEnd: _lastSelectionEnd,
      newBegin: newBegin,
      newEnd: newEnd,
    );

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

    _lastSelectionBegin = newBegin;
    _lastSelectionEnd = newEnd;

    notifyListeners();
  }

  SelectionAnimation _createSelectionAnimation({
    required SelectionAnimationType type,
    CellOffset? oldBegin,
    CellOffset? oldEnd,
    required CellOffset newBegin,
    required CellOffset newEnd,
  }) {
    final duration = type == SelectionAnimationType.insert
        ? const Duration(milliseconds: 100)
        : const Duration(milliseconds: 150);
    final controller = _createAndWireSelectionController(duration);
    final (
      :scaleAnimation,
      :positionAnimation,
    ) = type == SelectionAnimationType.insert
        ? _buildInsertTweens(controller)
        : _buildUpdateTweens(controller, oldBegin, newBegin);

    return SelectionAnimation(
      controller: controller,
      scaleAnimation: scaleAnimation,
      positionAnimation: positionAnimation,
      type: type,
    );
  }

  ({Animation<double> scaleAnimation, Animation<Offset> positionAnimation})
  _buildInsertTweens(AnimationController controller) {
    final scaleAnimation = Tween<double>(
      begin: 1.0,
      end: 1.0,
    ).animate(CurvedAnimation(parent: controller, curve: Curves.easeOut));

    final positionAnimation = Tween<Offset>(
      begin: Offset.zero,
      end: Offset.zero,
    ).animate(controller);

    return (
      scaleAnimation: scaleAnimation,
      positionAnimation: positionAnimation,
    );
  }

  ({Animation<double> scaleAnimation, Animation<Offset> positionAnimation})
  _buildUpdateTweens(
    AnimationController controller,
    CellOffset? oldBegin,
    CellOffset newBegin,
  ) {
    final scaleAnimation = Tween<double>(
      begin: 1.0,
      end: 1.0,
    ).animate(controller);
    final beginOffset = oldBegin != null && oldBegin != newBegin
        ? Offset(
            (oldBegin.x - newBegin.x).toDouble(),
            (oldBegin.y - newBegin.y).toDouble(),
          )
        : Offset.zero;

    final positionAnimation = Tween<Offset>(
      begin: beginOffset,
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: controller, curve: Curves.easeOut));

    return (
      scaleAnimation: scaleAnimation,
      positionAnimation: positionAnimation,
    );
  }

  AnimationController _createAndWireSelectionController(Duration duration) {
    final controller = AnimationController(duration: duration, vsync: _vsync);

    controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        _selectionAnimation?.dispose();
        _selectionAnimation = null;
        notifyListeners();
      }
    });

    controller.addListener(() {
      notifyListeners();
    });

    controller.forward();
    return controller;
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
    _selectionAnimation?.dispose();
    _selectionAnimation = null;

    _selectionBase?.dispose();
    _selectionBase = null;
    _selectionExtent?.dispose();
    _selectionExtent = null;

    _lastSelectionBegin = null;
    _lastSelectionEnd = null;

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
      notifyListeners();
    });

    return highlight;
  }

  @override
  void dispose() {
    _selectionAnimation?.dispose();
    _selectionAnimation = null;

    _selectionBase?.dispose();
    _selectionBase = null;
    _selectionExtent?.dispose();
    _selectionExtent = null;

    for (final highlight in _highlights.toList()) {
      highlight.dispose();
    }
    _highlights.clear();

    super.dispose();
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
    p2.dispose();
    super.dispose();
  }
}
