import 'package:test/test.dart';
import 'package:xterm/xterm.dart';

String _row(Terminal t, int y) => t.buffer.lines[y].getText().trimRight();

void main() {
  group('a sequence cut off by the end of a write', () {
    test('runs a control inside it once', () {
      final t = Terminal();
      t.write('\x1b[1\n');
      t.write('m');
      expect(t.buffer.cursorY, 1);
    });

    test('rings a bell inside it once however many writes it takes', () {
      var bells = 0;
      final t = Terminal(onBell: () => bells++);
      t.write('\x1b[1\x07');
      t.write('\n');
      t.write('\x07');
      t.write('m');
      expect(bells, 2);
    });
  });

  test('a huge parameter is capped rather than looped over', () {
    final t = Terminal()..resize(10, 3);
    final watch = Stopwatch()..start();
    t.write('a\x1b[9223372036854775807b');
    t.write('\x1b[9223372036854775807I');
    t.write('\x1b[1;1Hzz\x1b[9223372036854775807S');
    expect(watch.elapsed, lessThan(const Duration(seconds: 2)));
    expect(_row(t, t.buffer.scrollBack), isEmpty);
  });

  group('an unterminated sequence', () {
    test('a DCS does not make every later write slower', () {
      final t = Terminal();
      t.write('\x1bP');
      final chunk = 'x' * 4096;
      final watch = Stopwatch()..start();
      for (var i = 0; i < 2000; i++) {
        t.write(chunk);
      }
      t.write('\x1b\\ok');
      expect(watch.elapsed, lessThan(const Duration(seconds: 3)));
      expect(_row(t, 0), 'ok');
    });

    test('a CSI past its length is dropped up to its final byte', () {
      final t = Terminal();
      t.write('\x1b[');
      for (var i = 0; i < 2000; i++) {
        t.write('1;' * 512);
      }
      t.write('mok');
      expect(_row(t, 0), 'ok');
    });

    test('an OSC is read across writes', () {
      String? title;
      final t = Terminal(onTitleChange: (v) => title = v);
      t.write('\x1b]2;he');
      t.write('llo\x1b');
      t.write('\\after');
      expect(title, 'hello');
      expect(_row(t, 0), 'after');
    });
  });

  test('a paste cannot end bracketed paste early', () {
    final out = <String>[];
    final t = Terminal(onOutput: out.add);
    t.write('\x1b[?2004h');
    t.paste('safe\x1b[201~rm -rf ~\n');
    expect(out.single, '\x1b[200~safe[201~rm -rf ~\n\x1b[201~');
  });

  test('CPR in origin mode counts from the top margin', () {
    final out = <String>[];
    final t = Terminal(onOutput: out.add);
    t.write('\x1b[5;10r\x1b[?6h\x1b[6n');
    expect(out.last, '\x1b[1;1R');
  });

  test('DECSTBM with a top past the screen keeps the margins', () {
    final t = Terminal()..resize(80, 24);
    t.write('\x1b[30;40r');
    expect(t.buffer.marginTop, 0);
    expect(t.buffer.marginBottom, 23);
  });

  test(
    'a line feed below the scroll region at the last row scrolls nothing',
    () {
      final t = Terminal()..resize(80, 24);
      t.write('\x1b[1;10r\x1b[1;1Htop\x1b[24;1Hbottom\n');
      expect(_row(t, t.buffer.scrollBack), 'top');
      expect(_row(t, t.buffer.scrollBack + 23), 'bottom');
    },
  );

  test('CUU and CUD stop at the margins without origin mode', () {
    final t = Terminal()..resize(80, 24);
    t.write('\x1b[5;10r\x1b[8;1H\x1b[20A');
    expect(t.buffer.cursorY, 4);
    t.write('\x1b[20B');
    expect(t.buffer.cursorY, 9);
  });

  test('each screen saves its own modes with DECSC', () {
    // `?1049l` restores the main screen's cursor, which must not bring the
    // alternate screen's saved autowrap with it.
    final t = Terminal();
    t.write('\x1b[?1049h\x1b[?7l\x1b7\x1b[?1049l');
    expect(t.autoWrapMode, isTrue);
  });

  test('an escape with an unknown intermediate prints nothing', () {
    final t = Terminal();
    t.write('\x1b\$B\x1b&x\x1b!y');
    expect(_row(t, 0), isEmpty);
  });

  test('DECALN resets the margins and homes the cursor', () {
    final t = Terminal()..resize(80, 24);
    t.write('\x1b[5;10r\x1b[12;12H\x1b#8');
    expect(t.buffer.marginTop, 0);
    expect(t.buffer.marginBottom, 23);
    expect(t.buffer.cursorX, 0);
    expect(t.buffer.cursorY, 0);
  });
}
