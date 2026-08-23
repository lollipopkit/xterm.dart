import 'dart:typed_data';

import 'package:flutter/painting.dart';

import 'package:flutter/rendering.dart';
import 'package:xterm/src/ui/char_metrics.dart';
import 'package:xterm/src/ui/glyph_atlas.dart';
import 'package:xterm/src/ui/palette_builder.dart';
import 'package:xterm/src/ui/paragraph_cache.dart';
import 'package:xterm/xterm.dart';

/// Encapsulates the logic for painting various terminal elements.
///
/// [paintLine] keeps its run state in fields rather than locals, so a painter
/// paints one line at a time and is not reentrant. Painting is synchronous and
/// on one thread, so that costs nothing and saves a per-line allocation on
/// every frame.
class TerminalPainter {
  TerminalPainter({
    required TerminalTheme theme,
    required TerminalStyle textStyle,
    required TextScaler textScaler,
    double devicePixelRatio = 1.0,
  }) : _textStyle = textStyle,
       _theme = theme,
       _textScaler = textScaler,
       _devicePixelRatio = devicePixelRatio;

  /// A lookup table from terminal colors to Flutter colors.
  late var _colorPalette = PaletteBuilder(_theme).build();

  /// [_colorPalette] packed as ARGB32, so deciding whether two cells share a
  /// colour does not have to build a [Color] for each of them.
  late var _paletteArgb = _packPalette(_colorPalette);

  late var _foregroundArgb = _theme.foreground.toARGB32();

  late var _backgroundArgb = _theme.background.toARGB32();

  /// Size of each character in the terminal.
  late var _cellSize = _measureCharSize();

  /// Laid out single glyphs, for cells a run cannot absorb. Should be cleared
  /// when the same cell no longer produces the same visual output. For example,
  /// when [_textStyle] is changed, or when the system font changes.
  ///
  /// The two caches split one budget rather than each having their own, since a
  /// [Paragraph] holds native memory that [ParagraphCache] does not release on
  /// eviction. A run's paragraph holds more of it than a glyph's, so counting
  /// them against the same total is already generous to runs.
  final _glyphCache = ParagraphCache<GlyphKey>(8192);

  /// Laid out runs of cells. Smaller than [_glyphCache] because each entry
  /// covers many cells, and because a run's text is far less repetitive than a
  /// single character.
  ///
  /// Not smaller than this, though. A screen of short differently coloured runs
  /// has a working set in the low thousands, and at 1024 it thrashes: the
  /// `colored` profile of the paint benchmark goes from 0.95 ms a frame to
  /// 17.8 ms.
  final _runCache = ParagraphCache<RunKey>(2048);

  /// Laid out clusters, the cells holding a base character and its combining
  /// marks. Kept apart from [_runCache] rather than sharing its keys because a
  /// cluster is laid out with the font's default features: composing a base and
  /// its marks into one glyph is the shaping a run turns off. Small because a
  /// screen rarely has more than a handful.
  final _clusterCache = ParagraphCache<RunKey>(256);

  /// Reused across [Paint] calls; only its colour changes.
  final _backgroundPaint = Paint();

  /// Sprites for the cells a run could not absorb, rasterised once without a
  /// colour and tinted per cell when drawn.
  ///
  /// This is deliberately not used for cells that *do* coalesce. A run already
  /// draws its whole span in one call, where the atlas would write a sprite per
  /// cell into the arrays below; for a screen of plain text that is more work,
  /// not less. What the atlas fixes is the case coalescing cannot reach: a
  /// cell whose neighbours differ, or a wide character, which under the
  /// paragraph cache needs a layout keyed by its colour as well as its glyph.
  /// A screen where every cell has a colour of its own then misses the cache on
  /// every cell of every frame: 134 ms a frame at 240x70, against 1.1 ms
  /// through the atlas. A screen of CJK, where no cell ever joins a run, goes
  /// from 1.6 ms to 0.6 ms. Colour is not part of an atlas key, so the working
  /// set is the glyph set, which is small.
  GlyphAtlas? _atlas;

