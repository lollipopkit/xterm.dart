enum TerminalMouseButtonState {
  up,

  down,

  /// The pointer moved to another cell, with the button held, or with
  /// [TerminalMouseButton.none] when nothing is held.
  motion,
}
