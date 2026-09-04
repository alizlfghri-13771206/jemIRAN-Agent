import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../agent_workspace.dart';
import 'agent_storage.dart';
import 'task_store.dart';

class WorkSession {
  WorkSession({
    required this.id,
    required this.title,
    required this.createdAt,
    required this.updatedAt,
    this.transportSessionId,
    this.modelKey,
    this.projectPath,
    this.pinned = false,
    this.tainted = false,
    this.pinnedAt,
    List<AgentResource>? resources,
    List<Map<String, dynamic>>? timeline,
    this.activeTaskId,
  }) : resources = resources ?? <AgentResource>[],
       timeline = timeline ?? <Map<String, dynamic>>[];

  final String id;
  String title;
  final DateTime createdAt;
  DateTime updatedAt;
  int? transportSessionId;
  String? modelKey;
  String? projectPath;
  bool pinned;

  bool tainted;
  DateTime? pinnedAt;
  List<AgentResource> resources;
  List<Map<String, dynamic>> timeline;
  String? activeTaskId;

  Map<String, dynamic> toJson() => {
    'version': 1,
    'id': id,
    'title': SecretScrubber.scrub(title),
    'created_at': createdAt.toIso8601String(),
    'updated_at': updatedAt.toIso8601String(),
    if (transportSessionId != null) 'transport_session_id': transportSessionId,
    if (modelKey != null) 'model': modelKey,
    if (projectPath != null) 'project_path': projectPath,
    'pinned': pinned,
    'tainted': tainted,
    if (pinnedAt != null) 'pinned_at': pinnedAt!.toIso8601String(),
    'resources': resources.map((item) => item.toJson()).toList(),
    'timeline': timeline.map(_scrubTimelineEntry).toList(),
    if (activeTaskId != null) 'active_task_id': activeTaskId,
  };

  factory WorkSession.fromJson(Map<String, dynamic> json) {
    final resources = <AgentResource>[];
    for (final raw in json['resources'] as List? ?? const []) {
      if (raw is! Map) continue;
      final resource = AgentResource.fromJson(Map<String, dynamic>.from(raw));
      if (resource != null) resources.add(resource);
    }
    final timeline = <Map<String, dynamic>>[];
    for (final raw in json['timeline'] as List? ?? const []) {
      if (raw is Map) timeline.add(Map<String, dynamic>.from(raw));
    }
    return WorkSession(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? 'Work جدید',
      createdAt:
          DateTime.tryParse(json['created_at']?.toString() ?? '') ??
          DateTime.now(),
      updatedAt:
          DateTime.tryParse(json['updated_at']?.toString() ?? '') ??
          DateTime.now(),
      transportSessionId: (json['transport_session_id'] as num?)?.toInt(),
      modelKey: json['model']?.toString(),
      projectPath: json['project_path']?.toString(),
      pinned: json['pinned'] == true,
      tainted: json['tainted'] == true,
      pinnedAt: DateTime.tryParse(json['pinned_at']?.toString() ?? ''),
      resources: resources,
      timeline: timeline,
      activeTaskId: json['active_task_id']?.toString(),
    );
  }

  static Map<String, dynamic> _scrubTimelineEntry(Map<String, dynamic> entry) {
    final out = Map<String, dynamic>.from(entry);
    final rawMessage = out['message'];
    if (rawMessage is Map) {
      final message = Map<String, dynamic>.from(rawMessage);
      if (message['text'] is String) {
        message['text'] = SecretScrubber.scrub(message['text'] as String);
      }
      if (message['replyToPreview'] is String) {
        message['replyToPreview'] = SecretScrubber.scrub(
          message['replyToPreview'] as String,
        );
      }
      out['message'] = message;
    }
    return out;
  }
}

class WorkSessionStore extends ChangeNotifier {
  WorkSessionStore._();

  static final instance = WorkSessionStore._();

  final Map<String, WorkSession> _works = {};
  final Map<String, _PendingWorkWrite> _pending = {};
  static int _sequence = 0;

  List<WorkSession> get works {
    final result = _works.values.toList()
      ..sort((a, b) {
        if (a.pinned != b.pinned) return a.pinned ? -1 : 1;
        if (a.pinned && b.pinned) {
          final pinnedOrder = (b.pinnedAt ?? b.updatedAt).compareTo(
            a.pinnedAt ?? a.updatedAt,
          );
          if (pinnedOrder != 0) return pinnedOrder;
        }
        return b.updatedAt.compareTo(a.updatedAt);
      });
    return List.unmodifiable(result);
  }

