import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:xterm/src/ui/shortcut/shortcuts.dart';

class CustomTextEdit extends StatefulWidget {
  final Widget child;
  final void Function(String) onInsert;
  final void Function() onDelete;
  final void Function(String?) onComposing;
  final void Function(TextInputAction) onAction;
  final KeyEventResult Function(FocusNode, KeyEvent) onKeyEvent;
  final FocusNode focusNode;
  final TextEditingController? controller;
  final void Function(TextSelection selection, SelectionChangedCause? cause)? onSelectionChanged;
  final void Function(TextRange composing)? onComposingChanged;
  final bool autofocus;
  final bool readOnly;
  final TextInputType inputType;
  final TextInputAction inputAction;
  final Brightness keyboardAppearance;
  final bool deleteDetection;
  final bool enableSuggestions;

  CustomTextEdit({
    super.key,
    required this.child,
    required this.onInsert,
    required this.onDelete,
    required this.onComposing,
    required this.onAction,
    required this.onKeyEvent,
    required this.focusNode,
    this.controller,
    this.onSelectionChanged,
    this.onComposingChanged,
    this.autofocus = false,
    this.readOnly = false,
    this.inputType = TextInputType.text,
    this.inputAction = TextInputAction.done,
    this.keyboardAppearance = Brightness.light,
    this.deleteDetection = false,
    this.enableSuggestions = true,
  });

  @override
  CustomTextEditState createState() => CustomTextEditState();
}

