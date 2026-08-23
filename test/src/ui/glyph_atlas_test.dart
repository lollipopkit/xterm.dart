import 'dart:io';
import 'dart:ui';

import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xterm/src/terminal.dart';
import 'package:xterm/src/ui/glyph_atlas.dart';
import 'package:xterm/src/ui/painter.dart';
import 'package:xterm/src/ui/terminal_text_style.dart';
import 'package:xterm/src/ui/themes.dart';

// The atlas rasterises a glyph once and tints it when it draws, where the
// paragraph path lays the glyph out in its colour. That is not something the
// draw calls can say anything about; it is a claim about pixels, so the tests
// below render both and compare the images.
//
// Not byte for byte, and the reason is worth stating: the rasteriser adjusts a
// glyph's contrast for the colour it is drawn in, so a white mask tinted red
// has slightly different edge pixels from red text. It is confined to the
// partially covered pixels, and no atlas can avoid it. What [_expectSameInk]
// asserts is therefore the part that *is* exact: a pixel the reference covers
// fully is the same colour, and a pixel it does not cover at all is untouched.
// That is enough to catch the mistakes an atlas actually makes: a sprite off
// by a pixel, at the wrong scale, or tinted with the wrong colour.
//
// It cannot check a real font. Every glyph here is the FlutterTest font's
// identical box, with no overhang and no hinting. What it checks is the
// arithmetic, at every device pixel ratio.

/// A real monospace font, so the tests below are not all asking about the same
/// square box.
///
/// `flutter test` lays text out in the FlutterTest font, whose every glyph is
/// an identical rectangle that exactly fills its cell. That is the wrong shape
/// for almost everything an atlas can get wrong: nothing overhangs, nothing is
/// hinted, and a slot that clipped its glyph would clip nothing. Cascadia is
/// already in this repository for the example app, and loading it is what lets
/// the comparison see a real `f`.
const _realFont = 'CascadiaTest';

