/// The keys held during a mouse event, which a report carries in its button
/// code: shift 4, meta (alt) 8, control 16.
class TerminalMouseModifiers {
  const TerminalMouseModifiers({
    this.shift = false,
    this.alt = false,
    this.ctrl = false,
  });

  static const none = TerminalMouseModifiers();

  final bool shift;
  final bool alt;
  final bool ctrl;

  int get bits => (shift ? 4 : 0) | (alt ? 8 : 0) | (ctrl ? 16 : 0);

  @override
  bool operator ==(Object other) =>
      other is TerminalMouseModifiers &&
      other.shift == shift &&
      other.alt == alt &&
      other.ctrl == ctrl;

  @override
  int get hashCode => bits;
}
