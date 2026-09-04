import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('مخزن شامل endpoint خصوصی یا زیرساخت قدیمی نیست', () {
    final forbidden = <String>[
      ['Desktop', 'Agent', 'Api'].join(),
      ['Jemiran', 'Model', 'Adapter'].join(),
      ['Token', 'Storage'].join(),
      ['merchant', '_id'].join(),
      ['ADMIN', '_SECRET'].join(),
      ['OPENROUTER', '_API_KEY'].join(),
    ];
    final publicIpv4 = RegExp(
      r'(?<![\d.])((?!10\.|127\.|169\.254\.|192\.168\.)'
      r'(?!172\.(1[6-9]|2\d|3[01])\.)'
      r'(?:\d{1,3}\.){3}\d{1,3})(?![\d.])',
    );
    const textExtensions = {
      '.dart',
      '.md',
      '.yaml',
      '.yml',
      '.json',
      '.toml',
      '.txt',
      '.cpp',
      '.cc',
      '.c',
      '.h',
      '.hpp',
      '.cmake',
      '.rc',
    };
    final offenders = <String>[];

    for (final entity in Directory.current.listSync(recursive: true)) {
      if (entity is! File) continue;
      final normalized = entity.path.replaceAll('\\', '/');
      if (normalized.contains('/.git/') ||
          normalized.contains('/.dart_tool/') ||
          normalized.contains('/ephemeral/') ||
          normalized.contains('/build/')) {
        continue;
      }
      final dot = normalized.lastIndexOf('.');
      if (dot < 0 || !textExtensions.contains(normalized.substring(dot))) {
        continue;
      }
      String source;
      try {
        source = entity.readAsStringSync();
      } catch (_) {
        continue;
      }
      for (final needle in forbidden) {
        if (source.contains(needle)) offenders.add('$normalized: $needle');
      }
      for (final match in publicIpv4.allMatches(source)) {
        offenders.add('$normalized: public IPv4 ${match.group(1)}');
      }
    }

    expect(offenders, isEmpty, reason: offenders.join(' | '));
  });
}