void main() {
  setUpAll(() async {
    final bytes = File('example/fonts/CascadiaMonoPL.ttf').readAsBytesSync();
    await (FontLoader(_realFont)
          ..addFont(Future.value(ByteData.sublistView(bytes))))
        .load();
  });

  group('the atlas draws what the paragraph path drew', () {
    // Every cell a colour of its own, so none of them coalesces into a run and
    // all of them take the atlas.
    const line =
        '\x1b[38;2;255;0;0mA'
        '\x1b[38;2;0;255;0mB'
        '\x1b[38;2;0;0;255mC'
        '\x1b[38;2;255;255;0mD';

    const expected = [
      (0, 'A', 0xFFFF0000),
      (1, 'B', 0xFF00FF00),
      (2, 'C', 0xFF0000FF),
      (3, 'D', 0xFFFFFF00),
    ];

    for (final dpr in const [1.0, 2.0, 3.0]) {
      test('at a device pixel ratio of $dpr', () async {
        _expectSameInk(
          await _paint(line, dpr: dpr),
          await _reference(expected, dpr: dpr),
        );
      });
    }

    test('when the cell width is not a whole number of pixels', () async {
      // The case the rounding exists for. At the default scale the test font's
      // cell is exactly 13 logical pixels, so every column already lands on a
      // device pixel and the rounding is a no-op; at 1.1 the cell is 14.3 and
      // it is not.
      _expectSameInk(
        await _paint(line, dpr: 2, scale: 1.1),
        await _reference(expected, dpr: 2, scale: 1.1),
      );
    });

    test('for a wide character, which spans two columns', () async {
      _expectSameInk(
        await _paint('\x1b[38;2;255;0;0m中', dpr: 2),
        await _reference(const [(0, '中', 0xFFFF0000)], dpr: 2),
      );
    });

    test('for a faint cell, whose colour is half transparent', () async {
      // Tinting is a blend, so a colour that is not opaque is where the two
      // paths would come apart.
      _expectSameInk(
        await _paint('\x1b[2m\x1b[38;2;255;0;0mA', dpr: 2),
        await _reference(const [(0, 'A', 0x80FF0000)], dpr: 2),
      );
    });

    test('and a blank reference does not pass', () async {
      // [_expectSameInk] only constrains the pixels the reference covers, so a
      // reference that covered none would pass against anything. This is what
      // says it does not.
      final reference = await _reference(expected, dpr: 1);

      expect(
        () => _expectSameInk(_blank(reference), reference),
        throwsA(isA<TestFailure>()),
      );
    });

    test('and a sprite one column out does not pass', () async {
      final painted = await _paint(line, dpr: 1);
      final shifted = await _reference(const [
        (1, 'A', 0xFFFF0000),
        (2, 'B', 0xFF00FF00),
        (3, 'C', 0xFF0000FF),
        (4, 'D', 0xFFFFFF00),
      ], dpr: 1);

      expect(
        () => _expectSameInk(painted, shifted),
        throwsA(isA<TestFailure>()),
      );
    });
  });

  // What the box glyph could not be asked. Every case here is one the atlas is
  // capable of getting wrong on a real font and could not get wrong on a
  // rectangle that exactly fills its cell.
  group('with a real font', () {
    Future<void> sameAs(String written, List<(int, String, int)> cells) async {
      _expectSameInk(
        await _paint(written, dpr: 2, family: _realFont),
        await _reference(cells, dpr: 2, family: _realFont),
      );
    }

    test('plain letters', () async {
      // Narrow and wide ink in the same run of cells, which a monospace font
      // advances identically and draws nothing like.
      await sameAs(
        '\x1b[38;2;255;0;0mi\x1b[38;2;0;255;0mW\x1b[38;2;0;0;255ml',
        const [
          (0, 'i', 0xFFFF0000),
          (1, 'W', 0xFF00FF00),
          (2, 'l', 0xFF0000FF),
        ],
      );
    });

    test('an italic f, whose ink leaves its column', () async {
      // The reason the slot carries a margin. A slot sized to the cell would
      // cut the tail off here, and the reference draws it whole.
      _expectSameInk(
        await _paint('\x1b[3m\x1b[38;2;255;0;0mf', dpr: 2, family: _realFont),
        await _reference(
          const [(0, 'f', 0xFFFF0000)],
          dpr: 2,
          family: _realFont,
          italic: true,
        ),
      );
    });

    test('a box drawing vertical, which leaves the cell top and bottom', () {
      // The vertical half of the same claim, and the case that makes it
      // necessary rather than tidy. A box drawing character overflows its line
      // box on purpose, because that is the only way `\u2502` joins up with the
      // one on the row below. Measured against this font's cell of 7.6 by 16:
      // three logical pixels above and two below, where a letter with an accent
      // overflows by none at all.
      return sameAs(
        '\x1b[38;2;255;0;0m\u2502',
        const [(0, '\u2502', 0xFFFF0000)],
      );
    });

    test('a letter with an accent, which turns out not to overflow', () async {
      await sameAs('\x1b[38;2;255;0;0m\u00C5', const [(0, '\u00C5', 0xFFFF0000)]);
    });

    test('bold, which is a different entry and a wider glyph', () async {
      _expectSameInk(
        await _paint('\x1b[1m\x1b[38;2;255;0;0mB', dpr: 2, family: _realFont),
        await _reference(
          const [(0, 'B', 0xFFFF0000)],
          dpr: 2,
          family: _realFont,
          bold: true,
        ),
      );
    });

    test('a faint colour over a real antialiased edge', () async {
      await sameAs(
        '\x1b[2m\x1b[38;2;255;0;0mS',
        const [(0, 'S', 0x80FF0000)],
      );
    });

    test('and a sprite one column out still does not pass', () async {
      final painted = await _paint(
        '\x1b[38;2;255;0;0miWl',
        dpr: 2,
        family: _realFont,
      );
      final shifted = await _reference(
        const [(1, 'i', 0xFFFF0000), (2, 'W', 0xFFFF0000), (3, 'l', 0xFFFF0000)],
        dpr: 2,
        family: _realFont,
      );

      expect(
        () => _expectSameInk(painted, shifted),
        throwsA(isA<TestFailure>()),
      );
    });
  });

  group('when the device pixel ratio changes', () {
    // The atlas is rasterised at one ratio, so moving a window to a display
    // with another has to throw it away. Keeping it would draw sprites of the
    // wrong size, and keeping the *slots* while rebuilding at the new ratio
    // would draw them in the wrong places.
    const line =
        '\x1b[38;2;255;0;0mA'
        '\x1b[38;2;0;255;0mB'
        '\x1b[38;2;0;0;255mC';
    const expected = [
      (0, 'A', 0xFFFF0000),
      (1, 'B', 0xFF00FF00),
      (2, 'C', 0xFF0000FF),
    ];

    for (final (from, to) in const [(2.0, 3.0), (3.0, 1.0), (1.0, 2.0)]) {
      test('from $from to $to', () async {
        final painter = _painter(from, 1, _realFont);

        // Fill the atlas at the old ratio, then move.
        await _paint(line, dpr: from, family: _realFont, reuse: painter);
        painter.devicePixelRatio = to;

        _expectSameInk(
          await _paint(line, dpr: to, family: _realFont, reuse: painter),
          await _reference(expected, dpr: to, family: _realFont),
        );
      });
    }
  });

  group('GlyphAtlas', () {
    late GlyphAtlas atlas;

    setUp(() {
      atlas = GlyphAtlas(
        cellSize: const Size(8, 16),
        devicePixelRatio: 2,
        textScaler: TextScaler.noScaling,
        styleFor: (_) => const TextStyle(fontSize: 13),
      );
    });

    tearDown(() => atlas.dispose());

    test('the same key twice is one entry', () {
      final first = atlas.sprite((0x41, 0), 1);
      final second = atlas.sprite((0x41, 0), 1);

      expect(atlas.length, 1);
      expect(second!.source, first!.source);
    });

    test('entries do not overlap', () {
      final rects = [
        for (var char = 0x41; char < 0x51; char++)
          atlas.sprite((char, 0), 1)!.source,
      ];

      for (var i = 0; i < rects.length; i++) {
        for (var j = i + 1; j < rects.length; j++) {
          expect(
            rects[i].overlaps(rects[j]),
            isFalse,
            reason: '${rects[i]} overlaps ${rects[j]}',
          );
        }
      }
    });

    test('a slot carries a margin on every side', () {
      final narrow = atlas.sprite((0x41, 0), 1)!;
      final wide = atlas.sprite((0x4E00, 0), 2)!;

      // The cell is 8 by 16 at a ratio of 2, so 16 by 32 device pixels, and the
      // margin is a cell *width* on all four sides: 16.
      expect(narrow.margin, GlyphAtlas.padding * 16);
      expect(narrow.source.width, 16 + 2 * narrow.margin);
      expect(wide.source.width, 32 + 2 * narrow.margin);

      // Vertical too, or a glyph reaching above the line box is cut off where
      // drawing the paragraph straight to the canvas would have kept it.
      expect(narrow.source.height, 32 + 2 * narrow.margin);
      expect(wide.source.height, narrow.source.height);
    });

    test('the pen wraps rather than running off the edge', () {
      // Enough glyphs to fill more than one shelf: 2048 wide, 48 to a slot.
      for (var char = 0x41; char < 0x41 + 60; char++) {
        final sprite = atlas.sprite((char, 0), 1);
        expect(sprite, isNotNull);
        expect(sprite!.source.right, lessThanOrEqualTo(GlyphAtlas.maxDimension));
      }

      expect(atlas.length, 60);
    });

    test('a code point drawn in colour is refused', () {
      expect(atlas.sprite((0x1F600, 0), 2), isNull);
      expect(atlas.length, 0);
    });

    test('appending to the image gives what redrawing it would', () async {
      // The image is built by copying the previous one and drawing only what
      // is new, which is only correct because a slot is never moved once it is
      // handed out. Asking for the image between adds is what exercises that:
      // it bakes each glyph into its own generation.
      final incremental = GlyphAtlas(
        cellSize: const Size(8, 16),
        devicePixelRatio: 2,
        textScaler: TextScaler.noScaling,
        styleFor: (_) => const TextStyle(fontSize: 13),
      );
      final atOnce = GlyphAtlas(
        cellSize: const Size(8, 16),
        devicePixelRatio: 2,
        textScaler: TextScaler.noScaling,
        styleFor: (_) => const TextStyle(fontSize: 13),
      );

      for (var char = 0x41; char < 0x41 + 40; char++) {
        incremental.sprite((char, 0), 1);
        incremental.image;
        atOnce.sprite((char, 0), 1);
      }

      expect(
        await _bytesOf(incremental.image!),
        await _bytesOf(atOnce.image!),
      );

      incremental.dispose();
      atOnce.dispose();
    });

    test('the image grows only when a glyph is added', () {
      atlas.sprite((0x41, 0), 1);
      final first = atlas.image;

      atlas.sprite((0x41, 0), 1);
      expect(identical(atlas.image, first), isTrue);

      atlas.sprite((0x42, 0), 1);
      expect(identical(atlas.image, first), isFalse);
    });

    test('the image is null until something is in it', () {
      expect(atlas.image, isNull);
    });

    test('clearing empties it', () {
      atlas.sprite((0x41, 0), 1);
      atlas.clear();

      expect(atlas.length, 0);
      expect(atlas.image, isNull);
    });
  });
}

