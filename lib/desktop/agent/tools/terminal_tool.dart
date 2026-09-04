import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import '../agent_workspace.dart';
import '../core/agent_process.dart';
import '../network/agent_environment.dart';
import '../policy/agent_policy.dart';
import '../policy/command_risk.dart';
import 'agent_tool.dart';

enum ShellKind {
  powershell,
  cmd;

  static ShellKind parse(String? raw) =>
      (raw ?? '').toLowerCase().startsWith('cmd') ? cmd : powershell;

  String get executable => this == cmd ? 'cmd.exe' : 'powershell.exe';

  List<String> argsFor(String command) => switch (this) {
    ShellKind.cmd => ['/c', command],
    ShellKind.powershell => [
      '-NoProfile',
      '-NonInteractive',
      '-ExecutionPolicy',
      'Bypass',
      '-Command',
      '\$OutputEncoding=[Console]::OutputEncoding=[Text.Encoding]::UTF8; $command',
    ],
  };
}

class RunCommandTool extends AgentTool {
  @override
  bool get yieldsUntrustedContent => true;

  const RunCommandTool();

  static const defaultTimeout = Duration(seconds: 120);
  static const maxTimeout = Duration(minutes: 10);

  static const maxStreamChars = 12000;

  @override
  String get name => 'run_command';
  @override
  String get label => 'اجرای فرمان';
  @override
  ToolRisk get risk => ToolRisk.execute;
  @override
  String get permission => Perm.terminalExecute;
  @override
  bool get available => Platform.isWindows;

  @override
  bool get checkpointsChanges => false;

  @override
  String get signature =>
      'run_command {"command": "flutter analyze", "shell": "powershell", "cwd": ".", "timeout": 120} '
      '— اجرای فرمان و گرفتن stdout/stderr/exit code. غیرتعاملی بنویس.';

  @override
  Map<String, dynamic> get parameterSchema => const {
    'command': {'type': 'string', 'description': 'غیرتعاملی'},
    'shell': {
      'type': 'string',
      'enum': ['powershell', 'cmd'],
    },
    'cwd': {'type': 'string', 'description': 'پیش‌فرض .'},
    'timeout': {
      'type': 'integer',
      'minimum': 1,
      'description': 'ثانیه؛ پیش‌فرض ۱۲۰',
    },
  };

  @override
  List<String> get requiredParameters => const ['command'];

  @override
  ToolRisk riskOf(ToolCall call) =>
      CommandRisk.classify(call.str('command') ?? '').risk;

  @override
  String? hardDeny(ToolCall call) {
    final command = call.str('command');
    if (command == null || command.trim().isEmpty) {
      return 'پارامتر command لازم است.';
    }

    final verdict = CommandRisk.classify(command);
    if (verdict.isBlocked) return verdict.blockedReason;

    final cwd = call.str('cwd');
    if (cwd != null) {
      final resolved = AgentWorkspace.resolve(cwd);
      if (resolved == null) {
        return 'پوشهٔ اجرا «$cwd» بیرون از منابع مجاز است.';
      }
    } else if (AgentWorkspace.primaryRoot == null) {
      return 'هیچ پوشهٔ کاری انتخاب نشده، پس جایی برای اجرای فرمان نیست.';
    }
    return null;
  }

  @override
  ToolPreview preview(ToolCall call) {
    final command = call.str('command') ?? '';
    final verdict = CommandRisk.classify(command);
    final shell = ShellKind.parse(call.str('shell'));
    final cwd = call.str('cwd') ?? '.';
    return ToolPreview(
      title: 'اجرای فرمان در ${shell == ShellKind.cmd ? 'CMD' : 'PowerShell'}',
      subtitle: 'در پوشهٔ $cwd',
      body: command,
      bodyLanguage: shell == ShellKind.cmd ? 'bat' : 'powershell',
      warnings: verdict.warnings,
    );
  }

