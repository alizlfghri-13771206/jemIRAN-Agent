import 'dart:io';

import 'package:path/path.dart' as p;

abstract final class AgentStorage {
  static Directory? _root;
  static Directory? _baseRootForTesting;
  static String _accountKey = 'local';

  static String get accountKey => _accountKey;

  static bool setAccountKey(String key) {
    final normalized = key.trim().toLowerCase();
    if (!RegExp(r'^-?[0-9a-f]{1,16}$').hasMatch(normalized)) return false;
    _accountKey = normalized;
    _root = null;
    return true;
  }

  static void setBaseRootForTesting(Directory? directory) {
    _baseRootForTesting = directory;
    _root = null;
  }

  static void setAccountScope(String identity) {
    final normalized = identity.trim().toLowerCase();
    var hash = 0xcbf29ce484222325;
    for (final byte in normalized.codeUnits) {
      hash ^= byte;
      hash = (hash * 0x100000001b3) & 0xffffffffffffffff;
    }
    _accountKey = hash.toRadixString(16).padLeft(16, '0');
    _root = null;
  }

  static Directory? get root {
    if (_root != null) return _root;
    try {
      final appData =
          Platform.environment['APPDATA'] ??
          Platform.environment['LOCALAPPDATA'];
      if (_baseRootForTesting == null && (appData == null || appData.isEmpty)) {
        return null;
      }
      final base =
          _baseRootForTesting ??
          Directory(p.join(appData!, 'Jemiran', 'agent'));
      if (!base.existsSync()) base.createSync(recursive: true);
      final dir = Directory(p.join(base.path, 'accounts', _accountKey));
      if (!dir.existsSync()) dir.createSync(recursive: true);
      _root = dir;
      _migrateLegacy(base, dir);
      return _root;
    } catch (_) {
      return null;
    }
  }

  static void _migrateLegacy(Directory base, Directory account) {
    try {
      final oldMemory = File(p.join(base.path, 'memory.json'));
      final newMemory = File(p.join(account.path, 'memory.json'));
      if (oldMemory.existsSync() && !newMemory.existsSync()) {
        oldMemory.copySync(newMemory.path);
        oldMemory.deleteSync();
      }
      final oldSkills = Directory(p.join(base.path, 'skills'));
      final newSkills = Directory(p.join(account.path, 'skills'));
      if (oldSkills.existsSync() && !newSkills.existsSync()) {
        oldSkills.renameSync(newSkills.path);
      }
    } catch (_) {}
  }

  static Directory? subdir(String name) {
    final base = root;
    if (base == null) return null;
    try {
      final dir = Directory(p.join(base.path, name));
      if (!dir.existsSync()) dir.createSync(recursive: true);
      return dir;
    } catch (_) {
      return null;
    }
  }

  static Future<int> recoverInterruptedWrites(Directory dir) async {
    var recovered = 0;
    try {
      await for (final entity in dir.list(followLinks: false)) {
        if (entity is! File) continue;
        final path = entity.path;
        if (!path.endsWith('.bak')) continue;
        final target = File(path.substring(0, path.length - 4));
        try {
          if (await target.exists()) {
            await entity.delete();
            continue;
          }
          await entity.rename(target.path);
          recovered++;
        } catch (_) {}
      }
    } catch (_) {}
    return recovered;
  }

  static Future<void> writeTextAtomic(File target, String text) async {
    await target.parent.create(recursive: true);
    final stamp = DateTime.now().microsecondsSinceEpoch;
    final temp = File('${target.path}.$stamp.tmp');
    final backup = File('${target.path}.$stamp.bak');
    await temp.writeAsString(text, flush: true);
    try {
      if (await target.exists()) await target.rename(backup.path);
      await temp.rename(target.path);
      if (await backup.exists()) await backup.delete();
    } catch (_) {
      if (!await target.exists() && await backup.exists()) {
        await backup.rename(target.path);
      }
      rethrow;
    } finally {
      if (await temp.exists()) await temp.delete();
    }
  }
}

abstract final class SecretScrubber {
  static final _patterns = <RegExp>[
    RegExp(r'\b(sk|pk|ghp|gho|ghs|ghu|xox[baprs])[-_][A-Za-z0-9_\-]{16,}\b'),
    RegExp(r'\bAIza[0-9A-Za-z_\-]{20,}\b'),
    RegExp(r'\bey[A-Za-z0-9_\-]{10,}\.[A-Za-z0-9_\-]{10,}\.[A-Za-z0-9_\-]+'),
    RegExp(
      r'-----BEGIN [A-Z ]*PRIVATE KEY-----[\s\S]*?-----END [A-Z ]*PRIVATE KEY-----',
    ),
    RegExp(
      r'''(?<key>\b[A-Za-z0-9_-]{0,24}(?:password|passwd|pwd|secret|token|api[_-]?key|access[_-]?key|client[_-]?secret|private[_-]?key|cookie|session[_-]?id)[A-Za-z0-9_-]{0,24}\b["']?\s*[:=]\s*)(["']?)[^\s"',;]{4,}\2''',
      caseSensitive: false,
    ),
    RegExp(
      r'\b[a-z][a-z0-9+.\-]{0,15}://[^/\s:@]{1,256}:[^/\s@]{1,256}@',
      caseSensitive: false,
    ),
    RegExp(r'\bAuthorization\s*:\s*(?:\S+\s+)?\S+', caseSensitive: false),
  ];

  static const _mask = '«حذف‌شده»';

  static String scrub(String text) {
    var out = text;
    for (final pattern in _patterns) {
      out = out.replaceAllMapped(pattern, (m) {
        if (m is RegExpMatch && m.groupNames.contains('key')) {
          return '${m.namedGroup('key')}$_mask';
        }
        return _mask;
      });
    }
    return out;
  }

  static bool looksSensitive(String text) =>
      RegExp(r'[A-Za-z0-9_\-]{60,}').hasMatch(text);
}