  WorkSession? byId(String? id) => id == null ? null : _works[id];

  Directory? get _directory => AgentStorage.subdir('works');

  Future<void> load() async {
    await flush();
    _works.clear();
    final dir = _directory;
    if (dir == null) return;
    await AgentStorage.recoverInterruptedWrites(dir);
    try {
      await for (final entity in dir.list(followLinks: false)) {
        if (entity is! File || !entity.path.endsWith('.json')) continue;
        try {
          final decoded = jsonDecode(await entity.readAsString());
          if (decoded is! Map) continue;
          final work = WorkSession.fromJson(Map<String, dynamic>.from(decoded));
          if (!_safeId(work.id)) continue;
          work.resources = work.resources.where(_resourceExists).toList();
          if (work.projectPath != null &&
              !work.resources.any(
                (item) =>
                    item.isDirectory && p.equals(item.path, work.projectPath!),
              )) {
            work.projectPath = work.resources
                .where((item) => item.isDirectory)
                .firstOrNull
                ?.path;
          }
          _works[work.id] = work;
        } catch (_) {}
      }
    } catch (_) {}
    await _migrateTasksIfNeeded();
    notifyListeners();
  }

  static const _migrationMarker = 'migrated_v1.marker';

  Future<void> _migrateTasksIfNeeded() async {
    final dir = _directory;
    if (dir == null) return;
    final marker = File(p.join(dir.path, _migrationMarker));
    try {
      if (marker.existsSync()) return;
    } catch (_) {
      return;
    }

    final owned = <String>{
      for (final work in _works.values) ...[
        if (work.activeTaskId != null) work.activeTaskId!,
        for (final entry in work.timeline)
          if (entry['kind'] == 'step' && entry['task_id'] != null)
            entry['task_id'].toString(),
      ],
    };

    final grouped = <String, List<dynamic>>{};
    for (final task in AgentTaskStore.instance.tasks) {
      if (owned.contains(task.id)) continue;
      final key = task.sessionId == null ? task.id : 's_${task.sessionId}';
      grouped.putIfAbsent(key, () => []).add(task);
    }
    for (final entry in grouped.entries) {
      final id = 'work_${entry.key}';
      if (_works.containsKey(id)) continue;
      final tasks = entry.value
        ..sort((a, b) => a.startedAt.compareTo(b.startedAt));
      final first = tasks.first;
      final last = tasks.last;
      final resources = <AgentResource>[];
      if (first.projectPath != null &&
          Directory(first.projectPath!).existsSync()) {
        resources.add(
          AgentResource(
            path: first.projectPath!,
            kind: ResourceKind.directory,
            canWrite: true,
          ),
        );
      }
      final timeline = <Map<String, dynamic>>[];
      for (final task in tasks) {
        timeline.add({
          'kind': 'message',
          'message': {
            'id': 'legacy_user_${task.id}',
            'text': task.goal,
            'isUser': true,
          },
        });
        for (final step in task.steps) {
          timeline.add({
            'kind': 'step',
            'task_id': task.id,
            'step_id': step.id,
          });
        }
        if (task.finalAnswer?.trim().isNotEmpty == true) {
          timeline.add({
            'kind': 'message',
            'message': {
              'id': 'legacy_ai_${task.id}',
              'text': task.finalAnswer,
              'isUser': false,
              'aiSource': task.modelKey,
            },
          });
        }
      }
      final work = WorkSession(
        id: id,
        title: _titleFrom(first.goal),
        createdAt: first.startedAt,
        updatedAt: last.updatedAt,
        transportSessionId: first.sessionId,
        modelKey: last.modelKey,
        projectPath: first.projectPath,
        resources: resources,
        timeline: timeline,
        activeTaskId: last.phase.isTerminal ? null : last.id,
      );
      _works[id] = work;
      await _chain(work.id, () => _write(work));
    }

    try {
      await marker.writeAsString(DateTime.now().toIso8601String(), flush: true);
    } catch (_) {}
  }

  Future<WorkSession> create({
    String? projectPath,
    List<AgentResource>? resources,
  }) async {
    final now = DateTime.now();
    final id =
        'work_${now.microsecondsSinceEpoch.toRadixString(36)}_${(_sequence++).toRadixString(36)}';
    final work = WorkSession(
      id: id,
      title: 'Work جدید',
      createdAt: now,
      updatedAt: now,
      projectPath: projectPath,
      resources: List<AgentResource>.from(resources ?? const []),
    );
    _works[id] = work;
    await _chain(work.id, () => _write(work));
    notifyListeners();
    return work;
  }

