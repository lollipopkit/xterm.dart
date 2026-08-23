import 'dart:io';
import 'dart:ui';

import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xterm/src/terminal.dart';
import 'package:xterm/src/ui/painter.dart';
import 'package:xterm/src/ui/terminal_text_style.dart';
import 'package:xterm/src/ui/themes.dart';

// The glyph atlas rasterises without a colour and tints when it draws, so a
// code point the font draws in colour of its own has to keep the paragraph
// path or it comes out as a solid silhouette. `GlyphAtlas.wants` is what
// decides, and the rest of the suite can only check that it routes the cell
// somewhere else — not that colour actually survives the trip, because no font
// available to `flutter test` has a colour glyph to lose.
//
// One is available on macOS. It is a system font, so it cannot be committed and
// is not there on CI; this file skips itself when it is absent rather than
// pretending the platform is the same everywhere.
//
// What it costs: the font is nearly 200 MB, which is why this is its own file
// rather than another group in painter_test.

const _emojiFont = '/System/Library/Fonts/Apple Color Emoji.ttc';

const _family = 'AppleColorEmojiTest';

/// U+1F600 GRINNING FACE, Emoji_Presentation, drawn in yellows and browns.
const _emoji = '\u{1F600}';

void main() {
  setUpAll(() async {
    if (!File(_emojiFont).existsSync()) return;
    await (FontLoader(_family)
          ..addFont(
            Future.value(
              ByteData.sublistView(File(_emojiFont).readAsBytesSync()),
            ),
          ))
        .load();
  });

  test('a colour emoji keeps its colours through the painter', () async {
    final colours = await _coloursOf(_emoji);

    // Measured at 1113 with the rule in place and 6 with it removed, so the
    // threshold sits far from both. Six rather than one because tinting still
    // leaves a few blended values along the antialiased edge; what it does not
    // leave is a face.
    expect(
      colours.length,
      greaterThan(64),
      reason: 'the emoji was flattened to ${colours.length} colour(s)',
    );
  }, skip: File(_emojiFont).existsSync() ? false : 'no colour font on this host');

  test('a letter in the same font is a single colour, as a control', () async {
    // Says the count above measures the glyph rather than the antialiasing:
    // this one is drawn in one colour and comes back as one colour.
    final colours = await _coloursOf('A');

    expect(colours.length, lessThanOrEqualTo(1));
  }, skip: File(_emojiFont).existsSync() ? false : 'no colour font on this host');
}

/// The distinct fully opaque colours in a painted cell, which is how many the
/// glyph kept.
Future<Set<int>> _coloursOf(String text) async {
  final terminal = Terminal(maxLines: 4);
  terminal.resize(4, 2);
  terminal.write('\x1b[38;2;255;0;0m$text');

  final painter = TerminalPainter(
    theme: TerminalThemes.defaultTheme,
    textStyle: const TerminalStyle(
      fontFamily: _family,
      fontFamilyFallback: [_family],
      fontSize: 24,
    ),
    textScaler: TextScaler.noScaling,
    devicePixelRatio: 2,
  );

  final recorder = PictureRecorder();
  final canvas = Canvas(recorder)..scale(2);
  painter.paintLine(canvas, Offset.zero, terminal.buffer.lines[0]);

  final picture = recorder.endRecording();
  final image = await picture.toImage(
    (painter.cellSize.width * 4 * 2).ceil(),
    (painter.cellSize.height * 2).ceil(),
  );
  picture.dispose();

  final pixels = (await image.toByteData())!.buffer.asUint8List();
  image.dispose();

  final colours = <int>{};
  for (var i = 0; i < pixels.length; i += 4) {
    if (pixels[i + 3] < 250) continue;
    colours.add((pixels[i] << 16) | (pixels[i + 1] << 8) | pixels[i + 2]);
  }
  return colours;
}
