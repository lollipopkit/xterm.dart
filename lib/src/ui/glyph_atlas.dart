import 'dart:math' show max;
import 'dart:ui';

import 'package:flutter/painting.dart';
import 'package:xterm/src/ui/paragraph_cache.dart';
import 'package:xterm/src/utils/unicode_width.dart';

/// Identifies one rasterised glyph.
///
/// There is no colour in it, and that is the whole point of the atlas: a
/// terminal draws the same few hundred glyphs in a great many colours, and
/// keying a laid out [Paragraph] by the colour as well is what makes a screen
/// of uniquely coloured cells miss the cache on every cell of every frame.
/// A sprite is rasterised once and tinted when it is drawn.
typedef AtlasKey = (int charCode, int styleFlags);

/// Where a glyph sits in the atlas, and where its sprite sits relative to the
/// cell it is drawn into.
class AtlasSprite {
  const AtlasSprite(this.source, this.dxOffset);

  /// The sprite's rect in atlas pixels.
  final Rect source;

  /// How far left of the cell's own left edge the sprite starts, in *device*
  /// pixels. This is [GlyphAtlas.padding] wide, and it is what lets an italic
  /// or a fallback font's glyph spill outside its column the way it does when
  /// the paragraph is drawn straight to the canvas.
  ///
  /// Device pixels and a whole number of them, because that is what keeps a
  /// sprite crisp: the glyph is rasterised at a whole pixel inside the atlas
  /// and drawn to a whole pixel on screen, so it is copied rather than
  /// resampled. See [GlyphAtlas].
  final double dxOffset;
}

/// A texture of laid out glyphs, drawn through [Canvas.drawRawAtlas].
///
/// The atlas rasterises in white and is tinted per sprite at draw time, so a
/// code point a font draws in colour of its own cannot go in it: tinting one
/// leaves a solid silhouette. [wants] is where that is decided, from the
/// Unicode `Emoji_Presentation` property, and a glyph it turns down keeps the
/// painter's paragraph path.
///
/// Tinting a mask is not quite the same as laying the glyph out in its colour.
/// The rasteriser adjusts a glyph's contrast for the colour it is being drawn
/// in, so a white mask tinted red has edge pixels a little different from red
/// text. It is confined to partially covered pixels, and every renderer that
/// keeps a glyph atlas has it; `glyph_atlas_test.dart` is written around the
/// distinction.
///
/// Everything the atlas measures is in whole device pixels: the slots, the
/// padding, and the position a sprite is drawn at. A glyph rasterised at a
/// fractional offset and then drawn to a different fractional offset is
/// resampled, and text that has been through that twice is visibly soft. The
/// cost is that a cell's glyph can sit up to half a device pixel from where
/// laying the paragraph out at the exact column would have put it, which at any
/// ratio a display uses is less than the rounding the rasteriser does anyway.
///
/// The image is rebuilt whole whenever a glyph is added, because an [Image] is
/// immutable. That is affordable because a terminal's glyph set converges: the
/// first frames of a session add most of what a session ever needs, and after
/// that [image] hands back the same object every frame.
class GlyphAtlas {
  GlyphAtlas({
    required Size cellSize,
    required double devicePixelRatio,
    required TextScaler textScaler,
    required TextStyle Function(int styleFlags) styleFor,
  }) : _cellSize = cellSize,
       _devicePixelRatio = devicePixelRatio,
       _textScaler = textScaler,
       _styleFor = styleFor;

  /// How far outside its column a glyph may reach and still be kept whole, as
  /// a multiple of the cell width, on each side.
  ///
  /// Drawing a paragraph straight to the canvas clips nothing, so a sprite that
  /// covered only its own column would cut the tail off an italic `f` where the
  /// old path drew it. One cell each side covers what a monospace font does;
  /// the cost is that a one-column glyph occupies three columns of atlas.
  static const padding = 1;

  /// The atlas stops growing here, in device pixels on either axis. Past it a
  /// glyph is refused and the painter falls back, rather than the atlas
  /// evicting and rebuilding itself every frame.
  static const maxDimension = 2048;

