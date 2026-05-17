import 'package:flutter_test/flutter_test.dart';
import 'package:xterm/src/base/event.dart';

void main() {
  group('EventEmitter', () {
    test('Event.call returns a disposable subscription', () {
      final emitter = EventEmitter<int>();
      var count = 0;

      final subscription = emitter.event((event) {
        count += event;
      });

      emitter.emit(1);
      subscription.dispose();
      emitter.emit(1);

      expect(count, 1);
      expect(subscription.disposed, isTrue);
    });

    test('EventEmitter.emit tolerates listener removal', () {
      final emitter = EventEmitter<int>();
      var firstCount = 0;
      var secondCount = 0;

      late EventSubscription<int> secondSubscription;
      emitter((event) {
        firstCount += event;
        secondSubscription.dispose();
      });
      secondSubscription = emitter((event) {
        secondCount += event;
      });

      emitter.emit(1);

      expect(firstCount, 1);
      expect(secondCount, 0);
    });

    test('EventEmitter.emit ignores listeners added mid-emit', () {
      final emitter = EventEmitter<int>();
      var firstCount = 0;
      var secondCount = 0;

      emitter((event) {
        firstCount += event;
        emitter((event) {
          secondCount += event;
        });
      });

      emitter.emit(1);
      expect(firstCount, 1);
      expect(secondCount, 0);

      emitter.emit(1);
      expect(firstCount, 2);
      expect(secondCount, 1);
    });

    test('EventEmitter.clear removes all listeners', () {
      final emitter = EventEmitter<int>();
      var count = 0;

      final subscription = emitter((event) {
        count += event;
      });
      emitter((event) {
        count += event;
      });

      emitter.clear();
      emitter.emit(1);
      subscription.dispose();

      expect(count, 0);
      expect(subscription.disposed, isTrue);
    });
  });

  group('EventSubscription', () {
    test(
      'EventSubscription.dispose removes the matching duplicate listener',
      () {
        final emitter = EventEmitter<int>();
        var count = 0;
        void listener(int event) {
          count += event;
        }

        final firstSubscription = emitter(listener);
        final secondSubscription = emitter(listener);

        secondSubscription.dispose();
        emitter.emit(1);

        expect(count, 1);
        expect(firstSubscription.disposed, isFalse);
        expect(secondSubscription.disposed, isTrue);
      },
    );

    test('EventSubscription.dispose is idempotent', () {
      final emitter = EventEmitter<int>();
      var count = 0;
      final subscription = emitter((event) {
        count += event;
      });

      subscription.dispose();
      subscription.dispose();
      emitter.emit(1);

      expect(subscription.disposed, isTrue);
      expect(count, 0);
    });
  });
}