  /// [Canvas.drawRawAtlas] arguments for the line being painted, filled to
  /// [_spriteCount] and grown by doubling. Reused between lines: the terminal
  /// paints one line at a time on one thread, as [paintLine] already assumes.
  ///
  /// [FilterQuality.none] rather than a default: a sprite is drawn at exactly
  /// the size and offset it was rasterised at, so nearest sampling reproduces
  /// its pixels, where filtering would resample and soften every glyph on
  /// screen.
  var _spriteTransforms = Float32List(_initialSprites * 4);
  var _spriteRects = Float32List(_initialSprites * 4);
  var _spriteColors = Int32List(_initialSprites);
  var _spriteCount = 0;
  final _atlasPaint = Paint()..filterQuality = FilterQuality.none;

  static const _initialSprites = 256;

  /// Run kinds, [_runKind] of a style and a character class, whose glyphs do
  /// not advance by exactly one cell, found by measuring a run against the grid
  /// in [_flushRun]. Coalescing is abandoned for these, permanently until the
  /// font changes.
  final _uncoalescableKinds = <int>{};

  /// The [CellFlags] that reach [TerminalStyle.toTextStyle] and so change the
  /// laid out glyph. The rest either resolve into the colour (`faint`,
  /// `inverse`), stop the cell being painted at all (`invisible`), or are not
  /// rendered (`blink`). See [GlyphKey].
  static const _layoutFlags =
      CellFlags.bold |
      CellFlags.italic |
      CellFlags.underline |
      CellFlags.strikethrough |
      CellFlags.overline;

  /// The flags that draw a line across the cell rather than a glyph inside it,
  /// and so keep a cell off the atlas.
  ///
  /// A decoration covers the character's advance exactly. Drawn per cell out of
  /// an atlas, two neighbours' underlines meet at a boundary that rounding can
  /// leave a gap in; drawn as a run they are one unbroken line. Runs are also
  /// where decorated text already goes, so this costs nothing.
  static const _decorationFlags =
      CellFlags.underline | CellFlags.strikethrough | CellFlags.overline;

  /// Turned off on runs, and only on runs. A ligature would draw two cells'
  /// characters as one glyph of its own width, which puts the rest of the run
  /// off its columns, and the terminal's own idea of the cursor column does
  /// not change to match. Single glyphs have no neighbours to join with, so
  /// they are laid out exactly as before.
  static const _noLigatures = [
    FontFeature.disable('liga'),
    FontFeature.disable('clig'),
    FontFeature.disable('calt'),
    FontFeature.disable('dlig'),
  ];

  /// How far a run may end up from where painting it cell by cell would have
  /// put it, over the whole run, before it is rejected. Half a pixel, so no
  /// character can land in a different column than it would have.
  static const _gridTolerance = 0.5;

  /// Characters that may be drawn as part of a run.
  ///
  /// Two classes rather than one range because box drawing and block elements
  /// commonly come from a different fallback font than ASCII does. Both are one
  /// column wide and uniformly advanced in a terminal font, but keeping a run
  /// inside one class keeps a font boundary out of the middle of a paragraph,
  /// where the second font's metrics would move everything after it. It also
  /// keeps [_uncoalescableKinds] from writing off ASCII because a fallback
  /// font's box drawing did not measure up.
  static const _classAscii = 0;
  static const _classBoxDrawing = 1;

  /// The state of the run [_paintForegrounds] is accumulating. `-1` for none.
  var _runStart = -1;
  var _runArgb = 0;
  var _runFlags = 0;
  var _runClass = -1;
  final _runChars = <int>[];

  TerminalStyle get textStyle => _textStyle;
  TerminalStyle _textStyle;
  set textStyle(TerminalStyle value) {
    if (value == _textStyle) return;
    _textStyle = value;
    _cellSize = _measureCharSize();
    _clearFontDependentCaches();
  }

  TextScaler get textScaler => _textScaler;
  TextScaler _textScaler = TextScaler.linear(1.0);
  set textScaler(TextScaler value) {
    if (value == _textScaler) return;
    _textScaler = value;
    _cellSize = _measureCharSize();
    _clearFontDependentCaches();
  }

  /// The ratio the atlas rasterises at, so its sprites land on whole device
  /// pixels and can be sampled without filtering. Nothing else reads it: the
  /// grid is laid out in logical pixels.
  double get devicePixelRatio => _devicePixelRatio;
  double _devicePixelRatio;
  set devicePixelRatio(double value) {
    if (value == _devicePixelRatio) return;
    _devicePixelRatio = value;
    _discardAtlas();
  }

