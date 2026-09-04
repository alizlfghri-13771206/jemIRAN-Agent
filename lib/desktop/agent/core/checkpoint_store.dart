import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../agent_workspace.dart';
import 'agent_storage.dart';

abstract final class AgentCheckpointStore {
  static const int maxFileBytes = 20 * 1024 * 1024;
  static const int maxTaskBytes = 100 * 1024 * 1024;
  static const int maxDirectoryEntries = 1000;

  static const Duration retention = Duration(days: 14);

  static const Duration hardRetention = Duration(days: 60);

  static final RegExp _taskIdPattern = RegExp(r'^task_[A-Za-z0-9_-]+$');

  static Directory? _taskDir(String taskId) {
    if (!_taskIdPattern.hasMatch(taskId)) return null;
    final root = AgentStorage.subdir('checkpoints');
    if (root == null) return null;
    final dir = Directory(p.join(root.path, taskId));
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir;
  }

  static Future<bool> capture(String taskId, String rawPath) async {
    final dir = _taskDir(taskId);
    if (dir == null) return false;
    final path = p.normalize(p.absolute(rawPath));
    if (AgentWorkspace.owner(path) == null) return false;

    final manifestFile = File(p.join(dir.path, 'manifest.json'));
    final manifest = await _readManifest(manifestFile);
    final entries = (manifest['entries'] as List).cast<Map<String, dynamic>>();
    if (entries.any((entry) => p.equals(entry['path'] as String, path))) {
      return true;
    }

    final type = FileSystemEntity.typeSync(path, followLinks: false);
    if (type == FileSystemEntityType.link) return false;
    final slot = 'snapshot_${entries.length}';
    var bytes = 0;
    try {
      if (type == FileSystemEntityType.file) {
        final source = File(path);
        bytes = await source.length();
        if (bytes > maxFileBytes ||
            _usedBytes(entries) + bytes > maxTaskBytes) {
          return false;
        }
        await source.copy(p.join(dir.path, slot));
      } else if (type == FileSystemEntityType.directory) {
        final target = Directory(p.join(dir.path, slot));
        final copied = await _copyDirectory(
          Directory(path),
          target,
          remainingBytes: maxTaskBytes - _usedBytes(entries),
        );
        if (copied == null) {
          if (await target.exists()) await target.delete(recursive: true);
          return false;
        }
        bytes = copied;
      } else if (type != FileSystemEntityType.notFound) {
        return false;
      }

      entries.add({
        'path': path,
        'type': switch (type) {
          FileSystemEntityType.file => 'file',
          FileSystemEntityType.directory => 'directory',
          _ => 'absent',
        },
        if (type != FileSystemEntityType.notFound) 'snapshot': slot,
        'bytes': bytes,
      });
      await _writeJsonAtomic(manifestFile, manifest);
      return true;
    } catch (_) {
      final snapshot = FileSystemEntity.typeSync(
        p.join(dir.path, slot),
        followLinks: false,
      );
      try {
        if (snapshot == FileSystemEntityType.directory) {
          await Directory(p.join(dir.path, slot)).delete(recursive: true);
        } else if (snapshot != FileSystemEntityType.notFound) {
          await File(p.join(dir.path, slot)).delete();
        }
      } catch (_) {}
      return false;
    }
  }

  static Future<int> rollback(String taskId) async {
    final dir = _taskDir(taskId);
    if (dir == null) return 0;
    final manifestFile = File(p.join(dir.path, 'manifest.json'));
    if (!await manifestFile.exists()) return 0;
    final manifest = await _readManifest(manifestFile);
    final entries = (manifest['entries'] as List).cast<Map<String, dynamic>>();
    var restored = 0;

    for (final entry in entries.reversed) {
      final path = entry['path']?.toString();
      final type = entry['type']?.toString();
      if (path == null || AgentWorkspace.owner(path) == null) continue;
      final slot = entry['snapshot']?.toString();
      if (slot != null && !RegExp(r'^snapshot_\d+$').hasMatch(slot)) continue;
      try {
        if (type == 'absent') {
          await _deleteExisting(path);
        } else if (type == 'file' && slot != null) {
          final source = File(p.join(dir.path, slot));
          if (FileSystemEntity.typeSync(source.path, followLinks: false) !=
              FileSystemEntityType.file) {
            continue;
          }
          await _deleteExisting(path);
          final target = File(path);
          await target.parent.create(recursive: true);
          await source.copy(target.path);
        } else if (type == 'directory' && slot != null) {
          final source = Directory(p.join(dir.path, slot));
          if (FileSystemEntity.typeSync(source.path, followLinks: false) !=
              FileSystemEntityType.directory) {
            continue;
          }
          await _deleteExisting(path);
          final copied = await _copyDirectory(
            source,
            Directory(path),
            remainingBytes: maxTaskBytes,
          );
          if (copied == null) continue;
        } else {
          continue;
        }
        restored++;
      } catch (_) {}
    }
    return restored;
  }

