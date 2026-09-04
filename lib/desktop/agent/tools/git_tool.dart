import 'dart:convert';
import 'dart:io';

import '../agent_workspace.dart';
import '../core/agent_process.dart';
import '../network/agent_environment.dart';
import '../policy/agent_policy.dart';
import 'agent_tool.dart';

enum GitAction {
  status,
  diff,
  log,
  branch,
  show,

  checkpoint,

  restore;

  static GitAction? parse(String? raw) {
    final key = (raw ?? '').trim().toLowerCase();
    for (final a in GitAction.values) {
      if (a.name == key) return a;
    }
    return null;
  }

  bool get isRead => switch (this) {
    status || diff || log || branch || show => true,
    checkpoint || restore => false,
  };
}

class GitTool extends AgentTool {
  @override
  bool get yieldsUntrustedContent => true;

  const GitTool();

  static const _timeout = Duration(seconds: 45);

  @override
  String get name => 'git';
  @override
  String get label => 'گیت';
  @override
  ToolRisk get risk => ToolRisk.read;

  @override
  String get permission => Perm.gitRead;

  @override
  String permissionOf(ToolCall call) {
    final action = GitAction.parse(call.str('action'));
    return action == null || action.isRead ? Perm.gitRead : Perm.gitWrite;
  }

  @override
  bool get available => AgentWorkspace.hasRoot;

  @override
  bool get checkpointsChanges => false;

  @override
  String get signature =>
      'git {"action": "status|diff|log|branch|show|checkpoint|restore", "path": ".", "ref": "...", "staged": false} '
      '— وضعیت و تاریخچهٔ مخزن. checkpoint نقطهٔ بازگشت می‌سازد، restore به آن برمی‌گردد.';

  @override
  Map<String, dynamic> get parameterSchema => const {
    'action': {
      'type': 'string',
      'enum': [
        'status',
        'diff',
        'log',
        'branch',
        'show',
        'checkpoint',
        'restore',
      ],
    },
    'path': {'type': 'string', 'description': 'پیش‌فرض .'},
    'ref': {'type': 'string', 'description': 'برای show و restore'},
    'staged': {'type': 'boolean', 'description': 'فقط در diff'},
    'count': {'type': 'integer', 'minimum': 1, 'description': 'در log'},
    'message': {'type': 'string', 'description': 'برای checkpoint'},
    'target': {'type': 'string', 'description': 'نام شاخه'},
  };

  @override
  List<String> get requiredParameters => const ['action'];

  @override
  ToolRisk riskOf(ToolCall call) {
    final action = GitAction.parse(call.str('action'));
    return switch (action) {
      null => ToolRisk.read,
      GitAction.restore => ToolRisk.destructive,
      GitAction.checkpoint => ToolRisk.write,
      _ => ToolRisk.read,
    };
  }

  @override
  String? hardDeny(ToolCall call) {
    final action = GitAction.parse(call.str('action'));
    if (action == null) {
      return 'action نامعتبر است. یکی از: '
          '${GitAction.values.map((a) => a.name).join('، ')}';
    }
    final ref = call.str('ref');
    if ((action == GitAction.show || action == GitAction.restore) &&
        ref != null &&
        !_safeRef(ref, restore: action == GitAction.restore)) {
      return 'ref نامعتبر یا ناامن است.';
    }
    final dir = _workDir(call);
    if (dir == null) return 'پوشهٔ مخزن مشخص یا مجاز نیست.';

    if (!action.isRead) {
      final owner = AgentWorkspace.owner(dir);
      if (owner == null) return 'پوشهٔ مخزن بیرون از منابع مجاز است.';
      if (!owner.canWrite) {
        return 'روی «${owner.name}» اجازهٔ نوشتن داده نشده '
            '(اجازه‌های فعلی: ${owner.permissionLabel})؛ '
            '«${action.name}» چیزی روی دیسک عوض می‌کند.';
      }
    }
    return null;
  }

  @override
  ToolPreview preview(ToolCall call) {
    final action = GitAction.parse(call.str('action'));
    return switch (action) {
      GitAction.checkpoint => const ToolPreview(
        title: 'ساخت نقطهٔ بازگشت Git',
        subtitle: 'وضعیت فعلی ذخیره می‌شود؛ چیزی از پوشهٔ کاری کم نمی‌شود.',
      ),
      GitAction.restore => ToolPreview(
        title: 'بازگرداندن به نقطهٔ بازگشت',
        subtitle: call.str('ref'),
        warnings: const [
          'تغییرات فعلی پوشهٔ کاری با محتوای نقطهٔ بازگشت جایگزین می‌شود.',
        ],
      ),
      _ => ToolPreview(
        title: 'گیت · ${action?.name ?? '?'}',
        subtitle: call.str('path') ?? '.',
      ),
    };
  }

