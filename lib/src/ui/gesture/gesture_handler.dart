import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:xterm/src/core/buffer/cell_offset.dart';
import 'package:xterm/src/core/buffer/range_line.dart';
import 'package:xterm/src/core/mouse/button.dart';
import 'package:xterm/src/core/mouse/button_state.dart';
import 'package:xterm/src/terminal_view.dart';
import 'package:xterm/src/ui/controller.dart';
import 'package:xterm/src/ui/pointer_input.dart';
import 'package:xterm/src/ui/render.dart';

enum _DragHandleType { none, start, end }

class TerminalGestureHandler extends StatefulWidget {
  const TerminalGestureHandler({
    super.key,
    required this.terminalView,
    required this.terminalController,
    this.child,
    this.onTapUp,
    this.onTapDown,
    this.onSecondaryTapDown,
    this.onSecondaryTapUp,
    this.onTertiaryTapDown,
    this.onTertiaryTapUp,
    this.readOnly = false,
    this.viewOffset = Offset.zero,
    this.showToolbar = true,
    this.cursorColor = Colors.cyan,
    this.scrollController,
  });

  final TerminalViewState terminalView;
  final TerminalController terminalController;
  final Widget? child;
  final GestureTapUpCallback? onTapUp;
  final GestureTapDownCallback? onTapDown;
  final GestureTapDownCallback? onSecondaryTapDown;
  final GestureTapUpCallback? onSecondaryTapUp;
  final GestureTapDownCallback? onTertiaryTapDown;
  final GestureTapUpCallback? onTertiaryTapUp;
  final bool readOnly;
  final Offset viewOffset;
  final bool showToolbar;
  final Color cursorColor;
  final ScrollController? scrollController;

  @override
  State<TerminalGestureHandler> createState() => _TerminalGestureHandlerState();
}

class _TerminalGestureHandlerState extends State<TerminalGestureHandler> {
  TerminalViewState get terminalView => widget.terminalView;
  RenderTerminal get renderTerminal => terminalView.renderTerminal;

  BufferRangeLine? _selectedRange;
  CellOffset? _longPressInitialCellOffset;
  late double _originTextSize = terminalView.widget.textStyle.fontSize;

  // 拖杆相关状态
  _DragHandleType _activeDragHandle = _DragHandleType.none;
  CellOffset? _dragHandleFixedPoint; // 拖动时不变的选区端点
  bool _isDragHandleReady = false; // 拖杆是否准备就绪（点击检测到拖杆）

  // 优化的容忍度设置
  static const double _handleTouchRadius = 32.0; // 增加拖杆触摸区域半径
  static const double _selectionTolerance = 20.0; // 点击选区附近的容忍度
  static const Duration _tapTolerance = Duration(milliseconds: 150); // 点击时间容忍度

  // 防抖相关
  DateTime? _lastTapTime;
  Offset? _lastTapPosition;
  bool _isDraggingHandle = false;

  // 延迟 tapDown 执行相关
  Timer? _tapDownTimer;
  TapDownDetails? _pendingTapDownDetails;
  static const Duration _tapDownDelay = Duration(milliseconds: 100); // 延迟时间

  static final TextSelectionControls _materialSelectionControls =
      MaterialTextSelectionControls();
  static final TextSelectionControls _cupertinoSelectionControls =
      CupertinoTextSelectionControls();

  TextSelectionControls get _selectionControls {
    switch (defaultTargetPlatform) {
      case TargetPlatform.iOS:
      case TargetPlatform.macOS:
        return _cupertinoSelectionControls;
      default:
        return _materialSelectionControls;
    }
  }

  ScrollController? _attachedScrollController;
  bool _scrollUpdateScheduled = false;

  bool get _shouldShowHandles =>
      widget.showToolbar &&
      _selectedRange != null &&
      !_selectedRange!.isCollapsed;

  @override
  void initState() {
    super.initState();
    _attachScrollController(widget.scrollController);
  }

