import 'package:flutter_test/flutter_test.dart';
import 'package:xterm/src/base/disposable.dart';

class TestDisposable with Disposable {}

void main() {
  test('Disposable.onDisposed can be cancelled', () {
    final disposable = TestDisposable();
    var count = 0;

    final subscription = disposable.onDisposed((_) {
      count++;
    });

    subscription.dispose();
    disposable.dispose();

    expect(count, 0);
  });

  test('Disposable.dispose releases onDisposed subscriptions', () {
    final disposable = TestDisposable();
    var count = 0;

    final subscription = disposable.onDisposed((_) {
      count++;
    });

    disposable.dispose();
    subscription.dispose();

    expect(count, 1);
    expect(subscription.disposed, isTrue);
  });

  test('Disposable.dispose is idempotent', () {
    final disposable = TestDisposable();
    var callbackCount = 0;

    disposable.registerCallback(() {
      callbackCount++;
    });

    disposable.dispose();
    disposable.dispose();

    expect(disposable.disposed, isTrue);
    expect(callbackCount, 1);
  });

  test('Disposable.dispose only disposes shared children once', () {
    final firstParent = TestDisposable();
    final secondParent = TestDisposable();
    final child = TestDisposable();
    var callbackCount = 0;

    child.registerCallback(() {
      callbackCount++;
    });
    firstParent.register(child);
    secondParent.register(child);

    firstParent.dispose();
    secondParent.dispose();

    expect(child.disposed, isTrue);
    expect(callbackCount, 1);
  });

  test(
    'Disposable.register disposes children immediately after parent disposal',
    () {
      final parent = TestDisposable()..dispose();
      final child = TestDisposable();

      parent.register(child);

      expect(child.disposed, isTrue);
    },
  );

  test(
    'Disposable.registerCallback runs callbacks immediately after disposal',
    () {
      final parent = TestDisposable()..dispose();
      var callbackCount = 0;

      parent.registerCallback(() {
        callbackCount++;
      });

      expect(callbackCount, 1);
    },
  );

  test('Disposable.register ignores children that are already disposed', () {
    final parent = TestDisposable();
    final child = TestDisposable()..dispose();
    var callbackCount = 0;

    child.registerCallback(() {
      callbackCount++;
    });
    parent.register(child);
    parent.dispose();

    expect(child.disposed, isTrue);
    expect(callbackCount, 1);
  });
}
