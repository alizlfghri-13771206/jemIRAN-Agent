import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../core/agent_storage.dart';

enum MemoryScope {
  user,

  project,

  task;

  static MemoryScope parse(String? raw) {
    final key = (raw ?? '').trim().toLowerCase();
    for (final s in MemoryScope.values) {
      if (s.name == key) return s;
    }
    return MemoryScope.project;
  }

  String get label => switch (this) {
    user => 'کاربر',
    project => 'پروژه',
    task => 'کار جاری',
  };
}

class MemoryNote {
  MemoryNote({
    required this.id,
    required this.scope,
    required this.text,
    this.projectPath,
    this.taskId,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  final String id;
  final MemoryScope scope;
  final String text;

  final String? projectPath;
  final String? taskId;

  final DateTime createdAt;

  static int _sequence = 0;

  static String newId() =>
      'm_${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}'
      '_${(_sequence++).toRadixString(36)}';

  Map<String, dynamic> toJson() => {
    'id': id,
    'scope': scope.name,
    'text': text,
    if (projectPath != null) 'project_path': projectPath,
    if (taskId != null) 'task_id': taskId,
    'created_at': createdAt.toIso8601String(),
  };

  static MemoryNote? fromJson(Map<String, dynamic> json) {
    final text = (json['text'] ?? '').toString().trim();
    if (text.isEmpty) return null;
    return MemoryNote(
      id: (json['id'] ?? '').toString().isEmpty
          ? newId()
          : json['id'].toString(),
      scope: MemoryScope.parse(json['scope']?.toString()),
      text: SecretScrubber.scrub(
        text.length <= MemoryStore.maxNoteChars
            ? text
            : '${text.substring(0, MemoryStore.maxNoteChars)}…',
      ),
      projectPath: json['project_path']?.toString(),
      taskId: json['task_id']?.toString(),
      createdAt: DateTime.tryParse((json['created_at'] ?? '').toString()),
    );
  }
}

class MemoryStore {
  MemoryStore._();

  static final instance = MemoryStore._();

  final List<MemoryNote> _notes = [];
  String? _loadedAccount;

  List<MemoryNote> get all => List.unmodifiable(_notes);

  File? get _file {
    final dir = AgentStorage.root;
    return dir == null ? null : File(p.join(dir.path, 'memory.json'));
  }

  Future<void> load() async {
    final account = AgentStorage.accountKey;
    if (_loadedAccount == account) return;
    _loadedAccount = account;
    _notes.clear();
    final file = _file;
    if (file == null || !file.existsSync()) return;
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! List) return;
      for (final item in decoded) {
        if (item is! Map) continue;
        final note = MemoryNote.fromJson(Map<String, dynamic>.from(item));
        if (note != null) _notes.add(note);
      }
      for (final scope in MemoryScope.values) {
        _pruneScope(scope);
      }
    } catch (_) {}
  }

  Future<void> _persist() async {
    final file = _file;
    if (file == null) return;
    try {
      final durable = _notes
          .where((n) => n.scope != MemoryScope.task)
          .map((n) => n.toJson())
          .toList();
      await AgentStorage.writeTextAtomic(
        file,
        const JsonEncoder.withIndent('  ').convert(durable),
      );
    } catch (_) {}
  }

  static const maxNoteChars = 600;

  static const maxNotesPerScope = 60;

  Future<MemoryNote> remember({
    required MemoryScope scope,
    required String text,
    String? projectPath,
    String? taskId,
  }) async {
    final clean = SecretScrubber.scrub(text.trim());
    final clipped = clean.length <= maxNoteChars
        ? clean
        : '${clean.substring(0, maxNoteChars)}…';

    final duplicate = _notes.firstWhere(
      (n) =>
          n.scope == scope &&
          n.text == clipped &&
          (projectPath == null || n.projectPath == projectPath),
      orElse: () => MemoryNote(id: '', scope: scope, text: ''),
    );
    if (duplicate.id.isNotEmpty) return duplicate;

    final note = MemoryNote(
      id: MemoryNote.newId(),
      scope: scope,
      text: clipped,
      projectPath: projectPath,
      taskId: taskId,
    );
    _notes.insert(0, note);
    _pruneScope(scope);
    await _persist();
    return note;
  }

  void _pruneScope(MemoryScope scope) {
    final inScope = _notes.where((n) => n.scope == scope).toList();
    if (inScope.length <= maxNotesPerScope) return;
    for (final stale in inScope.skip(maxNotesPerScope)) {
      _notes.remove(stale);
    }
  }

  Future<void> forget(String id) async {
    _notes.removeWhere((n) => n.id == id);
    await _persist();
  }

  Future<void> clearScope(MemoryScope scope) async {
    _notes.removeWhere((n) => n.scope == scope);
    await _persist();
  }

  void clearEphemeral({String? taskId}) {
    _notes.removeWhere(
      (note) =>
          note.scope == MemoryScope.task &&
          (taskId == null || note.taskId == taskId),
    );
  }

  List<MemoryNote> relevantFor(String? projectPath, {String? taskId}) =>
      _notes.where((n) {
        if (n.scope == MemoryScope.user) return true;
        if (n.scope == MemoryScope.task) {
          return taskId != null && n.taskId == taskId;
        }
        if (projectPath == null || n.projectPath == null) return false;
        return p.equals(n.projectPath!, projectPath);
      }).toList();

  static String promptSection(List<MemoryNote> notes, {int max = 12}) =>
      notes.take(max).map((n) => '• [${n.scope.label}] ${n.text}').join('\n');
}

class MemoryNotifier extends Notifier<int> {
  @override
  int build() => 0;

  Future<void> reload() async {
    await MemoryStore.instance.load();
    state++;
  }

  Future<void> forget(String id) async {
    await MemoryStore.instance.forget(id);
    state++;
  }

  Future<void> clearScope(MemoryScope scope) async {
    await MemoryStore.instance.clearScope(scope);
    state++;
  }

  void bump() => state++;
}

final memoryProvider = NotifierProvider<MemoryNotifier, int>(
  MemoryNotifier.new,
);