  static Future<void> discard(String taskId) async {
    final dir = _taskDir(taskId);
    try {
      if (dir != null && await dir.exists()) await dir.delete(recursive: true);
    } catch (_) {}
  }

  static Future<void> sweep({
    required Set<String> knownTaskIds,
    required Set<String> resumableTaskIds,
    DateTime? now,
  }) async {
    final root = AgentStorage.subdir('checkpoints');
    if (root == null) return;
    final at = now ?? DateTime.now();
    final softCutoff = at.subtract(retention);
    final hardCutoff = at.subtract(hardRetention);
    try {
      await for (final entity in root.list(followLinks: false)) {
        if (entity is! Directory) continue;
        final id = p.basename(entity.path);
        if (!_taskIdPattern.hasMatch(id)) continue;
        bool expired;
        if (!knownTaskIds.contains(id)) {
          expired = true;
        } else {
          DateTime modified;
          try {
            modified = (await entity.stat()).modified;
          } catch (_) {
            continue;
          }
          expired = modified.isBefore(
            resumableTaskIds.contains(id) ? hardCutoff : softCutoff,
          );
        }
        if (!expired) continue;
        try {
          await entity.delete(recursive: true);
        } catch (_) {}
      }
    } catch (_) {}
  }

  static Future<Map<String, dynamic>> _readManifest(File file) async {
    try {
      if (await file.exists()) {
        final decoded = jsonDecode(await file.readAsString());
        if (decoded is Map && decoded['entries'] is List) {
          return {
            'version': 1,
            'entries': [
              for (final raw in decoded['entries'] as List)
                if (raw is Map) Map<String, dynamic>.from(raw),
            ],
          };
        }
      }
    } catch (_) {}
    return {'version': 1, 'entries': <Map<String, dynamic>>[]};
  }

  static int _usedBytes(List<Map<String, dynamic>> entries) => entries.fold(
    0,
    (sum, entry) => sum + ((entry['bytes'] as num?)?.toInt() ?? 0),
  );

  static Future<int?> _copyDirectory(
    Directory source,
    Directory target, {
    required int remainingBytes,
  }) async {
    var entries = 0;
    var bytes = 0;
    await target.create(recursive: true);
    await for (final entity in source.list(
      recursive: true,
      followLinks: false,
    )) {
      entries++;
      if (entries > maxDirectoryEntries) return null;
      final relative = p.relative(entity.path, from: source.path);
      final destination = p.join(target.path, relative);
      if (entity is Directory) {
        await Directory(destination).create(recursive: true);
      } else if (entity is File) {
        final size = await entity.length();
        bytes += size;
        if (size > maxFileBytes || bytes > remainingBytes) return null;
        await File(destination).parent.create(recursive: true);
        await entity.copy(destination);
      } else {
        return null;
      }
    }
    return bytes;
  }

  static Future<void> _deleteExisting(String path) async {
    final type = FileSystemEntity.typeSync(path, followLinks: false);
    if (type == FileSystemEntityType.directory) {
      await Directory(path).delete(recursive: true);
    } else if (type != FileSystemEntityType.notFound) {
      await File(path).delete();
    }
  }

  static Future<void> _writeJsonAtomic(
    File target,
    Map<String, dynamic> value,
  ) async {
    final temp = File('${target.path}.tmp');
    final backup = File('${target.path}.bak');
    await temp.writeAsString(jsonEncode(value), flush: true);
    try {
      if (await backup.exists()) await backup.delete();
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
