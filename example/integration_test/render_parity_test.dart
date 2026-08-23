// Runs the paint-path pixel comparison on the device's own rasteriser.
//
//   flutter test integration_test/render_parity_test.dart -d macos
//   flutter test integration_test/render_parity_test.dart -d <ios device>
//
// `test/src/ui/glyph_atlas_test.dart` in the package makes the same comparison,
// but `flutter test` runs it in `flutter_tester`, which rasterises with Skia in
// software. A shipped app does not: on macOS and iOS the engine reports
//
//   Using the Impeller rendering backend (MetalSDF).
//
// and `drawRawAtlas` is a different piece of code there than the one the unit
// tests exercise. This file is the same assertions on the backend that actually
// draws, which is the only part of the change a device was still needed for.
//
// It lives in the example rather than the package because integration tests
// need an app to run inside, and it repeats the harness rather than sharing it
// because the example is a separate package and cannot import the package's
// own tests. The cases are the handful where the two paths could disagree, not
// the whole unit suite.

import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
// The painter is not on the package's export surface, and should not be moved
// onto it to satisfy a test. This file is part of the package's own
// verification rather than a consumer of it.
// ignore: implementation_imports
import 'package:xterm/src/ui/painter.dart';
import 'package:xterm/xterm.dart';

/// Declared in the example's pubspec, so it is registered without a
/// [FontLoader]. A real font matters for the same reason it does in the unit
/// tests: the default one is a rectangle that fills its cell exactly, and
/// almost nothing an atlas gets wrong is visible on that.
const _family = 'Cascadia Mono';

/// Blank rows above and below the line, so ink outside the line box is inside
/// the image. A box drawing vertical overflows by three pixels above and two
/// below, and without this it falls off both renders and compares equal.
const _bleed = 8.0;

const _columns = 8;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // Each pair is what one line of the terminal is told to print, and the cells
  // that should come out of it. Every cell has a colour of its own so none of
  // them coalesces into a run and all of them take the atlas; the reference
  // draws the same glyphs as paragraphs, which is the path a run uses.
  const cases = <(String, String, List<(int, String, int)>, bool, bool)>[
    (
      'letters of different weight',
      '\x1b[38;2;255;0;0mi\x1b[38;2;0;255;0mW\x1b[38;2;0;0;255ml',
      [(0, 'i', 0xFFFF0000), (1, 'W', 0xFF00FF00), (2, 'l', 0xFF0000FF)],
      false,
      false,
    ),
    (
      'a box drawing vertical, which leaves the cell top and bottom',
      '\x1b[38;2;255;0;0m│',
      [(0, '│', 0xFFFF0000)],
      false,
      false,
    ),
    (
      'an italic f, whose ink leaves its column',
      '\x1b[3m\x1b[38;2;255;0;0mf',
      [(0, 'f', 0xFFFF0000)],
      false,
      true,
    ),
    (
      'bold',
      '\x1b[1m\x1b[38;2;255;0;0mB',
      [(0, 'B', 0xFFFF0000)],
      true,
      false,
    ),
    (
      'a faint colour, which tints through a half transparent blend',
      '\x1b[2m\x1b[38;2;255;0;0mS',
      [(0, 'S', 0x80FF0000)],
      false,
      false,
    ),
  ];

  for (final dpr in const [1.0, 2.0, 3.0]) {
    for (final (name, written, expected, bold, italic) in cases) {
      testWidgets('$name, at a device pixel ratio of $dpr', (tester) async {
        await tester.runAsync(() async {
          _expectSameInk(
            await _paint(written, dpr),
            await _reference(expected, dpr, bold: bold, italic: italic),
          );
        });
      });
    }
  }
}

TerminalPainter _painter(double dpr) {
  return TerminalPainter(
    theme: TerminalThemes.defaultTheme,
    textStyle: const TerminalStyle(
      fontFamily: _family,
      fontFamilyFallback: [_family],
    ),
    textScaler: TextScaler.noScaling,
    devicePixelRatio: dpr,
  );
}

Future<Uint8List> _paint(String input, double dpr) async {
  final terminal = Terminal(maxLines: 4);
  terminal.resize(_columns, 2);
  terminal.write(input);

  final painter = _painter(dpr);

  return _record(painter, dpr, (canvas) {
    painter.paintLine(canvas, Offset.zero, terminal.buffer.lines[0]);
  });
}

Future<Uint8List> _reference(
  List<(int, String, int)> cells,
  double dpr, {
  bool bold = false,
  bool italic = false,
}) async {
  final painter = _painter(dpr);

  return _record(painter, dpr, (canvas) {
    for (final (column, text, argb) in cells) {
      final style = painter.textStyle.toTextStyle(
        color: Color(argb),
        bold: bold,
        italic: italic,
      );

      final paragraph =
          (ParagraphBuilder(style.getParagraphStyle())
                ..pushStyle(style.getTextStyle(textScaler: painter.textScaler))
                ..addText(text))
              .build()
            ..layout(const ParagraphConstraints(width: double.infinity));

      // Snapped the way the atlas snaps, because that is deliberate: a sprite
      // drawn between two device pixels is resampled rather than copied.
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

Future<Uint8List> _record(
  TerminalPainter painter,
  double dpr,
  void Function(Canvas) draw,
) async {
  final recorder = PictureRecorder();
  final canvas = Canvas(recorder)
    ..scale(dpr)
    ..translate(0, _bleed);
  draw(canvas);

  final picture = recorder.endRecording();
  final image = await picture.toImage(
    (painter.cellSize.width * _columns * dpr).ceil(),
    ((painter.cellSize.height + 2 * _bleed) * dpr).ceil(),
  );
  picture.dispose();

  final bytes = await image.toByteData();
  image.dispose();

  return bytes!.buffer.asUint8List();
}

/// Coverage is what a sprite in the wrong place or at the wrong size gets
/// wrong, so a pixel the reference leaves untouched has to be untouched and one
/// it covers fully has to be covered fully. Colour may differ by the contrast
/// adjustment the rasteriser makes for the colour it is drawing in, which is a
/// blend and so reaches even a pixel two glyphs together cover completely.
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

/// As in the unit tests, where it was measured at 65 of 255 over real
/// antialiased edges. Impeller may not land on the same number, and if it needs
/// a different one that is itself worth knowing rather than papering over.
const _contrastTolerance = 96;
