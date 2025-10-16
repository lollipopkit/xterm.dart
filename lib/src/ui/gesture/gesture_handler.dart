import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:xterm/src/ui/render.dart';
import 'package:xterm/xterm.dart';

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

  // 桌面端拖动选区相关状态
  bool _isMouseDeviceDown = false;
  bool _isMouseSelectionInProgress = false;
  CellOffset? _mouseSelectionBase;
  PointerDeviceKind? _mousePointerKind;
  bool _suppressNextTapUp = false;
  bool _mouseTapDownDispatched = false;
  Offset? _mouseSelectionLastPosition;

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
  ValueListenable<bool>? _scrollActivityNotifier;

  bool get _shouldShowHandles =>
      widget.showToolbar &&
      _selectedRange != null &&
      !_selectedRange!.isCollapsed;

  bool get _isViewportScrolling => _scrollActivityNotifier?.value ?? false;

  @override
  void initState() {
    super.initState();
    widget.terminalController.addListener(_handleControllerSelectionChanged);
    _syncSelectionFromController();
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
    if (oldWidget.terminalController != widget.terminalController) {
      oldWidget.terminalController.removeListener(
        _handleControllerSelectionChanged,
      );
      widget.terminalController.addListener(_handleControllerSelectionChanged);
      _syncSelectionFromController();
    }
    if (oldWidget.scrollController != widget.scrollController) {
      _detachScrollController(oldWidget.scrollController);
      _attachScrollController(widget.scrollController);
    }
  }

  @override
  void dispose() {
    _cancelPendingTapDown();
    widget.terminalController.removeListener(_handleControllerSelectionChanged);
    _detachScrollController(_attachedScrollController);
    super.dispose();
  }

  bool get _shouldSendTapEvent =>
      !widget.readOnly &&
      widget.terminalController.shouldSendPointerInput(PointerInput.tap);

  /// 取消待执行的 tapDown
  void _cancelPendingTapDown() {
    final hadPending = _pendingTapDownDetails != null || _tapDownTimer != null;
    _tapDownTimer?.cancel();
    _tapDownTimer = null;
    _pendingTapDownDetails = null;
    if (hadPending) {
      _mouseTapDownDispatched = false;
    }
  }

  /// 执行待执行的 tapDown
  void _executePendingTapDown() {
    if (_pendingTapDownDetails != null) {
      final pendingDetails = _pendingTapDownDetails!;
      _tapDown(
        widget.onTapDown,
        pendingDetails,
        TerminalMouseButton.left,
        forceCallback: true,
      );
      if (_isPointerKindMouse(pendingDetails.kind)) {
        _mouseTapDownDispatched = true;
        _mouseSelectionLastPosition = pendingDetails.localPosition;
      }
      _pendingTapDownDetails = null;
    }
  }

  void _handleControllerSelectionChanged() {
    if (!mounted) {
      return;
    }
    _syncSelectionFromController();
  }

  void _syncSelectionFromController() {
    final selection = widget.terminalController.selection;

    BufferRangeLine? nextRange;
    if (selection == null) {
      nextRange = null;
    } else {
      nextRange = _controllerRangeAsLine(selection);
    }

    final previousRange = _selectedRange;
    final bool changed = previousRange != nextRange;

    if (changed) {
      setState(() {
        _selectedRange = nextRange;
      });
    } else {
      _selectedRange = nextRange;
    }

    if (!widget.showToolbar ||
        !widget.terminalView.isSelectionToolbarShown ||
        nextRange == null ||
        nextRange.isCollapsed) {
      if (widget.showToolbar &&
          widget.terminalView.isSelectionToolbarShown &&
          (nextRange == null || nextRange.isCollapsed)) {
        widget.terminalView.hideSelectionToolbar();
      }
      return;
    }

    if (_isViewportScrolling) {
      return;
    }

    final Rect? rect = _selectionRectForRange(nextRange);
    if (rect != null) {
      widget.terminalView.showSelectionToolbar(rect);
    }
  }

  List<Widget> _buildSelectionHandles() {
    if (!_shouldShowHandles) {
      return const <Widget>[];
    }

    final BufferRangeLine range = _selectedRange!.normalized;
    final _SelectionGeometry? geometry = _selectionGeometry(range);
    if (geometry == null) {
      return const <Widget>[];
    }

    final TextDirection textDirection = Directionality.of(context);
    final TextSelectionHandleType startHandleType = _startHandleTypeFor(
      textDirection,
    );
    final TextSelectionHandleType endHandleType = _endHandleTypeFor(
      textDirection,
    );

    return <Widget>[
      _buildHandleWidget(
        geometry.startAnchor,
        startHandleType,
        _DragHandleType.start,
      ),
      _buildHandleWidget(
        geometry.endAnchor,
        endHandleType,
        _DragHandleType.end,
      ),
    ];
  }

  TextSelectionHandleType _startHandleTypeFor(TextDirection textDirection) {
    return textDirection == TextDirection.ltr
        ? TextSelectionHandleType.left
        : TextSelectionHandleType.right;
  }

  TextSelectionHandleType _endHandleTypeFor(TextDirection textDirection) {
    return textDirection == TextDirection.ltr
        ? TextSelectionHandleType.right
        : TextSelectionHandleType.left;
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

  _SelectionGeometry? _selectionGeometry(BufferRangeLine range) {
    final BufferRangeLine normalized = range.normalized;
    final Size cellSize = renderTerminal.cellSize;
    final Offset startTopLeft = renderTerminal.getOffset(normalized.begin);
    final Offset startAnchor = startTopLeft + Offset(0, cellSize.height);

    final Offset endTopLeft = renderTerminal.getOffset(normalized.end);
    final Offset endBottomRight =
        endTopLeft + Offset(cellSize.width, cellSize.height);
    final Offset endAnchor = endBottomRight;

    return _SelectionGeometry(
      localRect: Rect.fromPoints(startTopLeft, endBottomRight),
      startAnchor: startAnchor,
      endAnchor: endAnchor,
    );
  }

  bool _selectionContains(BufferRangeLine range, CellOffset offset) {
    return range.normalized.contains(offset);
  }

  BufferRangeLine? _controllerRangeAsLine(BufferRange selection) {
    if (selection is BufferRangeLine) {
      return _inclusiveControllerRange(selection);
    }
    if (selection.isCollapsed) {
      return BufferRangeLine(selection.begin, selection.begin);
    }
    return null;
  }

  BufferRangeLine _inclusiveControllerRange(BufferRangeLine range) {
    final BufferRangeLine normalized = range.normalized;
    if (normalized.isCollapsed) {
      return normalized;
    }
    final bool shouldAdjust;
    if (normalized.end.y == normalized.begin.y) {
      shouldAdjust = normalized.end.x >= normalized.begin.x;
    } else {
      shouldAdjust = normalized.end.x >= normalized.begin.x;
    }
    if (!shouldAdjust) {
      return normalized;
    }
    final CellOffset inclusiveEnd = _exclusiveToInclusive(normalized.end);
    return BufferRangeLine(normalized.begin, inclusiveEnd);
  }

  CellOffset _exclusiveToInclusive(CellOffset exclusiveEnd) {
    if (exclusiveEnd.x > 0) {
      return CellOffset(exclusiveEnd.x - 1, exclusiveEnd.y);
    }
    final int lastColumn = terminalView.widget.terminal.viewWidth - 1;
    final int previousRow = math.max(0, exclusiveEnd.y - 1);
    return CellOffset(lastColumn, previousRow);
  }

  /// 检测点击位置是否在拖杆范围内
  _DragHandleType _detectDragHandle(Offset localPosition) {
    final BufferRangeLine? range = _selectedRange;
    if (range == null || range.isCollapsed) {
      return _DragHandleType.none;
    }

    final _SelectionGeometry? geometry = _selectionGeometry(range);
    if (geometry == null) {
      return _DragHandleType.none;
    }

    final TextDirection textDirection = Directionality.of(context);
    final TextSelectionHandleType startHandleType = _startHandleTypeFor(
      textDirection,
    );
    final TextSelectionHandleType endHandleType = _endHandleTypeFor(
      textDirection,
    );
    final double lineHeight = renderTerminal.cellSize.height;
    final Size handleSize = _selectionControls.getHandleSize(lineHeight);

    (_DragHandleType, double)? bestMatch;

    void considerHandle(
      _DragHandleType type,
      Offset anchor,
      TextSelectionHandleType visualType,
    ) {
      final Offset handleAnchor = _selectionControls.getHandleAnchor(
        visualType,
        lineHeight,
      );
      final Rect hitRect = Rect.fromLTWH(
        anchor.dx - handleAnchor.dx,
        anchor.dy - handleAnchor.dy,
        handleSize.width,
        handleSize.height,
      ).inflate(_handleTouchRadius);

      if (!hitRect.contains(localPosition)) {
        return;
      }

      final Offset center = hitRect.center;
      final double dx = localPosition.dx - center.dx;
      final double dy = localPosition.dy - center.dy;
      final double distanceSquared = dx * dx + dy * dy;

      if (bestMatch == null || distanceSquared < bestMatch!.$2) {
        bestMatch = (type, distanceSquared);
      }
    }

    considerHandle(
      _DragHandleType.start,
      geometry.startAnchor,
      startHandleType,
    );
    considerHandle(
      _DragHandleType.end,
      geometry.endAnchor,
      endHandleType,
    );

    return bestMatch?.$1 ?? _DragHandleType.none;
  }

  /// 检查点击位置是否在选区附近（容忍度范围内）
  bool _isNearSelection(Offset localPosition) {
    final BufferRangeLine? range = _selectedRange;
    if (range == null || range.isCollapsed) {
      return false;
    }

    final cellOffset = renderTerminal.getCellOffset(localPosition);

    if (_selectionContains(range, cellOffset)) {
      return true;
    }

    final _SelectionGeometry? geometry = _selectionGeometry(range);
    if (geometry == null) {
      return false;
    }

    final Rect expandedRect = geometry.localRect.inflate(_selectionTolerance);
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

  bool _isPointerKindMouse(PointerDeviceKind? kind) {
    return kind == PointerDeviceKind.mouse ||
        kind == PointerDeviceKind.trackpad ||
        kind == PointerDeviceKind.stylus ||
        kind == PointerDeviceKind.invertedStylus;
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

  bool _handleMouseSelectionUpdate(Offset localPosition) {
    if (!_isMouseDeviceDown ||
        !_isPointerKindMouse(_mousePointerKind) ||
        _isDraggingHandle ||
        _isDragHandleReady ||
        widget.terminalController.shouldSendPointerInput(PointerInput.drag)) {
      return false;
    }

    final base = _mouseSelectionBase;
    if (base == null) {
      return false;
    }

    final current = renderTerminal.getCellOffset(localPosition);
    _mouseSelectionLastPosition = localPosition;

    if (!_isMouseSelectionInProgress) {
      if (current == base) {
        return false;
      }

      _isMouseSelectionInProgress = true;
      _cancelPendingTapDown();
      _longPressInitialCellOffset = null;
      _resetDragHandleState();

      if (widget.showToolbar) {
        widget.terminalView.hideSelectionToolbar();
      }
    }

    BufferRangeLine newRange;
    var didMove = false;

    if (current == base) {
      newRange = BufferRangeLine(base, base);
    } else if (current.isBefore(base)) {
      newRange = BufferRangeLine(current, base);
      didMove = true;
    } else {
      newRange = BufferRangeLine(base, current);
      didMove = true;
    }

    _applySelection(newRange);

    if (didMove) {
      terminalView.autoScrollDown(localPosition);
    }

    return true;
  }

  void _dispatchMouseTapUpIfNeeded() {
    if (!_mouseTapDownDispatched) {
      return;
    }

    Offset localPosition;

    if (_mouseSelectionLastPosition != null) {
      localPosition = _mouseSelectionLastPosition!;
    } else if (_mouseSelectionBase != null) {
      final baseOffset = renderTerminal.getOffset(_mouseSelectionBase!);
      localPosition = baseOffset +
          Offset(
            renderTerminal.cellSize.width / 2,
            renderTerminal.cellSize.height / 2,
          );
    } else {
      localPosition = Offset.zero;
    }

    final globalPosition = renderTerminal.localToGlobal(localPosition);

    final details = TapUpDetails(
      kind: _mousePointerKind ?? PointerDeviceKind.mouse,
      localPosition: localPosition,
      globalPosition: globalPosition,
    );

    _tapUp(
      widget.onTapUp,
      details,
      TerminalMouseButton.left,
      forceCallback: true,
    );

    _mouseTapDownDispatched = false;
  }

  void _finishMouseSelection() {
    if (!_isMouseSelectionInProgress) {
      _resetMouseSelectionState();
      return;
    }

    _cancelPendingTapDown();

    final hasSelection =
        _selectedRange != null && !_selectedRange!.isCollapsed;

    if (widget.showToolbar && hasSelection) {
      final Rect? rect = _currentSelectionGlobalRect();
      if (rect != null) {
        widget.terminalView.showSelectionToolbar(rect);
      }
    }

    _dispatchMouseTapUpIfNeeded();
    _resetMouseSelectionState();
    _suppressNextTapUp = true;
  }

  void _resetMouseSelectionState() {
    _isMouseDeviceDown = false;
    _isMouseSelectionInProgress = false;
    _mouseSelectionBase = null;
    _mousePointerKind = null;
    _mouseTapDownDispatched = false;
    _mouseSelectionLastPosition = null;
  }

  void onTapUp(TapUpDetails details) {
    if (_suppressNextTapUp) {
      _suppressNextTapUp = false;
      _resetMouseSelectionState();
      return;
    }

    if (_isMouseSelectionInProgress) {
      _finishMouseSelection();
      return;
    }

    _resetMouseSelectionState();

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

      if (_selectionContains(_selectedRange!, cellOffset)) {
        // 点击选中区域内部，保持选择
      } else {
        // 点击选中区域外部，清除选择
        _clearSelection();
      }
    }
  }

  void onTapDown(TapDownDetails details) {
    _suppressNextTapUp = false;

    if (_isPointerKindMouse(details.kind)) {
      _isMouseDeviceDown = true;
      _mousePointerKind = details.kind;
      _mouseSelectionBase = renderTerminal.getCellOffset(
        details.localPosition,
      );
      _isMouseSelectionInProgress = false;
      _mouseSelectionLastPosition = details.localPosition;
      _mouseTapDownDispatched = false;
    } else {
      _resetMouseSelectionState();
    }

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

    if (widget.showToolbar &&
        widget.terminalView.isSelectionToolbarShown &&
        !_isViewportScrolling) {
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
    if (_scrollActivityNotifier == null) {
      _ensureScrollActivityBinding();
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
    _ensureScrollActivityBinding();
  }

  void _detachScrollController(ScrollController? controller) {
    if (controller == null) {
      return;
    }
    controller.removeListener(_handleScrollChange);
    if (_attachedScrollController == controller) {
      _scrollActivityNotifier?.removeListener(_handleScrollActivityChanged);
      _scrollActivityNotifier = null;
      _attachedScrollController = null;
    }
  }

  void _ensureScrollActivityBinding() {
    final controller = _attachedScrollController;
    if (controller == null) {
      return;
    }
    if (!controller.hasClients) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _attachedScrollController != controller) {
          return;
        }
        _ensureScrollActivityBinding();
      });
      return;
    }

    final ValueListenable<bool> notifier =
        controller.position.isScrollingNotifier;
    if (identical(_scrollActivityNotifier, notifier)) {
      return;
    }
    _scrollActivityNotifier?.removeListener(_handleScrollActivityChanged);
    _scrollActivityNotifier = notifier;
    _scrollActivityNotifier!.addListener(_handleScrollActivityChanged);
    _handleScrollActivityChanged();
  }

  void _handleScrollActivityChanged() {
    if (!mounted) {
      return;
    }
    if (_isViewportScrolling) {
      if (widget.showToolbar && widget.terminalView.isSelectionToolbarShown) {
        widget.terminalView.hideSelectionToolbar();
      }
      return;
    }

    if (!widget.showToolbar ||
        _selectedRange == null ||
        _selectedRange!.isCollapsed ||
        !widget.terminalView.isSelectionToolbarShown) {
      return;
    }

    final Rect? rect = _currentSelectionGlobalRect();
    if (rect != null) {
      widget.terminalView.showSelectionToolbar(rect);
    }
  }

  void _applySelection(BufferRangeLine range) {
    final BufferRangeLine normalized = range.normalized;
    if (normalized.isCollapsed) {
      renderTerminal.selectCharacters(normalized.begin);
    } else {
      renderTerminal.selectBufferRange(normalized);
    }
    _syncSelectionFromController();
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
    } else if (details.pointerCount == 1 &&
        _handleMouseSelectionUpdate(details.localFocalPoint)) {
      return;
    } else if (details.pointerCount == 2 &&
        details.scale != 1.0 &&
        !_isDraggingHandle &&
        !_isDragHandleReady) {
      // 处理双指缩放
      _handleZoomUpdate(details);
    }
  }

  void onScaleEnd(ScaleEndDetails details) {
    if (_isMouseSelectionInProgress) {
      _finishMouseSelection();
    } else if (_activeDragHandle != _DragHandleType.none && _isDraggingHandle) {
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

  Rect? _selectionRectForRange(BufferRangeLine range) {
    final _SelectionGeometry? geometry = _selectionGeometry(range);
    if (geometry == null) {
      return null;
    }
    final Offset globalTopLeft = renderTerminal.localToGlobal(
      geometry.localRect.topLeft,
    );
    final Offset globalBottomRight = renderTerminal.localToGlobal(
      geometry.localRect.bottomRight,
    );
    return Rect.fromPoints(globalTopLeft, globalBottomRight);
  }

  Rect? _currentSelectionGlobalRect() {
    final range = _selectedRange;
    if (range == null || range.isCollapsed) {
      return null;
    }
    return _selectionRectForRange(range);
  }
}

class _SelectionGeometry {
  const _SelectionGeometry({
    required this.localRect,
    required this.startAnchor,
    required this.endAnchor,
  });

  final Rect localRect;
  final Offset startAnchor;
  final Offset endAnchor;
}
