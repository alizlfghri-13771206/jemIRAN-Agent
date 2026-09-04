import 'dart:async';

abstract final class DesktopRuntimeControl {
  static Future<void> Function()? _shutdown;

  static void attach(Future<void> Function() shutdown) {
    _shutdown = shutdown;
  }

  static void detach() => _shutdown = null;

  static Future<void> shutdownAll() =>
      _shutdown?.call() ?? Future<void>.value();
}
