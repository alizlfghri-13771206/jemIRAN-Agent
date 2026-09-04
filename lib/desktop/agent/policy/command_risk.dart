import '../tools/agent_tool.dart';

class CommandVerdict {
  const CommandVerdict({
    required this.risk,
    this.warnings = const [],
    this.blockedReason,
  });

  final ToolRisk risk;

  final List<String> warnings;

  final String? blockedReason;

  bool get isBlocked => blockedReason != null;
}

class _ReadForm {
  const _ReadForm({
    this.options = const {},
    this.valueOptions = const {},
    this.positional = false,
    this.requiredOptions = const {},
  });

  final Set<String> options;

  final Set<String> valueOptions;

  final bool positional;

  final Set<String> requiredOptions;
}

abstract final class CommandRisk {
  static final _blocked = <({RegExp pattern, String reason})>[
    (
      pattern: RegExp(r'\bformat\s+[a-z]:', caseSensitive: false),
      reason: 'فرمت کردن درایو',
    ),
    (
      pattern: RegExp(r'\bdiskpart\b', caseSensitive: false),
      reason: 'تغییر جدول پارتیشن دیسک',
    ),
    (
      pattern: RegExp(r'\bbcdedit\b', caseSensitive: false),
      reason: 'تغییر تنظیمات بوت ویندوز',
    ),
    (
      pattern: RegExp(r'\bvssadmin\s+delete\s+shadows', caseSensitive: false),
      reason: 'حذف نسخه‌های پشتیبان سیستم',
    ),
    (
      pattern: RegExp(r'\bcipher\s+/w', caseSensitive: false),
      reason: 'پاک‌سازی غیرقابل‌بازیابی فضای دیسک',
    ),
    (
      pattern: RegExp(
        r'(iwr|invoke-webrequest|curl|wget|irm|invoke-restmethod)[^|;\n]*[|;]\s*(iex|invoke-expression|bash|sh|powershell)',
        caseSensitive: false,
      ),
      reason: 'دانلود و اجرای مستقیم اسکریپت از اینترنت',
    ),
    (
      pattern: RegExp(
        r'\bremove-item\b[^\n]*\b[a-z]:\\?\s*(-recurse|$)',
        caseSensitive: false,
      ),
      reason: 'حذف بازگشتی ریشهٔ یک درایو',
    ),
    (
      pattern: RegExp(r'\brm\s+(-[a-z]*r[a-z]*f|-[a-z]*f[a-z]*r)\s+/\s*$'),
      reason: 'حذف بازگشتی ریشهٔ سیستم فایل',
    ),
  ];

