import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../core/agent_storage.dart';

class AgentSkill {
  AgentSkill({
    required this.id,
    required this.name,
    required this.purpose,
    this.patterns = const [],
    this.diagnosticSteps = const [],
    this.knownErrors = const [],
    this.solutions = const [],
    this.warnings = const [],
    this.tools = const [],
    this.tags = const [],
    DateTime? createdAt,
    DateTime? updatedAt,
  }) : createdAt = createdAt ?? DateTime.now(),
       updatedAt = updatedAt ?? DateTime.now();

  final String id;
  final String name;

  final String purpose;

  final List<String> patterns;

  final List<String> diagnosticSteps;

  final List<String> knownErrors;

  final List<String> solutions;

  final List<String> warnings;

  final List<String> tools;

  final List<String> tags;
  final DateTime createdAt;
  final DateTime updatedAt;

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': SecretScrubber.scrub(name),
    'purpose': SecretScrubber.scrub(purpose),
    'patterns': patterns.map(SecretScrubber.scrub).toList(),
    'diagnostic_steps': diagnosticSteps.map(SecretScrubber.scrub).toList(),
    'known_errors': knownErrors.map(SecretScrubber.scrub).toList(),
    'solutions': solutions.map(SecretScrubber.scrub).toList(),
    'warnings': warnings.map(SecretScrubber.scrub).toList(),
    'tools': tools.map(SecretScrubber.scrub).toList(),
    'tags': tags.map(SecretScrubber.scrub).toList(),
    'created_at': createdAt.toIso8601String(),
    'updated_at': updatedAt.toIso8601String(),
  };

  static List<String> _list(Object? raw) {
    if (raw is List) {
      return raw
          .map((e) => e.toString().trim())
          .where((e) => e.isNotEmpty)
          .toList();
    }
    if (raw is String && raw.trim().isNotEmpty) return [raw.trim()];
    return const [];
  }

  static final _idPattern = RegExp(
    r'^[\p{L}\p{N}][\p{L}\p{N}_-]{0,63}$',
    unicode: true,
  );

  static bool isSafeId(String id) => _idPattern.hasMatch(id);

  static const maxFieldChars = 400;

  static const maxListItems = 20;

  static String _clip(String value) => value.length <= maxFieldChars
      ? value
      : '${value.substring(0, maxFieldChars)}…';

  static List<String> _bounded(List<String> items) =>
      items.take(maxListItems).map(_clip).toList();

  static AgentSkill? fromJson(Map<String, dynamic> json) {
    final name = (json['name'] ?? '').toString().trim();
    if (name.isEmpty) return null;
    final rawId = (json['id'] ?? '').toString();
    final id = isSafeId(rawId) ? rawId : slugify(name);
    if (!isSafeId(id)) return null;
    return AgentSkill(
      id: id,
      name: _clip(SecretScrubber.scrub(name)),
      purpose: _clip(
        SecretScrubber.scrub((json['purpose'] ?? '').toString().trim()),
      ),
      patterns: _bounded(
        _list(json['patterns']).map(SecretScrubber.scrub).toList(),
      ),
      diagnosticSteps: _bounded(
        _list(
          json['diagnostic_steps'] ?? json['steps'],
        ).map(SecretScrubber.scrub).toList(),
      ),
      knownErrors: _bounded(
        _list(
          json['known_errors'] ?? json['errors'],
        ).map(SecretScrubber.scrub).toList(),
      ),
      solutions: _bounded(
        _list(json['solutions']).map(SecretScrubber.scrub).toList(),
      ),
      warnings: _bounded(
        _list(json['warnings']).map(SecretScrubber.scrub).toList(),
      ),
      tools: _bounded(_list(json['tools']).map(SecretScrubber.scrub).toList()),
      tags: _bounded(_list(json['tags']).map(SecretScrubber.scrub).toList()),
      createdAt: DateTime.tryParse((json['created_at'] ?? '').toString()),
      updatedAt: DateTime.tryParse((json['updated_at'] ?? '').toString()),
    );
  }

  static String slugify(String name) {
    final cleaned = name
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^\p{L}\p{N}]+', unicode: true), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    return cleaned.isEmpty
        ? 'skill-${DateTime.now().millisecondsSinceEpoch}'
        : cleaned;
  }

  String promptDigest() {
    final buffer = StringBuffer('• ${SecretScrubber.scrub(name)}');
    if (purpose.isNotEmpty) {
      buffer.write(' — ${SecretScrubber.scrub(purpose)}');
    }
    buffer.writeln();
    void section(String label, List<String> items, int max) {
      if (items.isEmpty) return;
      for (final item in items.take(max)) {
        buffer.writeln('    $label: ${SecretScrubber.scrub(item)}');
      }
    }

    section('تشخیص', diagnosticSteps, 4);
    section('خطای شناخته‌شده', knownErrors, 3);
    section('راه‌حل', solutions, 3);
    section('هشدار', warnings, 2);
    return buffer.toString().trimRight();
  }
}

