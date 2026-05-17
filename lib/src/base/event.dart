import 'package:xterm/src/base/disposable.dart';

typedef EventListener<T> = void Function(T event);

class Event<T> {
  final EventEmitter<T> emitter;

  Event(this.emitter);

  EventSubscription<T> call(EventListener<T> listener) {
    return emitter(listener);
  }
}

class EventEmitter<T> {
  final _listeners = <_EventListenerEntry<T>>[];

  EventSubscription<T> call(EventListener<T> listener) {
    final entry = _EventListenerEntry(listener);
    _listeners.add(entry);
    return EventSubscription._(this, entry);
  }

  void emit(T event) {
    for (final entry in _listeners.toList()) {
      if (_listeners.contains(entry)) {
        entry.listener(event);
      }
    }
  }

  void clear() {
    _listeners.clear();
  }

  Event<T> get event => Event(this);
}

class EventSubscription<T> with Disposable {
  final EventEmitter<T> emitter;
  final _EventListenerEntry<T> _entry;

  EventSubscription._(this.emitter, this._entry);

  EventListener<T> get listener => _entry.listener;

  @override
  void dispose() {
    if (disposed) {
      return;
    }

    emitter._listeners.remove(_entry);
    super.dispose();
  }
}

class _EventListenerEntry<T> {
  _EventListenerEntry(this.listener);

  final EventListener<T> listener;
}
