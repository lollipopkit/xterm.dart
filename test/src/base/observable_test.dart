import 'package:flutter_test/flutter_test.dart';
import 'package:xterm/src/base/observable.dart';

class TestObservable with Observable {}

void main() {
  test('Observable.notifyListeners tolerates listener removal', () {
    final observable = TestObservable();
    var firstCount = 0;
    var secondCount = 0;

    void second() {
      secondCount++;
    }

    void first() {
      firstCount++;
      observable.removeListener(second);
    }

    observable.addListener(first);
    observable.addListener(second);

    observable.notifyListeners();

    expect(firstCount, 1);
    expect(secondCount, 0);
  });

  test('Observable.notifyListeners ignores listeners added mid-notify', () {
    final observable = TestObservable();
    var firstCount = 0;
    var secondCount = 0;

    void second() {
      secondCount++;
    }

    void first() {
      firstCount++;
      observable.addListener(second);
    }

    observable.addListener(first);

    observable.notifyListeners();
    expect(firstCount, 1);
    expect(secondCount, 0);

    observable.notifyListeners();
    expect(firstCount, 2);
    expect(secondCount, 1);
  });

  test('Observable.removeListener removes one matching duplicate listener', () {
    final observable = TestObservable();
    var count = 0;

    void listener() {
      count++;
    }

    observable.addListener(listener);
    observable.addListener(listener);

    observable.removeListener(listener);
    observable.notifyListeners();

    expect(count, 1);
  });
}
