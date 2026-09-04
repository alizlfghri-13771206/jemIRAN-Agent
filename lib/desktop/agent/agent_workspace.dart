import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'core/agent_storage.dart';

enum ResourceKind { directory, file }

class AgentResource {
  const AgentResource({
    required this.path,
    required this.kind,
    this.canRead = true,
    this.canWrite = false,
    this.canDelete = false,
  });

  final String path;
  final ResourceKind kind;
  final bool canRead;
  final bool canWrite;
  final bool canDelete;

  bool get isDirectory => kind == ResourceKind.directory;

  String get name => p.basename(path);

  AgentResource copyWith({bool? canRead, bool? canWrite, bool? canDelete}) =>
      AgentResource(
        path: path,
        kind: kind,
        canRead: canRead ?? this.canRead,
        canWrite: canWrite ?? this.canWrite,
        canDelete: canDelete ?? this.canDelete,
      );

  Map<String, dynamic> toJson() => {
    'path': path,
    'kind': kind.name,
    'read': canRead,
    'write': canWrite,
    'delete': canDelete,
  };

  static AgentResource? fromJson(Map<String, dynamic> json) {
    final path = (json['path'] ?? '').toString();
    if (path.isEmpty) return null;
    return AgentResource(
      path: path,
      kind: (json['kind'] ?? 'directory') == 'file'
          ? ResourceKind.file
          : ResourceKind.directory,
      canRead: json['read'] != false,
      canWrite: json['write'] == true,
      canDelete: json['delete'] == true,
    );
  }

  String get shortPermissions =>
      [if (canRead) 'خ', if (canWrite) 'ن', if (canDelete) 'ح'].join(' ');

  String get permissionLabel {
    final parts = <String>[
      if (canRead) 'خواندن',
      if (canWrite) 'نوشتن',
      if (canDelete) 'حذف',
    ];
    return parts.isEmpty ? 'بدون دسترسی' : parts.join('، ');
  }
}

class AgentWorkspaceSnapshot {
  const AgentWorkspaceSnapshot({
    required this.resources,
    required this.activeProjectPath,
  });

  final List<AgentResource> resources;
  final String? activeProjectPath;
}

class AgentWorkspace {
  AgentWorkspace._();

  static const _legacyKey = 'desktop_agent_roots_v1';

  static const _prefsKey = 'desktop_agent_resources_v1';
  static const _activeProjectKey = 'desktop_agent_active_project_v1';
  static String get _scopedPrefsKey =>
      '${_prefsKey}_${AgentStorage.accountKey}';
  static String get _scopedActiveProjectKey =>
      '${_activeProjectKey}_${AgentStorage.accountKey}';

  static final List<AgentResource> _resources = [];
  static String? _activeProjectPath;
  static final Object _zoneSnapshotKey = Object();

  static AgentWorkspaceSnapshot? get _zoneSnapshot =>
      Zone.current[_zoneSnapshotKey] as AgentWorkspaceSnapshot?;

  static List<AgentResource> get _effectiveResources =>
      _zoneSnapshot?.resources ?? _resources;

  static String? get _effectiveActiveProject =>
      _zoneSnapshot?.activeProjectPath ?? _activeProjectPath;

  static List<AgentResource> get resources =>
      List.unmodifiable(_effectiveResources);

  static List<String> get roots =>
      List.unmodifiable(_effectiveResources.map((r) => r.path));

  static bool get hasRoot => _effectiveResources.isNotEmpty;

  static String? get primaryRoot {
    final resources = _effectiveResources;
    final active = _effectiveActiveProject;
    if (active != null &&
        resources.any((r) => r.isDirectory && p.equals(r.path, active))) {
      return active;
    }
    for (final r in resources) {
      if (r.isDirectory) return r.path;
    }
    return null;
  }

  static Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final scopedRaw = prefs.getStringList(_scopedPrefsKey);
      final savedActiveProject = prefs.getString(_scopedActiveProjectKey);
      final legacyRaw = prefs.getStringList(_prefsKey);
      final legacyRoots = prefs.getStringList(_legacyKey);
      final raw = scopedRaw ?? legacyRaw;

      final loaded = <AgentResource>[];
      if (raw != null) {
        for (final line in raw) {
          try {
            final decoded = jsonDecode(line);
            if (decoded is! Map) continue;
            final res = AgentResource.fromJson(
              Map<String, dynamic>.from(decoded),
            );
            if (res != null) loaded.add(res);
          } catch (_) {}
        }
      } else {
        for (final dir in legacyRoots ?? const <String>[]) {
          loaded.add(
            AgentResource(
              path: dir,
              kind: ResourceKind.directory,
              canWrite: true,
            ),
          );
        }
      }