/// Renders one line through the painter and returns its pixels.
Future<Uint8List> _paint(
  String input, {
  required double dpr,
  double scale = 1,
  int columns = 8,
  String? family,
  TerminalPainter? reuse,
}) async {
  final terminal = Terminal(maxLines: 4);
  terminal.resize(columns, 2);
  terminal.write(input);

  final painter = reuse ?? _painter(dpr, scale, family);

  return _record(painter, dpr, columns, (canvas) {
    painter.paintLine(canvas, Offset.zero, terminal.buffer.lines[0]);
  });
}

/// Renders [cells] the way the painter's paragraph path would, as the image the
/// atlas has to reproduce.
///
/// Written out rather than derived from the painter: a reference that shares
/// the code under test agrees with it by construction. What each cell's colour
/// should be is asserted separately, in painter_test.dart.
///
/// The columns are snapped to whole device pixels, because that is what the
/// atlas does and it is deliberate; see [GlyphAtlas]. Comparing against an
/// unsnapped reference would be asserting that a glyph atlas does not round,
/// which is the one thing every glyph atlas does.
Future<Uint8List> _reference(
  List<(int, String, int)> cells, {
  required double dpr,
  double scale = 1,
  int columns = 8,
  String? family,
  bool bold = false,
  bool italic = false,
}) async {
  final painter = _painter(dpr, scale, family);

  return _record(painter, dpr, columns, (canvas) {
    for (final (column, text, argb) in cells) {
      final style = painter.textStyle.toTextStyle(
        color: Color(argb),
        bold: bold,
        italic: italic,
      );
      final builder = ParagraphBuilder(style.getParagraphStyle())
        ..pushStyle(style.getTextStyle(textScaler: painter.textScaler))
        ..addText(text);

      final paragraph = builder.build()
        ..layout(const ParagraphConstraints(width: double.infinity));

      canvas.drawParagraph(
        paragraph,
        Offset(
          (column * painter.cellSize.width * dpr).roundToDouble() / dpr,
          0,
        ),
      );
      paragraph.dispose();
    }
  });
}