  TerminalTheme get theme => _theme;
  TerminalTheme _theme;
  set theme(TerminalTheme value) {
    if (value == _theme) return;
    _theme = value;
    _colorPalette = PaletteBuilder(value).build();
    _paletteArgb = _packPalette(_colorPalette);
    _foregroundArgb = value.foreground.toARGB32();
    _backgroundArgb = value.background.toARGB32();
    _glyphCache.clear();
    _runCache.clear();
    _clusterCache.clear();
  }

  Size _measureCharSize() {
    return CharMetricsCache.instance.measure(_textStyle, _textScaler);
  }

  /// The size of each character in the terminal.
  Size get cellSize => _cellSize;

  /// When the set of font available to the system changes, call this method to
  /// clear cached state related to font rendering.
  void clearFontCache() {
    CharMetricsCache.instance.clear();
    _cellSize = _measureCharSize();
    _clearFontDependentCaches();
  }

  /// [_uncoalescableKinds] is a verdict about the *font*, so it survives a
  /// theme change and only these three paths reset it.
  void _clearFontDependentCaches() {
    _discardAtlas();
    _glyphCache.clear();
    _runCache.clear();
    _clusterCache.clear();
    _uncoalescableKinds.clear();
  }

  static List<int> _packPalette(List<Color> palette) {
    return List<int>.unmodifiable(palette.map((color) => color.toARGB32()));
  }

  /// Paints the cursor based on the current cursor type.
  void paintCursor(
    Canvas canvas,
    Offset offset, {
    required TerminalCursorType cursorType,
    bool hasFocus = true,
  }) {
    final paint = Paint()
      ..color = _theme.cursor
      ..strokeWidth = 1;

    if (!hasFocus) {
      paint.style = PaintingStyle.stroke;
      canvas.drawRect(offset & _cellSize, paint);
      return;
    }

    switch (cursorType) {
      case TerminalCursorType.block:
        paint.style = PaintingStyle.fill;
        canvas.drawRect(offset & _cellSize, paint);
        return;
      case TerminalCursorType.underline:
        final y = offset.dy + _cellSize.height - 1;
        return canvas.drawLine(
          Offset(offset.dx, y),
          Offset(offset.dx + _cellSize.width, y),
          paint,
        );
      case TerminalCursorType.verticalBar:
        return canvas.drawLine(
          offset,
          Offset(offset.dx, offset.dy + _cellSize.height),
          paint,
        );
    }
  }

  @pragma('vm:prefer-inline')
  /// [length] is in cells and may be fractional: the selection highlight is
  /// drawn part way between two of them while it is catching up with a drag.
  void paintHighlight(Canvas canvas, Offset offset, double length, Color color) {
    final endOffset = offset.translate(
      length * _cellSize.width,
      _cellSize.height,
    );

    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;

    canvas.drawRect(Rect.fromPoints(offset, endOffset), paint);
  }

  /// Paints [line] to [canvas] at [offset]. The x offset of [offset] is usually
  /// 0, and the y offset is the top of the line.
  ///
  /// Backgrounds are painted for the whole line before any glyph is. Painting
  /// cell by cell used to interleave them, so a glyph wider than its cell,
  /// italic or a fallback font's, was clipped by the next cell's background.
  void paintLine(
    Canvas canvas,
    Offset offset,
    BufferLine line, {
    bool reverseDisplay = false,
  }) {
    _paintBackgrounds(canvas, offset, line, reverseDisplay);
    _paintForegrounds(canvas, offset, line, reverseDisplay);
    _flushSprites(canvas);
  }

