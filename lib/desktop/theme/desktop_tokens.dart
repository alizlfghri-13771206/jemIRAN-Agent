import 'package:flutter/material.dart';
import 'package:jemiran/themes/colors.dart';
import 'package:jemiran/themes/jemiran_design.dart';

abstract final class WinSpace {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
  static const double xxl = 28;
  static const double xxxl = 40;

  static const double gutter = 28;

  static const EdgeInsets composer = EdgeInsets.symmetric(
    horizontal: 20,
    vertical: 14,
  );

  static const EdgeInsets composerField = EdgeInsets.symmetric(
    horizontal: 6,
    vertical: 12,
  );
}

abstract final class WinRadius {
  static const double control = 6;

  static const double card = 8;

  static const double layer = 12;

  static const double flyout = 10;
}

abstract final class WinMetrics {
  static const double sidebarWidth = 292;

  static const double railWidth = 56;

  static const double topBarHeight = 48;

  static const double contentMaxWidth = 780;

  static const double composerMaxWidth = 900;

  static const double composerMaxHeight = 260;

  static const double sidebarBreakpoint = 900;
}

abstract final class WinSurface {
  static Color window(bool isDark) =>
      isDark ? const Color(0xFF0D0D10) : const Color(0xFFF3F3F6);

  static Color layer(bool isDark) =>
      isDark ? DarkColors.background : LightColors.surface;

  static Color sidebar(bool isDark) =>
      isDark ? const Color(0xFF121216) : const Color(0xFFF7F7F9);

  static Color card(bool isDark) =>
      isDark ? DarkColors.surfaceElevated : LightColors.surface;

  static Color hover(bool isDark) => isDark
      ? Colors.white.withValues(alpha: .055)
      : const Color(0xFF15151F).withValues(alpha: .045);

  static Color pressed(bool isDark) => isDark
      ? Colors.white.withValues(alpha: .09)
      : const Color(0xFF15151F).withValues(alpha: .075);

  static Color selected(bool isDark) =>
      JColor.primary(isDark).withValues(alpha: isDark ? .18 : .10);

  static Color hairline(bool isDark) => JSurface.hairline(isDark);

  static Color seam(bool isDark) => isDark
      ? Colors.white.withValues(alpha: .06)
      : const Color(0xFF15151F).withValues(alpha: .08);
}

abstract final class WinText {
  static const double body = 14.5;
  static const double bodySm = 13;
  static const double caption = 11.5;
  static const double sectionLabel = 11;
  static const double title = 15.5;
}

abstract final class WinFont {
  static const family = 'vazir';
}

abstract final class WinMono {
  static const family = 'Consolas';
  static const fallback = ['Cascadia Mono', 'Courier New', 'monospace'];
}
