import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:jemiran/themes/colors.dart';
import 'package:jemiran/themes/jemiran_design.dart';

class ModelConfig {
  static const Map<String, Map<String, dynamic>> info = {};

  static final Map<String, Map<String, dynamic>> _models = {};

  static void ingest(List<Map<String, dynamic>> models) {
    for (final m in models) {
      final k = m['key'];
      if (k is String && k.isNotEmpty) _models[k] = m;
    }
  }

  static bool supportsFile(String source) {
    final key = source.trim();
    final local = info[key]?['read_files'] as bool?;
    if (local != null) return local;
    return (_models[key]?['read_files'] as bool?) ?? false;
  }

  static Color color(String source) => ModelAccent.raw(source.trim());

  static Color mutedColor(String source, {bool isDark = false}) =>
      ModelAccent.muted(source.trim(), isDark: isDark);

  static bool isImageModel(String key) {
    final k = key.trim();
    if (k == 'gemini_image' || k == 'gpt_image' || k == 'gpt_image2') {
      return true;
    }
    return (_models[k]?['isImage'] as bool?) ?? false;
  }

  static String label(String source) {
    final key = source.trim();
    return (info[key]?['label'] as String?) ??
        (_models[key]?['label'] as String?) ??
        source;
  }

  static String company(String source) =>
      (_models[source.trim()]?['company'] as String?) ?? 'سایر';

  static List<String> tags(String source) {
    final raw = info[source.trim()]?['tags'];
    if (raw is List) return raw.cast<String>();
    return const [];
  }

  static String avatar(String source) {
    final key = source.trim();
    final local = info[key]?['avatar'] as String?;
    if (local != null) return local;
    final icon = _models[key]?['icon'] as String?;
    if (icon != null && icon.trim().isNotEmpty) {
      final name = icon.trim();
      final hasExtension = RegExp(
        r'\.(webp|png|jpe?g|gif)$',
        caseSensitive: false,
      ).hasMatch(name);
      return 'assets/images/ai_icons/${hasExtension ? name : '$name.webp'}';
    }
    return 'assets/images/aiIcon.png';
  }

  static String? avatarUrl(String source) {
    final raw = (_models[source.trim()]?['icon_url'] as String?)?.trim();
    if (raw == null || raw.isEmpty) return null;
    return raw.startsWith('https://') ? raw : null;
  }

  static ImageProvider avatarImage(String source, {int cachePx = 128}) {
    final url = avatarUrl(source);
    final localName =
        (_models[source.trim()]?['icon'] as String?)?.trim() ?? '';
    final hasLocal =
        localName.isNotEmpty &&
        _bundledIcons.contains(
          localName.replaceAll(
            RegExp(r'\.(webp|png|jpe?g|gif)$', caseSensitive: false),
            '',
          ),
        );

    if (!hasLocal && url != null) {
      return jSizedImage(CachedNetworkImageProvider(url), cachePx: cachePx);
    }
    return jAvatarImage(avatar(source), cachePx: cachePx);
  }

  static const Set<String> _bundledIcons = {
    'claude',
    'deepseek',
    'dream',
    'fdeepseek',
    'forest',
    'gemini',
    'geminimid',
    'gemma',
    'glm',
    'gpthigh',
    'gptlow',
    'gptlowmid',
    'gptmid',
    'grok',
    'mai',
    'meta',
    'nano',
    'nex',
    'nvidia',
    'progemini',
    'qwenn',
    'tencent',
    'tencent11',
    'xiaomi',
  };
}
