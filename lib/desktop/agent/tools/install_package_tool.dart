import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../acquisition/tool_probe.dart';
import '../core/agent_process.dart';
import '../network/agent_environment.dart';
import '../policy/agent_policy.dart';
import 'agent_tool.dart';

class InstallPackageTool extends AgentTool {
  const InstallPackageTool();

  @override
  String get name => 'install_package';
  @override
  String get label => 'نصب بسته';

  @override
  ToolRisk get risk => ToolRisk.execute;

  @override
  String get permission => Perm.toolInstall;

  @override
  bool get checkpointsChanges => false;

  @override
  String get signature =>
      'install_package {"manager": "pip|npm|winget|cargo|wsl", "package": "نام", '
      '"verify_command": "فقط نام فایل اجرایی مثل python یا pandoc (اختیاری؛ نه خط فرمان کامل)"} '
      '— هر بسته‌ای از مخزن رسمی. اول با check_capability ببین لازم هست یا نه.';

  @override
  Map<String, dynamic> get parameterSchema => const {
    'manager': {
      'type': 'string',
      'enum': ['pip', 'npm', 'winget', 'cargo', 'wsl'],
    },
    'package': {'type': 'string'},
    'verify_command': {
      'type': 'string',
      'description': 'فقط نام اجرایی، نه خط فرمان',
    },
  };

  @override
  List<String> get requiredParameters => const ['manager', 'package'];

  static final _validName = RegExp(r'^@?[A-Za-z0-9][A-Za-z0-9._@/+-]{0,120}$');
  static final _validVerifyCommand = RegExp(r'^[A-Za-z0-9_.+-]{1,80}$');

  @override
  String? hardDeny(ToolCall call) {
    final pkg = call.str('package');
    if (pkg != null) {
      if (!_validName.hasMatch(pkg)) {
        return 'نام بستهٔ «$pkg» شکل معتبری ندارد.';
      }
      if (pkg.contains('..')) {
        return 'نام بسته نمی‌تواند «..» داشته باشد.';
      }
    }
    final manager = call.str('manager');
    if (manager != null && _managerOf(manager) == null) {
      return 'مدیر بستهٔ «$manager» شناخته‌شده نیست. '
          'یکی از: pip، npm، winget، cargo، wsl';
    }
    final verifyCommand = call.str('verify_command');
    if (verifyCommand != null && !_validVerifyCommand.hasMatch(verifyCommand)) {
      return 'نام فرمان بررسی سلامت معتبر نیست.';
    }
    return null;
  }

  @override
  ToolPreview preview(ToolCall call) {
    final manager = _managerOf(call.str('manager'));
    final pkg = call.str('package') ?? '';

    return ToolPreview(
      title: 'نصب بسته روی سیستم شما',
      subtitle: pkg,
      body: manager == null
          ? null
          : 'بسته: $pkg\n'
                'منبع: ${manager.label}\n'
                'دامنه: ${manager.scopeLabel}',
      warnings: [
        'این بسته از اینترنت دانلود و روی سیستم شما نصب می‌شود.',
        if (manager == _Manager.npm) 'npm می‌تواند هنگام نصب اسکریپت اجرا کند.',
        if (manager != null && manager.acceptsAgreements)
          'شرایط استفادهٔ ناشر بسته هم پذیرفته می‌شود.',
        'نام بسته را ببینید؛ نام مشابه اما غلط می‌تواند بستهٔ مخرب باشد.',
      ],
    );
  }

