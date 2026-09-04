import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../core/agent_storage.dart';

enum AuditKind {
  taskStarted('task_started'),
  taskFinished('task_finished'),
  tool('tool'),
  permission('permission'),
  modelSwitch('model_switch'),
  compaction('compaction'),
  error('error');

  const AuditKind(this.wire);

  final String wire;
}

class AuditEntry {
  const AuditEntry({
    required this.at,
    required this.kind,
    required this.fields,
  });

  final DateTime at;
  final String kind;
  final Map<String, dynamic> fields;

  String? get taskId => fields['task'] as String?;
  String? get model => fields['model'] as String?;

  static AuditEntry? tryParse(String line) {
    try {
      final decoded = jsonDecode(line);
      if (decoded is! Map) return null;
      final map = Map<String, dynamic>.from(decoded);
      final ts = (map.remove('ts') as num?)?.toInt();
      final kind = map.remove('kind')?.toString();
      if (ts == null || kind == null) return null;
      return AuditEntry(
        at: DateTime.fromMillisecondsSinceEpoch(ts * 1000),
        kind: kind,
        fields: map,
      );
    } catch (_) {
      return null;
    }
  }
}

abstract final class AuditLog {
  static const _dirName = 'audit';
  static const _activeName = 'audit.jsonl';

  static int maxActiveBytes = 2 * 1024 * 1024;

  static const maxRotatedFiles = 4;

  static bool enabled = true;

  static Directory? _dir() {
    final root = AgentStorage.root;
    if (root == null) return null;
    final dir = Directory(p.join(root.path, _dirName));
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir;
  }

  static File? _activeFile() {
    final dir = _dir();
    return dir == null ? null : File(p.join(dir.path, _activeName));
  }

  static void record(
    AuditKind kind, {
    String? task,
    String? model,
    Map<String, dynamic> fields = const {},
  }) {
    if (!enabled) return;
    try {
      final file = _activeFile();
      if (file == null) return;
      final row = <String, dynamic>{
        'ts': DateTime.now().millisecondsSinceEpoch ~/ 1000,
        'kind': kind.wire,
        'task': ?task,
        'model': ?model,
      };
      for (final entry in fields.entries) {
        final value = entry.value;
        row[entry.key] = value is String
            ? SecretScrubber.scrub(_clip(value))
            : value;
      }
      file.writeAsStringSync(
        '${jsonEncode(row)}\n',
        mode: FileMode.append,
        flush: false,
      );
      _rotateIfNeeded(file);
    } catch (error) {
      stderr.writeln('[audit] ثبت نشد: $error');
    }
  }

  static String _clip(String value, {int max = 600}) =>
      value.length <= max ? value : '${value.substring(0, max)}…';

  static void _rotateIfNeeded(File file) {
    if (!file.existsSync() || file.lengthSync() < maxActiveBytes) return;
    final dir = file.parent;
    final oldest = File(p.join(dir.path, 'audit.$maxRotatedFiles.jsonl'));
    if (oldest.existsSync()) oldest.deleteSync();
    for (var i = maxRotatedFiles - 1; i >= 1; i--) {
      final from = File(p.join(dir.path, 'audit.$i.jsonl'));
      if (from.existsSync()) {
        from.renameSync(p.join(dir.path, 'audit.${i + 1}.jsonl'));
      }
    }
    file.renameSync(p.join(dir.path, 'audit.1.jsonl'));
  }

  static List<File> _files() {
    final dir = _dir();
    if (dir == null) return const [];
    final files = <File>[];
    final active = File(p.join(dir.path, _activeName));
    if (active.existsSync()) files.add(active);
    for (var i = 1; i <= maxRotatedFiles; i++) {
      final rotated = File(p.join(dir.path, 'audit.$i.jsonl'));
      if (rotated.existsSync()) files.add(rotated);
    }
    return files;
  }

  static List<AuditEntry> read({
    int limit = 200,
    Set<AuditKind>? kinds,
    String? taskId,
    String? contains,
    DateTime? since,
  }) {
    final wanted = kinds?.map((kind) => kind.wire).toSet();
    final needle = contains?.trim().toLowerCase();
    final out = <AuditEntry>[];

    for (final file in _files()) {
      List<String> lines;
      try {
        lines = file.readAsLinesSync();
      } catch (_) {
        continue;
      }
      for (var i = lines.length - 1; i >= 0; i--) {
        if (out.length >= limit) return out;
        final line = lines[i];
        if (line.trim().isEmpty) continue;
        if (needle != null && !line.toLowerCase().contains(needle)) continue;
        final entry = AuditEntry.tryParse(line);
        if (entry == null) continue;
        if (wanted != null && !wanted.contains(entry.kind)) continue;
        if (taskId != null && entry.taskId != taskId) continue;
        if (since != null && entry.at.isBefore(since)) continue;
        out.add(entry);
      }
    }
    return out;
  }

  static String exportJsonl({int limit = 5000}) {
    final entries = read(limit: limit);
    final buffer = StringBuffer();
    for (final entry in entries.reversed) {
      buffer.writeln(
        jsonEncode({
          'ts': entry.at.millisecondsSinceEpoch ~/ 1000,
          'kind': entry.kind,
          ...entry.fields,
        }),
      );
    }
    return buffer.toString();
  }

  static void clear() {
    for (final file in _files()) {
      try {
        file.deleteSync();
      } catch (_) {}
    }
  }
}
