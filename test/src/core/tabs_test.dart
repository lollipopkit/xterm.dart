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
      const largeStart = 100000;
      const largeEnd = largeStart + 9;
      const largeIndex = 200000;
      const anotherLargeIndex = largeIndex + 2;

      expect(tabStops.find(largeStart, largeEnd), largeStart);
      tabStops.clearAt(largeIndex);
      expect(tabStops.isSetAt(largeIndex), false);
      tabStops.setAt(anotherLargeIndex);
      expect(
        tabStops.find(largeIndex, anotherLargeIndex + 1),
        anotherLargeIndex,
      );
      tabStops.reset();
      expect(tabStops.isSetAt(largeIndex), true);
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

    test('clamps negative bounds', () {
      final tabStops = TabStops();
      expect(tabStops.findPrevious(8, -1), 0);
      expect(tabStops.findPrevious(-1, -2), isNull);
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

    test('clamps negative bounds', () {
      final tabStops = TabStops();
      expect(tabStops.find(-1, 1), 0);
      expect(tabStops.find(-2, -1), isNull);
    });
  });
}
