import 'dart:isolate';

import 'package:xterm/buffer/buffer_line.dart';
import 'package:xterm/input/keys.dart';
import 'package:xterm/mouse/position.dart';
import 'package:xterm/mouse/selection.dart';
import 'package:xterm/terminal/platform.dart';
import 'package:xterm/terminal/terminal.dart';
import 'package:xterm/terminal/terminal_ui_interaction.dart';
import 'package:xterm/theme/terminal_color.dart';
import 'package:xterm/theme/terminal_theme.dart';
import 'package:xterm/theme/terminal_themes.dart';
import 'package:xterm/util/observable.dart';

void terminalMain(SendPort port) async {
  final rp = ReceivePort();
  port.send(rp.sendPort);

  Terminal? _terminal;

  await for (var msg in rp) {
    final String action = msg[0];
    switch (action) {
      case 'sendPort':
        port = msg[1];
        break;
      case 'init':
        final TerminalInitData initData = msg[1];
        _terminal = Terminal(
            onInput: (String input) {
              port.send(['onInput', input]);
            },
            onTitleChange: (String title) {
              port.send(['onTitleChange', title]);
            },
            onIconChange: (String icon) {
              port.send(['onIconChange', icon]);
            },
            onBell: () {
              port.send(['onBell']);
            },
            platform: initData.platform,
            theme: initData.theme,
            maxLines: initData.maxLines);
        _terminal.addListener(() {
          port.send(['notify']);
        });
        break;
      case 'write':
        if (_terminal == null) {
          break;
        }
        _terminal.write(msg[1]);
        break;
      case 'refresh':
        if (_terminal == null) {
          break;
        }

        _terminal.refresh();
        break;
      case 'selection.clear':
        if (_terminal == null) {
          break;
        }
        _terminal.selection.clear();
        break;
      case 'mouseMode.onTap':
        if (_terminal == null) {
          break;
        }
        _terminal.mouseMode.onTap(_terminal, msg[1]);
        break;
      case 'mouseMode.onPanStart':
        if (_terminal == null) {
          break;
        }
        _terminal.mouseMode.onPanStart(_terminal, msg[1]);
        break;
      case 'mouseMode.onPanUpdate':
        if (_terminal == null) {
          break;
        }
        _terminal.mouseMode.onPanUpdate(_terminal, msg[1]);
        break;
      case 'setScrollOffsetFromBottom':
        if (_terminal == null) {
          break;
        }
        _terminal.buffer.setScrollOffsetFromBottom(msg[1]);
        break;
      case 'resize':
        if (_terminal == null) {
          break;
        }
        _terminal.resize(msg[1], msg[2]);
        break;
      case 'setScrollOffsetFromBottom':
        if (_terminal == null) {
          break;
        }
        _terminal.buffer.setScrollOffsetFromBottom(msg[1]);
        break;
      case 'keyInput':
        if (_terminal == null) {
          break;
        }
        _terminal.keyInput(msg[1],
            ctrl: msg[2], alt: msg[3], shift: msg[4], mac: msg[5]);
        break;
      case 'requestNewStateWhenDirty':
        if (_terminal == null) {
          break;
        }
        if (_terminal.dirty) {
          final newState = TerminalState(
              _terminal.buffer.scrollOffsetFromBottom,
              _terminal.buffer.scrollOffsetFromTop,
              _terminal.buffer.height,
              _terminal.invisibleHeight,
              _terminal.viewHeight,
              _terminal.viewWidth,
              _terminal.selection,
              _terminal.getSelectedText(),
              _terminal.theme.background,
              _terminal.cursorX,
              _terminal.cursorY,
              _terminal.showCursor,
              _terminal.theme.cursor,
              _terminal.getVisibleLines(),
              _terminal.scrollOffset);
          port.send(['newState', newState]);
        }
        break;
      case 'paste':
        if (_terminal == null) {
          break;
        }
        _terminal.paste(msg[1]);
        break;
    }
  }
}

class TerminalInitData {
  PlatformBehavior platform;
  TerminalTheme theme;
  int maxLines;

  TerminalInitData(this.platform, this.theme, this.maxLines);
}

class TerminalState {
  int scrollOffsetFromTop;
  int scrollOffsetFromBottom;

  int bufferHeight;
  int invisibleHeight;

  int viewHeight;
  int viewWidth;

  Selection selection;
  String? selectedText;

  int backgroundColor;

  int cursorX;
  int cursorY;
  bool showCursor;
  int cursorColor;

  List<BufferLine> visibleLines;

  int scrollOffset;

  bool consumed = false;

  TerminalState(
      this.scrollOffsetFromBottom,
      this.scrollOffsetFromTop,
      this.bufferHeight,
      this.invisibleHeight,
      this.viewHeight,
      this.viewWidth,
      this.selection,
      this.selectedText,
      this.backgroundColor,
      this.cursorX,
      this.cursorY,
      this.showCursor,
      this.cursorColor,
      this.visibleLines,
      this.scrollOffset);
}

void _defaultInputHandler(String _) {}
void _defaultBellHandler() {}
void _defaultTitleHandler(String _) {}
void _defaultIconHandler(String _) {}

class TerminalIsolate with Observable implements TerminalUiInteraction {
  final _receivePort = ReceivePort();
  SendPort? _sendPort;
  late Isolate _isolate;

  final TerminalInputHandler onInput;
  final BellHandler onBell;
  final TitleChangeHandler onTitleChange;
  final IconChangeHandler onIconChange;
  final PlatformBehavior _platform;