  /// Fills each maximal span of cells sharing a background colour with one
  /// rect.
  ///
  /// Cells are compared by the raw field their colour comes from rather than by
  /// the resolved [Color], which keeps this from allocating one per cell. The
  /// cost is that a span can be split where it did not have to be, since an
  /// inverse cell and a plain one can resolve to the same colour by different
  /// routes,
  /// which draws one extra rect and nothing else.
  void _paintBackgrounds(
    Canvas canvas,
    Offset offset,
    BufferLine line,
    bool reverseDisplay,
  ) {
    var start = -1;
    var startSource = 0;
    var startInverse = false;
    var color = const Color(0x00000000);

    for (var i = 0; i < line.length; i++) {
      // Read only the fields this pass needs. Filling a CellData costs four
      // reads and four writes per cell, and this runs over every cell of every
      // visible line on every frame.
      final inverse =
          (line.getAttributes(i) & CellFlags.inverse != 0) ^ reverseDisplay;
      final source = inverse ? line.getForeground(i) : line.getBackground(i);

      // A plain cell with no background of its own is left as the terminal's
      // background rather than filled.
      final fills =
          inverse || (source & CellColor.typeMask) != CellColor.normal;

      if (start >= 0) {
        if (fills && inverse == startInverse && source == startSource) {
          continue;
        }
        _backgroundPaint.color = color;
        canvas.drawRect(_spanRect(offset, start, i), _backgroundPaint);
        start = -1;
      }

      if (fills) {
        start = i;
        startSource = source;
        startInverse = inverse;
        color = Color(
          inverse
              ? _resolveForegroundArgb(source)
              : _resolveBackgroundArgb(source),
        );
      }
    }

    if (start >= 0) {
      _backgroundPaint.color = color;
      canvas.drawRect(_spanRect(offset, start, line.length), _backgroundPaint);
    }
  }

  /// The rect covering cells `[start, end)` of the line at [offset].
  ///
  /// One pixel wider than the cells it covers, as painting a cell at a time
  /// was, so that rounding cannot leave a seam against the next span.
  @pragma('vm:prefer-inline')
  Rect _spanRect(Offset offset, int start, int end) {
    return Rect.fromLTWH(
      offset.dx + start * _cellSize.width,
      offset.dy,
      (end - start) * _cellSize.width + 1,
      _cellSize.height,
    );
  }

  /// Draws each maximal run of cells that can share one [Paragraph], and every
  /// remaining cell on its own.
  ///
  /// A cell joins a run only if it is one column wide and ASCII printable.
  /// Those are the characters a monospace font is relied on to advance exactly
  /// one cell for. Anything else, a wide character, a fallback font's glyph or
  /// the empty second half of a wide character, is drawn at its own column,
  /// where its width cannot move its neighbours.
  void _paintForegrounds(
    Canvas canvas,
    Offset offset,
    BufferLine line,
    bool reverseDisplay,
  ) {
    for (var i = 0; i < line.length; i++) {
      // As in [_paintBackgrounds], the fields are read one at a time rather
      // than through a CellData.
      final content = line.getContent(i);
      final charCode = content & CellContent.codepointMask;
      final flags = line.getAttributes(i);

      if (charCode == 0 || flags & CellFlags.invisible != 0) {
        _flushRun(canvas, offset);
        continue;
      }

      final layoutFlags = flags & _layoutFlags;
      final inverse = (flags & CellFlags.inverse != 0) ^ reverseDisplay;
      final argb = _foregroundArgbOf(
        flags,
        inverse ? line.getBackground(i) : line.getForeground(i),
        inverse,
      );

      // A cluster is drawn on its own: its glyph is composed from more than one
      // code point and need not advance by one cell, so a run cannot hold it.
      if (content & CellContent.clusterFlag != 0) {
        _flushRun(canvas, offset);
        _paintCluster(
          canvas,
          offset.translate(i * _cellSize.width, 0),
          line.getCluster(i) ?? String.fromCharCode(charCode),
          argb,
          layoutFlags,
        );
        continue;
      }

      final charClass = content >> CellContent.widthShift == 1
          ? _charClass(charCode)
          : -1;
      final joinable =
          charClass >= 0 &&
          !_uncoalescableKinds.contains(_runKind(layoutFlags, charClass));

      if (!joinable) {
        _flushRun(canvas, offset);
        _paintGlyph(
          canvas,
          offset.translate(i * _cellSize.width, 0),
          _glyphChar(charCode, layoutFlags),
          argb,
          layoutFlags,
          cells: content >> CellContent.widthShift,
        );
        continue;
      }

      if (_runStart >= 0 &&
          argb == _runArgb &&
          layoutFlags == _runFlags &&
          charClass == _runClass) {
        _runChars.add(_glyphChar(charCode, layoutFlags));
        continue;
      }

      _flushRun(canvas, offset);
      _runStart = i;
      _runArgb = argb;
      _runFlags = layoutFlags;
      _runClass = charClass;
      _runChars
        ..clear()
        ..add(_glyphChar(charCode, layoutFlags));
    }

    _flushRun(canvas, offset);
  }