      _resources
        ..clear()
        ..addAll(loaded.where(_exists));
      _activeProjectPath =
          _resources.any(
            (r) => r.isDirectory && p.equals(r.path, savedActiveProject ?? ''),
          )
          ? savedActiveProject
          : null;

      if ((scopedRaw == null || raw == null) && _resources.isNotEmpty) {
        await _persist();
      }
      if (scopedRaw == null && (legacyRaw != null || legacyRoots != null)) {
        await prefs.remove(_prefsKey);
        await prefs.remove(_legacyKey);
      }
    } catch (_) {}
  }

  static bool _exists(AgentResource r) => r.isDirectory
      ? Directory(r.path).existsSync()
      : File(r.path).existsSync();

  static Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(
        _scopedPrefsKey,
        _resources.map((r) => jsonEncode(r.toJson())).toList(),
      );
      final active = primaryRoot;
      if (active == null) {
        await prefs.remove(_scopedActiveProjectKey);
      } else {
        await prefs.setString(_scopedActiveProjectKey, active);
      }
    } catch (_) {}
  }

  static Future<bool> addDirectory(
    String dir, {
    bool canWrite = true,
    bool canDelete = false,
  }) async {
    final normalized = _canonicalize(p.normalize(p.absolute(dir)));
    if (normalized == null || !Directory(normalized).existsSync()) return false;
    if (_resources.any((r) => p.equals(r.path, normalized))) return false;

    _resources.add(
      AgentResource(
        path: normalized,
        kind: ResourceKind.directory,
        canWrite: canWrite,
        canDelete: canDelete,
      ),
    );
    _activeProjectPath ??= normalized;
    await _persist();
    return true;
  }

  static Future<bool> addFile(
    String file, {
    bool canWrite = true,
    bool canDelete = false,
  }) async {
    final normalized = _canonicalize(p.normalize(p.absolute(file)));
    if (normalized == null || !File(normalized).existsSync()) return false;
    if (_resources.any((r) => p.equals(r.path, normalized))) return false;
    _resources.add(
      AgentResource(
        path: normalized,
        kind: ResourceKind.file,
        canWrite: canWrite,
        canDelete: canDelete,
      ),
    );
    await _persist();
    return true;
  }

  static Future<bool> addRoot(String dir) => addDirectory(dir);

  static Future<void> removeRoot(String path) async {
    final canonical = _canonicalize(path);
    _resources.removeWhere((r) {
      final resourcePath = _canonicalize(r.path);
      return canonical != null &&
          resourcePath != null &&
          p.equals(resourcePath, canonical);
    });
    if (_activeProjectPath != null && p.equals(_activeProjectPath!, path)) {
      _activeProjectPath = null;
    }
    await _persist();
  }

  static Future<void> setPrimaryProject(String path) async {
    final canonical = _canonicalize(path);
    if (canonical == null) return;
    final resource = _resources.where(
      (r) => r.isDirectory && p.equals(r.path, canonical),
    );
    if (resource.isEmpty) return;
    _activeProjectPath = resource.first.path;
    await _persist();
  }

  static Future<void> setPermissions(
    String path, {
    bool? canRead,
    bool? canWrite,
    bool? canDelete,
  }) async {
    final canonical = _canonicalize(path);
    if (canonical == null) return;
    for (var i = 0; i < _resources.length; i++) {
      final resourcePath = _canonicalize(_resources[i].path);
      if (resourcePath == null || !p.equals(resourcePath, canonical)) continue;
      _resources[i] = _resources[i].copyWith(
        canRead: canRead,
        canWrite: canWrite,
        canDelete: canDelete,
      );
      await _persist();
      return;
    }
  }

  static Future<void> clear() async {
    _resources.clear();
    _activeProjectPath = null;
    await _persist();
  }

  static AgentWorkspaceSnapshot snapshot() => AgentWorkspaceSnapshot(
    resources: List<AgentResource>.unmodifiable(_resources),
    activeProjectPath: primaryRoot,
  );

  static Future<void> replace(
    List<AgentResource> resources, {
    String? activeProjectPath,
  }) async {
    _resources
      ..clear()
      ..addAll(resources.where(_exists));
    _activeProjectPath =
        activeProjectPath != null &&
            _resources.any(
              (item) =>
                  item.isDirectory && p.equals(item.path, activeProjectPath),
            )
        ? activeProjectPath
        : null;
    await _persist();
  }

  static Future<T> runWithSnapshot<T>(
    AgentWorkspaceSnapshot snapshot,
    Future<T> Function() action,
  ) => runZoned(
    action,
    zoneValues: <Object, Object>{_zoneSnapshotKey: snapshot},
  );

  static AgentResource? owner(String absolutePath) {
    final target = _canonicalize(absolutePath);
    if (target == null) return null;
    AgentResource? mostSpecific;
    var mostSpecificLength = -1;
    for (final r in _effectiveResources) {
      final root = _canonicalize(r.path);
      if (root == null) continue;
      final matches =
          p.equals(root, target) || (r.isDirectory && p.isWithin(root, target));
      if (!matches) continue;
      if (root.length > mostSpecificLength) {
        mostSpecific = r;
        mostSpecificLength = root.length;
      }
    }
    return mostSpecific;
  }

  static bool isAllowed(String absolutePath) => owner(absolutePath) != null;

  static bool isResourceRoot(String absolutePath) {
    final target = canonical(absolutePath);
    if (target == null) return false;
    for (final resource in _effectiveResources) {
      final root = canonical(resource.path);
      if (root != null && p.equals(root, target)) return true;
    }
    return false;
  }

  static bool canRead(String absolutePath) =>
      owner(absolutePath)?.canRead ?? false;

  static bool canWrite(String absolutePath) =>
      owner(absolutePath)?.canWrite ?? false;

  static bool canDelete(String absolutePath) =>
      owner(absolutePath)?.canDelete ?? false;

  static String? resolve(String rawPath) {
    final absolute = toAbsolute(rawPath);
    if (absolute == null) return null;
    final canonical = _canonicalize(absolute);
    if (canonical == null) return null;
    return isAllowed(canonical) ? canonical : null;
  }

  static String? canonical(String rawPath) => _canonicalize(rawPath);

  static String? _canonicalize(String rawPath) {
    var cursor = p.normalize(p.absolute(rawPath));
    final missingTail = <String>[];

    while (FileSystemEntity.typeSync(cursor, followLinks: true) ==
        FileSystemEntityType.notFound) {
      final parent = p.dirname(cursor);
      if (p.equals(parent, cursor)) return null;
      missingTail.insert(0, p.basename(cursor));
      cursor = parent;
    }

    try {
      final type = FileSystemEntity.typeSync(cursor, followLinks: true);
      final resolved = type == FileSystemEntityType.directory
          ? Directory(cursor).resolveSymbolicLinksSync()
          : File(cursor).resolveSymbolicLinksSync();
      return p.normalize(
        missingTail.isEmpty ? resolved : p.joinAll([resolved, ...missingTail]),
      );
    } on FileSystemException {
      return null;
    }
  }

  static String? toAbsolute(String rawPath) {
    final input = rawPath.trim();
    if (input.isEmpty) return null;

    final root = primaryRoot;
    final absolute = p.isAbsolute(input)
        ? input
        : (root == null ? null : p.join(root, input));
    if (absolute == null) return null;
    return p.normalize(absolute);
  }

  static String display(String absolutePath) {
    for (final r in _effectiveResources) {
      if (r.isDirectory && p.isWithin(r.path, absolutePath)) {
        return p.relative(absolutePath, from: r.path).replaceAll('\\', '/');
      }
      if (p.equals(r.path, absolutePath)) return p.basename(r.path);
    }

    final target = canonical(absolutePath);
    if (target == null) return absolutePath;
    for (final r in _effectiveResources) {
      final root = canonical(r.path);
      if (root == null) continue;
      if (r.isDirectory && p.isWithin(root, target)) {
        return p.relative(target, from: root).replaceAll('\\', '/');
      }
      if (p.equals(root, target)) return p.basename(root);
    }
    return absolutePath;
  }
}

class AgentWorkspaceNotifier extends Notifier<int> {
  @override
  int build() => 0;

  Future<void> pick(String dir) async {
    if (await AgentWorkspace.addDirectory(dir)) state++;
  }

  Future<void> pickFile(String file) async {
    if (await AgentWorkspace.addFile(file)) state++;
  }

  Future<void> remove(String path) async {
    await AgentWorkspace.removeRoot(path);
    state++;
  }

  Future<void> selectProject(String path) async {
    await AgentWorkspace.setPrimaryProject(path);
    state++;
  }

  Future<void> setPermissions(
    String path, {
    bool? canRead,
    bool? canWrite,
    bool? canDelete,
  }) async {
    await AgentWorkspace.setPermissions(
      path,
      canRead: canRead,
      canWrite: canWrite,
      canDelete: canDelete,
    );
    state++;
  }

  void bump() => state++;
}

final agentWorkspaceProvider = NotifierProvider<AgentWorkspaceNotifier, int>(
  AgentWorkspaceNotifier.new,
);
