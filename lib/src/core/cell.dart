import 'package:xterm/src/utils/hash_values.dart';

class CellData {
  CellData({
    required this.foreground,
    required this.background,
    required this.flags,
    required this.content,
    this.cluster,
  });

  factory CellData.empty() {
    return CellData(foreground: 0, background: 0, flags: 0, content: 0);
  }

  int foreground;

  int background;

  int flags;

  int content;

  /// The cell's whole text when it holds more than the one code point [content]
  /// has room for, and null when it does not. See [CellContent.clusterFlag].
  ///
  /// Carried here so that a cell copied out of a line and written back to
  /// another arrives intact; [content] alone cannot say what the marks were.
  String? cluster;

  // TODO: remove. Its only caller was the painter's paragraph cache key, which
  // XORed this with another hash and so could collide and paint the wrong
  // glyph; the cache is keyed by a `GlyphKey` record now and nothing in the
  // package calls this. Kept for one release because `CellData` is exported
  // from `core.dart`.
  @Deprecated(
    'Folding a cell into one int loses information. Compare the fields, or '
    'build a record from the ones that matter.',
  )
  int getHash() {
    return hashValues(foreground, background, flags, content);
  }

  @override
  String toString() {
    return 'CellData{foreground: $foreground, background: $background, flags: $flags, content: $content, cluster: $cluster}';
  }
}

abstract class CellAttr {
  static const bold = 1 << 0;
  static const faint = 1 << 1;
  static const italic = 1 << 2;
  static const underline = 1 << 3;
  static const blink = 1 << 4;
  static const inverse = 1 << 5;
  static const invisible = 1 << 6;
  static const strikethrough = 1 << 7;
  static const overline = 1 << 8;
}

abstract class CellColor {
  static const valueMask = 0xFFFFFF;

  static const typeShift = 25;
  static const typeMask = 3 << typeShift;

  static const normal = 0 << typeShift;
  static const named = 1 << typeShift;
  static const palette = 2 << typeShift;
  static const rgb = 3 << typeShift;
}

abstract class CellContent {
  static const codepointMask = 0x1fffff;

  /// Set when the cell's text is longer than the single code point below, and
  /// the whole of it is held beside the line's `Uint32List`. The code point
  /// stays the cluster's base, so a reader that does not know about clusters
  /// gets the character without its marks rather than nothing.
  ///
  /// Bit 21 is free because a code point stops at U+10FFFF, which fits in the
  /// 21 of [codepointMask]. It is the same bit xterm.js uses for the same
  /// purpose.
  static const clusterFlag = 1 << 21;

  static const widthShift = 22;
  static const widthMask = 3 << widthShift;
}