  String? _workDir(ToolCall call) {
    final raw = call.str('path');
    if (raw == null) return AgentWorkspace.primaryRoot;
    return AgentWorkspace.resolve(raw);
  }

  @override
  Future<ToolResult> run(ToolCall call, ToolContext context) async {
    final action = GitAction.parse(call.str('action'));
    if (action == null) {
      return ToolResult.failure(
        'action نامعتبر است. یکی از: '
        '${GitAction.values.map((a) => a.name).join('، ')}',
      );
    }

    final dir = _workDir(call);
    if (dir == null) {
      return ToolResult.failure('پوشهٔ مخزن مشخص یا مجاز نیست.');
    }

    final inside = await _git(['rev-parse', '--is-inside-work-tree'], dir);
    if (inside.exitCode != 0) {
      return ToolResult.failure(
        'این پوشه یک مخزن Git نیست: ${AgentWorkspace.display(dir)}',
      );
    }

    return switch (action) {
      GitAction.status => _status(dir),
      GitAction.diff => _diff(call, dir),
      GitAction.log => _log(call, dir),
      GitAction.branch => _branch(dir),
      GitAction.show => _show(call, dir),
      GitAction.checkpoint => _checkpoint(call, dir),
      GitAction.restore => _restore(call, dir),
    };
  }

  Future<ToolResult> _status(String dir) async {
    final res = await _git(['status', '--porcelain=v1', '-b'], dir);
    if (res.exitCode != 0) return _fail(res);

    final lines = const LineSplitter().convert(res.stdout);
    String? branch;
    final changes = <Map<String, String>>[];
    for (final line in lines) {
      if (line.startsWith('##')) {
        branch = line.substring(2).trim();
        continue;
      }
      if (line.length < 4) continue;
      changes.add({
        'status': line.substring(0, 2).trim(),
        'path': line.substring(3),
      });
    }

    return ToolResult.success(
      summary: changes.isEmpty
          ? 'پوشهٔ کاری تمیز است'
          : '${changes.length} فایل تغییر کرده',
      data: {'branch': branch, 'clean': changes.isEmpty, 'changes': changes},
      detail: res.stdout.trim().isEmpty
          ? '(بدون تغییر)'
          : res.stdout.trimRight(),
    );
  }

  Future<ToolResult> _diff(ToolCall call, String dir) async {
    final args = ['diff', '--no-color'];
    if (call.flag('staged')) args.add('--staged');
    final target = call.str('target');
    if (target != null) args.addAll(['--', target]);

    final res = await _git(args, dir);
    if (res.exitCode != 0) return _fail(res);

    final text = _clipOutput(res.stdout);
    return ToolResult.success(
      summary: text.isEmpty
          ? 'بدون تفاوت'
          : '${text.split('\n').length} خط دیف',
      data: {'diff': text, 'staged': call.flag('staged')},
      detail: text.isEmpty ? '(بدون تفاوت)' : text,
    );
  }

  Future<ToolResult> _log(ToolCall call, String dir) async {
    final count = (call.integer('count') ?? 20).clamp(1, 100);
    final res = await _git([
      'log',
      '-n',
      '$count',
      '--pretty=format:%h|%an|%ar|%s',
    ], dir);
    if (res.exitCode != 0) return _fail(res);

    final commits = <Map<String, String>>[];
    for (final line in const LineSplitter().convert(res.stdout)) {
      final parts = line.split('|');
      if (parts.length < 4) continue;
      commits.add({
        'hash': parts[0],
        'author': parts[1],
        'when': parts[2],
        'subject': parts.sublist(3).join('|'),
      });
    }

    return ToolResult.success(
      summary: '${commits.length} کامیت اخیر',
      data: {'commits': commits},
      detail: res.stdout.trimRight(),
    );
  }

  Future<ToolResult> _branch(String dir) async {
    final current = await _git(['rev-parse', '--abbrev-ref', 'HEAD'], dir);
    if (current.exitCode != 0) return _fail(current);
    final all = await _git(['branch', '--format=%(refname:short)'], dir);
    if (all.exitCode != 0) return _fail(all);
    final branches = const LineSplitter()
        .convert(all.stdout)
        .map((b) => b.trim())
        .where((b) => b.isNotEmpty)
        .toList();

    return ToolResult.success(
      summary: 'شاخهٔ فعلی: ${current.stdout.trim()}',
      data: {'current': current.stdout.trim(), 'branches': branches},
      detail: branches.join('\n'),
    );
  }

