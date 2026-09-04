import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../theme/desktop_tokens.dart';

class SidebarOpenNotifier extends Notifier<bool> {
  @override
  bool build() => true;

  void toggle() => state = !state;
  void set(bool value) => state = value;
}

final sidebarOpenProvider = NotifierProvider<SidebarOpenNotifier, bool>(
  SidebarOpenNotifier.new,
);

class SidebarWidthNotifier extends Notifier<double> {
  static const _key = 'desktop_sidebar_width_v1';

  static const minWidth = 220.0;
  static const maxWidth = 460.0;

  @override
  double build() {
    unawaited(_restore());
    return WinMetrics.sidebarWidth;
  }

  Future<void> _restore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getDouble(_key);
      if (saved != null) state = _clamp(saved);
    } catch (_) {}
  }

  static double _clamp(double value) => value.clamp(minWidth, maxWidth);

  void set(double value) {
    final next = _clamp(value);
    if (next != state) state = next;
  }

  Future<void> persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(_key, state);
    } catch (_) {}
  }

  void reset() {
    state = WinMetrics.sidebarWidth;
    unawaited(persist());
  }
}

final sidebarWidthProvider = NotifierProvider<SidebarWidthNotifier, double>(
  SidebarWidthNotifier.new,
);

class SessionsRefreshNotifier extends Notifier<int> {
  @override
  int build() => 0;

  void bump() => state++;
}

final sessionsRefreshProvider = NotifierProvider<SessionsRefreshNotifier, int>(
  SessionsRefreshNotifier.new,
);

class ActiveSessionNotifier extends Notifier<int?> {
  @override
  int? build() => null;

  void set(int? id) => state = id;
}

final activeSessionProvider = NotifierProvider<ActiveSessionNotifier, int?>(
  ActiveSessionNotifier.new,
);

enum DesktopConversationKind { chat, work }

class DesktopConversationKindNotifier
    extends Notifier<DesktopConversationKind> {
  @override
  DesktopConversationKind build() => DesktopConversationKind.work;

  void set(DesktopConversationKind value) => state = value;
}

final desktopConversationKindProvider =
    NotifierProvider<DesktopConversationKindNotifier, DesktopConversationKind>(
      DesktopConversationKindNotifier.new,
    );

class ActiveWorkNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  void set(String? id) => state = id;
}

final activeWorkProvider = NotifierProvider<ActiveWorkNotifier, String?>(
  ActiveWorkNotifier.new,
);
