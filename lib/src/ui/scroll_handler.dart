import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:xterm/core.dart';

/// Handles scrolling gestures when the terminal application declares support
/// for mouse tracking (alt screen buffer or mouse mode with scroll reporting).
///
/// When the terminal is in alternate screen buffer, there is no scrollback, so
/// scroll gestures are converted to escape sequences (mouse wheel events or
/// arrow key simulation).
///
/// When the terminal is in main screen buffer but has enabled mouse scroll
/// reporting, scroll gestures are forwarded to the application as mouse events
/// and the inner scrollable is suppressed (via [NeverScrollableScrollPhysics]
/// in [TerminalView]).
///
/// When neither condition is met, normal scrollback scrolling is used.
class TerminalScrollGestureHandler extends StatefulWidget {
  const TerminalScrollGestureHandler({
    super.key,
    required this.terminal,
    required this.getCellOffset,
    required this.getLineHeight,
    this.simulateScroll = true,
    required this.child,
  });

  final Terminal terminal;

  /// Returns the cell offset for the pixel offset.
  final CellOffset Function(Offset) getCellOffset;

  /// Returns the pixel height of lines in the terminal.
  final double Function() getLineHeight;

  /// Whether to simulate scroll events in the terminal when the application
  /// doesn't declare it supports mouse wheel events. true by default as it
  /// is the default behavior of most terminals.
  final bool simulateScroll;

  final Widget child;

  @override
  State<TerminalScrollGestureHandler> createState() =>
      _TerminalScrollGestureHandlerState();
}

class _TerminalScrollGestureHandlerState
    extends State<TerminalScrollGestureHandler> {
  var isAltBuffer = false;
  var lastPointerPosition = Offset.zero;
  var _mouseMode = MouseMode.none;
  double _accumulatedScroll = 0.0;
  double? _lastTouchY;

  /// Whether scroll events should be intercepted and forwarded to the terminal
  /// instead of being handled by the inner scrollable.
  bool get _shouldForwardScroll {
    if (widget.terminal.isUsingAltBuffer) return true;
    final mode = widget.terminal.mouseMode;
    return mode != MouseMode.none && mode.reportScroll;
  }

  bool _isTouchPointer(PointerDeviceKind kind) {
    return kind == PointerDeviceKind.touch || kind == PointerDeviceKind.stylus;
  }

  @override
  void initState() {
    widget.terminal.addListener(_onTerminalUpdated);
    isAltBuffer = widget.terminal.isUsingAltBuffer;
    _mouseMode = widget.terminal.mouseMode;
    super.initState();
  }

  @override
  void dispose() {
    widget.terminal.removeListener(_onTerminalUpdated);
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant TerminalScrollGestureHandler oldWidget) {
    if (oldWidget.terminal != widget.terminal) {
      oldWidget.terminal.removeListener(_onTerminalUpdated);
      widget.terminal.addListener(_onTerminalUpdated);
      isAltBuffer = widget.terminal.isUsingAltBuffer;
      _mouseMode = widget.terminal.mouseMode;
    }
    super.didUpdateWidget(oldWidget);
  }

  void _onTerminalUpdated() {
    final newIsAltBuffer = widget.terminal.isUsingAltBuffer;
    final newMouseMode = widget.terminal.mouseMode;
    if (isAltBuffer != newIsAltBuffer || _mouseMode != newMouseMode) {
      isAltBuffer = newIsAltBuffer;
      _mouseMode = newMouseMode;
      _accumulatedScroll = 0.0;
      _lastTouchY = null;
      setState(() {});
    }
  }

  /// Process a raw scroll delta from [PointerScrollEvent], accumulating
  /// fractional scrolls and dispatching discrete scroll events per line.
  void _handleScrollDelta(double dy, {bool fromTouch = false}) {
    _accumulatedScroll += dy;
    final lineHeight = widget.getLineHeight();
    if (lineHeight <= 0) return;

    // Use a larger threshold for touch to prevent overly sensitive scrolling
    final threshold = fromTouch ? lineHeight * 3 : lineHeight;
    final lines = (_accumulatedScroll.abs() / threshold).floor();
    if (lines > 0) {
      final up = _accumulatedScroll < 0;
      for (var i = 0; i < lines; i++) {
        _sendScrollEvent(up, fromTouch: fromTouch);
      }
      _accumulatedScroll -= (up ? -lines : lines) * threshold;
    }
  }

  /// Send a single scroll event to the terminal. The event is first offered to
  /// terminal mouse reporting. If it is not handled and [simulateScroll] is
  /// enabled, this falls back to sending
  /// up/down arrow keys — but only when the application has NOT enabled mouse
  /// mode (to avoid sending unintended arrow keys to apps expecting mouse
  /// events).
  ///
  /// When [fromTouch] is true (touch drag on mobile), the arrow key fallback
  /// is disabled to avoid flooding the terminal with key events during
  /// continuous touch gestures.
  void _sendScrollEvent(bool up, {bool fromTouch = false}) {
    final position = widget.getCellOffset(lastPointerPosition);
    final handled = widget.terminal.mouseInput(
      up ? TerminalMouseButton.wheelUp : TerminalMouseButton.wheelDown,
      TerminalMouseButtonState.down,
      position,
    );

    if (!handled && !fromTouch && widget.simulateScroll) {
      widget.terminal.keyInput(
        up ? TerminalKey.arrowUp : TerminalKey.arrowDown,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_shouldForwardScroll) {
      return widget.child;
    }

    return Listener(
      onPointerSignal: (event) {
        if (event is PointerScrollEvent) {
          lastPointerPosition = event.localPosition;
          _handleScrollDelta(event.scrollDelta.dy);
        }
      },
      onPointerDown: (event) {
        lastPointerPosition = event.localPosition;
        if (_isTouchPointer(event.kind)) {
          _lastTouchY = event.position.dy;
        }
      },
      onPointerMove: (event) {
        if (_lastTouchY != null && _isTouchPointer(event.kind)) {
          final dy = _lastTouchY! - event.position.dy;
          lastPointerPosition = event.localPosition;
          _handleScrollDelta(dy, fromTouch: true);
          _lastTouchY = event.position.dy;
        }
      },
      onPointerUp: (event) {
        _lastTouchY = null;
      },
      onPointerCancel: (event) {
        _lastTouchY = null;
      },
      child: widget.child,
    );
  }
}