  /// Draws the accumulated run, if any, and clears it.
  void _flushRun(Canvas canvas, Offset lineOffset) {
    if (_runStart < 0) return;

    final start = _runStart;
    final argb = _runArgb;
    final flags = _runFlags;
    final charClass = _runClass;
    _runStart = -1;

    final offset = lineOffset.translate(start * _cellSize.width, 0);

    if (_runChars.length == 1) {
      _paintGlyph(canvas, offset, _runChars.first, argb, flags);
      return;
    }

    final text = String.fromCharCodes(_runChars);
    final key = (text, argb, flags);
    var paragraph = _runCache.getLayoutFromCache(key);

    if (paragraph == null) {
      paragraph = buildParagraph(
        text,
        _styleFor(argb, flags, fontFeatures: _noLigatures),
        _textScaler,
      );

      // The run assumes every character advanced by exactly one cell. If the
      // font disagrees, the text would sit progressively further from its
      // columns, so give up on this style and draw the run cell by cell.
      final expected = _runChars.length * _cellSize.width;
      if ((paragraph.maxIntrinsicWidth - expected).abs() > _gridTolerance) {
        paragraph.dispose();
        _uncoalescableKinds.add(_runKind(flags, charClass));

        for (var i = 0; i < _runChars.length; i++) {
          _paintGlyph(
            canvas,
            lineOffset.translate((start + i) * _cellSize.width, 0),
            _runChars[i],
            argb,
            flags,
          );
        }
        return;
      }

      _runCache.put(key, paragraph);
    }

    canvas.drawParagraph(paragraph, offset);
  }

  /// Paints the character in the cell represented by [cellData] to [canvas] at
  /// [offset].
  @pragma('vm:prefer-inline')
  void paintCellForeground(
    Canvas canvas,
    Offset offset,
    CellData cellData, {
    bool reverseDisplay = false,
  }) {
    final charCode = cellData.content & CellContent.codepointMask;
    if (charCode == 0) return;

    final flags = cellData.flags;
    if (flags & CellFlags.invisible != 0) return;

    final layoutFlags = flags & _layoutFlags;
    final argb = _cellForegroundArgb(cellData, reverseDisplay);

    final cluster = cellData.cluster;
    if (cluster != null) {
      _paintCluster(canvas, offset, cluster, argb, layoutFlags);
      return;
    }

    _paintGlyph(
      canvas,
      offset,
      _glyphChar(charCode, layoutFlags),
      argb,
      layoutFlags,
      cells: cellData.content >> CellContent.widthShift,
    );

    // Unlike [paintLine] there is no line to flush at the end of.
    _flushSprites(canvas);
  }

  /// Draws one cell whose text is [text], a base character and the marks that
  /// belong to it.
  ///
  /// Unlike [_paintGlyph] this does not substitute a non-breaking space for an
  /// underlined space: a cluster's base is never a space, since a mark attaches
  /// to whatever character it followed and a space with marks is not something
  /// a program writes.
  @pragma('vm:prefer-inline')
  void _paintCluster(
    Canvas canvas,
    Offset offset,
    String text,
    int argb,
    int layoutFlags,
  ) {
    final key = (text, argb, layoutFlags);
    final paragraph =
        _clusterCache.getLayoutFromCache(key) ??
        _clusterCache.performAndCacheLayout(
          text,
          _styleFor(argb, layoutFlags),
          _textScaler,
          key,
        );

    canvas.drawParagraph(paragraph, offset);
  }

  /// Draws one cell's glyph at [offset], through the atlas where it can and a
  /// laid out [Paragraph] otherwise.
  ///
  /// [cells] is how many columns the glyph occupies, which the atlas needs
  /// because a sprite is placed by its own width rather than by the grid.
  @pragma('vm:prefer-inline')
  void _paintGlyph(
    Canvas canvas,
    Offset offset,
    int charCode,
    int argb,
    int layoutFlags, {
    int cells = 1,
  }) {
    if (layoutFlags & _decorationFlags == 0) {
      final atlas = _atlas ??= GlyphAtlas(
        cellSize: _cellSize,
        devicePixelRatio: _devicePixelRatio,
        textScaler: _textScaler,
        styleFor: (flags) => _styleFor(_opaqueWhite, flags),
      );

      final sprite = atlas.sprite((charCode, layoutFlags), cells);
      if (sprite != null) {
        _addSprite(sprite, offset, argb);
        return;
      }
    }

    final key = (charCode, argb, layoutFlags);
    final paragraph =
        _glyphCache.getLayoutFromCache(key) ??
        _glyphCache.performAndCacheLayout(
          String.fromCharCode(charCode),
          _styleFor(argb, layoutFlags),
          _textScaler,
          key,
        );

    canvas.drawParagraph(paragraph, offset);
  }