  Future<void> save(WorkSession work, {bool immediate = false}) async {
    if (!_safeId(work.id)) return;
    work.updatedAt = DateTime.now();
    _works[work.id] = work;
    _pending.remove(work.id)?.timer.cancel();
    final pending = _PendingWorkWrite(work, _directory);
    _pending[work.id] = pending;
    if (immediate) {
      _pending.remove(work.id);
      await _chain(work.id, () => _write(work, pending.directory));
    } else {
      pending.timer = Timer(const Duration(milliseconds: 180), () {
        if (!identical(_pending[work.id], pending)) return;
        _pending.remove(work.id);
        _chain(work.id, () => _write(work, pending.directory));
      });
    }
    notifyListeners();
  }

  Future<void> rename(String id, String title) async {
    final work = _works[id];
    final clean = title.trim();
    if (work == null || clean.isEmpty) return;
    work.title = clean.length > 80 ? clean.substring(0, 80) : clean;
    work.updatedAt = DateTime.now();
    await _chain(work.id, () => _write(work));
    notifyListeners();
  }

  Future<void> togglePin(String id) async {
    final work = _works[id];
    if (work == null) return;
    work.pinned = !work.pinned;
    work.pinnedAt = work.pinned ? DateTime.now() : null;
    work.updatedAt = DateTime.now();
    await _chain(work.id, () => _write(work));
    notifyListeners();
  }

  final Map<String, Future<void>> _inFlight = {};

  Future<void> _chain(String id, Future<void> Function() write) {
    final previous = _inFlight[id];
    final next = previous == null
        ? write()
        : previous.then((_) => write(), onError: (_) => write());
    _inFlight[id] = next;
    unawaited(
      next.whenComplete(() {
        if (identical(_inFlight[id], next)) _inFlight.remove(id);
      }),
    );
    return next;
  }

  Future<void> delete(String id) async {
    if (!_safeId(id)) return;
    _pending.remove(id)?.timer.cancel();
    final running = _inFlight.remove(id);
    if (running != null) {
      try {
        await running;
      } catch (_) {}
    }
    final removed = _works.remove(id);
    final dir = _directory;
    if (dir != null) {
      final file = File(p.join(dir.path, '$id.json'));
      try {
        if (await file.exists()) await file.delete();
      } catch (_) {}
    }
    if (removed != null) {
      final taskIds = <String>{
        if (removed.activeTaskId != null) removed.activeTaskId!,
        for (final entry in removed.timeline)
          if (entry['kind'] == 'step' && entry['task_id'] != null)
            entry['task_id'].toString(),
      };
      for (final taskId in taskIds) {
        await AgentTaskStore.instance.delete(taskId);
      }
    }
    notifyListeners();
  }

  Future<void> flush() async {
    final writes = _pending.values.toList();
    _pending.clear();
    for (final pending in writes) {
      pending.timer.cancel();
      await _chain(
        pending.work.id,
        () => _write(pending.work, pending.directory),
      );
    }
    await Future.wait(_inFlight.values.toList());
  }

  Future<void> _write(WorkSession work, [Directory? capturedDirectory]) async {
    if (!_safeId(work.id)) return;
    final dir = capturedDirectory ?? _directory;
    if (dir == null) return;
    try {
      await AgentStorage.writeTextAtomic(
        File(p.join(dir.path, '${work.id}.json')),
        jsonEncode(work.toJson()),
      );
    } catch (_) {}
  }

  static String _titleFrom(String text) {
    final clean = text.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (clean.isEmpty) return 'Work جدید';
    return clean.length <= 54 ? clean : '${clean.substring(0, 54)}…';
  }

  static bool _resourceExists(AgentResource item) => item.isDirectory
      ? Directory(item.path).existsSync()
      : File(item.path).existsSync();

  static bool _safeId(String id) =>
      RegExp(r'^work_[A-Za-z0-9_-]+$').hasMatch(id);
}

class _PendingWorkWrite {
  _PendingWorkWrite(this.work, this.directory);

  final WorkSession work;
  final Directory? directory;
  Timer timer = Timer(Duration.zero, () {});
}