  static final _dangerous = <({RegExp pattern, String warning})>[
    (
      pattern: RegExp(
        r'\b(remove-item|rd|rmdir|del|erase)\b.*(?:^|\s)(-recurse|/s)\b',
        caseSensitive: false,
      ),
      warning: 'این فرمان یک پوشه را با تمام محتوایش حذف می‌کند.',
    ),
    (
      pattern: RegExp(r'\brm\s+-[a-z]*r', caseSensitive: false),
      warning: 'این فرمان بازگشتی حذف می‌کند.',
    ),
    (
      pattern: RegExp(
        r'\b(runas|start-process)\b.*\brunas\b|(?:^|\s)-verb\s+runas\b',
        caseSensitive: false,
      ),
      warning: 'این فرمان دسترسی Administrator می‌خواهد.',
    ),
    (
      pattern: RegExp(
        r'\breg\s+(add|delete)\b|\bset-itemproperty\b.*\bhk(lm|cu)',
        caseSensitive: false,
      ),
      warning: 'این فرمان رجیستری ویندوز را تغییر می‌دهد.',
    ),
    (
      pattern: RegExp(r'\bset-executionpolicy\b', caseSensitive: false),
      warning: 'این فرمان سیاست امنیتی اجرای اسکریپت را تغییر می‌دهد.',
    ),
    (
      pattern: RegExp(r'\b(icacls|takeown|attrib)\b', caseSensitive: false),
      warning: 'این فرمان مجوزهای دسترسی فایل‌ها را تغییر می‌دهد.',
    ),
    (
      pattern: RegExp(
        r'\bnetsh\b|\bnew-netfirewallrule\b',
        caseSensitive: false,
      ),
      warning: 'این فرمان تنظیمات شبکه یا فایروال را تغییر می‌دهد.',
    ),
    (
      pattern: RegExp(
        r'\bnet\s+(user|localgroup)\b|\bnew-localuser\b',
        caseSensitive: false,
      ),
      warning: 'این فرمان حساب‌های کاربری ویندوز را تغییر می‌دهد.',
    ),
    (
      pattern: RegExp(
        r'\b(cmdkey|vaultcmd|get-credential|export-pfx)\b',
        caseSensitive: false,
      ),
      warning: 'این فرمان با اطلاعات ورود ذخیره‌شده کار می‌کند.',
    ),
    (
      pattern: RegExp(
        r'\bshutdown\b|\brestart-computer\b|\bstop-computer\b',
        caseSensitive: false,
      ),
      warning: 'این فرمان سیستم را خاموش یا راه‌اندازی مجدد می‌کند.',
    ),
    (
      pattern: RegExp(
        r'\btaskkill\b.*\b/f\b|\bstop-process\b.*-force',
        caseSensitive: false,
      ),
      warning:
          'این فرمان فرآیندها را به‌اجبار می‌بندد؛ کار ذخیره‌نشده از بین می‌رود.',
    ),
    (
      pattern: RegExp(r'\bgit\s+push\b.*(--force|-f)\b', caseSensitive: false),
      warning: 'این فرمان تاریخچهٔ مخزن راه دور را بازنویسی می‌کند.',
    ),
    (
      pattern: RegExp(r'\bgit\s+reset\b.*--hard', caseSensitive: false),
      warning: 'این فرمان تغییرات ذخیره‌نشده را دور می‌ریزد.',
    ),
    (
      pattern: RegExp(r'\bgit\s+clean\b.*-[a-z]*f', caseSensitive: false),
      warning: 'این فرمان فایل‌های ردیابی‌نشده را حذف می‌کند.',
    ),
    (
      pattern: RegExp(
        r'\b(npm|pnpm|yarn)\s+(publish|unpublish)\b|\bdart\s+pub\s+publish\b',
        caseSensitive: false,
      ),
      warning: 'این فرمان بسته را به‌صورت عمومی منتشر می‌کند.',
    ),
    (
      pattern: RegExp(
        r'\b(choco|winget|scoop|npm\s+i(nstall)?\s+-g|pip\s+install)\b',
        caseSensitive: false,
      ),
      warning: 'این فرمان نرم‌افزار روی سیستم نصب می‌کند.',
    ),
  ];

  static const _ReadForm _noArgs = _ReadForm();

  static const _readForms = <String, _ReadForm>{
    'git status': _ReadForm(
      options: {
        '-s',
        '--short',
        '-b',
        '--branch',
        '--long',
        '--no-color',
        '--porcelain',
        '--porcelain=v1',
        '--porcelain=v2',
        '-uno',
        '-uall',
        '-unormal',
      },
    ),
    'git diff': _ReadForm(
      options: {
        '--stat',
        '--shortstat',
        '--numstat',
        '--name-only',
        '--name-status',
        '--cached',
        '--staged',
        '--no-color',
        '-w',
        '--ignore-all-space',
        '--',
        '--summary',
      },
      positional: true,
    ),
    'git log': _ReadForm(
      options: {
        '--oneline',
        '--graph',
        '--stat',
        '--shortstat',
        '--name-only',
        '--name-status',
        '--no-color',
        '--decorate',
        '--all',
        '-n',
        '--no-merges',
        '--first-parent',
        '--',
      },
      valueOptions: {
        '--pretty',
        '--format',
        '--max-count',
        '--since',
        '--until',
        '--author',
        '--grep',
        '-n',
      },
      positional: true,
    ),
    'git branch': _ReadForm(
      options: {
        '-a',
        '--all',
        '-r',
        '--remotes',
        '-v',
        '-vv',
        '--verbose',
        '--list',
        '--show-current',
        '--no-color',
      },
      valueOptions: {'--format', '--contains', '--merged', '--no-merged'},
    ),
    'git remote': _ReadForm(options: {'-v', '--verbose'}),
    'git show': _ReadForm(
      options: {
        '--stat',
        '--shortstat',
        '--name-only',
        '--name-status',
        '--no-color',
        '--oneline',
        '--',
      },
      valueOptions: {'--pretty', '--format'},
      positional: true,
    ),
    'git rev-parse': _ReadForm(
      options: {
        '--abbrev-ref',
        '--show-toplevel',
        '--is-inside-work-tree',
        '--git-dir',
        '--verify',
        '--short',
      },
      positional: true,
    ),
    'git --version': _noArgs,
    'flutter analyze': _ReadForm(
      options: {
        '--no-pub',
        '--no-fatal-infos',
        '--no-fatal-warnings',
        '--fatal-infos',
        '--fatal-warnings',
        '--suggestions',
      },
      positional: true,
      requiredOptions: {'--no-pub'},
    ),
    'flutter --version': _noArgs,
    'dart analyze': _ReadForm(
      options: {
        '--fatal-infos',
        '--no-fatal-infos',
        '--fatal-warnings',
        '--no-fatal-warnings',
      },
      positional: true,
    ),
    'dart --version': _noArgs,
    'npm ls': _ReadForm(
      options: {'-g', '--global', '--json', '--long', '--parseable', '--all'},
      valueOptions: {'--depth'},
      positional: true,
    ),
    'npm list': _ReadForm(
      options: {'-g', '--global', '--json', '--long', '--parseable', '--all'},
      valueOptions: {'--depth'},
      positional: true,
    ),
    'npm outdated': _ReadForm(
      options: {'-g', '--global', '--json', '--long'},
      positional: true,
    ),
    'npm --version': _noArgs,
    'node --version': _noArgs,
    'python --version': _noArgs,
    'py --version': _noArgs,
    'where': _ReadForm(positional: true),
    'which': _ReadForm(positional: true),
    'get-command': _ReadForm(positional: true),
    'pwd': _noArgs,
    'whoami': _noArgs,
    'hostname': _noArgs,
    'get-location': _noArgs,
    'echo': _ReadForm(positional: true),
  };