TerminalPainter _painter(double dpr, double scale, String? family) {
  return TerminalPainter(
    theme: TerminalThemes.defaultTheme,
    textStyle: family == null
        ? const TerminalStyle()
        : TerminalStyle(fontFamily: family, fontFamilyFallback: [family]),
    textScaler: TextScaler.linear(scale),
    devicePixelRatio: dpr,
  );
}

/// Blank rows kept above and below the line, in logical pixels.
///
/// Without them the image is exactly one cell tall and anything drawn outside
/// the line box falls off it in *both* renders, so a slot that clipped a glyph
/// would compare equal to one that did not. A box drawing vertical overflows by
/// three pixels above and two below, which is the case that needs seeing.
///
/// Whole device pixels at every ratio the tests use, so it does not disturb the
/// rounding the atlas does.
const _bleed = 8.0;

Future<Uint8List> _record(
  TerminalPainter painter,
  double dpr,
  int columns,
  void Function(Canvas) draw,
) async {
  final recorder = PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.scale(dpr);
  canvas.translate(0, _bleed);
  draw(canvas);

  final picture = recorder.endRecording();
  final image = await picture.toImage(
    (painter.cellSize.width * columns * dpr).ceil(),
    ((painter.cellSize.height + 2 * _bleed) * dpr).ceil(),
  );
  picture.dispose();

  final bytes = await image.toByteData();
  image.dispose();

  return bytes!.buffer.asUint8List();
}