  Future<ToolResult> _show(ToolCall call, String dir) async {
    final ref = call.str('ref') ?? 'HEAD';
    if (!_safeRef(ref)) return ToolResult.failure('ref نامعتبر یا ناامن است.');
    final res = await _git(['show', '--stat', '--no-color', ref], dir);
    if (res.exitCode != 0) return _fail(res);
    final text = _clipOutput(res.stdout);
    return ToolResult.success(
      summary: 'محتوای $ref',
      data: {'ref': ref, 'show': text},
      detail: text,
    );
  }

  Future<ToolResult> _checkpoint(ToolCall call, String dir) async {
    final note = call.str('message') ?? 'jemiran-agent checkpoint';

    final created = await _git(['stash', 'create'], dir);
    if (created.exitCode != 0) return _fail(created);

    final sha = created.stdout.trim();
    if (sha.isEmpty) {
      final head = await _git(['rev-parse', 'HEAD'], dir);
      if (head.exitCode != 0) return _fail(head);
      return ToolResult.success(
        summary: 'پوشهٔ کاری تمیز بود؛ نقطهٔ بازگشت همان HEAD است',
        data: {'checkpoint': head.stdout.trim(), 'kind': 'head', 'clean': true},
      );
    }

    final stored = await _git(['stash', 'store', '-m', note, sha], dir);
    if (stored.exitCode != 0) return _fail(stored);
    return ToolResult.success(
      summary: 'نقطهٔ بازگشت ساخته شد: ${sha.substring(0, 8)}',
      data: {'checkpoint': sha, 'kind': 'stash', 'message': note},
      detail: 'برای بازگشت: git {"action":"restore","ref":"$sha"}',
    );
  }

  Future<ToolResult> _restore(ToolCall call, String dir) async {
    final ref = call.str('ref');
    if (ref == null) {
      return ToolResult.failure(
        'پارامتر ref لازم است — همان SHA که checkpoint داده بود.',
      );
    }
    if (!_safeRef(ref, restore: true)) {
      return ToolResult.failure(
        'برای restore فقط SHA کامل checkpoint مجاز است.',
      );
    }

    final res = await _git(['checkout', ref, '--', '.'], dir);
    if (res.exitCode != 0) return _fail(res);

    return ToolResult.success(
      summary: 'پوشهٔ کاری به $ref برگشت',
      data: {'restored_to': ref},
      changedPaths: [dir],
    );
  }

  Future<({int exitCode, String stdout, String stderr})> _git(
    List<String> args,
    String dir,
  ) async {
    try {
      final res = await AgentProcess.run(
        'git',
        args,
        timeout: _timeout,
        workingDirectory: dir,
        environment: AgentEnvironment.sanitizedEnvironment(
          Platform.environment,
        ),
      );
      return (
        exitCode: res.exitCode,
        stdout: res.stdout,
        stderr: res.timedOut
            ? 'git در مهلت ${_timeout.inSeconds} ثانیه تمام نشد و بسته شد.'
            : res.stderr,
      );
    } on ProcessException {
      return (
        exitCode: 127,
        stdout: '',
        stderr: 'دستور git روی این سیستم پیدا نشد.',
      );
    } catch (e) {
      return (exitCode: 1, stdout: '', stderr: '$e');
    }
  }

  ToolResult _fail(({int exitCode, String stdout, String stderr}) res) =>
      ToolResult.failure(
        res.stderr.trim().isEmpty
            ? 'git با کد ${res.exitCode} شکست خورد'
            : res.stderr.trim(),
        data: {'exit_code': res.exitCode},
      );

  static String _clipOutput(String text, [int max = 12000]) {
    final trimmed = text.trimRight();
    return trimmed.length <= max
        ? trimmed
        : '${trimmed.substring(0, max)}\n…(بریده شد)';
  }

  static bool _safeRef(String ref, {bool restore = false}) {
    if (restore) return RegExp(r'^[0-9a-fA-F]{40,64}$').hasMatch(ref);
    return ref.length <= 160 &&
        !ref.startsWith('-') &&
        !ref.contains('..') &&
        RegExp(r'^[A-Za-z0-9_./~^{}-]+$').hasMatch(ref);
  }
}
