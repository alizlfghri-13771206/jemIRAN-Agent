import 'package:flutter/foundation.dart';
import 'package:local_notifier/local_notifier.dart';
import 'package:window_manager/window_manager.dart';

class AgentNotifier {
  AgentNotifier._();

  static final AgentNotifier instance = AgentNotifier._();

  bool _ready = false;

  final List<LocalNotification> _open = [];

  Future<void> init() async {
    if (_ready) return;
    try {
      await localNotifier.setup(appName: 'jemIRAN');
      _ready = true;
    } catch (e) {
      debugPrint('[notifier] راه‌اندازی ناموفق: $e');
    }
  }

  Future<bool> _windowIsVisible() async {
    try {
      final visible = await windowManager.isVisible();
      if (!visible) return false;
      if (await windowManager.isMinimized()) return false;
      return await windowManager.isFocused();
    } catch (_) {
      return false;
    }
  }

  Future<void> permissionNeeded({
    required String title,
    String? subtitle,
    String? origin,
  }) => _notify(
    title: origin == null || origin.isEmpty
        ? 'جمیران منتظر اجازه است'
        : 'اجازه لازم است — $origin',
    body: subtitle == null ? title : '$title\n$subtitle',
    focusOnClick: true,
  );

  Future<void> questionAsked(String question, {String? origin}) => _notify(
    title: origin == null || origin.isEmpty
        ? 'جمیران سؤالی دارد'
        : 'سؤال — $origin',
    body: question,
    focusOnClick: true,
  );

  Future<void> taskFinished({required bool ok, required String summary}) =>
      _notify(
        title: ok ? 'کار تمام شد' : 'کار ناتمام ماند',
        body: summary,
        focusOnClick: true,
      );

  Future<void> _notify({
    required String title,
    required String body,
    bool focusOnClick = false,
  }) async {
    if (!_ready) return;
    if (await _windowIsVisible()) return;

    try {
      final notification = LocalNotification(title: title, body: _clip(body));

      if (focusOnClick) {
        notification.onClick = () async {
          try {
            await windowManager.show();
            await windowManager.focus();
          } catch (_) {}
        };
      }

      notification.onClose = (_) => _open.remove(notification);

      await notification.show();
      _open.add(notification);
    } catch (e) {
      debugPrint('[notifier] نمایش ناموفق: $e');
    }
  }

  Future<void> clearAll() async {
    for (final n in List.of(_open)) {
      try {
        await n.close();
      } catch (_) {}
    }
    _open.clear();
  }

  static String _clip(String text) {
    final flat = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    return flat.length <= 180 ? flat : '${flat.substring(0, 180)}…';
  }
}
