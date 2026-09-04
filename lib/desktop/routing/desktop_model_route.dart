import 'package:flutter_riverpod/legacy.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../agent/core/agent_storage.dart';

class DesktopModelRouteState {
  const DesktopModelRouteState({this.priority = const []});

  final List<String> priority;

  String? get primary => priority.isEmpty ? null : priority.first;
  bool contains(String key) => priority.contains(key);
}

class DesktopModelRouteNotifier extends StateNotifier<DesktopModelRouteState> {
  DesktopModelRouteNotifier() : super(const DesktopModelRouteState()) {
    _restored = _restore();
  }

  String get _prefsKey => 'desktop_model_route_v1_${AgentStorage.accountKey}';

  late final Future<void> _restored;
  Future<void> _writeQueue = Future<void>.value();
  Set<String> _available = const {};
  Future<void> get ready => _restored;

  Future<void> _restore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getStringList(_prefsKey);
      if (saved != null && saved.isNotEmpty) {
        state = DesktopModelRouteState(priority: _unique(saved));
      }
    } catch (_) {}
  }

  Future<void> reconcile(
    List<String> available, {
    bool allowEmpty = false,
  }) async {
    if (available.isEmpty && !allowEmpty) return;
    await ready;
    final allowed = available.toSet();
    _available = allowed;
    final kept = state.priority.where(allowed.contains).toList();
    final next = kept.isNotEmpty
        ? kept
        : (available.isEmpty ? <String>[] : <String>[available.first]);
    if (_same(next, state.priority)) return;
    state = DesktopModelRouteState(priority: next);
    await _persist();
  }

  void setPrimary(String key) {
    if (!_available.contains(key)) return;
    final next = [key, ...state.priority.where((item) => item != key)];
    state = DesktopModelRouteState(priority: next);
    _persist();
  }

  void toggle(String key) {
    if (!_available.contains(key)) return;
    final next = [...state.priority];
    if (next.contains(key)) {
      if (next.length == 1) return;
      next.remove(key);
    } else {
      next.add(key);
    }
    state = DesktopModelRouteState(priority: next);
    _persist();
  }

  void move(String key, int delta) {
    final from = state.priority.indexOf(key);
    if (from < 0) return;
    final to = (from + delta).clamp(0, state.priority.length - 1);
    if (from == to) return;
    final next = [...state.priority];
    next.insert(to, next.removeAt(from));
    state = DesktopModelRouteState(priority: next);
    _persist();
  }

  Future<void> _persist() async {
    final key = _prefsKey;
    final snapshot = List<String>.from(state.priority);
    _writeQueue = _writeQueue.then((_) async {
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setStringList(key, snapshot);
      } catch (_) {}
    });
    await _writeQueue;
  }

  Future<void> flush() => _writeQueue;

  Future<void> resetForAccount() async {
    await flush();
    _available = const {};
    state = const DesktopModelRouteState();
    await _restore();
  }

  static List<String> _unique(List<String> values) =>
      values.toSet().toList(growable: false);

  static bool _same(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

final desktopModelRouteProvider =
    StateNotifierProvider<DesktopModelRouteNotifier, DesktopModelRouteState>(
      (ref) => DesktopModelRouteNotifier(),
    );
