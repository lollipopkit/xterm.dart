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

/// How much of the text a click takes, and how much a drag started by that
/// click adds at a time. Which one applies is decided by how many times the
/// pointer went down in the same place, as it is in a text field.
enum _SelectionGranularity { character, word, line }

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

  // Selection handles.
  _DragHandleType _activeDragHandle = _DragHandleType.none;
  CellOffset? _dragHandleFixedPoint; // The end a handle drag holds still.
  bool _isDragHandleReady = false; // A tap landed on a handle; a drag may come.

  static const double _handleTouchRadius = 32.0;
  static const double _selectionTolerance = 20.0;
  static const Duration _tapTolerance = Duration(milliseconds: 150);

  DateTime? _lastTapTime;
  Offset? _lastTapPosition;
  bool _isDraggingHandle = false;

  // Dragging a selection out with a mouse.
  bool _isMouseDeviceDown = false;
  bool _isMouseSelectionInProgress = false;
  CellOffset? _mouseSelectionBase;
  PointerDeviceKind? _mousePointerKind;
  bool _suppressNextTapUp = false;
  bool _mouseTapDownDispatched = false;
  Offset? _mouseSelectionLastPosition;

  // Held back so that a long press or a drag beginning at the same point is
  // seen first, and the terminal is not told about a click that turned out to
  // be the start of something else.
  Timer? _tapDownTimer;
  TapDownDetails? _pendingTapDownDetails;
  static const Duration _tapDownDelay = Duration(milliseconds: 50);

  /// How many times the pointer has gone down in the same place without the
  /// run being broken by [kDoubleTapTimeout] or by moving further than
  /// [kDoubleTapSlop]. One is a click, two is a word, three is a line.
  ///
  /// Counted here rather than taken from a [DoubleTapGestureRecognizer],
  /// which stops at two, or from [TapAndPanGestureRecognizer], which would
  /// mean taking the drag out of the arena that pinch-to-zoom shares. The
  /// rule for what breaks a run is the framework's own, from
  /// `_TapStatusTrackerMixin`.
  int _consecutiveTapCount = 0;
  Offset? _lastTapDownPosition;
  Timer? _tapCountResetTimer;

  /// The last pointer to go down, seen by [_onPointerDown] rather than by the
  /// arena, so that a drag which never produced a tap still knows where it
  /// started and what it started with.
  PointerDeviceKind? _lastPointerDownKind;
  Offset? _lastPointerDownPosition;

  /// What the drag now under way grows by. Set when it starts, from the tap
  /// count that started it, and read on every move: a drag begun by a double
  /// click keeps taking whole words however far it goes.
  _SelectionGranularity _granularity = _SelectionGranularity.character;

  /// Set when this tap made or grew a selection, so that its own tap-up does
  /// not turn round and clear it.
  bool _tapChangedSelection = false;

  /// The loupe shown while a finger is choosing where the selection ends.
  ///
  /// A finger covers the text it is pointing at, which is the whole reason a
  /// text field shows one; the terminal was asking people to place a boundary
  /// they could not see. The configuration is the platform's own, so this is
  /// a Cupertino loupe on iOS and a Material one on Android, and on a desktop
  /// [MagnifierConfiguration.magnifierBuilder] returns null and nothing is
  /// shown — which is right, since a mouse hides nothing.
  final MagnifierController _magnifierController = MagnifierController();
  final ValueNotifier<MagnifierInfo> _magnifierInfo =
      ValueNotifier<MagnifierInfo>(MagnifierInfo.empty);

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

    // The pointer going down is watched outside the arena, because half of
    // what this widget does keys off it and the tap recogniser cannot be
    // relied on to report it: see [_onPointerDown].
    return Listener(
      behavior: HitTestBehavior.deferToChild,
      onPointerDown: _onPointerDown,
      child: GestureDetector(
        behavior: HitTestBehavior.deferToChild,
        child: content,
        onTapUp: onTapUp,
        onTapDown: onTapDown,
        onSecondaryTapDown: onSecondaryTapDown,
        onSecondaryTapUp: onSecondaryTapUp,
        onTertiaryTapDown: widget.onTertiaryTapDown,
        onTertiaryTapUp: widget.onTertiaryTapUp,
        // No `onDoubleTapDown`. Registering a double tap takes the second tap
        // out of `onTapDown`, and then a third one looks like a second.
        onScaleEnd: onScaleEnd,
        onScaleStart: onScaleStart,
        onScaleUpdate: onScaleUpdate,
        onLongPressStart: _onLongPressStart,
        onLongPressMoveUpdate: _onLongPressMoveUpdate,
        onLongPressEnd: _onLongPressEnd,
      ),
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
    _tapCountResetTimer?.cancel();
    // The loupe is in an overlay, which outlives this widget and would keep
    // the last thing it magnified on screen.
    _hideMagnifier();
    _magnifierInfo.dispose();
    widget.terminalController.removeListener(_handleControllerSelectionChanged);
    _detachScrollController(_attachedScrollController);
    super.dispose();
  }

  bool get _shouldSendTapEvent =>
      !widget.readOnly &&
      widget.terminalController.shouldSendPointerInput(PointerInput.tap);

  /// Drops a tap-down that was being held back, so it never reaches the
  /// terminal.
  void _cancelPendingTapDown() {
    final hadPending = _pendingTapDownDetails != null || _tapDownTimer != null;
    _tapDownTimer?.cancel();
    _tapDownTimer = null;
    _pendingTapDownDetails = null;
    if (hadPending) {
      _mouseTapDownDispatched = false;
    }
  }

  /// Sends the tap-down that was being held back.
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

  /// The selection handle under [localPosition], or none.
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

  /// Whether [localPosition] is inside the selection or close enough to it
  /// to count as on it.
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

  /// Whether this is the same tap as the last one arriving twice.
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

  /// Every pointer going down, before the arena has decided anything.
  ///
  /// [GestureDetector.onTapDown] is not that. A tap recogniser reports one
  /// only when it wins the arena or when [kPressTimeout] passes, and a press
  /// that turns straight into a drag gives it neither: the drag takes the
  /// arena first. Anything hung off `onTapDown` therefore does not happen at
  /// all unless the pointer is held still for a moment first, which is how
  /// dragging a selection out came to need a pause before it would start,
  /// and how the second click of a double click went uncounted when the
  /// drag began on it.
  void _onPointerDown(PointerDownEvent event) {
    _lastPointerDownKind = event.kind;
    _lastPointerDownPosition = renderTerminal.globalToLocal(event.position);

    // Per gesture, and this is a new one. Set at the end of the last drag for
    // a tap-up that only arrives if the tap recogniser won.
    _suppressNextTapUp = false;

    _countTap(_lastPointerDownPosition!);
  }

  /// Counts this pointer-down into the run of taps at the same place, and
  /// returns how many that makes. A run is broken by moving too far or by
  /// waiting too long, and stops counting up at three, which is the most any
  /// of them means something.
  int _countTap(Offset position) {
    final last = _lastTapDownPosition;
    if (last == null || (position - last).distance > kDoubleTapSlop) {
      _consecutiveTapCount = 1;
    } else if (_consecutiveTapCount < 3) {
      _consecutiveTapCount++;
    }

    _lastTapDownPosition = position;

    // Restarted on every tap, so the timeout runs from the last one rather
    // than from the first: a slow but steady run of clicks is still a run.
    _tapCountResetTimer?.cancel();
    _tapCountResetTimer = Timer(kDoubleTapTimeout, _resetTapCount);

    return _consecutiveTapCount;
  }

  void _resetTapCount() {
    _tapCountResetTimer?.cancel();
    _tapCountResetTimer = null;
    _consecutiveTapCount = 0;
    _lastTapDownPosition = null;
  }

  static _SelectionGranularity _granularityForTapCount(int count) {
    switch (count) {
      case 1:
        return _SelectionGranularity.character;
      case 2:
        return _SelectionGranularity.word;
      default:
        return _SelectionGranularity.line;
    }
  }

  bool get _isShiftPressed {
    final pressed = HardwareKeyboard.instance.logicalKeysPressed;
    return pressed.contains(LogicalKeyboardKey.shiftLeft) ||
        pressed.contains(LogicalKeyboardKey.shiftRight) ||
        pressed.contains(LogicalKeyboardKey.shift);
  }

  /// The selection from [base] to [current], grown at both ends to whole
  /// words or whole lines when that is what the drag is taking.
  ///
  /// Both ends grow, not just the moving one: a drag that started inside a
  /// word and ran left has that first word in it, and losing it as soon as
  /// the pointer passes the word's start is the thing this avoids.
  BufferRangeLine _rangeFor(CellOffset base, CellOffset current) {
    final plain = current.isBefore(base)
        ? BufferRangeLine(current, base)
        : BufferRangeLine(base, current);

    switch (_granularity) {
      case _SelectionGranularity.character:
        return plain;
      case _SelectionGranularity.word:
        final begin = renderTerminal.wordBoundaryAt(plain.begin);
        final end = renderTerminal.wordBoundaryAt(plain.end);
        if (begin == null && end == null) return plain;
        return (begin ?? plain).merge(end ?? plain);
      case _SelectionGranularity.line:
        return renderTerminal
            .lineBoundaryAt(plain.begin)
            .merge(renderTerminal.lineBoundaryAt(plain.end));
    }
  }

  /// Grows the selection to [target], keeping whichever of its ends is
  /// further away. This is shift-click: the end that moves is the near one,
  /// so the text between the anchor and the pointer is what ends up selected
  /// however the two are ordered.
  void _extendSelectionTo(CellOffset target) {
    final range = _selectedRange?.normalized;
    if (range == null) {
      return;
    }

    final anchor = target.isBefore(range.begin) ? range.end : range.begin;
    _mouseSelectionBase = anchor;
    _isMouseSelectionInProgress = true;
    _applySelection(_rangeFor(anchor, target));
  }

  /// Puts the loupe over [localPosition], or moves it there if it is already
  /// up. Does nothing on a platform that has no loupe.
  void _showMagnifier(Offset localPosition) {
    if (!mounted) {
      return;
    }

    final cellSize = renderTerminal.cellSize;
    final cell = renderTerminal.getCellOffset(localPosition);
    final cellTopLeft = renderTerminal.localToGlobal(
      renderTerminal.getOffset(cell),
    );
    final viewTopLeft = renderTerminal.localToGlobal(Offset.zero);
    final viewSize = renderTerminal.size;

    _magnifierInfo.value = MagnifierInfo(
      globalGesturePosition: renderTerminal.localToGlobal(localPosition),
      // The cell being pointed at stands in for the caret: it is the thing
      // the loupe is meant to centre on and what the finger is covering.
      caretRect: cellTopLeft & cellSize,
      fieldBounds: viewTopLeft & viewSize,
      currentLineBoundaries: Rect.fromLTWH(
        viewTopLeft.dx,
        cellTopLeft.dy,
        viewSize.width,
        cellSize.height,
      ),
    );

    if (_magnifierController.shown) {
      return;
    }

    final builder =
        TextMagnifier.adaptiveMagnifierConfiguration.magnifierBuilder;

    // Asked before the overlay is put up rather than inside it: a platform
    // with no loupe answers null, and an overlay holding nothing would still
    // be an overlay, taking the pointer and outliving the gesture.
    if (builder(context, _magnifierController, _magnifierInfo) == null) {
      return;
    }

    _magnifierController.show(
      context: context,
      builder: (BuildContext context) {
        return builder(context, _magnifierController, _magnifierInfo)!;
      },
    );
  }

  void _hideMagnifier() {
    if (_magnifierController.shown) {
      _magnifierController.hide();
    }
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

    _applySelection(_rangeFor(base, current));

    if (current != base) {
      terminalView.updateAutoScroll(
        localPosition,
        onTick: () => _handleMouseSelectionUpdate(localPosition),
      );
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
    terminalView.stopAutoScroll();
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

    // A tap-down still being held back has run out of reasons to wait.
    if (_pendingTapDownDetails != null) {
      _executePendingTapDown();
    }
    _cancelPendingTapDown();

    // The same tap arriving twice.
    if (_isDuplicateTap(details.localPosition)) {
      return;
    }

    // A handle was taken hold of but never dragged.
    if (_isDragHandleReady && !_isDraggingHandle) {
      _resetDragHandleState();
    }

    widget.onTapUp?.call(details);

    // The tap that made this selection is still going up. Clearing here would
    // undo what the same gesture just did, which is what a registered double
    // tap used to hide by swallowing the second tap.
    if (_tapChangedSelection) {
      return;
    }

    if (_selectedRange != null) {
      final dragHandle = _detectDragHandle(details.localPosition);
      if (dragHandle != _DragHandleType.none) {
        // On a handle. Leave the selection alone and wait for the drag.
        return;
      }

      // A click anywhere else drops the selection, inside it or out.
      _clearSelection();
    }
  }

  void onTapDown(TapDownDetails details) {
    _suppressNextTapUp = false;
    _tapChangedSelection = false;

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

    // Already counted, by [_onPointerDown], for this same press.
    final tapCount = _consecutiveTapCount;
    final cellOffset = renderTerminal.getCellOffset(details.localPosition);

    final hasSelection =
        _selectedRange != null && !_selectedRange!.isCollapsed;

    // Shift held asks for a bigger selection rather than a new one, and says
    // so plainly enough to come before the handles: extending backwards means
    // clicking to the left of the selection, which is where its start handle
    // is, and no one holds shift to take hold of one.
    //
    // The granularity stays whatever the run that made the selection set, so
    // shift-clicking after a double click goes on taking whole words. That is
    // what a text field on this platform does, and an editor.
    if (_isShiftPressed && hasSelection) {
      _resetTapCount();
      _cancelPendingTapDown();
      _tapChangedSelection = true;
      _extendSelectionTo(cellOffset);
      return;
    }

    // A handle takes the tap ahead of anything else — but only a tap that
    // begins a run. The second and third clicks of one land in the middle of
    // the selection the first made, which is where that selection's handles
    // now are, and reading those as a grab is what stopped a third click ever
    // arriving.
    if (tapCount <= 1 && hasSelection) {
      final dragHandle = _detectDragHandle(details.localPosition);
      if (dragHandle != _DragHandleType.none) {
        _resetTapCount();
        _prepareDragHandle(dragHandle);
        return;
      }
    }

    _granularity = _granularityForTapCount(tapCount);

    if (_granularity != _SelectionGranularity.character) {
      _tapChangedSelection = true;
      _cancelPendingTapDown();
      _resetDragHandleState();
      _selectAtGranularity(cellOffset, details.kind);
      return;
    }

    // Held back so that a long press or a drag beginning here is seen first.
    _cancelPendingTapDown();
    _pendingTapDownDetails = details;

    _tapDownTimer = Timer(_tapDownDelay, () {
      if (!_isDragHandleReady) {
        _executePendingTapDown();
      }
      _tapDownTimer = null;
    });
  }

  /// Selects the word or the line under [cellOffset], whichever the run of
  /// taps has reached.
  void _selectAtGranularity(CellOffset cellOffset, PointerDeviceKind? kind) {
    final BufferRangeLine? range;

    switch (_granularity) {
      case _SelectionGranularity.character:
        return;
      case _SelectionGranularity.word:
        // A word, whatever the pointer was. A second click is what asks for
        // the word under it, in a text field and in every other terminal; the
        // mouse used to get a single cell here, which is what one click
        // already gives.
        range = renderTerminal.selectWord(cellOffset);
      case _SelectionGranularity.line:
        range = renderTerminal.selectLine(cellOffset);
    }

    if (range != null) {
      _applySelection(range);
    }

    if (widget.showToolbar) {
      final Rect? selectionRect = _currentSelectionGlobalRect();
      if (selectionRect != null) {
        widget.terminalView.showSelectionToolbar(selectionRect);
      }
    }

    // Only where there is something to feel it: a mouse double click on a
    // desktop would buzz the phone-shaped part of the API for nothing.
    if (kind == PointerDeviceKind.touch) {
      HapticFeedback.lightImpact();
    }
  }

  /// Arms a handle drag: the tap landed on one, and a drag may follow.
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

    // Confirms the handle was found, before anything has moved.
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
    terminalView.stopAutoScroll();
    _hideMagnifier();
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

  /// Forgets any handle drag, armed or under way.
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

  /// Anchors a mouse selection that [onTapDown] never got to anchor.
  ///
  /// The anchor is where the button went down, not where the drag was
  /// recognised: by then the pointer has already moved past the slop, and
  /// starting there would drop the first character or two of every selection
  /// dragged out in one motion.
  void _anchorMouseSelectionIfNeeded() {
    if (_isMouseDeviceDown || _isDraggingHandle || _isDragHandleReady) {
      return;
    }

    final position = _lastPointerDownPosition;
    if (position == null || !_isPointerKindMouse(_lastPointerDownKind)) {
      return;
    }

    _isMouseDeviceDown = true;
    _mousePointerKind = _lastPointerDownKind;
    _mouseSelectionBase = renderTerminal.getCellOffset(position);
    _isMouseSelectionInProgress = false;
    _mouseSelectionLastPosition = position;
    _mouseTapDownDispatched = false;

    // From the run this press belongs to, which [_onPointerDown] counted even
    // though no tap came of it. Dragging off the second click of a double
    // click goes on taking whole words.
    _granularity = _granularityForTapCount(_consecutiveTapCount);
  }

  void onScaleStart(ScaleStartDetails details) {
    // Whatever this turns out to be, it is not the click being held back.
    _cancelPendingTapDown();

    _anchorMouseSelectionIfNeeded();

    // Already armed by the tap that landed on the handle.
    if (_isDragHandleReady && _activeDragHandle != _DragHandleType.none) {
      // Armed, and now moving.
      _isDraggingHandle = true;
      _longPressInitialCellOffset = null;
      if (widget.showToolbar) {
        widget.terminalView.hideSelectionToolbar();
      }

      // The drag is under way.
      HapticFeedback.selectionClick();
      return;
    }

    // A drag that began on a handle without a tap-down arming it first.
    // Reachable, but not by any ordinary sequence of events.
    _activeDragHandle = _detectDragHandle(details.localFocalPoint);

    if (_activeDragHandle != _DragHandleType.none && _selectedRange != null) {
      // Take hold of the handle here instead.
      _isDraggingHandle = true;
      final BufferRangeLine range = _selectedRange!.normalized;
      _dragHandleFixedPoint = _activeDragHandle == _DragHandleType.start
          ? range.end
          : range.begin;
      _longPressInitialCellOffset = null;
      if (widget.showToolbar) {
        widget.terminalView.hideSelectionToolbar();
      }

      // The drag is under way.
      HapticFeedback.selectionClick();
    } else {
      // Not a handle, so a pinch or a click on the background.
      _resetDragHandleState();

      // Away from the selection, which drops it.
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
      // Moving a handle.
      if (!_isDraggingHandle) {
        // Armed, and now moving.
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
      // Two fingers, which is the font size.
      _handleZoomUpdate(details);
    }
  }

  void onScaleEnd(ScaleEndDetails details) {
    _hideMagnifier();
    if (_isMouseSelectionInProgress) {
      _finishMouseSelection();
    } else if (_activeDragHandle != _DragHandleType.none && _isDraggingHandle) {
      // A handle was let go of.
      HapticFeedback.selectionClick();
      if (widget.showToolbar) {
        final Rect? rect = _currentSelectionGlobalRect();
        if (rect != null) {
          widget.terminalView.showSelectionToolbar(rect);
        }
      }
    } else if (!_isDraggingHandle && !_isDragHandleReady) {
      // A pinch ended; the size it reached is the one to grow from next.
      _originTextSize = terminalView.textSizeNoti.value;
    }

    _resetDragHandleState();
  }

  void _handleDragUpdate(Offset localPosition) {
    if (_dragHandleFixedPoint == null) return;

    // Ahead of the did-anything-change test below. The loupe follows the
    // finger rather than the selection, and stopping it every time a move
    // stayed inside one cell is most of them.
    _showMagnifier(localPosition);

    final currentCellOffset = renderTerminal.getCellOffset(localPosition);

    // Still on the cell it was already on.
    final currentHandleEnd = _activeDragHandle == _DragHandleType.start
        ? _selectedRange?.begin
        : _selectedRange?.end;
    if (currentCellOffset == currentHandleEnd) {
      return;
    }

    // Which handle is being held makes no difference to the range: it runs
    // from the fixed end to the pointer either way.
    final isBefore = currentCellOffset.isBefore(_dragHandleFixedPoint!);
    final newStart = isBefore ? currentCellOffset : _dragHandleFixedPoint!;
    final newEnd = isBefore ? _dragHandleFixedPoint! : currentCellOffset;

    final draggingStart = _activeDragHandle == _DragHandleType.start;
    if (draggingStart && currentCellOffset.isAfter(_dragHandleFixedPoint!)) {
      _activeDragHandle = _DragHandleType.end;
      _dragHandleFixedPoint = newStart;
    } else if (!draggingStart && isBefore) {
      _activeDragHandle = _DragHandleType.start;
      _dragHandleFixedPoint = newEnd;
    }

    _applySelection(BufferRangeLine(newStart, newEnd));

    terminalView.updateAutoScroll(
      localPosition,
      onTick: () => _handleDragUpdate(localPosition),
    );
  }

  void _handleZoomUpdate(ScaleUpdateDetails details) {
    // Two fingers moving apart or together, and nothing else.
    if (details.pointerCount != 2 || details.scale == 1.0) {
      return;
    }

    final scale = math.pow(details.scale, 0.3);
    final fontSize = _originTextSize * scale;

    // Outside this the terminal stops being readable.
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
    // This is a long press, not the click being held back.
    _cancelPendingTapDown();

    // A handle is armed, and a long press on one means nothing.
    if (_isDragHandleReady) {
      return;
    }

    // A long press only starts a selection. Adjusting one that already
    // exists is what its handles are for.
    if (_selectedRange != null && !_selectedRange!.isCollapsed) {
      // Outside it, so start again from here.
      if (!_isNearSelection(details.localPosition)) {
        _clearSelection();
      } else {
        // On it, which is not a request for anything.
        return;
      }
    }

    // Nothing is selected now, whether or not something was.
    _clearSelection();

    final longPressCellOffset = renderTerminal.getCellOffset(
      details.localPosition,
    );

    // Where a drag that grows out of this press starts from, and how much it
    // takes at a time. Set on both paths below: it used to be set only when
    // there was no word to select, so a long press that found one - which is
    // nearly all of them - could not be dragged at all. Dragging on from the
    // press is how a selection is made on a touch screen without going for a
    // handle, and it did nothing.
    _longPressInitialCellOffset = longPressCellOffset;
    _granularity = _SelectionGranularity.word;

    final wordRange = renderTerminal.selectWord(longPressCellOffset);
    if (wordRange != null) {
      _applySelection(wordRange);

      // With the toolbar already up: there is something to act on.
      if (widget.showToolbar && !wordRange.isCollapsed) {
        final Rect? selectionRect = _currentSelectionGlobalRect();
        if (selectionRect != null) {
          widget.terminalView.showSelectionToolbar(selectionRect);
        }
      }
    } else {
      // No word here — a blank, or the edge. Take the one cell instead, and
      // let a drag from it go by the cell rather than by the word.
      _granularity = _SelectionGranularity.character;
      _applySelection(BufferRangeLine.collapsed(longPressCellOffset));
    }

    // The handles this selection just put on screen are untouched so far.
    _resetDragHandleState();

    // The press registered.
    HapticFeedback.lightImpact();
  }

  void _onLongPressMoveUpdate(LongPressMoveUpdateDetails details) {
    // A handle is being moved, and it has its own path for this.
    if (_isDragHandleReady || _isDraggingHandle) {
      return;
    }

    // Only a long press that started a selection of its own extends it.
    if (_longPressInitialCellOffset == null) {
      return;
    }

    // Before the did-anything-change test, as in [_handleDragUpdate].
    _showMagnifier(details.localPosition);

    final currentCellOffset = renderTerminal.getCellOffset(
      details.localPosition,
    );

    // Still on the cell it was already on.
    if (currentCellOffset == _longPressInitialCellOffset) {
      return;
    }

    // Whole words, since the press took one. The word it started on stays in
    // however far the finger travels, which is what stops the selection
    // collapsing the moment it moves back over its own start.
    _applySelection(
      _rangeFor(_longPressInitialCellOffset!, currentCellOffset),
    );

    terminalView.updateAutoScroll(
      details.localPosition,
      onTick: () => _onLongPressMoveUpdate(details),
    );
  }

  void _onLongPressEnd(LongPressEndDetails details) {
    terminalView.stopAutoScroll();
    _hideMagnifier();

    // Only a long press that started a selection has anything to finish.
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
