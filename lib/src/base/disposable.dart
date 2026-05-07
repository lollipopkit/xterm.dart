import 'package:xterm/src/base/event.dart';

mixin Disposable {
  final _disposables = <Disposable>[];

  bool get disposed => _disposed;
  bool _disposed = false;

  /// Emits once while this object is being disposed.
  ///
  /// Disposal runs in this order: registered child objects and callbacks are
  /// disposed first, this event is emitted next, and listeners are cleared after
  /// emission. Subscribing after [disposed] is true will not invoke the callback.
  Event<void> get onDisposed => _onDisposed.event;

  /// Backing emitter for [onDisposed] with the same disposal sequencing.
  final _onDisposed = EventEmitter<void>();

  void register(Disposable disposable) {
    if (disposable.disposed) {
      return;
    }

    if (_disposed) {
      disposable.dispose();
      return;
    }

    _disposables.add(disposable);
  }

  void registerCallback(void Function() callback) {
    final disposable = _DisposeCallback(callback);
    if (_disposed) {
      disposable.dispose();
      return;
    }

    _disposables.add(disposable);
  }

  /// Disposes this object and its registered children.
  ///
  /// Registered child objects and callbacks are disposed before [onDisposed] is
  /// emitted. After the event is emitted, its listeners are cleared. Calling
  /// [dispose] again has no effect, and callbacks subscribed after disposal are
  /// not invoked.
  void dispose() {
    if (_disposed) {
      return;
    }

    _disposed = true;
    for (final disposable in _disposables) {
      disposable.dispose();
    }
    _disposables.clear();
    _onDisposed.emit(null);
    _onDisposed.clear();
  }
}

class _DisposeCallback with Disposable {
  final void Function() callback;

  _DisposeCallback(this.callback);

  @override
  void dispose() {
    if (disposed) {
      return;
    }

    super.dispose();
    callback();
  }
}