class SkillStore {
  SkillStore._();

  static final instance = SkillStore._();

  final List<AgentSkill> _skills = [];
  String? _loadedAccount;

  List<AgentSkill> get all => List.unmodifiable(_skills);

  Directory? get _dir => AgentStorage.subdir('skills');

  Future<void> load() async {
    final account = AgentStorage.accountKey;
    if (_loadedAccount == account) return;
    _loadedAccount = account;
    _skills.clear();
    final dir = _dir;
    if (dir == null) return;
    try {
      for (final entity in dir.listSync()) {
        if (entity is! File || !entity.path.endsWith('.json')) continue;
        try {
          final decoded = jsonDecode(await entity.readAsString());
          if (decoded is! Map) continue;
          final skill = AgentSkill.fromJson(Map<String, dynamic>.from(decoded));
          if (skill != null) _skills.add(skill);
        } catch (_) {}
      }
      _skills.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      if (_skills.length > maxSkills) {
        _skills.removeRange(maxSkills, _skills.length);
      }
    } catch (_) {}
  }

  AgentSkill? find(String id) {
    for (final s in _skills) {
      if (s.id == id) return s;
    }
    return null;
  }

  static const maxSkills = 80;

  Future<bool> save(AgentSkill skill) async {
    final dir = _dir;
    if (dir == null) return false;
    if (!AgentSkill.isSafeId(skill.id)) return false;
    if (_skills.length >= maxSkills && !_skills.any((s) => s.id == skill.id)) {
      return false;
    }
    try {
      final file = File(p.join(dir.path, '${skill.id}.json'));
      await AgentStorage.writeTextAtomic(
        file,
        const JsonEncoder.withIndent('  ').convert(skill.toJson()),
      );
      _skills
        ..removeWhere((s) => s.id == skill.id)
        ..insert(0, skill);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> delete(String id) async {
    if (!AgentSkill.isSafeId(id)) return false;
    final dir = _dir;
    if (dir == null) return false;
    try {
      final file = File(p.join(dir.path, '$id.json'));
      if (file.existsSync()) await file.delete();
      _skills.removeWhere((s) => s.id == id);
      return true;
    } catch (_) {
      return false;
    }
  }

  List<AgentSkill> suggestFor(String goal) {
    final words = goal
        .toLowerCase()
        .split(RegExp(r'[\s\p{P}]+', unicode: true))
        .where((w) => w.length > 2)
        .toSet();
    if (words.isEmpty) return const [];

    final scored = <({AgentSkill skill, int score})>[];
    for (final skill in _skills) {
      final haystack = [
        skill.name,
        skill.purpose,
        ...skill.tags,
        ...skill.patterns,
      ].join(' ').toLowerCase();
      final score = words.where(haystack.contains).length;
      if (score > 0) scored.add((skill: skill, score: score));
    }
    scored.sort((a, b) => b.score.compareTo(a.score));
    return scored.take(4).map((e) => e.skill).toList();
  }

  static String promptSection(List<AgentSkill> selected) =>
      selected.map((s) => s.promptDigest()).join('\n');
}

class SkillsNotifier extends Notifier<int> {
  @override
  int build() => 0;

  Future<void> reload() async {
    await SkillStore.instance.load();
    state++;
  }

  Future<void> save(AgentSkill skill) async {
    await SkillStore.instance.save(skill);
    state++;
  }

  Future<void> delete(String id) async {
    await SkillStore.instance.delete(id);
    state++;
  }

  void bump() => state++;
}

final skillsProvider = NotifierProvider<SkillsNotifier, int>(
  SkillsNotifier.new,
);

class ActiveSkillsNotifier extends Notifier<Set<String>> {
  @override
  Set<String> build() => const {};

  void toggle(String id) =>
      state = state.contains(id) ? ({...state}..remove(id)) : {...state, id};

  void set(Set<String> ids) => state = ids;

  void clear() => state = const {};
}

final activeSkillsProvider =
    NotifierProvider<ActiveSkillsNotifier, Set<String>>(
      ActiveSkillsNotifier.new,
    );
