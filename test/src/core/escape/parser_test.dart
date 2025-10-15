import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:test/test.dart';
import 'package:xterm/xterm.dart';

@GenerateNiceMocks([MockSpec<EscapeHandler>()])
import 'parser_test.mocks.dart';

void main() {
  group('EscapeParser', () {
    test('can parse window manipulation', () {
      final parser = EscapeParser(MockEscapeHandler());
      parser.write('\x1b[8;24;80t');
      verify(parser.handler.resize(80, 24));
    });

    test('maps ESC = to application keypad mode', () {
      final handler = MockEscapeHandler();
      final parser = EscapeParser(handler);

      parser.write('\x1b=');

      verify(handler.setAppKeypadMode(true));
    });

    test('maps ESC > to normal keypad mode', () {
      final handler = MockEscapeHandler();
      final parser = EscapeParser(handler);

      parser.write('\x1b>');

      verify(handler.setAppKeypadMode(false));
    });

    test('designates G2 charset via ESC *', () {
      final handler = MockEscapeHandler();
      final parser = EscapeParser(handler);

      parser.write('\x1b*B');

      verify(handler.designateCharset(2, 'B'.codeUnitAt(0)));
    });

    test('designates G3 charset via ESC +', () {
      final handler = MockEscapeHandler();
      final parser = EscapeParser(handler);

      parser.write('\x1b+B');

      verify(handler.designateCharset(3, 'B'.codeUnitAt(0)));
    });
  });
}
