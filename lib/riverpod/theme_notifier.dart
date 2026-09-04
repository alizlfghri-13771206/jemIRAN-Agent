import 'package:flutter/material.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ThemeNotifier extends StateNotifier<ThemeMode> {
  ThemeNotifier(super.initial);

  SharedPreferences? _prefs;

  Future<SharedPreferences> get _storage async {
    _prefs ??= await SharedPreferences.getInstance();
    return _prefs!;
  }

  Future<void> setTheme(ThemeMode mode) async {
    state = mode;
    final prefs = await _storage;
    await prefs.setString('theme_mode', mode.name);
    await prefs.setBool('is_dark', mode == ThemeMode.dark);
  }

  static ThemeMode readFrom(SharedPreferences prefs) {
    final saved = prefs.getString('theme_mode');
    switch (saved) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
    }
    final isDark = prefs.getBool('is_dark') ?? false;
    return isDark ? ThemeMode.dark : ThemeMode.light;
  }
}

final themeProvider = StateNotifierProvider<ThemeNotifier, ThemeMode>((ref) {
  return ThemeNotifier(ThemeMode.light);
});
