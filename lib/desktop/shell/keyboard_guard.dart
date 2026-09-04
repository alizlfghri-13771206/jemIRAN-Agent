import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

abstract final class WindowsKeyboardGuard {
  static bool _installed = false;
  static int _suppressed = 0;

  static int get suppressedCount => _suppressed;

  static void install() {
    if (_installed) return;
    _installed = true;

    final previous = FlutterError.onError;
    FlutterError.onError = (details) {
      if (_isKeyStateDesync(details)) {
        _suppressed++;
        _recover();
        return;
      }
      previous?.call(details);
    };
  }

  static bool _isKeyStateDesync(FlutterErrorDetails details) {
    if (details.library != 'services library') return false;

    final text = details.exception.toString();
    return text.contains('KeyDownEvent') &&
        text.contains('already pressed') &&
        text.contains('_pressedKeys');
  }

  static void _recover() {
    try {
      // ignore: invalid_use_of_visible_for_testing_member
      HardwareKeyboard.instance.clearState();
    } catch (_) {}
  }

  @visibleForTesting
  static void resetForTest() {
    _installed = false;
    _suppressed = 0;
  }

  @visibleForTesting
  static bool matchesForTest(FlutterErrorDetails details) =>
      _isKeyStateDesync(details);
}