  final Size _cellSize;
  final double _devicePixelRatio;
  final TextScaler _textScaler;
  final TextStyle Function(int styleFlags) _styleFor;

  final _sprites = <AtlasKey, AtlasSprite>{};
  final _paragraphs = <AtlasKey, Paragraph>{};

  /// Keys in insertion order, so a rebuild draws them where [_sprites] says.
  final _order = <AtlasKey>[];

  Image? _image;
  var _dirty = false;

  /// The shelf allocator's pen, in device pixels. Every glyph is one cell tall,
  /// so the shelves are uniform and a row never needs to be measured.
  var _penX = 0.0;
  var _penY = 0.0;

  /// The padding either side of a glyph, in whole device pixels.
  late final double _padding =
      (padding * _cellSize.width * _devicePixelRatio).roundToDouble();

  late final double _slotHeight =
      (_cellSize.height * _devicePixelRatio).ceilToDouble();

  double _slotWidth(int cells) {
    return (cells * _cellSize.width * _devicePixelRatio).ceilToDouble() +
        2 * _padding;
  }

  /// How many sprites the atlas holds. For tests and for the benchmark.
  int get length => _sprites.length;

  /// Whether [charCode] may be rasterised into the atlas at all.
  ///
  /// The rule is the Unicode `Emoji_Presentation` property: a code point a font
  /// draws in colour by default cannot be tinted. A code point that reaches
  /// colour only through a variation selector forms a cluster instead, and the
  /// painter already keeps clusters off this path.
  static bool wants(int charCode) {
    return !unicodeWidth.hasEmojiPresentation(charCode);
  }

  /// The sprite for [key], rasterising it if the atlas does not have it yet.
  /// Null when the glyph will not go in: refused by [wants], or the atlas is
  /// full.
  AtlasSprite? sprite(AtlasKey key, int cells) {
    final existing = _sprites[key];
    if (existing != null) {
      return existing;
    }

    if (!wants(key.$1)) {
      return null;
    }

    final width = _slotWidth(cells);
    if (width > maxDimension) {
      return null;
    }

    if (_penX + width > maxDimension) {
      _penX = 0;
      _penY += _slotHeight;
    }

    if (_penY + _slotHeight > maxDimension) {
      return null;
    }

    final sprite = AtlasSprite(
      Rect.fromLTWH(_penX, _penY, width, _slotHeight),
      _padding,
    );
    _penX += width;

    _sprites[key] = sprite;
    _paragraphs[key] = buildParagraph(
      String.fromCharCode(key.$1),
      _styleFor(key.$2),
      _textScaler,
    );
    _order.add(key);
    _dirty = true;

    return sprite;
  }

  /// The texture, rebuilt if a glyph has been added since it was last asked
  /// for. Null only when nothing has been rasterised yet.
  Image? get image {
    if (_dirty) {
      _rebuild();
    }
    return _image;
  }

  void _rebuild() {
    _dirty = false;

    final recorder = PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.scale(_devicePixelRatio);

    for (final key in _order) {
      final sprite = _sprites[key]!;
      // Both components are whole device pixels, and the canvas is scaled by
      // the ratio, so the glyph is rasterised at a whole pixel of the image.
      canvas.drawParagraph(
        _paragraphs[key]!,
        Offset(
          (sprite.source.left + sprite.dxOffset) / _devicePixelRatio,
          sprite.source.top / _devicePixelRatio,
        ),
      );
    }

    final picture = recorder.endRecording();
    final width = max(1, _usedWidth().ceil());
    final height = max(1, (_penY + _slotHeight).ceil());

    _image?.dispose();
    _image = picture.toImageSync(width, height);
    picture.dispose();
  }

  /// The width the image needs: the full line if the pen has wrapped at least
  /// once, and only what the first shelf used if it has not.
  double _usedWidth() {
    return _penY > 0 ? maxDimension.toDouble() : _penX;
  }

  void clear() {
    for (final paragraph in _paragraphs.values) {
      paragraph.dispose();
    }
    _paragraphs.clear();
    _sprites.clear();
    _order.clear();
    _image?.dispose();
    _image = null;
    _dirty = false;
    _penX = 0;
    _penY = 0;
  }

  void dispose() => clear();
}
