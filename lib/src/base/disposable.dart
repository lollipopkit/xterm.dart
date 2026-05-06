import 'package:xterm/src/base/event.dart';

mixin Disposable {
  final _disposables = <Disposable>[];

  bool get disposed => _disposed;
  bool _disposed = false;

  Event<void> get onDisposed => _onDisposed.event;
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