  @override
  Future<ToolResult> run(ToolCall call, ToolContext context) async {
    final command = call.str('command');
    if (command == null || command.trim().isEmpty) {
      return ToolResult.failure('پارامتر command لازم است.');
    }

    final verdict = CommandRisk.classify(command);
    if (verdict.isBlocked) return ToolResult.failure(verdict.blockedReason!);

    final workingDir = call.str('cwd') == null
        ? AgentWorkspace.primaryRoot
        : AgentWorkspace.resolve(call.str('cwd')!);
    if (workingDir == null) {
      return ToolResult.failure(
        'پوشهٔ اجرا مشخص یا مجاز نیست. یک پوشه از منابع مجاز بده.',
      );
    }
    if (!Directory(workingDir).existsSync()) {
      return ToolResult.failure('پوشهٔ اجرا وجود ندارد: ${call.str('cwd')}');
    }

    final shell = ShellKind.parse(call.str('shell'));
    final seconds = call.integer('timeout') ?? defaultTimeout.inSeconds;
    final timeout = Duration(seconds: seconds.clamp(1, maxTimeout.inSeconds));

    final started = DateTime.now();
    Process process;
    try {
      process = await Process.start(
        shell.executable,
        shell.argsFor(command),
        workingDirectory: workingDir,
        runInShell: false,
        environment: await AgentEnvironment.build(),
        includeParentEnvironment: false,
      );
    } on ProcessException catch (e) {
      return ToolResult.failure(
        'اجرای ${shell.executable} ممکن نشد: ${e.message}',
      );
    }

    final stdoutBuffer = TailBuffer(maxStreamChars);
    final stderrBuffer = TailBuffer(maxStreamChars);

    StreamSubscription<String> pipe(
      Stream<List<int>> source,
      TailBuffer sink,
      String tag,
    ) => source
        .transform(const Utf8Decoder(allowMalformed: true))
        .transform(const LineSplitter())
        .listen((line) {
          sink.add(line);
          context.report(tag.isEmpty ? line : '$tag$line');
        });

    final outSub = pipe(process.stdout, stdoutBuffer, '');
    final errSub = pipe(process.stderr, stderrBuffer, '');

    var timedOut = false;
    var cancelled = false;

    Future<void>? killing;
    void killTree() {
      killing ??= AgentProcess.killTree(process);
    }

    final cancelWatch = Timer.periodic(const Duration(milliseconds: 250), (t) {
      if (!context.isCancelled()) return;
      cancelled = true;
      t.cancel();
      killTree();
    });

    var exitCode = -1;
    try {
      exitCode = await process.exitCode.timeout(
        timeout,
        onTimeout: () {
          timedOut = true;
          killTree();
          return AgentProcess.timedOutExitCode;
        },
      );
    } finally {
      cancelWatch.cancel();
      if (killing != null) {
        await killing!.timeout(
          const Duration(seconds: 8),
          onTimeout: () => context.report(
            'هشدار: بسته‌شدن کامل فرآیند در مهلت مقرر تأیید نشد.',
          ),
        );
        await process.exitCode
            .timeout(const Duration(seconds: 5))
            .catchError((_) => exitCode);
      }
      await outSub.cancel();
      await errSub.cancel();
    }

    final duration = DateTime.now().difference(started);
    final stdoutText = stdoutBuffer.render();
    final stderrText = stderrBuffer.render();

    if (cancelled) {
      return ToolResult(
        ok: false,
        summary: 'فرمان توسط کاربر لغو شد',
        error: 'cancelled',
        data: {
          'ok': false,
          'command': command,
          'cancelled': true,
          'stdout': stdoutText,
          'stderr': stderrText,
        },
        detail: _detail(command, stdoutText, stderrText),
      );
    }

    final ok = !timedOut && exitCode == 0;
    final summary = timedOut
        ? 'به تایم‌اوت ${timeout.inSeconds} ثانیه خورد'
        : (ok
              ? 'موفق (${duration.inMilliseconds} میلی‌ثانیه)'
              : 'کد خروج $exitCode');

    return ToolResult(
      ok: ok,
      summary: '$command — $summary',
      error: ok ? null : summary,
      data: {
        'ok': ok,
        'command': command,
        'shell': shell.name,
        'cwd': AgentWorkspace.display(workingDir),
        'exit_code': exitCode,
        'stdout': stdoutText,
        'stderr': stderrText,
        'duration_ms': duration.inMilliseconds,
        'timed_out': timedOut,
      },
      detail: _detail(command, stdoutText, stderrText),
    );
  }

  static String _detail(String command, String out, String err) {
    final buffer = StringBuffer('> $command\n');
    if (out.isNotEmpty) buffer.writeln(out);
    if (err.isNotEmpty) {
      buffer
        ..writeln('--- stderr ---')
        ..writeln(err);
    }
    return buffer.toString().trimRight();
  }
}

class TailBuffer {
  TailBuffer(this.maxChars);

  final int maxChars;
  final Queue<String> _lines = Queue<String>();
  int _chars = 0;
  int _dropped = 0;

  void add(String line) {
    var text = line;
    if (text.length > maxChars) {
      _dropped += text.length - maxChars;
      text = text.substring(text.length - maxChars);
    }
    _lines.addLast(text);
    _chars += text.length + 1;
    while (_chars > maxChars && _lines.length > 1) {
      final removed = _lines.removeFirst();
      _chars -= removed.length + 1;
      _dropped += removed.length + 1;
    }
  }

  String render() {
    final text = _lines.join('\n').trimRight();
    if (_dropped == 0) return text;
    return '…($_dropped کاراکتر ابتدایی حذف شد)\n$text';
  }
}
