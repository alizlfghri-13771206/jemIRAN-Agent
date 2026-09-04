import 'package:flutter/material.dart';

class LightColors {
  static const Color background = Color(0xFFF8F8FA);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surfaceElevated = Color(0xFFFCFCFD);
  static const Color surfaceHigh = Color(0xFFF1F1F4);

  static const Color primary = Color.fromARGB(255, 84, 115, 229);
  static const Color primaryLight = Color(0xFF8285F0);
  static const Color accent = Color(0xFF8B5CF6);

  static const Color text = Color(0xFF18181F);
  static const Color secondaryText = Color(0xFF6B6B76);
  static const Color tertiaryText = Color(0xFFA0A0AC);
  static const Color seconndaryText = secondaryText;

  static const Color border = Color(0xFFE7E7EC);
  static const Color divider = Color(0xFFEEEEF2);
  static const Color overlay = Color(0x14181820);

  static const Color success = Color(0xFF1BA672);
  static const Color danger = Color(0xFFDC3545);
  static const Color warning = Color(0xFFC97A1E);
}

class DarkColors {
  static const Color background = Color(0xFF111114);
  static const Color surface = Color(0xFF19191E);
  static const Color surfaceElevated = Color(0xFF212127);
  static const Color surfaceHigh = Color(0xFF2A2A32);

  static const Color primary = Color(0xFF9295F5);
  static const Color primaryLight = Color(0xFFB0B2FA);
  static const Color accent = Color(0xFFAB8CF9);

  static const Color text = Color(0xFFEDEDF1);
  static const Color secondaryText = Color(0xFFA3A3AF);
  static const Color tertiaryText = Color(0xFF75757F);
  static const Color seconndaryText = secondaryText;

  static const Color border = Color(0x15FFFFFF);
  static const Color divider = Color(0x0FFFFFFF);
  static const Color overlay = Color(0x66000000);

  static const Color success = Color(0xFF3DD68C);
  static const Color danger = Color(0xFFF2707D);
  static const Color warning = Color(0xFFE0A64D);
}

class AppRadius {
  static const double xs = 8;
  static const double sm = 12;
  static const double md = 16;
  static const double lg = 20;
  static const double xl = 26;
  static const double pill = 999;
}

class AppSpacing {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;
}

class AppShadows {
  static List<BoxShadow> soft(bool isDark) => [
    BoxShadow(
      color: (isDark ? Colors.black : const Color(0xFF15151F)).withValues(
        alpha: isDark ? .32 : .05,
      ),
      blurRadius: 24,
      offset: const Offset(0, 8),
    ),
  ];

  static List<BoxShadow> subtle(bool isDark) => [
    BoxShadow(
      color: (isDark ? Colors.black : const Color(0xFF15151F)).withValues(
        alpha: isDark ? .24 : .035,
      ),
      blurRadius: 12,
      offset: const Offset(0, 3),
    ),
  ];

  static List<BoxShadow> glow(Color color, {double alpha = .22}) => [
    BoxShadow(color: color.withValues(alpha: alpha), blurRadius: 20),
  ];
}

class ModelAccent {
  static const Map<String, Color> _raw = {
    'nemotron': Colors.lightGreen,
    'deepseek': Colors.indigo,
    'gpt5_mini': Color.fromARGB(255, 14, 145, 112),
    'gpt': Color.fromARGB(255, 255, 195, 64),
    'gpt_oss_120b': Color.fromARGB(255, 63, 181, 175),
    'gpt5': Color.fromARGB(255, 14, 145, 112),
    'glm': Colors.purple,
    'grok': Colors.grey,
    'gemini_studio': Colors.lightBlue,
    'gemini': Color.fromARGB(255, 8, 35, 83),
    'hy3_preview': Colors.lightBlueAccent,
    'hy3': Colors.lightBlueAccent,
    'gemini_pro': Colors.redAccent,
    'mimo_v25': Color.fromARGB(233, 255, 86, 34),
    'claude_sonnet': Color(0xFFCB7B3E),
  };

  static Color raw(String key) => _raw[key.trim()] ?? LightColors.tertiaryText;

  static Color muted(String key, {bool isDark = false}) {
    final base = raw(key);
    final hsl = HSLColor.fromColor(base);
    return hsl
        .withSaturation((hsl.saturation * (isDark ? 0.75 : 0.62)).clamp(0, 1))
        .withLightness(isDark ? 0.72 : 0.42)
        .toColor();
  }
}

const aiLightTheme = {
  'comment': TextStyle(color: Colors.green, fontStyle: FontStyle.italic),
  'quote': TextStyle(color: Colors.indigo),

  'variable': TextStyle(color: Color(0xFFDC2626)),
  'template-variable': TextStyle(color: Color(0xFFDC2626)),
  'tag': TextStyle(color: Color(0xFFDC2626)),
  'name': TextStyle(color: Color(0xFFDC2626)),
  'selector-id': TextStyle(color: Color(0xFFDC2626)),
  'selector-class': TextStyle(color: Color(0xFFDC2626)),
  'regexp': TextStyle(color: Color(0xFFDC2626)),
  'deletion': TextStyle(color: Color(0xFFDC2626)),

  'number': TextStyle(color: Colors.brown, fontWeight: FontWeight.w400),
  'built_in': TextStyle(color: Colors.brown, fontWeight: FontWeight.w400),
  'builtin-name': TextStyle(color: Color(0xFF2563EB)),
  'literal': TextStyle(color: Color(0xFF2563EB)),

  'type': TextStyle(color: Color(0xFF0891B2)),
  'params': TextStyle(color: Color(0xFF334155)),
  'meta': TextStyle(color: Colors.red),
  'link': TextStyle(color: Color(0xFF2563EB)),

  'attribute': TextStyle(color: Color(0xFFD97706)),

  'string': TextStyle(color: Colors.black),
  'symbol': TextStyle(color: Color(0xFF059669)),
  'bullet': TextStyle(color: Color(0xFF059669)),
  'addition': TextStyle(color: Color(0xFF059669)),

  'title': TextStyle(color: Color(0xFF7C3AED), fontWeight: FontWeight.w600),
  'section': TextStyle(color: Color(0xFF7C3AED), fontWeight: FontWeight.w600),

  'keyword': TextStyle(color: Color(0xFF9333EA), fontWeight: FontWeight.w600),
  'selector-tag': TextStyle(
    color: Color(0xFF9333EA),
    fontWeight: FontWeight.w600,
  ),

  'root': TextStyle(
    backgroundColor: Color(0xFFF8FAFC),
    color: Color(0xFF1E293B),
    fontSize: 15,
    height: 1.5,
  ),

  'emphasis': TextStyle(fontStyle: FontStyle.italic),

  'strong': TextStyle(fontWeight: FontWeight.w700),
};
