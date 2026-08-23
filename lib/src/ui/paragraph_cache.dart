import 'dart:ui';

import 'package:flutter/widgets.dart';
import 'package:quiver/collection.dart';

/// Identifies a laid out glyph: the character, the colour it is painted in,
/// and the style flags that change how it is laid out.
///
/// A record rather than a hashed int, so the components are compared
/// structurally. A hashed key that collides hands back a [Paragraph] laid out
/// for a different cell, and the terminal paints the wrong glyph — silently,
/// and depending on what else happens to be in the LRU at that moment.
///
/// Everything that only affects the *colour* — `faint`, `inverse`, the
/// painter's `reverseDisplay` — is resolved into the colour before the key is
/// built, and so must not appear in `styleFlags`. Two cells arriving at the
/// same colour by different routes share a paragraph, correctly.
///
/// The colour is an ARGB32 int rather than a [Color] because hashing four
/// doubles and a colour space on every cell of every frame costs more than the
/// whole rest of the lookup. That flattens to 8 bits per channel and drops the
/// colour space, which is lossless for every colour the terminal produces
/// itself: the palette is 256 entries and SGR carries 24-bit RGB. A
/// `TerminalTheme` built from wide-gamut colours is the one way to reach this
/// key with something ARGB32 cannot tell apart.
typedef GlyphKey = (int charCode, int argb, int styleFlags);

/// A cache of laid out [Paragraph]s. This is used to avoid laying out the same
/// text multiple times, which is expensive.
class ParagraphCache {
  ParagraphCache(int maximumSize)
      : _cache = LruMap<GlyphKey, Paragraph>(maximumSize: maximumSize);

  final LruMap<GlyphKey, Paragraph> _cache;

  /// Returns a [Paragraph] for the given [key]. [key] is the same as the
  /// key argument to [performAndCacheLayout].
  Paragraph? getLayoutFromCache(GlyphKey key) {
    return _cache[key];
  }

  /// Applies [style] and [textScaler] to [text] and lays it out to create
  /// a [Paragraph]. The [Paragraph] is cached and can be retrieved with the
  /// same [key] by calling [getLayoutFromCache].
  Paragraph performAndCacheLayout(
    String text,
    TextStyle style,
    TextScaler textScaler,
    GlyphKey key,
  ) {
    final builder = ParagraphBuilder(style.getParagraphStyle());
    builder.pushStyle(style.getTextStyle(textScaler: textScaler));
    builder.addText(text);

    final paragraph = builder.build();
    paragraph.layout(ParagraphConstraints(width: double.infinity));

    _cache[key] = paragraph;
    return paragraph;
  }

  /// Clears the cache. This should be called when the same text and style
  /// pair no longer produces the same layout. For example, when a font is
  /// loaded.
  void clear() {
    _cache.clear();
  }

  /// Returns the number of [Paragraph]s in the cache.
  int get length {
    return _cache.length;
  }
}
