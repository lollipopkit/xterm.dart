import 'package:flutter/cupertino.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xterm/xterm.dart';

// The selection toolbar: what it is built out of, and when it appears.
//
// Flutter puts nothing at all in a text selection menu - not even copy - until
// it knows whether the clipboard has anything to paste, so every test here has
// to say what the clipboard would answer.

/// How long the mocked platform takes to say whether the clipboard has
/// anything in it. Until it does the status is unknown, which is the state a
/// menu can be asked for in and find nothing to show.
///
/// A delay rather than a failure: `ClipboardStatusNotifier` reports a failed
/// query through [FlutterError], and a reported error fails the test on its
/// own before any of this can be looked at.
Duration _clipboardDelay = Duration.zero;

void main() {
  setUp(() {
    _clipboardDelay = Duration.zero;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.hasStrings') {
        if (_clipboardDelay > Duration.zero) {
          await Future<void>.delayed(_clipboardDelay);
        }
        return <String, bool>{'value': true};
      }
      return null;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  testWidgets(
    'the selection toolbar is Material',
    (tester) async {
      // AdaptiveTextSelectionToolbar, which this used to be, gives a
      // Cupertino toolbar on iOS, a desktop Cupertino one on macOS and a
      // desktop Material one on Linux and Windows, so the same terminal came
      // up looking like three different things depending on where it ran.
      final harness = await _pump(tester);

      await harness.doubleTapAt(2);
      await tester.pump();
      await tester.pump();

      expect(harness.controller.selection, isNotNull);
      expect(find.byType(TextSelectionToolbar), findsOneWidget);

      // The two the adaptive toolbar would have reached for instead.
      expect(find.byType(CupertinoTextSelectionToolbar), findsNothing);
      expect(find.byType(CupertinoDesktopTextSelectionToolbar), findsNothing);
    },
    variant: const TargetPlatformVariant(<TargetPlatform>{
      TargetPlatform.macOS,
      TargetPlatform.iOS,
      TargetPlatform.android,
      TargetPlatform.windows,
    }),
  );

  testWidgets('a menu asked for before the clipboard answers still appears', (
    tester,
  ) async {
    // The menu is asked for once, finds no items because the status is not
    // known yet, and nothing asks again. It used to be dropped there.
    _clipboardDelay = const Duration(seconds: 1);
    final harness = await _pump(tester);

    await harness.doubleTapAt(2);
    expect(
      find.byType(TextSelectionToolbar),
      findsNothing,
      reason: 'the clipboard has not answered yet',
    );

    await tester.pump(const Duration(seconds: 2));
    await tester.pump();

    expect(find.byType(TextSelectionToolbar), findsOneWidget);
  });

  testWidgets('a menu dismissed before the clipboard answers stays away', (
    tester,
  ) async {
    // Or putting the dropped one back would resurrect a menu the user had
    // already got rid of.
    _clipboardDelay = const Duration(seconds: 1);
    final harness = await _pump(tester);

    await harness.doubleTapAt(2);
    harness.view.hideSelectionToolbar();

    await tester.pump(const Duration(seconds: 2));
    await tester.pump();

    expect(find.byType(TextSelectionToolbar), findsNothing);
  });
}

Future<_Harness> _pump(WidgetTester tester) async {
  final terminal = Terminal(maxLines: 32);
  final controller = TerminalController();
  final key = GlobalKey<TerminalViewState>();

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: TerminalView(terminal, controller: controller, key: key),
      ),
    ),
  );
  await tester.pump();

  terminal.write('alpha beta gamma');
  await tester.pump();

  return _Harness(tester, terminal, controller, key);
}

class _Harness {
  _Harness(this.tester, this.terminal, this.controller, this.key);

  final WidgetTester tester;
  final Terminal terminal;
  final TerminalController controller;
  final GlobalKey<TerminalViewState> key;

  TerminalViewState get view => key.currentState!;

  Future<void> doubleTapAt(int column) async {
    final topLeft = tester.getTopLeft(find.byType(TerminalView));
    final render = tester.renderObject(find.byType(TerminalView));
    final cellWidth = render.paintBounds.width / terminal.viewWidth;
    final cellHeight = render.paintBounds.height / terminal.viewHeight;
    final position =
        topLeft + Offset((column + 0.5) * cellWidth, 0.5 * cellHeight);

    for (var i = 0; i < 2; i++) {
      final gesture = await tester.startGesture(
        position,
        kind: PointerDeviceKind.mouse,
      );
      await gesture.up();
      await tester.pump(
        i == 1
            ? kDoubleTapTimeout + const Duration(milliseconds: 1)
            : kDoubleTapMinTime,
      );
    }
  }
}
