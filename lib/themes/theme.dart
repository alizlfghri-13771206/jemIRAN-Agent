import 'package:flutter/material.dart';
import 'colors.dart';

class AppTheme {
  static const _seed = LightColors.primary;

  static ThemeData get light => ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    fontFamily: 'Vazirmatn',
    colorScheme: ColorScheme.fromSeed(
      seedColor: _seed,
      brightness: Brightness.light,
      primary: LightColors.primary,
      secondary: LightColors.accent,
      surface: LightColors.surface,
      error: LightColors.danger,
    ),
    scaffoldBackgroundColor: LightColors.background,
    cardColor: LightColors.surface,
    dividerColor: LightColors.divider,
    splashFactory: InkRipple.splashFactory,
    appBarTheme: const AppBarTheme(
      backgroundColor: LightColors.background,
      foregroundColor: LightColors.text,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      centerTitle: false,
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
        side: const BorderSide(color: LightColors.border),
      ),
      color: LightColors.surface,
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: LightColors.surface,
      surfaceTintColor: Colors.transparent,
      modalBarrierColor: LightColors.overlay,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: LightColors.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: LightColors.text,
      contentTextStyle: const TextStyle(color: Colors.white, fontSize: 13),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: LightColors.surfaceHigh,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
        borderSide: const BorderSide(color: LightColors.primary, width: 1.4),
      ),
      hintStyle: const TextStyle(color: LightColors.tertiaryText),
    ),
    textTheme: const TextTheme(
      bodyLarge: TextStyle(color: LightColors.text),
      bodyMedium: TextStyle(color: LightColors.text),
      titleLarge: TextStyle(
        color: LightColors.text,
        fontWeight: FontWeight.w700,
      ),
    ),
    iconTheme: const IconThemeData(color: LightColors.text),
    dividerTheme: const DividerThemeData(
      color: LightColors.divider,
      thickness: 1,
      space: 1,
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: LightColors.primary,
        foregroundColor: Colors.white,
        elevation: 0,
        padding: const EdgeInsets.symmetric(vertical: 14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm + 2),
        ),
      ),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected)
            ? LightColors.primary
            : LightColors.surface,
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected)
            ? LightColors.primary.withValues(alpha: 0.35)
            : LightColors.surfaceHigh,
      ),
    ),
  );

  static ThemeData get dark => ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    fontFamily: 'Vazirmatn',
    colorScheme: ColorScheme.fromSeed(
      seedColor: _seed,
      brightness: Brightness.dark,
      surface: DarkColors.surface,
      onSurface: DarkColors.text,
      primary: DarkColors.primary,
      onPrimary: const Color(0xFF15151B),
      secondary: DarkColors.surfaceHigh,
      onSecondary: DarkColors.text,
      tertiary: const Color(0xFF2C2A45),
      onTertiary: DarkColors.accent,
      surfaceContainerHighest: DarkColors.surfaceHigh,
      surfaceContainer: DarkColors.surfaceElevated,
      error: DarkColors.danger,
    ),
    scaffoldBackgroundColor: DarkColors.background,
    cardColor: DarkColors.surface,
    dividerColor: DarkColors.divider,
    splashFactory: InkRipple.splashFactory,
    appBarTheme: const AppBarTheme(
      backgroundColor: DarkColors.background,
      foregroundColor: DarkColors.text,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      centerTitle: false,
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: DarkColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
        side: const BorderSide(color: DarkColors.border),
      ),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: DarkColors.surface,
      surfaceTintColor: Colors.transparent,
      modalBarrierColor: DarkColors.overlay,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: DarkColors.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: DarkColors.surfaceHigh,
      contentTextStyle: const TextStyle(color: DarkColors.text, fontSize: 13),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
    ),
    drawerTheme: const DrawerThemeData(backgroundColor: DarkColors.background),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: DarkColors.surfaceElevated,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
        borderSide: const BorderSide(color: DarkColors.primary, width: 1.4),
      ),
      hintStyle: const TextStyle(color: DarkColors.tertiaryText),
    ),
    iconTheme: const IconThemeData(color: DarkColors.text),
    textTheme: const TextTheme(
      bodyLarge: TextStyle(color: DarkColors.text),
      bodyMedium: TextStyle(color: DarkColors.text),
      titleLarge: TextStyle(
        color: DarkColors.text,
        fontWeight: FontWeight.w700,
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: DarkColors.primary,
        foregroundColor: const Color(0xFF15151B),
        elevation: 0,
        padding: const EdgeInsets.symmetric(vertical: 14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm + 2),
        ),
      ),
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: DarkColors.primary,
      foregroundColor: Color(0xFF15151B),
    ),
    listTileTheme: ListTileThemeData(
      tileColor: Colors.transparent,
      textColor: DarkColors.text,
      iconColor: DarkColors.accent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
    ),
    dividerTheme: const DividerThemeData(
      color: DarkColors.divider,
      thickness: 1,
      space: 1,
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected)
            ? DarkColors.primary
            : DarkColors.tertiaryText,
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected)
            ? DarkColors.primary.withValues(alpha: 0.3)
            : DarkColors.surfaceHigh,
      ),
    ),
  );
}