  @override
  Future<ToolResult> run(ToolCall call, ToolContext context) async {
    final pkg = call.str('package');
    final managerName = call.str('manager');
    if (pkg == null || managerName == null) {
      return ToolResult.failure('پارامترهای manager و package لازم‌اند.');
    }

    final manager = _managerOf(managerName);
    if (manager == null) {
      return ToolResult.failure('مدیر بستهٔ «$managerName» شناخته‌شده نیست.');
    }

    final probe = await ToolProbe.probe(manager.command);
    if (!probe.installed) {
      return ToolResult.failure(
        '«${manager.command}» روی این سیستم نصب نیست، پس نمی‌شود با آن '
        'چیزی نصب کرد. اول خودش را نصب کنید.',
        data: {'manager': manager.command, 'manager_installed': false},
      );
    }

    final verifyCommand = call.str('verify_command');
    if (verifyCommand != null) {
      final existing = await ToolProbe.probe(verifyCommand);
      if (existing.installed) {
        return ToolResult.success(
          summary: '«$verifyCommand» از قبل نصب است',
          data: {
            'package': pkg,
            'installed_now': false,
            'tool': existing.toJson(),
          },
        );
      }
    }

    final args = manager.installArgs(pkg);
    context.report('${manager.command} ${args.join(' ')}');

    final log = StringBuffer();
    Process process;
    try {
      process = await Process.start(
        manager.command,
        args,
        runInShell: true,
        environment: await AgentEnvironment.build(),
        includeParentEnvironment: false,
      );
    } on ProcessException catch (e) {
      return ToolResult.failure(
        'اجرای ${manager.command} ممکن نشد: ${e.message}',
      );
    }

    StreamSubscription<String> pipe(Stream<List<int>> src) => src
        .transform(const Utf8Decoder(allowMalformed: true))
        .transform(const LineSplitter())
        .listen((line) {
          if (log.length < 20000) log.writeln(line);
          context.report(line);
        });

    final outSub = pipe(process.stdout);
    final errSub = pipe(process.stderr);

    var cancelled = false;
    Future<void>? killing;
    void killTree() {
      killing ??= AgentProcess.killTree(process);
    }

    final cancelWatch = Timer.periodic(const Duration(milliseconds: 250), (
      timer,
    ) {
      if (!context.isCancelled()) return;
      cancelled = true;
      timer.cancel();
      killTree();
    });

    int exitCode;
    try {
      exitCode = await process.exitCode.timeout(
        const Duration(minutes: 15),
        onTimeout: () {
          killTree();
          return -1;
        },
      );
    } on TimeoutException {
      exitCode = -1;
    }

    cancelWatch.cancel();
    if (killing != null) await killing;
    await outSub.cancel();
    await errSub.cancel();

    if (cancelled) {
      return ToolResult.failure('نصب به درخواست کاربر متوقف شد.');
    }
    if (exitCode == -1) {
      return ToolResult.failure(
        'نصب بیش از حد طول کشید و تمام فرایندهایش متوقف شدند.',
        data: {'package': pkg},
      );
    }

    ProbeResult? health;
    if (verifyCommand != null) {
      health = await ToolProbe.probe(verifyCommand, refresh: true);
    }

    final ok = exitCode == 0 && (health == null || health.installed);
    if (!ok) {
      final message = exitCode != 0
          ? 'نصب ناموفق بود (کد $exitCode).'
          : 'نصب بدون خطا تمام شد ولی «$verifyCommand» هنوز اجرا نمی‌شود — '
                'معمولاً یعنی PATH باید دوباره خوانده شود.';
      return ToolResult(
        ok: false,
        summary: message,
        error: message,
        detail: log.toString(),
        data: {'ok': false, 'package': pkg, 'exit_code': exitCode},
      );
    }

    return ToolResult.success(
      summary:
          '$pkg نصب شد${health?.version == null ? '' : ' — ${health!.version}'}',
      detail: log.toString(),
      data: {
        'package': pkg,
        'manager': manager.command,
        'installed_now': true,
        'verified': health != null,
        if (health != null) 'tool': health.toJson(),
      },
    );
  }

  static _Manager? _managerOf(String? raw) {
    switch ((raw ?? '').trim().toLowerCase()) {
      case 'pip':
      case 'pip3':
      case 'python':
        return _Manager.pip;
      case 'npm':
      case 'node':
        return _Manager.npm;
      case 'winget':
      case 'windows':
        return _Manager.winget;
      case 'cargo':
      case 'rust':
        return _Manager.cargo;
      case 'wsl':
      case 'apt':
      case 'linux':
        return _Manager.wsl;
      default:
        return null;
    }
  }
}

enum _Manager {
  pip,
  npm,
  winget,
  cargo,

  wsl;

  String get command => switch (this) {
    _Manager.pip => 'pip',
    _Manager.npm => 'npm',
    _Manager.winget => 'winget',
    _Manager.cargo => 'cargo',
    _Manager.wsl => 'wsl',
  };

  String get label => switch (this) {
    _Manager.pip => 'PyPI (مخزن رسمی پایتون)',
    _Manager.npm => 'npm (مخزن رسمی نود)',
    _Manager.winget => 'winget (کاتالوگ رسمی مایکروسافت)',
    _Manager.cargo => 'crates.io (مخزن رسمی راست)',
    _Manager.wsl => 'مخزن اوبونتو داخل WSL',
  };

  String get scopeLabel => switch (this) {
    _Manager.pip => 'کاربر (بدون دسترسی مدیر)',
    _Manager.npm => 'سراسری — ممکن است دسترسی مدیر بخواهد',
    _Manager.winget => 'کاربر (بدون دسترسی مدیر)',
    _Manager.cargo => 'کاربر (بدون دسترسی مدیر)',
    _Manager.wsl => 'داخل WSL — روی خود ویندوز اثری ندارد',
  };

  bool get acceptsAgreements => this == _Manager.winget;

  List<String> installArgs(String pkg) => switch (this) {
    _Manager.pip => ['install', '--user', pkg],
    _Manager.npm => ['install', '--global', pkg],
    _Manager.winget => [
      'install',
      '--id',
      pkg,
      '--exact',
      '--scope',
      'user',
      '--silent',
      '--accept-package-agreements',
      '--accept-source-agreements',
    ],
    _Manager.cargo => ['install', pkg],
    _Manager.wsl => ['-e', 'sudo', 'apt-get', 'install', '-y', pkg],
  };
}
