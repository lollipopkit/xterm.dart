mixin Observable {
  final _listeners = <_ObservableListenerEntry>[];

  void addListener(void Function() listener) {
    _listeners.add(_ObservableListenerEntry(listener));
  }

  void removeListener(void Function() listener) {
    final index = _listeners.indexWhere((entry) => entry.listener == listener);
    if (index != -1) {
      _listeners.removeAt(index);
    }
  }

  void notifyListeners() {
    for (final entry in _listeners.toList()) {
      if (_listeners.contains(entry)) {
        entry.listener();
      }
    }
  }
}

class _ObservableListenerEntry {
  _ObservableListenerEntry(this.listener);

  final void Function() listener;
}
