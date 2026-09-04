import 'package:flutter/material.dart';

class AppTheme {
  static const _purple = Colors.blueAccent;
  static const _purpleLight = Color.fromARGB(255, 135, 178, 252);

  static ThemeData get light => ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    colorScheme: ColorScheme.fromSeed(
      seedColor: _purple,
      brightness: Brightness.light,
    ),
    scaffoldBackgroundColor: const Color(0xFFF4F4F8),
    cardColor: Colors.white,
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.white,
      foregroundColor: Color(0xFF1A1A2E),
      elevation: 0,
      centerTitle: false,
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      color: Colors.white,
    ),
    inputDecorationTheme: InputDecorationTheme(
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide.none,
      ),
    ),
  );

  static ThemeData get dark => ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: ColorScheme.fromSeed(
      seedColor: _purple,
      brightness: Brightness.dark,
      surface: const Color(0xFF1A1A24),
      onSurface: const Color(0xFFECECF1),
      primary: _purpleLight,
      onPrimary: const Color(0xFF0F0F1A),
      secondary: const Color(0xFF2E2E3F),
      onSecondary: const Color.fromARGB(255, 212, 196, 196),
      tertiary: const Color(0xFF312E56),
      onTertiary: const Color(0xFFC4B5FD),
      surfaceContainerHighest: const Color(0xFF22222E),
      surfaceContainer: const Color(0xFF2A2A38),
    ),
    scaffoldBackgroundColor: const Color(0xFF1A1A24),
    cardColor: const Color(0xFF22222E),
    dividerColor: Colors.white.withValues(alpha: 0.08),
    appBarTheme: const AppBarTheme(
      backgroundColor: Color(0xFF1A1A24),
      foregroundColor: Color(0xFFECECF1),
      surfaceTintColor: Colors.transparent,
      elevation: 0,
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: const Color(0xFF22222E),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
      ),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: Color(0xFF22222E),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
    ),
    drawerTheme: const DrawerThemeData(backgroundColor: Color(0xFF16161F)),
    inputDecorationTheme: InputDecorationTheme(
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide.none,
      ),
      hintStyle: const TextStyle(color: Color(0xFF8B8BA8)),
    ),
    iconTheme: const IconThemeData(color: Color(0xFFECECF1)),
    textTheme: const TextTheme(
      bodyLarge: TextStyle(color: Color(0xFFECECF1)),
      bodyMedium: TextStyle(color: Color(0xFFECECF1)),
      titleLarge: TextStyle(
        color: Color(0xFFECECF1),
        fontWeight: FontWeight.bold,
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: _purpleLight,
        foregroundColor: const Color(0xFF0F0F1A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: _purpleLight,
      foregroundColor: Color(0xFF0F0F1A),
    ),
    listTileTheme: ListTileThemeData(
      tileColor: Colors.transparent,
      textColor: const Color(0xFFECECF1),
      iconColor: const Color(0xFFC4B5FD),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected)
            ? _purpleLight
            : const Color(0xFF8B8BA8),
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected)
            ? _purpleLight.withValues(alpha: 0.3)
            : const Color(0xFF3F3F5A),
      ),
    ),
  );
}
