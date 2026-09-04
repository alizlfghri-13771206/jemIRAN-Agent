import 'dart:convert';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/widgets.dart';

abstract final class DesktopAvatarImage {
  static const _maxEntries = 4;
  static final Map<String, ImageProvider> _cache = {};

  static ImageProvider? of(String? raw) {
    final url = raw?.trim();
    if (url == null || url.isEmpty) return null;

    final cached = _cache[url];
    if (cached != null) return cached;

    ImageProvider? provider;
    if (url.startsWith('data:')) {
      try {
        provider = MemoryImage(base64Decode(url.split(',').last));
      } catch (_) {
        return null;
      }
    } else {
      provider = CachedNetworkImageProvider(url);
    }

    if (_cache.length >= _maxEntries) {
      _cache.remove(_cache.keys.first);
    }
    _cache[url] = provider;
    return provider;
  }

  static void clear() => _cache.clear();
}
