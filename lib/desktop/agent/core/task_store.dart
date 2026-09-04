import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'agent_storage.dart';
import 'agent_task.dart';
import 'checkpoint_store.dart';

class AgentTaskStore {
  AgentTaskStore._();

  static final instance = AgentTaskStore._();

  final Map<String, AgentTask> _tasks = {};
  final Map<String, _PendingTaskWrite> _pending = {};

  List<AgentTask> get tasks {
    final out = _tasks.values.toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return List.unmodifiable(out);
  }

  AgentTask? byId(String? id) => id == null ? null : _tasks[id];

  AgentStepRecord? stepById(String taskId, String stepId) {
    final task = _tasks[taskId];
    if (task == null) return null;
    for (final step in task.steps) {
      if (step.id == stepId) return step;
    }
    return null;
  }

  String promptSectionForProject(
    String? projectPath, {
    int maxTasks = 8,
    int maxChars = 6000,
  }) {
    if (projectPath == null || projectPath.isEmpty) return '';
    final relevant =
        _tasks.values
            .where(
              (task) =>
                  task.projectPath != null &&
                  p.equals(task.projectPath!, projectPath),
            )
            .toList()
          ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    final lines = <String>[];
    var size = 0;
    for (final task in relevant.take(maxTasks)) {
      final changes = task.changedPaths.take(8).map(p.basename).join('، ');
      final answer = _compact(task.finalAnswer ?? '', 420);
      final line = [
        'کار: ${_compact(task.goal, 300)}',
        if (changes.isNotEmpty) 'فایل‌های تغییرکرده: $changes',
        if (answer.isNotEmpty) 'نتیجه: $answer',
      ].join('\n');
      if (size + line.length > maxChars) break;
      lines.add(line);
      size += line.length;
    }
    if (lines.isEmpty) return '';
    return 'زمینهٔ محلی پروژهٔ فعال (از جدید به قدیم):\n${lines.join('\n---\n')}';
  }

  String? projectPathForSession(int sessionId) {
    final matches =
        _tasks.values
            .where(
              (task) => task.sessionId == sessionId && task.projectPath != null,
            )
            .toList()
          ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return matches.isEmpty ? null : matches.first.projectPath;
  }

  static String _compact(String value, int max) {
    final text = value.trim().replaceAll(RegExp(r'\s+'), ' ');
    return text.length <= max ? text : '${text.substring(0, max)}…';
  }

  Directory? get _directory => AgentStorage.subdir('tasks');

  Future<void> load() async {
    await flush();
    _tasks.clear();
    final dir = _directory;
    if (dir == null) return;
    await AgentStorage.recoverInterruptedWrites(dir);
    try {
      await for (final entity in dir.list()) {
        if (entity is! File || !entity.path.endsWith('.json')) continue;
        try {
          final decoded = jsonDecode(await entity.readAsString());
          if (decoded is! Map) continue;
          final task = AgentTask.fromJson(Map<String, dynamic>.from(decoded));
          if (!_safeId(task.id)) continue;
          if (!task.phase.isTerminal) {
            task
              ..phase = AgentPhase.interrupted
              ..currentAction = null
              ..note(
                'برنامه پیش از پایان این کار بسته شد؛ ادامه نیازمند تأیید کاربر است.',
              )
              ..touch();
            await _chain(task.id, () => _write(task));
          }
          _tasks[task.id] = task;
        } catch (_) {}
      }
    } catch (_) {}
    await _prune();
  }

  static const int maxJournalTasks = 500;

  Future<void> _prune() async {
    final removable =
        _tasks.values.where((task) => task.phase == AgentPhase.done).toList()
          ..sort((a, b) => a.updatedAt.compareTo(b.updatedAt));
    final excess = _tasks.length - maxJournalTasks;
    for (var i = 0; i < excess && i < removable.length; i++) {
      await delete(removable[i].id);
    }
    await AgentCheckpointStore.sweep(
      knownTaskIds: _tasks.keys.toSet(),
      resumableTaskIds: {
        for (final task in _tasks.values)
          if (task.phase != AgentPhase.done) task.id,
      },
    );
  }

  void scheduleSave(AgentTask task) {
    task.touch();
    _tasks[task.id] = task;
    _pending.remove(task.id)?.timer.cancel();
    final pending = _PendingTaskWrite(task, _directory);
    _pending[task.id] = pending;
    pending.timer = Timer(const Duration(milliseconds: 200), () {
      if (!identical(_pending[task.id], pending)) return;
      _pending.remove(task.id);
      _chain(task.id, () => _write(task, pending.directory));
    });
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

  Future<void> flush() async {
    final writes = _pending.values.toList();
    _pending.clear();
    for (final pending in writes) {
      pending.timer.cancel();
      await _chain(
        pending.task.id,
        () => _write(pending.task, pending.directory),
      );
    }
    await Future.wait(_inFlight.values.toList());
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
    _tasks.remove(id);
    final dir = _directory;
    if (dir == null) return;
    final file = File(p.join(dir.path, '$id.json'));
    try {
      if (await file.exists()) await file.delete();
    } catch (_) {}
    await AgentCheckpointStore.discard(id);
  }

  Future<void> _write(AgentTask task, [Directory? capturedDirectory]) async {
    if (!_safeId(task.id)) return;
    final dir = capturedDirectory ?? _directory;
    if (dir == null) return;
    final file = File(p.join(dir.path, '${task.id}.json'));
    final temp = File(
      '${file.path}.${DateTime.now().microsecondsSinceEpoch}.tmp',
    );
    final backup = File('${file.path}.bak');
    try {
      await temp.writeAsString(jsonEncode(task.toJson()), flush: true);
      if (await backup.exists()) await backup.delete();
      if (await file.exists()) await file.rename(backup.path);
      await temp.rename(file.path);
      if (await backup.exists()) await backup.delete();
    } catch (_) {
      try {
        if (!await file.exists() && await backup.exists()) {
          await backup.rename(file.path);
        }
        if (await temp.exists()) await temp.delete();
      } catch (_) {}
    }
  }

  static bool _safeId(String id) =>
      RegExp(r'^task_[A-Za-z0-9_-]+$').hasMatch(id);
}

class _PendingTaskWrite {
  _PendingTaskWrite(this.task, this.directory);

  final AgentTask task;
  final Directory? directory;
  late final Timer timer;
}
