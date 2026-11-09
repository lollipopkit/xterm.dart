class EscapeEmitter {
  const EscapeEmitter();

  String primaryDeviceAttributes() {
    return '\x1b[?1;2c';
  }

  String secondaryDeviceAttributes() {
    const model = 0;
    const version = 0;
    return '\x1b[>$model;$version;0c';
  }

  String tertiaryDeviceAttributes() {
    return '\x1bP!|00000000\x1b\\';
  }

  String operatingStatus() {
    return '\x1b[0n';
  }

  String cursorPosition(int x, int y) {
    return '\x1b[${y + 1};${x + 1}R';
  }

  String extendedCursorPosition(int x, int y) {
    return '\x1b[?${y + 1};${x + 1}R';
  }

  /// [text] between the paste markers, with ESC and the 8-bit CSI dropped:
  /// a pasted `ESC [201~` would end the paste early and run the rest as
  /// typed.
  String bracketedPaste(String text) {
    final safe = text.replaceAll(_pasteEscapes, '');
    return '\x1b[200~$safe\x1b[201~';
  }

  static final _pasteEscapes = RegExp('[\x1b\x9b]');

  String size(int rows, int cols) {
    return '\x1b[8;$rows;${cols}t';
  }
}