  /// The colour the atlas rasterises in. Opaque, so a sprite's alpha is the
  /// glyph's coverage and nothing else, which is what the tint needs.
  static const _opaqueWhite = 0xFFFFFFFF;

  @pragma('vm:prefer-inline')
  void _addSprite(AtlasSprite sprite, Offset offset, int argb) {
    if (_spriteCount == _spriteColors.length) {
      _growSpriteBuffers();
    }

    final i = _spriteCount++;
    final at = i * 4;

    // No rotation, and a scale that undoes the ratio the sprite was rasterised
    // at, so it covers the same device pixels it was drawn into.
    //
    // The destination is rounded to a whole device pixel first. The sprite is
    // a whole number of pixels holding a glyph rasterised at a whole pixel, so
    // landing it on one is a copy; landing it between two is a resample, and
    // the difference is the whole reason a terminal's text looks sharp or
    // soft. A cell can end up half a device pixel from its exact column, which
    // is smaller than the step the rasteriser would have rounded it to.
    _spriteTransforms[at] = 1 / _devicePixelRatio;
    _spriteTransforms[at + 1] = 0;
    _spriteTransforms[at + 2] =
        ((offset.dx * _devicePixelRatio).roundToDouble() - sprite.margin) /
        _devicePixelRatio;
    _spriteTransforms[at + 3] =
        ((offset.dy * _devicePixelRatio).roundToDouble() - sprite.margin) /
        _devicePixelRatio;

    final source = sprite.source;
    _spriteRects[at] = source.left;
    _spriteRects[at + 1] = source.top;
    _spriteRects[at + 2] = source.right;
    _spriteRects[at + 3] = source.bottom;

    _spriteColors[i] = argb;
  }

  /// Draws the sprites collected for the line, if any.
  ///
  /// They land above the paragraphs drawn on the way through the line, rather
  /// than interleaved with them. Only a glyph reaching outside its own column
  /// can tell, and the atlas is what draws the ordinary cells, so this puts the
  /// exception underneath rather than the rule.
  void _flushSprites(Canvas canvas) {
    if (_spriteCount == 0) return;

    final count = _spriteCount;
    _spriteCount = 0;

    final image = _atlas?.image;
    if (image == null) return;

    canvas.drawRawAtlas(
      image,
      Float32List.sublistView(_spriteTransforms, 0, count * 4),
      Float32List.sublistView(_spriteRects, 0, count * 4),
      Int32List.sublistView(_spriteColors, 0, count),
      // The sprite is the source and the colour the destination, so this reads
      // "keep the colour where the glyph covers". `srcIn`, which is the way
      // round it looks like it should be, draws the sprite untinted.
      BlendMode.dstIn,
      null,
      _atlasPaint,
    );
  }

  void _growSpriteBuffers() {
    final size = _spriteColors.length * 2;
    _spriteTransforms = Float32List(size * 4)..setAll(0, _spriteTransforms);
    _spriteRects = Float32List(size * 4)..setAll(0, _spriteRects);
    _spriteColors = Int32List(size)..setAll(0, _spriteColors);
  }

  void _discardAtlas() {
    _atlas?.dispose();
    _atlas = null;
    _spriteCount = 0;
  }

  /// Releases the atlas texture. The paragraph caches are left alone: a
  /// [Paragraph] recorded into a [Picture] is kept alive by it, and disposing
  /// one the compositor may still be holding is not this class's call to make.
  void dispose() {
    _discardAtlas();
  }

