import 'package:xterm/src/core/platform.dart';

/// The scroll unit of the platform the terminal is running on.
///
/// The engine hands the framework a scroll delta in logical pixels, and how
/// many pixels one click of the wheel is depends on the system the click came
/// from. The macOS embedder scales a wheel's delta by 40, the Windows one by
/// the system's own "lines per click" times 100/3, and the Linux one by 53 —
/// the last two the numbers Chromium uses. A terminal that took those pixels
/// at face value scrolled two lines of text per click on a Mac and six on
/// Windows, for the same gesture, and the Mac was the one that felt stuck.
///
/// This is the conversion, and it is the system's own: a click of the wheel
/// is worth the same three lines of text wherever it was made.
///
/// The lines are the terminal's, not the system's — a system scrolls by its
/// own lines, and a terminal's lines are the ones on the screen.
class TerminalScrollUnit {
  const TerminalScrollUnit._({
    required this.pixelsPerClick,
    required this.linesPerClick,
  });

  /// The unit of [platform], or null where there is no wheel to have one: a
  /// phone scrolls with a finger, and the finger is its own unit.
  static TerminalScrollUnit? of(TerminalTargetPlatform platform) =>
      switch (platform) {
        TerminalTargetPlatform.macos =>
          const TerminalScrollUnit._(pixelsPerClick: 40, linesPerClick: 3),
        TerminalTargetPlatform.windows =>
          const TerminalScrollUnit._(pixelsPerClick: 100, linesPerClick: 3),
        TerminalTargetPlatform.linux =>
          const TerminalScrollUnit._(pixelsPerClick: 53, linesPerClick: 3),
        _ => null,
      };

  /// How many logical pixels one click of the wheel is on this platform.
  final double pixelsPerClick;

  /// How many lines of text one click of the wheel is worth.
  final int linesPerClick;

  /// Whether [pixels] is a whole number of clicks of the wheel.
  ///
  /// A wheel says how big a click is and nothing else; a trackpad says how
  /// far the finger went, which is never a whole number of clicks. The two
  /// are told apart by that, because the platforms do not agree on saying it
  /// themselves: Windows sends a trackpad as a trackpad, but macOS and Linux
  /// send both as a mouse.
  bool isClicks(double pixels) {
    final clicks = pixels / pixelsPerClick;
    return (clicks - clicks.roundToDouble()).abs() < 0.001;
  }

  /// The lines of text that [pixels] of scrolling is worth.
  ///
  /// A click is [linesPerClick] lines. A trackpad's pixels are the finger's
  /// own, and a line of travel is a line of text — as it is on the platform
  /// that reports one.
  double linesFor(double pixels, double lineHeight) {
    if (isClicks(pixels)) {
      return pixels / pixelsPerClick * linesPerClick;
    }
    return pixels / lineHeight;
  }
}
