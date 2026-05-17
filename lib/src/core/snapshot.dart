import 'package:xterm/src/core/buffer/buffer.dart';

/// A snapshot of a terminal's buffer state at a point in time.
///
/// This captures a reference to the active buffer, allowing scrollback to be
/// trimmed independently of ongoing terminal activity.
class TerminalSnapshot {
  TerminalSnapshot(this.buffer);

  /// The captured buffer.
  final Buffer buffer;

  /// Trims the scrollback history, removing all lines above the current
  /// viewport.
  void trimScrollback() {
    buffer.clearScrollback();
  }
}