  @override
  Widget build(BuildContext context) {
    Widget content = widget.child ?? const SizedBox.shrink();

    final List<Widget> handles = _buildSelectionHandles();
    if (handles.isNotEmpty) {
      content = Stack(
        clipBehavior: Clip.none,
        children: <Widget>[content, ...handles],
      );
    }

    return GestureDetector(
      behavior: HitTestBehavior.deferToChild,
      child: content,
      onTapUp: onTapUp,
      onTapDown: onTapDown,
      onSecondaryTapDown: onSecondaryTapDown,
      onSecondaryTapUp: onSecondaryTapUp,
      onTertiaryTapDown: widget.onTertiaryTapDown,
      onTertiaryTapUp: widget.onTertiaryTapUp,
      onDoubleTapDown: onDoubleTapDown,
      onScaleEnd: onScaleEnd,
      onScaleStart: onScaleStart,
      onScaleUpdate: onScaleUpdate,
      onLongPressStart: _onLongPressStart,
      onLongPressMoveUpdate: _onLongPressMoveUpdate,
      onLongPressEnd: _onLongPressEnd,
    );
  }

  @override
  void didUpdateWidget(TerminalGestureHandler oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.scrollController != widget.scrollController) {
      _detachScrollController(oldWidget.scrollController);
      _attachScrollController(widget.scrollController);
    }
  }

  @override
  void dispose() {
    _cancelPendingTapDown();
    _detachScrollController(_attachedScrollController);
    super.dispose();
  }

  bool get _shouldSendTapEvent =>
      !widget.readOnly &&
      widget.terminalController.shouldSendPointerInput(PointerInput.tap);

  /// 取消待执行的 tapDown
  void _cancelPendingTapDown() {
    _tapDownTimer?.cancel();
    _tapDownTimer = null;
    _pendingTapDownDetails = null;
  }

  /// 执行待执行的 tapDown
  void _executePendingTapDown() {
    if (_pendingTapDownDetails != null) {
      _tapDown(
        widget.onTapDown,
        _pendingTapDownDetails!,
        TerminalMouseButton.left,
        forceCallback: true,
      );
      _pendingTapDownDetails = null;
    }
  }

  List<Widget> _buildSelectionHandles() {
    if (!_shouldShowHandles) {
      return const <Widget>[];
    }

    final BufferRangeLine range = _selectedRange!.normalized;
    final TextDirection textDirection = Directionality.of(context);
    final Size cellSize = renderTerminal.cellSize;

    final Offset startAnchor = renderTerminal.getOffset(range.begin);
    final Offset endAnchor =
        renderTerminal.getOffset(range.end) +
        Offset(cellSize.width, cellSize.height);

    final TextSelectionHandleType startHandleType =
        textDirection == TextDirection.ltr
        ? TextSelectionHandleType.left
        : TextSelectionHandleType.right;
    final TextSelectionHandleType endHandleType =
        textDirection == TextDirection.ltr
        ? TextSelectionHandleType.right
        : TextSelectionHandleType.left;

    return <Widget>[
      _buildHandleWidget(startAnchor, startHandleType, _DragHandleType.start),
      _buildHandleWidget(endAnchor, endHandleType, _DragHandleType.end),
    ];
  }

  Widget _buildHandleWidget(
    Offset anchor,
    TextSelectionHandleType visualType,
    _DragHandleType dragType,
  ) {
    final Offset handleAnchor = _selectionControls.getHandleAnchor(
      visualType,
      renderTerminal.cellSize.height,
    );
    final Offset position = anchor - handleAnchor;

    return Positioned(
      left: position.dx,
      top: position.dy,
      child: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (PointerDownEvent event) {
          _beginHandleDrag(dragType);
          _updateHandleDragFromGlobal(event.position);
        },
        onPointerMove: (PointerMoveEvent event) {
          _updateHandleDragFromGlobal(event.position);
        },
        onPointerUp: (PointerUpEvent event) => _finishHandleDrag(),
        onPointerCancel: (PointerCancelEvent event) => _finishHandleDrag(),
        child: _selectionControls.buildHandle(
          context,
          visualType,
          renderTerminal.cellSize.height,
          widget.showToolbar
              ? () {
                  final Rect? rect = _currentSelectionGlobalRect();
                  if (rect != null) {
                    widget.terminalView.showSelectionToolbar(rect);
                  }
                }
              : null,
        ),
      ),
    );
  }

  /// 检测点击位置是否在拖杆范围内
  _DragHandleType _detectDragHandle(Offset localPosition) {
    if (_selectedRange == null || _selectedRange!.isCollapsed) {
      return _DragHandleType.none;
    }

    // 获取选区开始和结束的像素位置
    final startOffset = renderTerminal.getOffset(_selectedRange!.begin);
    final endOffset = renderTerminal.getOffset(_selectedRange!.end);
    final cellSize = renderTerminal.cellSize;

    // 计算拖杆中心位置，稍微向外偏移以避免重叠
    final startHandleCenter = startOffset + Offset(0, cellSize.height / 2);
    final endHandleCenter =
        endOffset + Offset(cellSize.width, cellSize.height / 2);

    // 优先检查距离更近的拖杆
    final distanceToStart = (localPosition - startHandleCenter).distance;
    final distanceToEnd = (localPosition - endHandleCenter).distance;

    if (distanceToStart <= _handleTouchRadius &&
        distanceToStart <= distanceToEnd) {
      return _DragHandleType.start;
    }

    if (distanceToEnd <= _handleTouchRadius) {
      return _DragHandleType.end;
    }

    return _DragHandleType.none;
  }

  /// 检查点击位置是否在选区附近（容忍度范围内）
  bool _isNearSelection(Offset localPosition) {
    if (_selectedRange == null || _selectedRange!.isCollapsed) {
      return false;
    }

    final cellOffset = renderTerminal.getCellOffset(localPosition);

    // 计算到选区的最短距离
    if (_selectedRange!.contains(cellOffset)) {
      return true; // 在选区内部
    }

    // 检查是否在选区边界附近
    final startPixel = renderTerminal.getOffset(_selectedRange!.begin);
    final endPixel = renderTerminal.getOffset(_selectedRange!.end);

    // 简单的矩形区域检查
    final selectionRect = Rect.fromPoints(
      startPixel,
      endPixel + renderTerminal.cellSize.bottomRight(Offset.zero),
    );
    final expandedRect = selectionRect.inflate(_selectionTolerance);

    return expandedRect.contains(localPosition);
  }

  /// 防抖检查
  bool _isDuplicateTap(Offset position) {
    final now = DateTime.now();
    if (_lastTapTime != null && _lastTapPosition != null) {
      final timeDiff = now.difference(_lastTapTime!);
      final positionDiff = (position - _lastTapPosition!).distance;

      if (timeDiff < _tapTolerance && positionDiff < 10.0) {
        return true;
      }
    }

    _lastTapTime = now;
    _lastTapPosition = position;
    return false;
  }

  void _tapDown(
    GestureTapDownCallback? callback,
    TapDownDetails details,
    TerminalMouseButton button, {
    bool forceCallback = false,
  }) {
    var handled = false;
    if (_shouldSendTapEvent && !_isNearSelection(details.localPosition)) {
      handled = renderTerminal.mouseEvent(
        button,
        TerminalMouseButtonState.down,
        details.localPosition,
      );
    }
    if (!handled || forceCallback) {
      callback?.call(details);
    }
  }

  void _tapUp(
    GestureTapUpCallback? callback,
    TapUpDetails details,
    TerminalMouseButton button, {
    bool forceCallback = false,
  }) {
    var handled = false;
    if (_shouldSendTapEvent && !_isNearSelection(details.localPosition)) {
      handled = renderTerminal.mouseEvent(
        button,
        TerminalMouseButtonState.up,
        details.localPosition,
      );
    }
    if (!handled || forceCallback) {
      callback?.call(details);
    }
  }

  void onTapUp(TapUpDetails details) {
    // 如果有待执行的 tapDown，立即执行
    if (_pendingTapDownDetails != null) {
      _executePendingTapDown();
    }
    _cancelPendingTapDown();

    // 防抖检查
    if (_isDuplicateTap(details.localPosition)) {
      return;
    }

    // 如果之前检测到拖杆准备状态但没有实际拖动，重置状态
    if (_isDragHandleReady && !_isDraggingHandle) {
      _resetDragHandleState();
    }

    widget.onTapUp?.call(details);

    final cellOffset = renderTerminal.getCellOffset(details.localPosition);

    if (_selectedRange != null) {
      // 检查是否点击了拖杆
      final dragHandle = _detectDragHandle(details.localPosition);
      if (dragHandle != _DragHandleType.none) {
        // 点击了拖杆，不做任何操作，等待可能的拖动
        return;
      }

      if (_selectedRange!.contains(cellOffset)) {
        // 点击选中区域内部，保持选择
      } else {
        // 点击选中区域外部，清除选择
        _clearSelection();
      }
    }
  }

  void onTapDown(TapDownDetails details) {
    // 优先检查是否点击了拖杆（如果已有选区）
    if (_selectedRange != null && !_selectedRange!.isCollapsed) {
      final dragHandle = _detectDragHandle(details.localPosition);
      if (dragHandle != _DragHandleType.none) {
        // 点击了拖杆，准备拖动状态
        _prepareDragHandle(dragHandle);
        // 不设置延迟的 tapDown，因为这是拖杆操作
        return;
      }
    }

    // 延迟执行 tapDown，先等待可能的长按或拖动事件
    _cancelPendingTapDown();
    _pendingTapDownDetails = details;

    _tapDownTimer = Timer(_tapDownDelay, () {
      // 只有在没有进入拖杆模式时才执行 tapDown
      if (!_isDragHandleReady) {
        _executePendingTapDown();
      }
      _tapDownTimer = null;
    });
  }

  /// 准备拖杆拖动状态
  void _prepareDragHandle(_DragHandleType dragHandle) {
    if (_selectedRange == null) {
      return;
    }
    final BufferRangeLine range = _selectedRange!.normalized;
    _activeDragHandle = dragHandle;
    _isDragHandleReady = true;
    _dragHandleFixedPoint = dragHandle == _DragHandleType.start
        ? range.end
        : range.begin;

    // 提供轻微的触觉反馈表示检测到拖杆
    HapticFeedback.lightImpact();
  }

  void _beginHandleDrag(_DragHandleType dragHandle) {
    if (_selectedRange == null) {
      return;
    }
    final BufferRangeLine range = _selectedRange!.normalized;
    _activeDragHandle = dragHandle;
    _dragHandleFixedPoint = dragHandle == _DragHandleType.start
        ? range.end
        : range.begin;
    _isDragHandleReady = false;
    _isDraggingHandle = true;
    _longPressInitialCellOffset = null;
    if (widget.showToolbar) {
      widget.terminalView.hideSelectionToolbar();
    }
    HapticFeedback.selectionClick();
  }

  void _updateHandleDragFromGlobal(Offset globalPosition) {
    if (_activeDragHandle == _DragHandleType.none) {
      return;
    }
    final Offset localPosition = renderTerminal.globalToLocal(globalPosition);
    _handleDragUpdate(localPosition);
  }

  void _finishHandleDrag() {
    if (_activeDragHandle == _DragHandleType.none) {
      return;
    }
    if (widget.showToolbar) {
      final Rect? rect = _currentSelectionGlobalRect();
      if (rect != null) {
        widget.terminalView.showSelectionToolbar(rect);
      }
    }
    _resetDragHandleState();
  }

  void _onViewportChanged() {
    if (!mounted) {
      return;
    }
    if (_selectedRange == null || _selectedRange!.isCollapsed) {
      if (widget.showToolbar && widget.terminalView.isSelectionToolbarShown) {
        widget.terminalView.hideSelectionToolbar();
      }
      return;
    }

    setState(() {});

    if (widget.showToolbar && widget.terminalView.isSelectionToolbarShown) {
      final Rect? rect = _currentSelectionGlobalRect();
      if (rect != null) {
        widget.terminalView.showSelectionToolbar(rect);
      }
    }
  }

  void _handleScrollChange() {
    if (_scrollUpdateScheduled || !mounted) {
      return;
    }
    _scrollUpdateScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        _scrollUpdateScheduled = false;
        return;
      }
      _scrollUpdateScheduled = false;
      _onViewportChanged();
    });
  }

  void _attachScrollController(ScrollController? controller) {
    if (controller == null || controller == _attachedScrollController) {
      return;
    }
    controller.addListener(_handleScrollChange);
    _attachedScrollController = controller;
  }

  void _detachScrollController(ScrollController? controller) {
    if (controller == null) {
      return;
    }
    controller.removeListener(_handleScrollChange);
    if (_attachedScrollController == controller) {
      _attachedScrollController = null;
    }
  }

  void _applySelection(BufferRangeLine range) {
    final BufferRangeLine normalized = range.normalized;
    renderTerminal.selectCharacters(normalized.begin, normalized.end);
    if (_selectedRange != normalized) {
      setState(() {
        _selectedRange = normalized;
      });
    } else {
      _selectedRange = normalized;
    }
  }

  /// 重置拖杆状态
  void _resetDragHandleState() {
    _activeDragHandle = _DragHandleType.none;
    _isDragHandleReady = false;
    _dragHandleFixedPoint = null;
    _isDraggingHandle = false;
  }

  void onSecondaryTapDown(TapDownDetails details) {
    _tapDown(widget.onSecondaryTapDown, details, TerminalMouseButton.right);
  }

  void onSecondaryTapUp(TapUpDetails details) {
    _tapUp(widget.onSecondaryTapUp, details, TerminalMouseButton.right);
  }

  void onTertiaryTapDown(TapDownDetails details) {
    _tapDown(widget.onTertiaryTapDown, details, TerminalMouseButton.middle);
  }

  void onTertiaryTapUp(TapUpDetails details) {
    _tapUp(widget.onTertiaryTapUp, details, TerminalMouseButton.right);
  }

  void onDoubleTapDown(TapDownDetails details) {
    // 双击时取消待执行的 tapDown 和拖杆状态
    _cancelPendingTapDown();
    _resetDragHandleState();

    final cellOffset = renderTerminal.getCellOffset(details.localPosition);

    if (details.kind == PointerDeviceKind.touch) {
      final BufferRangeLine? wordRange = renderTerminal.selectWord(cellOffset);
      if (wordRange != null) {
        _applySelection(wordRange);
      }
    } else {
      renderTerminal.selectCharacters(cellOffset, cellOffset);
      if (widget.terminalController.selection != null) {
        _applySelection(BufferRangeLine(cellOffset, cellOffset));
      }
    }

    if (widget.showToolbar) {
      final Rect? selectionRect = _currentSelectionGlobalRect();
      if (selectionRect != null) {
        widget.terminalView.showSelectionToolbar(selectionRect);
      }
    }
  }

  void onScaleStart(ScaleStartDetails details) {
    // 缩放开始时取消待执行的 tapDown
    _cancelPendingTapDown();

    // 优先检查是否已经准备好拖杆状态
    if (_isDragHandleReady && _activeDragHandle != _DragHandleType.none) {
      // 从准备状态进入实际拖动
      _isDraggingHandle = true;
      _longPressInitialCellOffset = null;
      if (widget.showToolbar) {
        widget.terminalView.hideSelectionToolbar();
      }

      // 提供拖动开始的触觉反馈
      HapticFeedback.selectionClick();
      return;
    }

    // 检测是否是拖杆操作（fallback，通常不应该到这里）
    _activeDragHandle = _detectDragHandle(details.localFocalPoint);

    if (_activeDragHandle != _DragHandleType.none && _selectedRange != null) {
      // 开始拖杆操作
      _isDraggingHandle = true;
      final BufferRangeLine range = _selectedRange!.normalized;
      _dragHandleFixedPoint = _activeDragHandle == _DragHandleType.start
          ? range.end
          : range.begin;
      _longPressInitialCellOffset = null;
      if (widget.showToolbar) {
        widget.terminalView.hideSelectionToolbar();
      }

      // 提供触觉反馈
      HapticFeedback.selectionClick();
    } else {
      // 不是拖杆操作，处理缩放或清除选区
      _resetDragHandleState();

      // 如果不在选区附近，清除选区
      if (_selectedRange != null &&
          !_isNearSelection(details.localFocalPoint)) {
        _clearSelection();
      }

      _longPressInitialCellOffset = null;
      _originTextSize = terminalView.textSizeNoti.value;
    }
  }

  void onScaleUpdate(ScaleUpdateDetails details) {
    if (_activeDragHandle != _DragHandleType.none &&
        (_isDraggingHandle || _isDragHandleReady)) {
      // 处理拖杆拖动
      if (!_isDraggingHandle) {
        // 从准备状态进入拖动状态
        _isDraggingHandle = true;
        HapticFeedback.selectionClick();
      }
      _handleDragUpdate(details.localFocalPoint);
    } else if (details.pointerCount == 2 &&
        details.scale != 1.0 &&
        !_isDraggingHandle &&
        !_isDragHandleReady) {
      // 处理双指缩放
      _handleZoomUpdate(details);
    }
  }

  void onScaleEnd(ScaleEndDetails details) {
    if (_activeDragHandle != _DragHandleType.none && _isDraggingHandle) {
      // 拖杆拖动结束
      HapticFeedback.selectionClick();
      if (widget.showToolbar) {
        final Rect? rect = _currentSelectionGlobalRect();
        if (rect != null) {
          widget.terminalView.showSelectionToolbar(rect);
        }
      }
    } else if (!_isDraggingHandle && !_isDragHandleReady) {
      // 缩放结束
      _originTextSize = terminalView.textSizeNoti.value;
    }

    _resetDragHandleState();
  }

  void _handleDragUpdate(Offset localPosition) {
    if (_dragHandleFixedPoint == null) return;

    final currentCellOffset = renderTerminal.getCellOffset(localPosition);

    // 防止拖动到相同位置
    if (currentCellOffset ==
        (_activeDragHandle == _DragHandleType.start
            ? _selectedRange?.begin
            : _selectedRange?.end)) {
      return;
    }

    // 根据拖动的拖杆更新选区
    CellOffset newStart, newEnd;
    if (_activeDragHandle == _DragHandleType.start) {
      // 拖动开始拖杆
      if (currentCellOffset.isBefore(_dragHandleFixedPoint!) ||
          currentCellOffset == _dragHandleFixedPoint!) {
        newStart = currentCellOffset;
        newEnd = _dragHandleFixedPoint!;
      } else {
        newStart = _dragHandleFixedPoint!;
        newEnd = currentCellOffset;
      }
    } else {
      // 拖动结束拖杆
      if (currentCellOffset.isBefore(_dragHandleFixedPoint!) ||
          currentCellOffset == _dragHandleFixedPoint!) {
        newStart = currentCellOffset;
        newEnd = _dragHandleFixedPoint!;
      } else {
        newStart = _dragHandleFixedPoint!;
        newEnd = currentCellOffset;
      }
    }

    // 确保选区不为空
    if (newStart != newEnd) {
      final bool draggingStart = _activeDragHandle == _DragHandleType.start;
      if (draggingStart && currentCellOffset.isAfter(_dragHandleFixedPoint!)) {
        _activeDragHandle = _DragHandleType.end;
        _dragHandleFixedPoint = newStart;
      } else if (!draggingStart &&
          currentCellOffset.isBefore(_dragHandleFixedPoint!)) {
        _activeDragHandle = _DragHandleType.start;
        _dragHandleFixedPoint = newEnd;
      }

      _applySelection(BufferRangeLine(newStart, newEnd));

      // 自动滚动
      terminalView.autoScrollDown(localPosition);
    }
  }

  void _handleZoomUpdate(ScaleUpdateDetails details) {
    // 只处理双指缩放
    if (details.pointerCount != 2 || details.scale == 1.0) {
      return;
    }

    final scale = math.pow(details.scale, 0.3);
    final fontSize = _originTextSize * scale;

    // 限制字体大小范围
    if (fontSize >= 7 && fontSize <= 17) {
      terminalView.textSizeNoti.value = fontSize;
    }
  }

  void _clearSelection() {
    if (_selectedRange != null) {
      setState(() {
        _selectedRange = null;
      });
    }
    renderTerminal.clearSelection();
    _resetDragHandleState();
    if (widget.showToolbar) {
      widget.terminalView.hideSelectionToolbar();
    }
  }

  void _onLongPressStart(LongPressStartDetails details) {
    // 长按开始时取消待执行的 tapDown
    _cancelPendingTapDown();

    // 如果已经在拖杆准备状态，不处理长按
    if (_isDragHandleReady) {
      return;
    }

    // 长按只用于初始化选区，不处理已有选区的调整
    if (_selectedRange != null && !_selectedRange!.isCollapsed) {
      // 如果点击在选区外，清除选区并重新开始
      if (!_isNearSelection(details.localPosition)) {
        _clearSelection();
      } else {
        // 在选区内或附近的长按不做处理
        return;
      }
    }

    // 执行原有的长按逻辑 - 仅用于初始化选区
    _clearSelection();

    _longPressInitialCellOffset = renderTerminal.getCellOffset(
      details.localPosition,
    );

    _applySelection(BufferRangeLine.collapsed(_longPressInitialCellOffset!));

    // 重置拖杆状态
    _resetDragHandleState();

    // 提供长按反馈
    HapticFeedback.lightImpact();
  }

  void _onLongPressMoveUpdate(LongPressMoveUpdateDetails details) {
    // 如果在拖杆模式，不处理长按移动
    if (_isDragHandleReady || _isDraggingHandle) {
      return;
    }

    // 处理传统的长按拖动选择（仅用于初始化选区）
    if (_longPressInitialCellOffset == null) {
      return;
    }

    final currentCellOffset = renderTerminal.getCellOffset(
      details.localPosition,
    );

    // 防止无效更新
    if (currentCellOffset == _longPressInitialCellOffset) {
      return;
    }

    final BufferRangeLine range;
    if (currentCellOffset.isBefore(_longPressInitialCellOffset!)) {
      range = BufferRangeLine(currentCellOffset, _longPressInitialCellOffset!);
    } else {
      range = BufferRangeLine(_longPressInitialCellOffset!, currentCellOffset);
    }

    _applySelection(range);

    terminalView.autoScrollDown(details.localPosition);
  }

  void _onLongPressEnd(LongPressEndDetails details) {
    // 长按结束只处理初始选区创建的情况
    if (_longPressInitialCellOffset != null) {
      _longPressInitialCellOffset = null;

      if (widget.showToolbar &&
          _selectedRange != null &&
          !_selectedRange!.isCollapsed) {
        final Rect? selectionRect = _currentSelectionGlobalRect();
        if (selectionRect != null) {
          widget.terminalView.showSelectionToolbar(selectionRect);
        }
      }
    }
  }

  Rect? _currentSelectionGlobalRect() {
    if (_selectedRange == null || _selectedRange!.isCollapsed) {
      return null;
    }
    final Offset startLocal = renderTerminal.getOffset(_selectedRange!.begin);
    final Offset endLocal = renderTerminal.getOffset(_selectedRange!.end);
    final Offset endBottomRight =
        endLocal + renderTerminal.cellSize.bottomRight(Offset.zero);
    final Rect localRect = Rect.fromPoints(startLocal, endBottomRight);
    final Offset globalTopLeft = renderTerminal.localToGlobal(
      localRect.topLeft,
    );
    final Offset globalBottomRight = renderTerminal.localToGlobal(
      localRect.bottomRight,
    );
    return Rect.fromPoints(globalTopLeft, globalBottomRight);
  }
}