  /// Which class of run [charCode] may join, or -1 if it has to be drawn on its
  /// own. See [_classAscii].
  @pragma('vm:prefer-inline')
  int _charClass(int charCode) {
    if (charCode >= 0x20 && charCode <= 0x7E) return _classAscii;
    // Box Drawing and Block Elements, which is what a TUI's frames and meters
    // are made of and so most of what is on screen while one is running.
    if (charCode >= 0x2500 && charCode <= 0x259F) return _classBoxDrawing;
    return -1;
  }

  /// Identifies what a run is made of, for [_uncoalescableKinds]. The layout
  /// flags occupy the low bits, so the class is moved clear of them.
  @pragma('vm:prefer-inline')
  int _runKind(int layoutFlags, int charClass) {
    return layoutFlags | (charClass << 16);
  }

  /// Flutter does not draw an underline below a space unless it sits between
  /// other regular characters, so an underlined space becomes a non-breaking
  /// space, below which it does.
  @pragma('vm:prefer-inline')
  int _glyphChar(int charCode, int layoutFlags) {
    if (charCode == 0x20 && layoutFlags & CellFlags.underline != 0) {
      return 0xA0;
    }
    return charCode;
  }

  @pragma('vm:prefer-inline')
  TextStyle _styleFor(
    int argb,
    int layoutFlags, {
    List<FontFeature>? fontFeatures,
  }) {
    return _textStyle.toTextStyle(
      color: Color(argb),
      bold: layoutFlags & CellFlags.bold != 0,
      italic: layoutFlags & CellFlags.italic != 0,
      underline: layoutFlags & CellFlags.underline != 0,
      strikethrough: layoutFlags & CellFlags.strikethrough != 0,
      overline: layoutFlags & CellFlags.overline != 0,
      fontFeatures: fontFeatures,
    );
  }

  /// The colour a cell's glyph is painted in, packed as ARGB32.
  ///
  /// `inverse` and `reverseDisplay` pick which of the cell's two colours is
  /// used, and `faint` halves its alpha, so all three end here rather than in
  /// the glyph key.
  @pragma('vm:prefer-inline')
  int _cellForegroundArgb(CellData cellData, bool reverseDisplay) {
    final inverse = (cellData.flags & CellFlags.inverse != 0) ^ reverseDisplay;
    return _foregroundArgbOf(
      cellData.flags,
      inverse ? cellData.background : cellData.foreground,
      inverse,
    );
  }

  /// [_cellForegroundArgb] with the cell's fields already read: [source] is
  /// whichever of the two colours `inverse` selected.
  @pragma('vm:prefer-inline')
  int _foregroundArgbOf(int flags, int source, bool inverse) {
    final argb = inverse
        ? _resolveBackgroundArgb(source)
        : _resolveForegroundArgb(source);

    if (flags & CellFlags.faint == 0) return argb;

    // The alpha the old per-cell path reached through
    // `Color.withValues(alpha: 0.5)`, quantised: 0x80 is 0.502 rather than
    // 0.500, which is under a step of an 8-bit channel.
    return (argb & 0x00FFFFFF) | 0x80000000;
  }

  /// Get the effective foreground color for a cell from information encoded in
  /// [cellColor].
  @pragma('vm:prefer-inline')
  Color resolveForegroundColor(int cellColor) {
    return Color(_resolveForegroundArgb(cellColor));
  }

  /// Get the effective background color for a cell from information encoded in
  /// [cellColor].
  @pragma('vm:prefer-inline')
  Color resolveBackgroundColor(int cellColor) {
    return Color(_resolveBackgroundArgb(cellColor));
  }

  @pragma('vm:prefer-inline')
  int _resolveForegroundArgb(int cellColor) {
    final colorValue = cellColor & CellColor.valueMask;

    switch (cellColor & CellColor.typeMask) {
      case CellColor.normal:
        return _foregroundArgb;
      case CellColor.named:
      case CellColor.palette:
        return _paletteArgb[colorValue];
      case CellColor.rgb:
      default:
        return colorValue | 0xFF000000;
    }
  }

  @pragma('vm:prefer-inline')
  int _resolveBackgroundArgb(int cellColor) {
    final colorValue = cellColor & CellColor.valueMask;

    switch (cellColor & CellColor.typeMask) {
      case CellColor.normal:
        return _backgroundArgb;
      case CellColor.named:
      case CellColor.palette:
        return _paletteArgb[colorValue];
      case CellColor.rgb:
      default:
        return colorValue | 0xFF000000;
    }
  }
}
