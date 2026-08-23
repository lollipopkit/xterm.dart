import 'dart:ui';

import 'package:flutter/widgets.dart';
import 'package:quiver/collection.dart';

/// Identifies one laid out glyph: the character, the colour it is painted in,
/// and the style flags that change how it is laid out.
///
/// A record rather than a hashed int, so the components are compared
/// structurally. A hashed key that collides hands back a [Paragraph] laid out
/// for a different cell, and the terminal paints the wrong glyph: silently,
/// and depending on what else happens to be in the LRU at that moment.
///
/// Everything that only affects the *colour*, meaning `faint`, `inverse` and
/// the painter's `reverseDisplay`, is resolved into the colour before the key
/// is built, and so must not appear in `styleFlags`. Two cells arriving at the
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

/// Identifies a run of cells laid out as one [Paragraph]. As [GlyphKey], but
/// the text is the whole run.
///
/// Runs are kept in their own cache rather than sharing the glyph cache: a
/// single cell can be looked up from its code point without building a string,
/// and that path runs for every cell a run cannot absorb.
typedef RunKey = (String text, int argb, int styleFlags);

/// Lays [text] out with [style] at [textScaler], unconstrained.
///
/// Separate from [ParagraphCache] so a caller can inspect a paragraph before
/// deciding whether to keep it. The run painter measures one against the cell
/// grid and throws it away if the font did not advance uniformly.
Paragraph buildParagraph(String text, TextStyle style, TextScaler textScaler) {
  final builder = ParagraphBuilder(style.getParagraphStyle());
  builder.pushStyle(style.getTextStyle(textScaler: textScaler));
  builder.addText(text);

  final paragraph = builder.build();
  paragraph.layout(const ParagraphConstraints(width: double.infinity));
  return paragraph;
}

/// A cache of laid out [Paragraph]s. This is used to avoid laying out the same
/// text multiple times, which is expensive.
class ParagraphCache<K extends Object> {
  ParagraphCache(int maximumSize)
    : _cache = LruMap<K, Paragraph>(maximumSize: maximumSize);

  final LruMap<K, Paragraph> _cache;

  /// Returns a [Paragraph] for the given [key]. [key] is the same as the
  /// key argument to [performAndCacheLayout].
  Paragraph? getLayoutFromCache(K key) {
    return _cache[key];
  }

  /// Applies [style] and [textScaler] to [text] and lays it out to create
  /// a [Paragraph]. The [Paragraph] is cached and can be retrieved with the
  /// same [key] by calling [getLayoutFromCache].
  Paragraph performAndCacheLayout(
    String text,
    TextStyle style,
    TextScaler textScaler,
    K key,
  ) {
    final paragraph = buildParagraph(text, style, textScaler);
    _cache[key] = paragraph;
    return paragraph;
  }

  /// Stores an already built [paragraph] under [key].
  void put(K key, Paragraph paragraph) {
    _cache[key] = paragraph;
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