class CustomTextEditState extends State<CustomTextEdit>
    with TextInputClient, TextSelectionDelegate {
  TextInputConnection? _connection;
  final ContextMenuController _menuController = ContextMenuController();
  Rect _caretRect = Rect.zero;
  TextEditingController? _controller;
  VoidCallback? _controllerListener;

  @override
  void initState() {
    super.initState();
    widget.focusNode.addListener(_onFocusChange);
    _initController();
    _currentEditingState = _getInitialEditingValue();
    if (widget.focusNode.hasFocus) {
      _openOrCloseInputConnectionIfNeeded();
    }
  }

  void _initController() {
    _controller = widget.controller;
    if (_controller != null) {
      _controllerListener = () {
        if (_currentEditingState != _controller!.value) {
          final oldValue = _currentEditingState;
          setState(() {
            _currentEditingState = _controller!.value;
          });
          // selection/composing 变更回调
          if (widget.onSelectionChanged != null && oldValue.selection != _currentEditingState.selection) {
            widget.onSelectionChanged!(_currentEditingState.selection, null);
          }
          if (widget.onComposingChanged != null && oldValue.composing != _currentEditingState.composing) {
            widget.onComposingChanged!(_currentEditingState.composing);
          }
        }
      };
      _controller!.addListener(_controllerListener!);
    }
  }

  void _disposeController() {
    if (_controller != null && _controllerListener != null) {
      _controller!.removeListener(_controllerListener!);
    }
    _controller = null;
    _controllerListener = null;
  }

  @override
  void didUpdateWidget(CustomTextEdit oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.controller != oldWidget.controller) {
      _disposeController();
      _initController();
      if (_controller != null) {
        setState(() {
          _currentEditingState = _controller!.value;
        });
      }
    }

    if (widget.focusNode != oldWidget.focusNode) {
      oldWidget.focusNode.removeListener(_onFocusChange);
      widget.focusNode.addListener(_onFocusChange);
      // If focus changed and the new node has focus, ensure connection is open.
      if (widget.focusNode.hasFocus) {
        _openOrCloseInputConnectionIfNeeded();
      } else {
        // If new node does not have focus, ensure connection is closed.
        _closeInputConnectionIfNeeded();
      }
    }

    // If relevant properties change, and we have an active connection,
    // we might need to re-create the connection with the new configuration.
    if (widget.readOnly != oldWidget.readOnly ||
        widget.inputType != oldWidget.inputType ||
        widget.inputAction != oldWidget.inputAction ||
        widget.keyboardAppearance != oldWidget.keyboardAppearance ||
        widget.enableSuggestions != oldWidget.enableSuggestions) {
      if (hasInputConnection) {
        _closeInputConnectionIfNeeded();
        _openInputConnection(); // This will use the new widget properties
      }
    } else if (!_shouldCreateInputConnection) {
      // If we shouldn't have a connection (e.g., became readOnly), close it.
      _closeInputConnectionIfNeeded();
    } else {
      // If we should have a connection, and previously were readOnly but now not,
      // and have focus, open it.
      if (oldWidget.readOnly && !widget.readOnly && widget.focusNode.hasFocus) {
        _openInputConnection();
      }
    }
  }

  @override
  void dispose() {
    widget.focusNode.removeListener(_onFocusChange);
    _disposeController();
    _closeInputConnectionIfNeeded();
    _menuController.remove();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Shortcuts(
      shortcuts: defaultTerminalShortcuts,
      child: Actions(
        actions: <Type, Action<Intent>>{
          CopySelectionTextIntent: CallbackAction<CopySelectionTextIntent>(
            onInvoke: (intent) {
              copySelection(SelectionChangedCause.keyboard);
              return null;
            },
          ),
          PasteTextIntent: CallbackAction<PasteTextIntent>(
            onInvoke: (intent) => pasteText(intent.cause),
          ),
          SelectAllTextIntent: CallbackAction<SelectAllTextIntent>(
            onInvoke: (intent) => selectAll(intent.cause),
          ),
        },
        child: Focus(
          focusNode: widget.focusNode,
          autofocus: widget.autofocus,
          onKeyEvent: _onKeyEvent,
          child: widget.child,
        ),
      ),
    );
  }

  bool get hasInputConnection => _connection != null && _connection!.attached;

  void requestKeyboard() {
    if (widget.focusNode.hasFocus) {
      _openInputConnection();
    } else {
      widget.focusNode.requestFocus();
    }
  }

  void closeKeyboard() {
    _closeInputConnectionIfNeeded();
  }

  void toggleKeyboard() {
    if (hasInputConnection) {
      closeKeyboard();
    } else {
      requestKeyboard();
    }
  }

  void _showCaretOnScreen() {
    if (_caretRect == Rect.zero) return;
    final renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox == null || !renderBox.hasSize) return;
    final scrollableState = Scrollable.maybeOf(context);
    if (scrollableState == null) return;
    scrollableState.position.ensureVisible(
      renderBox,
      alignment: 0.5,
      duration: const Duration(milliseconds: 150),
      curve: Curves.ease,
      alignmentPolicy: ScrollPositionAlignmentPolicy.explicit,
    );
  }

  @override
  void bringIntoView(TextPosition position) {
    _showCaretOnScreen();
  }

  void setEditingState(TextEditingValue value) {
    if (_currentEditingState == value) {
      return;
    }
    final oldValue = _currentEditingState;
    _currentEditingState = value;
    if (widget.controller != null && widget.controller!.value != value) {
      widget.controller!.value = value;
    }
    // selection/composing 变更回调
    if (widget.onSelectionChanged != null && oldValue.selection != value.selection) {
      widget.onSelectionChanged!(value.selection, null);
    }
    if (widget.onComposingChanged != null && oldValue.composing != value.composing) {
      widget.onComposingChanged!(value.composing);
    }
    _connection?.setEditingState(value);
    _showCaretOnScreen();
    setState(() {}); // UI 响应
  }

  void setEditableRect(Rect rect, Rect caretRect) {
    _caretRect = caretRect;

    if (!hasInputConnection) {
      return;
    }

    // The transform should be based on the editable area's position relative to the screen.
    // If 'rect' is already in global coordinates, translation might be (0,0,0).
    // If 'rect' is local to some parent, its top-left needs to be translated.
    // For simplicity, assuming 'rect' is the global bounds for now.
    // EditableText uses renderEditable.getTransformTo(null)
    _connection?.setEditableSizeAndTransform(
      rect.size,
      Matrix4.translationValues(rect.left, rect.top, 0),
    );
    _connection?.setCaretRect(caretRect);
  }

  void _onFocusChange() {
    _openOrCloseInputConnectionIfNeeded();
    if (!widget.focusNode.hasFocus && _menuController.isShown) {
      _menuController.remove();
    }
  }

  KeyEventResult _onKeyEvent(FocusNode focusNode, KeyEvent event) {
    // Only handle KeyDownEvent for custom logic if not composing.
    // Other events (KeyUp, KeyRepeat) might be handled by the system or other listeners.
    if (event is KeyDownEvent && _currentEditingState.composing.isCollapsed) {
      return widget.onKeyEvent(focusNode, event);
    }
    // Let other handlers process the event if composing or not a KeyDownEvent.
    return KeyEventResult.skipRemainingHandlers;
  }

  void _openOrCloseInputConnectionIfNeeded() {
    if (!mounted) return;
    if (widget.focusNode.hasFocus && _shouldCreateInputConnection) {
      _openInputConnection();
    } else {
      _closeInputConnectionIfNeeded();
    }
  }

  bool get _shouldCreateInputConnection => !widget.readOnly && (kIsWeb || widget.focusNode.hasFocus);

  void _openInputConnection() {
    if (!_shouldCreateInputConnection || !mounted) {
      return;
    }

    if (!widget.focusNode.hasFocus) {
      return;
    }
    if (hasInputConnection) {
      _connection!.show();
      _connection!.setEditingState(_currentEditingState);
      return;
    }
    final config = TextInputConfiguration(
      inputType: widget.inputType,
      inputAction: widget.inputAction,
      keyboardAppearance: widget.keyboardAppearance,
      autocorrect: false,
      enableSuggestions: widget.enableSuggestions,
      enableIMEPersonalizedLearning: false,
      textCapitalization: TextCapitalization.none,
      readOnly: widget.readOnly,
    );
    _connection = TextInput.attach(this, config);
    if (!mounted) {
      _connection?.close();
      _connection = null;
      return;
    }
    _connection!.show();
    _connection!.setEditingState(_currentEditingState);
  }

  void _closeInputConnectionIfNeeded() {
    if (hasInputConnection) {
      _connection!.close();
      _connection = null;
    }
  }

  TextEditingValue _getInitialEditingValue() {
    if (widget.controller != null) {
      return widget.controller!.value;
    }
    return _initEditingState;
  }

  TextEditingValue get _initEditingState => widget.deleteDetection
      ? const TextEditingValue(
          text: '  ', // Two spaces for backspace detection
          selection: TextSelection.collapsed(offset: 2),
        )
      : TextEditingValue.empty;

  // Ensure _currentEditingState is initialized before _openInputConnection might use it.
  late var _currentEditingState = TextEditingValue.empty;

  @override
  TextEditingValue? get currentTextEditingValue {
    return _currentEditingState;
  }

  @override
  AutofillScope? get currentAutofillScope {
    return null; // Autofill not typically used in terminals
  }

  @override
  void updateEditingValue(TextEditingValue value) {
    if (_currentEditingState == value) {
      return;
    }
    final TextEditingValue oldValue = _currentEditingState;
    _currentEditingState = value;
    if (widget.controller != null && widget.controller!.value != value) {
      widget.controller!.value = value;
    }
    // selection/composing
    if (widget.onSelectionChanged != null && oldValue.selection != value.selection) {
      widget.onSelectionChanged!(value.selection, null);
    }
    if (widget.onComposingChanged != null && oldValue.composing != value.composing) {
      widget.onComposingChanged!(value.composing);
    }

    if (!_currentEditingState.composing.isCollapsed) {
      final String composingText = _currentEditingState.composing.textInside(
        _currentEditingState.text,
      );
      widget.onComposing(composingText);
      return;
    }

    // If we were composing and now we are not, notify with null.
    if (!oldValue.composing.isCollapsed &&
        _currentEditingState.composing.isCollapsed) {
      widget.onComposing(null);
    }

    final String previousText = oldValue.text;
    final String currentText = _currentEditingState.text;
    final int initTextLength = _initEditingState.text.length;

    bool textChanged = false;
    if (widget.deleteDetection) {
      // Specific logic for delete detection using initial placeholder characters
      if (currentText.length < previousText.length &&
          previousText ==
              _initEditingState
                  .text && // Deletion happened from the initial state
          currentText.startsWith(
            _initEditingState.text.substring(0, initTextLength - 1),
          )) {
        // Check if one char was removed
        widget.onDelete();
        textChanged = true;
      } else if (currentText.length > initTextLength &&
          currentText.startsWith(_initEditingState.text)) {
        final String textDelta = currentText.substring(initTextLength);
        if (textDelta.isNotEmpty) {
          widget.onInsert(textDelta);
          textChanged = true;
        }
      } else if (currentText.length > previousText.length &&
          previousText == _initEditingState.text) {
        // Catch case where init text was empty and then text was added
        final String textDelta = currentText.substring(initTextLength);
        if (textDelta.isNotEmpty) {
          widget.onInsert(textDelta);
          textChanged = true;
        }
      }
    } else {
      // Generic insert/delete logic
      if (currentText.length < previousText.length) {
        // This is a simplification. For robust deletion detection without the
        // deleteDetection trick, a diff algorithm or more context is needed.
        // Assuming any reduction when not composing is a delete.
        widget.onDelete();
        textChanged = true;
      } else if (currentText.length > previousText.length) {
        // Assumes text is appended. More complex changes (e.g. replacing selection)
        // are handled by setting textEditingValue directly.
        final String textDelta = currentText.substring(previousText.length);
        if (textDelta.isNotEmpty) {
          widget.onInsert(textDelta);
          textChanged = true;
        }
      }
    }

    // Reset editing state to the initial state if composing is done
    // and text was actually processed (either by insert/delete or composing finished).
    // This is crucial for the IME to correctly handle subsequent input.
    if (_currentEditingState.composing.isCollapsed &&
        (_currentEditingState.text != _initEditingState.text || textChanged)) {
      _currentEditingState = _initEditingState.copyWith();
      _connection?.setEditingState(_currentEditingState);
    }
    _showCaretOnScreen();
  }

  @override
  void performAction(TextInputAction action) {
    widget.onAction(action);
  }

  @override
  void insertContent(KeyboardInsertedContent content) {
    // Handle rich content insertion if needed
    // For a terminal, this might involve converting to text or specific escape codes
    if (content.data != null) {
      widget.onInsert(utf8.decode(content.data!));
    }
  }

  @override
  void updateFloatingCursor(RawFloatingCursorPoint point) {
    // Handle floating cursor updates if supported
  }

  @override
  void showAutocorrectionPromptRect(int start, int end) {
    // Handle autocorrection prompt if supported
  }

  @override
  void connectionClosed() {
    // Called by the system when the connection is closed.
    // We should not call _connection.close() here as it's already closed.
    // Setting _connection to null indicates that we no longer have a connection.
    if (_connection != null) {
      _connection = null;
    }
  }

  @override
  void didChangeInputControl(
    TextInputControl? oldControl,
    TextInputControl? newControl,
  ) {
    // Handle input control changes if necessary
  }

  @override
  void insertTextPlaceholder(Size size) {
    // Handle text placeholder insertion if necessary
  }

  @override
  void removeTextPlaceholder() {
    // Handle text placeholder removal if necessary
  }

  @override
  void performSelector(String selectorName) {
    // Handle platform-specific selectors if necessary
  }

  @override
  TextEditingValue get textEditingValue => _currentEditingState;

  set textEditingValue(TextEditingValue value) {
    if (_currentEditingState == value) {
      return;
    }
    final oldValue = _currentEditingState;
    _currentEditingState = value;
    if (widget.controller != null && widget.controller!.value != value) {
      widget.controller!.value = value;
    }
    // selection/composing
    if (widget.onSelectionChanged != null && oldValue.selection != value.selection) {
      widget.onSelectionChanged!(value.selection, null);
    }
    if (widget.onComposingChanged != null && oldValue.composing != value.composing) {
      widget.onComposingChanged!(value.composing);
    }
    _connection?.setEditingState(_currentEditingState);
    setState(() {});
  }

  @override
  void hideToolbar([bool hideHandles = true]) {
    if (_menuController.isShown) {
      _menuController.remove();
    }
    // If text handles are being managed by this widget, hide them too.
    // EditableText manages its own handles.
  }

  @override
  bool get copyEnabled =>
      !widget.readOnly && !_currentEditingState.selection.isCollapsed;

  @override
  bool get cutEnabled =>
      !widget.readOnly && !_currentEditingState.selection.isCollapsed;

  @override
  bool get pasteEnabled => !widget.readOnly;

  @override
  bool get selectAllEnabled =>
      !widget.readOnly &&
      _currentEditingState.text.isNotEmpty &&
      (_currentEditingState.selection.baseOffset != 0 ||
          _currentEditingState.selection.extentOffset !=
              _currentEditingState.text.length);

  @override
  void copySelection(SelectionChangedCause cause) {
    if (!copyEnabled) {
      return;
    }
    Clipboard.setData(
      ClipboardData(
        text: _currentEditingState.selection.textInside(
          _currentEditingState.text,
        ),
      ),
    );
    if (cause == SelectionChangedCause.toolbar) {
      hideToolbar();
    }
  }

  @override
  void cutSelection(SelectionChangedCause cause) {
    if (!cutEnabled) {
      return;
    }
    final selection = _currentEditingState.selection;
    final text = _currentEditingState.text;
    Clipboard.setData(ClipboardData(text: selection.textInside(text)));
    final newText = selection.textBefore(text) + selection.textAfter(text);
    textEditingValue = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: selection.start),
    );
    if (cause == SelectionChangedCause.toolbar) {
      hideToolbar();
    }
    _showCaretOnScreen();
  }

  @override
  Future<void> pasteText(SelectionChangedCause cause) async {
    if (!pasteEnabled) {
      return;
    }
    final ClipboardData? data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data == null || data.text == null) {
      return;
    }
    final selection = _currentEditingState.selection;
    final text = _currentEditingState.text;
    final newText =
        selection.textBefore(text) + data.text! + selection.textAfter(text);
    textEditingValue = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(
        offset: selection.start + data.text!.length,
      ),
    );
    if (cause == SelectionChangedCause.toolbar) {
      hideToolbar();
    }
    _showCaretOnScreen();
  }

  @override
  void selectAll(SelectionChangedCause cause) {
    if (!widget.readOnly && _currentEditingState.text.isNotEmpty) {
      textEditingValue = _currentEditingState.copyWith(
        selection: TextSelection(
          baseOffset: 0,
          extentOffset: _currentEditingState.text.length,
        ),
      );
      _showCaretOnScreen();
    }
  }

  @override
  void userUpdateTextEditingValue(
    TextEditingValue value,
    SelectionChangedCause cause,
  ) {
    if (_currentEditingState == value) return;
    final oldValue = _currentEditingState;
    _currentEditingState = value;
    if (widget.controller != null && widget.controller!.value != value) {
      widget.controller!.value = value;
    }
    if (widget.onSelectionChanged != null && oldValue.selection != value.selection) {
      widget.onSelectionChanged!(value.selection, cause);
    }
    if (widget.onComposingChanged != null && oldValue.composing != value.composing) {
      widget.onComposingChanged!(value.composing);
    }
    _connection?.setEditingState(_currentEditingState);
    _showCaretOnScreen();
    setState(() {});
  }

  // Helper to get RenderEditable, similar to EditableTextState.renderEditable
  // This is a common pattern but might not fit all CustomTextEdit use cases
  // if the text rendering is handled differently.
  RenderEditable? get renderEditable {
    // Attempt to find a RenderEditable in the widget tree.
    // This is a common pattern but might not fit all CustomTextEdit use cases
    // if the text rendering is handled differently.
    RenderObject? object = context.findRenderObject();
    while (object != null) {
      if (object is RenderEditable) {
        return object;
      }
      // Iterate up or down depending on structure. For now, just checking current.
      // A more robust way might be to have the child widget provide this.
      break; // Simplified: only checks the direct RenderObject.
    }
    return null;
  }

  // Helper for toolbar anchor calculation, similar to EditableTextState
  Offset globalToLocal(Offset global) {
    final RenderBox? box = context.findRenderObject() as RenderBox?;
    return box?.globalToLocal(global) ?? global;
  }
  
  @override
  void performPrivateCommand(String action, Map<String, dynamic> data) {
    // TODO: implement performPrivateCommand
  }
}
