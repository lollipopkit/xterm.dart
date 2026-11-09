import 'package:flutter/gestures.dart';
import 'package:material_ui/material_ui.dart';
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
      // `byType` matches the exact type, so the adaptive toolbar's other
      // choices do not count.
      expect(find.byType(TextSelectionToolbar), findsOneWidget);
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

  testWidgets('a long press on nothing puts up a menu to paste from', (
    tester,
  ) async {
    // How a touch screen pastes. It used to put up nothing, so paste was only
    // reachable by pressing on a word, and a cleared screen had none.
    final harness = await _pump(tester);

    await harness.longPressAt(30, 2);

    expect(find.byType(TextSelectionToolbar), findsOneWidget);
    expect(find.text('Paste'), findsOneWidget);
    expect(find.text('Copy'), findsNothing);
    // Not the one cell the press took: it is nothing to copy, and a selection
    // left behind is what a secondary click copies instead of pasting.
    expect(harness.controller.selection, isNull);

    await tester.tap(find.text('Paste'));
    await tester.pump();

    expect(find.byType(TextSelectionToolbar), findsNothing);
  });

  testWidgets('a tap puts the paste menu away', (tester) async {
    final harness = await _pump(tester);

    await harness.longPressAt(30, 2);
    expect(find.byType(TextSelectionToolbar), findsOneWidget);

    await tester.tapAt(harness.offsetOf(30, 20));
    await tester.pump(kDoubleTapTimeout);

    expect(find.byType(TextSelectionToolbar), findsNothing);
  });

  testWidgets('a held mouse button on nothing puts up no menu', (tester) async {
    // A mouse has a secondary click for that.
    final harness = await _pump(tester);

    await harness.longPressAt(30, 2, kind: PointerDeviceKind.mouse);

    expect(find.byType(TextSelectionToolbar), findsNothing);
  });

  testWidgets('a long press near a handle does not stop the next one', (
    tester,
  ) async {
    // A press within reach of a handle arms it, and when the press becomes a
    // long press the tap-up that disarms it never comes. Every long press
    // after that returned at once, wherever it landed, so the menu was gone
    // until a tap: what ServerBox #1795 reports.
    final harness = await _pump(tester);
    harness.terminal.write('\r\nalpha beta gamma' * 4);
    await tester.pump();

    await harness.longPressAt(7, 0);
    expect(find.byType(TextSelectionToolbar), findsOneWidget);
    // Put away by something other than a tap, as typing does, which leaves
    // the selection and its handles.
    harness.view.hideSelectionToolbar();
    await tester.pump();

    // Just under the selected word, where its handles hang.
    await harness.longPressAt(7, 1);
    expect(
      find.byType(TextSelectionToolbar),
      findsOneWidget,
      reason: 'a press on the selection asks for its menu',
    );
    harness.view.hideSelectionToolbar();
    await tester.pump();

    await harness.longPressAt(7, 3);

    final selection = harness.controller.selection!;
    expect(harness.terminal.buffer.getText(selection).trim(), 'beta');
    expect(selection.begin.y, 3);
    expect(find.byType(TextSelectionToolbar), findsOneWidget);
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

  /// The centre of cell [column], [row] in global coordinates.
  Offset offsetOf(int column, [int row = 0]) {
    final topLeft = tester.getTopLeft(find.byType(TerminalView));
    final render = tester.renderObject(find.byType(TerminalView));
    final cellWidth = render.paintBounds.width / terminal.viewWidth;
    final cellHeight = render.paintBounds.height / terminal.viewHeight;
    return topLeft +
        Offset((column + 0.5) * cellWidth, (row + 0.5) * cellHeight);
  }

  /// A long press and its release, then long enough that the next press
  /// starts a run of its own.
  Future<void> longPressAt(
    int column,
    int row, {
    PointerDeviceKind kind = PointerDeviceKind.touch,
  }) async {
    final gesture = await tester.startGesture(
      offsetOf(column, row),
      kind: kind,
    );
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 1));
    await gesture.up();
    await tester.pump();
    await tester.pump(kDoubleTapTimeout);
  }

  Future<void> doubleTapAt(int column) async {
    final position = offsetOf(column);

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
