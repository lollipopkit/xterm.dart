import 'dart:async';
import 'dart:math' as math;

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

  @override
  State<TerminalGestureHandler> createState() => _TerminalGestureHandlerState();
}

class _TerminalGestureHandlerState extends State<TerminalGestureHandler> {
  final ContextMenuController _menuController = ContextMenuController();

  TerminalViewState get terminalView => widget.terminalView;

  RenderTerminal get renderTerminal => terminalView.renderTerminal;

  BufferRangeLine? _selectedRange;
  bool? _isMovingStartCursor;
  Timer? _longPressTimer;

  late double _originTextSize = terminalView.widget.textStyle.fontSize;

  @override
  Widget build(BuildContext context) {
    final child = GestureDetector(
      child: widget.child,
      onTapUp: onTapUp,
      onTapDown: onTapDown,
      onSecondaryTapDown: onSecondaryTapDown,
      onSecondaryTapUp: onSecondaryTapUp,
      onTertiaryTapDown: onSecondaryTapDown,
      onTertiaryTapUp: onSecondaryTapUp,
      onDoubleTapDown: onDoubleTapDown,
      onScaleEnd: onScaleEnd,
      onScaleStart: onScaleStart,
      onScaleUpdate: onScaleUpdate,
    );
    return child;
  }

  @override
  void dispose() {
    super.dispose();
    _hideCopyToolbar();
  }

  bool get _shouldSendTapEvent =>
      !widget.readOnly &&
      widget.terminalController.shouldSendPointerInput(PointerInput.tap);

  void _tapDown(
    GestureTapDownCallback? callback,
    TapDownDetails details,
    TerminalMouseButton button, {
    bool forceCallback = false,
  }) {
    // Check if the terminal should and can handle the tap down event.
    var handled = false;
    if (_shouldSendTapEvent) {
      handled = renderTerminal.mouseEvent(
        button,
        TerminalMouseButtonState.down,
        details.localPosition,
      );
    }
    // If the event was not handled by the terminal, use the supplied callback.
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
    // Check if the terminal should and can handle the tap up event.
    var handled = false;
    if (_shouldSendTapEvent) {
      handled = renderTerminal.mouseEvent(
        button,
        TerminalMouseButtonState.up,
        details.localPosition,
      );
    }
    // If the event was not handled by the terminal, use the supplied callback.
    if (!handled || forceCallback) {
      callback?.call(details);
    }
  }

  void onTapUp(TapUpDetails details) {
    widget.onTapUp?.call(details);

    final cellOffset = renderTerminal.getCellOffset(details.localPosition);
    if (_selectedRange != null) {
      if (_selectedRange!.contains(cellOffset) && !_menuController.isShown) {
        _showCopyToolbar(details.globalPosition);
      } else {
        _hideCopyToolbar();
      }
    } else {
      _hideCopyToolbar();
    }
  }

  void onTapDown(TapDownDetails details) {
    _longPressTimer = Timer(const Duration(milliseconds: 77), () {
      final cellOffset = renderTerminal.getCellOffset(details.localPosition);
      final selected = _selectedRange;
      if (selected != null) {
        if (!selected.contains(cellOffset)) {
          _selectedRange = null;
          renderTerminal.clearSelection();
        }
      } else {
        renderTerminal.clearSelection();
      }
    });

    // onTapDown is special, as it will always call the supplied callback.
    // The TerminalView depends on it to bring the terminal into focus.
    _tapDown(
      widget.onTapDown,
      details,
      TerminalMouseButton.left,
      forceCallback: true,
    );
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
    renderTerminal.selectWord(
      renderTerminal.getCellOffset(details.localPosition),
    );
    _showCopyToolbar(details.localPosition);
  }

  void _showCopyToolbar(Offset position) {
    final selected = renderTerminal.selectedText;
    if (selected == null) return;

    if (selected.trim().isNotEmpty) {
      _menuController.show(
        context: context,
        contextMenuBuilder: (context) {
          return TextSelectionToolbar(
            anchorAbove: position,
            anchorBelow: position,
            toolbarBuilder: (context, child) {
              return Material(
                elevation: 1.0,
                borderRadius: BorderRadius.circular(13),
                child: child,
              );
            },
            children: [
              IconButton(
                icon: const Icon(Icons.copy),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: selected));
                  _hideCopyToolbar();
                },
              ),
            ],
          );
        },
      );
    }
  }

  void _hideCopyToolbar() {
    if (_menuController.isShown) {
      _menuController.remove();
      return;
    }
  }

  BufferRangeLine arroudCell(CellOffset cellOffset) {
    return BufferRangeLine(
      cellOffset.moveRelative(const CellOffset(-3, -1)),
      cellOffset.moveRelative(
        const CellOffset(3, 1),
        maxX: terminalView.widget.terminal.viewWidth,
        maxY: terminalView.widget.terminal.viewHeight,
      ),
    );
  }

  void onScaleStart(ScaleStartDetails details) {
    _longPressTimer?.cancel();
    _longPressTimer = null;

    final cellOffset = renderTerminal.getCellOffset(details.localFocalPoint);
    if (_selectedRange == null) {
      _selectedRange = BufferRangeLine.collapsed(cellOffset);
      _isMovingStartCursor = false;
      return;
    }

    final startRange = arroudCell(_selectedRange!.begin);
    if (startRange.contains(cellOffset)) {
      _isMovingStartCursor = true;
      return;
    }
    final endRange = arroudCell(_selectedRange!.end);
    if (endRange.contains(cellOffset)) {
      _isMovingStartCursor = false;
      return;
    }
  }

  void onScaleEnd(ScaleEndDetails details) {
    if (widget.showToolbar) {
      _showCopyToolbar(renderTerminal.getOffset(_selectedRange!.end));
    }
    _originTextSize = terminalView.textSizeNoti.value;
    _isMovingStartCursor = null;
  }

  void onScaleUpdate(ScaleUpdateDetails details) {
    if (details.pointerCount == 1) {
      final cf = renderTerminal.getCellOffset(details.localFocalPoint);
      if (_isMovingStartCursor == true) {
        _selectedRange = BufferRangeLine(
          cf,
          _selectedRange!.end,
        );
      } else if (_isMovingStartCursor == false) {
        _selectedRange = BufferRangeLine(
          _selectedRange!.begin,
          cf,
        );
      }

      renderTerminal.selectCharacters(
        _selectedRange!.begin,
        _selectedRange!.end,
      );
      terminalView.autoScrollDown(details);
      return;
    }
    if (details.pointerCount != 2 || details.scale == 1) {
      return;
    }
    final scale = math.pow(details.scale, 0.3);
    final fontSize = _originTextSize * scale;
    if (fontSize < 7 || fontSize > 17) {
      return;
    }
    terminalView.textSizeNoti.value = fontSize;
  }
}
