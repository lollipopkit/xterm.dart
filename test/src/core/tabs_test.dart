import 'package:flutter_test/flutter_test.dart';
import 'package:xterm/src/core/tabs.dart';

void main() {
  group('TabStops', () {
    test('has default tab stops after created', () {
      final tabStops = TabStops();

      expect(tabStops.isSetAt(0), true);
      expect(tabStops.isSetAt(1), false);
      expect(tabStops.isSetAt(7), false);
      expect(tabStops.isSetAt(8), true);
      expect(tabStops.isSetAt(9), false);
      expect(tabStops.isSetAt(15), false);
      expect(tabStops.isSetAt(16), true);
    });

    test('grows beyond the initial column allocation', () {
      final tabStops = TabStops();

      expect(tabStops.find(1024, 1033), 1024);
      tabStops.clearAt(2048);
      expect(tabStops.isSetAt(2048), false);
      tabStops.setAt(2050);
      expect(tabStops.find(2048, 2051), 2050);
      tabStops.reset();
      expect(tabStops.isSetAt(2048), true);
    });

    test('does not create default stops in new columns after clearAll', () {
      final tabStops = TabStops();

      tabStops.clearAll();

      expect(tabStops.find(1024, 1033), isNull);
      expect(tabStops.isSetAt(2048), false);
    });
  });

  group('TabStops.findPrevious()', () {
    test('excludes start and includes end', () {
      final tabStops = TabStops();
      expect(tabStops.findPrevious(17, 0), 16);
      expect(tabStops.findPrevious(16, 0), 8);
      expect(tabStops.findPrevious(8, 8), isNull);
    });
  });

  group('TabStops.find()', () {
    test('includes start', () {
      final tabStops = TabStops();
      expect(tabStops.find(0, 10), 0);
    });

    test('excludes end', () {
      final tabStops = TabStops();
      expect(tabStops.find(0, 8), 0);
      expect(tabStops.find(1, 9), 8);
    });
  });
}