/// Asserts [actual] draws the same ink as [expected], allowing for the one
/// difference tinting a mask cannot avoid.
///
/// Coverage is what a sprite in the wrong place or at the wrong size gets
/// wrong, so a pixel the reference leaves untouched has to be untouched and one
/// it covers fully has to be covered fully. Colour may differ by the contrast
/// adjustment, which is a blend and so reaches even a pixel two glyphs together
/// cover completely.
void _expectSameInk(Uint8List actual, Uint8List expected) {
  expect(actual, hasLength(expected.length));

  for (var i = 0; i < expected.length; i += 4) {
    final alpha = expected[i + 3];

    if (alpha == 255 || alpha == 0) {
      expect(
        (actual[i + 3] - alpha).abs(),
        lessThanOrEqualTo(_coverageTolerance),
        reason: 'pixel ${i ~/ 4} is covered differently',
      );
    }

    for (var channel = 0; channel < 4; channel++) {
      expect(
        (actual[i + channel] - expected[i + channel]).abs(),
        lessThanOrEqualTo(_contrastTolerance),
        reason: 'pixel ${i ~/ 4} channel $channel is further out than the '
            'contrast adjustment accounts for',
      );
    }
  }
}

/// How far coverage may differ where the reference is fully on or fully off.
///
/// One step of 255, and only because the two rasterisers round a tinted blend
/// in a different order: the atlas multiplies the glyph's coverage by the
/// colour's alpha, and a faint cell makes that two multiplications instead of
/// one. Measured across the parity cases on Impeller, every case is exact
/// except the faint one, which is out by exactly this at two of three ratios.
///
/// It is not slack for a sprite in the wrong place. A glyph off by a pixel puts
/// hundreds of alpha steps into an edge that should be blank.
const _coverageTolerance = 1;

/// How far a partially covered pixel may differ.
///
/// Measured at 65 of 255 over the real font's antialiased edges, and 43 over
/// the test font's; the round number above both is there so a small change in
/// how Flutter rasterises text does not fail the suite. It is the loose half of
/// [_expectSameInk] and it is meant to be — the coverage rule above it is what
/// has teeth, and the cases that fail on purpose (a blank image, a sprite one
/// column out) fail on that rather than on this.
const _contrastTolerance = 96;

/// [pixels] with nothing drawn, for the test that says a blank image fails.
Uint8List _blank(Uint8List pixels) => Uint8List(pixels.length);

Future<Uint8List> _bytesOf(Image image) async {
  return (await image.toByteData())!.buffer.asUint8List();
}