  static final _unsafeChars = RegExp(r"""[><|&;$()`%^{}"'*?~]""");

  static final _commandName = RegExp(r'^[A-Za-z][A-Za-z0-9_.-]*$');

  static bool isProvablyReadOnly(String command) {
    final trimmed = command.trim();
    if (trimmed.isEmpty || _unsafeChars.hasMatch(trimmed)) return false;
    if (trimmed.contains('\n') || trimmed.contains('\r')) return false;

    final tokens = trimmed.split(RegExp(r'\s+'));
    if (tokens.isEmpty) return false;
    final name = tokens.first.toLowerCase();
    if (!_commandName.hasMatch(name)) return false;

    var key = name;
    var rest = tokens.skip(1).toList();
    if (tokens.length > 1) {
      final withSub = '$name ${tokens[1].toLowerCase()}';
      if (_readForms.containsKey(withSub)) {
        key = withSub;
        rest = tokens.skip(2).toList();
      }
    }
    final form = _readForms[key];
    if (form == null) return false;

    for (final token in rest) {
      if (token.startsWith('-')) {
        if (form.options.contains(token)) continue;
        final equals = token.indexOf('=');
        if (equals > 0 &&
            form.valueOptions.contains(token.substring(0, equals))) {
          continue;
        }
        return false;
      }
      if (!form.positional) return false;
    }
    for (final needed in form.requiredOptions) {
      if (!rest.contains(needed)) return false;
    }
    return true;
  }

  static CommandVerdict classify(String command) {
    final trimmed = command.trim();
    if (trimmed.isEmpty) {
      return const CommandVerdict(
        risk: ToolRisk.execute,
        blockedReason: 'فرمان خالی است.',
      );
    }

    for (final rule in _blocked) {
      if (rule.pattern.hasMatch(trimmed)) {
        return CommandVerdict(
          risk: ToolRisk.destructive,
          blockedReason:
              'این فرمان به دلیل «${rule.reason}» اجازهٔ اجرا ندارد. '
              'اگر واقعاً لازم است، کاربر باید خودش آن را در ترمینال ویندوز اجرا کند.',
        );
      }
    }

    final warnings = <String>[
      for (final rule in _dangerous)
        if (rule.pattern.hasMatch(trimmed)) rule.warning,
    ];

    if (warnings.isNotEmpty) {
      return CommandVerdict(risk: ToolRisk.destructive, warnings: warnings);
    }

    if (isProvablyReadOnly(trimmed)) {
      return const CommandVerdict(risk: ToolRisk.read);
    }

    return const CommandVerdict(risk: ToolRisk.execute);
  }
}
