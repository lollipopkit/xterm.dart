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
  insert,  // 插入新选区
  update,  // 更新现有选区
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
  })  : _selectionMode = selectionMode,
        _pointerInputs = pointerInputs,
        _suspendPointerInputs = suspendPointerInput,
        _vsync = vsync;

  final TickerProvider _vsync;
  
  CellAnchor? _selectionBase;
  CellAnchor? _selectionExtent;
  
  // 动画相关状态
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

  // 动画访问器
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
    final newBegin = base.offset;
    final newEnd = extent.offset;
    
    // 检测是插入还是更新
    final isNewSelection = _selectionBase == null || _selectionExtent == null;
    final animationType = isNewSelection 
        ? SelectionAnimationType.insert 
        : SelectionAnimationType.update;

    // 清理旧动画
    _selectionAnimation?.dispose();
    
    // 创建新动画
    _selectionAnimation = _createSelectionAnimation(
      type: animationType,
      oldBegin: _lastSelectionBegin,
      oldEnd: _lastSelectionEnd,
      newBegin: newBegin,
      newEnd: newEnd,
    );

    // 更新选区
    _selectionBase?.dispose();
    _selectionBase = base;

    _selectionExtent?.dispose();
    _selectionExtent = extent;

    if (mode != null) {
      _selectionMode = mode;
    }

    // 记录位置用于下次动画
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
    final controller = AnimationController(
      duration: type == SelectionAnimationType.insert 
          ? const Duration(milliseconds: 200)
          : const Duration(milliseconds: 300),
      vsync: _vsync,
    );

    late Animation<double> scaleAnimation;
    late Animation<Offset> positionAnimation;

    if (type == SelectionAnimationType.insert) {
      // 插入动画：130% 缩小到 100%
      scaleAnimation = Tween<double>(
        begin: 1.3,
        end: 1.0,
      ).animate(CurvedAnimation(
        parent: controller,
        curve: Curves.elasticOut,
      ));
      
      // 插入时位置不变
      positionAnimation = Tween<Offset>(
        begin: Offset.zero,
        end: Offset.zero,
      ).animate(controller);
    } else {
      // 更新动画：位置从旧位置移动到新位置
      scaleAnimation = Tween<double>(
        begin: 1.0,
        end: 1.0,
      ).animate(controller);

      final beginOffset = oldBegin != null && oldBegin != newBegin
          ? Offset(
              (oldBegin.x - newBegin.x).toDouble(),
              (oldBegin.y - newBegin.y).toDouble(),
            )
          : Offset.zero;

      positionAnimation = Tween<Offset>(
        begin: beginOffset,
        end: Offset.zero,
      ).animate(CurvedAnimation(
        parent: controller,
        curve: Curves.easeOutCubic,
      ));
    }

    // 动画完成后清理
    controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        _selectionAnimation?.dispose();
        _selectionAnimation = null;
        notifyListeners();
      }
    });

    // 动画过程中触发重绘
    controller.addListener(() {
      notifyListeners();
    });

    // 启动动画
    controller.forward();

    return SelectionAnimation(
      controller: controller,
      scaleAnimation: scaleAnimation,
      positionAnimation: positionAnimation,
      type: type,
    );
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
    // 清理动画
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
    final highlight = TerminalHighlight(
      this,
      p1: p1,
      p2: p2,
      color: color,
    );

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
}