  final TerminalTheme theme;
  final int maxLines;

  TerminalState? _lastState;

  TerminalState? get lastState {
    return _lastState;
  }

  TerminalIsolate(
      {this.onInput = _defaultInputHandler,
      this.onBell = _defaultBellHandler,
      this.onTitleChange = _defaultTitleHandler,
      this.onIconChange = _defaultIconHandler,
      PlatformBehavior platform = PlatformBehaviors.unix,
      this.theme = TerminalThemes.defaultTheme,
      required this.maxLines})
      : _platform = platform;

  @override
  int get scrollOffsetFromBottom => _lastState?.scrollOffsetFromBottom ?? 0;

  @override
  int get scrollOffsetFromTop => _lastState?.scrollOffsetFromTop ?? 0;

  @override
  int get scrollOffset => _lastState?.scrollOffset ?? 0;

  @override
  int get bufferHeight => _lastState?.bufferHeight ?? 0;

  @override
  int get terminalHeight => _lastState?.viewHeight ?? 0;

  @override
  int get terminalWidth => _lastState?.viewWidth ?? 0;

  @override
  int get invisibleHeight => _lastState?.invisibleHeight ?? 0;

  @override
  Selection? get selection => _lastState?.selection;

  @override
  bool get showCursor => _lastState?.showCursor ?? true;

  @override
  List<BufferLine> getVisibleLines() {
    if (_lastState == null) {
      return List<BufferLine>.empty();
    }
    return _lastState!.visibleLines;
  }

  @override
  int get cursorY => _lastState?.cursorY ?? 0;

  @override
  int get cursorX => _lastState?.cursorX ?? 0;

  @override
  BufferLine? get currentLine {
    if (_lastState == null) {
      return null;
    }

    int visibleLineIndex =
        _lastState!.cursorY - _lastState!.scrollOffsetFromTop;
    if (visibleLineIndex < 0) {
      visibleLineIndex = _lastState!.cursorY;
    }
    return _lastState!.visibleLines[visibleLineIndex];
  }

  @override
  int get cursorColor => _lastState?.cursorColor ?? 0;

  @override
  int get backgroundColor => _lastState?.backgroundColor ?? 0;

  @override
  bool get dirty {
    if (_lastState == null) {
      return false;
    }
    if (_lastState!.consumed) {
      return false;
    }
    _lastState!.consumed = true;
    return true;
  }

  @override
  PlatformBehavior get platform => _platform;

  void start() async {
    var firstReceivePort = ReceivePort();
    _isolate = await Isolate.spawn(terminalMain, firstReceivePort.sendPort);
    _sendPort = await firstReceivePort.first;
    _sendPort!.send(['sendPort', _receivePort.sendPort]);
    _receivePort.listen((message) {
      String action = message[0];
      switch (action) {
        case 'onInput':
          this.onInput(message[1]);
          break;
        case 'onBell':
          this.onBell();
          break;
        case 'onTitleChange':
          this.onTitleChange(message[1]);
          break;
        case 'onIconChange':
          this.onIconChange(message[1]);
          break;
        case 'notify':
          poll();
          break;
        case 'newState':
          _lastState = message[1];
          this.notifyListeners();
          break;
      }
    });
    _sendPort!.send(
        ['init', TerminalInitData(this.platform, this.theme, this.maxLines)]);
  }

  void stop() {
    _isolate.kill();
  }

  void poll() {
    if (_sendPort == null) {
      return;
    }
    _sendPort!.send(['requestNewStateWhenDirty']);
  }

  void refresh() {
    if (_sendPort == null) {
      return;
    }
    _sendPort!.send(['refresh']);
  }

  void clearSelection() {
    if (_sendPort == null) {
      return;
    }
    _sendPort!.send(['clearSelection']);
  }

  void onMouseTap(Position position) {
    if (_sendPort == null) {
      return;
    }
    _sendPort!.send(['mouseMode.onTap', position]);
  }

  void onPanStart(Position position) {
    if (_sendPort == null) {
      return;
    }
    _sendPort!.send(['mouseMode.onPanStart', position]);
  }

  void onPanUpdate(Position position) {
    if (_sendPort == null) {
      return;
    }
    _sendPort!.send(['mouseMode.onPanUpdate', position]);
  }

  void setScrollOffsetFromBottom(int offset) {
    if (_sendPort == null) {
      return;
    }
    _sendPort!.send(['setScrollOffsetFromBottom', offset]);
  }

  int convertViewLineToRawLine(int viewLine) {
    if (_lastState == null) {
      return 0;
    }
    if (_lastState!.viewHeight > _lastState!.bufferHeight) {
      return viewLine;
    }

    return viewLine + (_lastState!.bufferHeight - _lastState!.viewHeight);
  }

  void write(String text) {
    if (_sendPort == null) {
      return;
    }
    _sendPort!.send(['write', text]);
  }

  void paste(String data) {
    if (_sendPort == null) {
      return;
    }
    _sendPort!.send(['paste', data]);
  }

  void resize(int newWidth, int newHeight) {
    if (_sendPort == null) {
      return;
    }
    _sendPort!.send(['resize', newWidth, newHeight]);
  }

  void raiseOnInput(String text) {
    onInput(text);
  }

  void keyInput(
    TerminalKey key, {
    bool ctrl = false,
    bool alt = false,
    bool shift = false,
    bool mac = false,
    // bool meta,
  }) {
    if (_sendPort == null) {
      return;
    }
    _sendPort!.send(['keyInput', key, ctrl, alt, shift, mac]);
  }
}
