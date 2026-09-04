import '../acquisition/capability_catalog.dart';
import '../acquisition/capability_service.dart';
import '../policy/agent_policy.dart';
import 'agent_tool.dart';

List<AgentTool> get capabilityTools => const [
  CheckCapabilityTool(),
  InstallCapabilityTool(),
];

class CheckCapabilityTool extends AgentTool {
  const CheckCapabilityTool();

  @override
  String get name => 'check_capability';
  @override
  String get label => 'بررسی قابلیت';
  @override
  ToolRisk get risk => ToolRisk.read;
  @override
  String get permission => Perm.toolExecute;

  @override
  String get signature =>
      'check_capability {"capability": "pdf"} '
      '— قبل از کاری که ابزار لازم دارد، اول بپرس در دسترس هست یا نه. '
      'بدون آرگومان، همهٔ قابلیت‌ها را گزارش می‌کند. '
      'قابلیت‌ها: ${CapabilityCatalog.keys.join('، ')}';

  @override
  Map<String, dynamic> get parameterSchema => const {
    'capability': {
      'type': 'string',
      'enum': [
        'pdf',
        'docx',
        'ocr',
        'document_convert',
        'image_convert',
        'compression',
        'python',
        'node',
        'git',
        'linux',
        'ffmpeg',
      ],
    },
  };

  @override
  List<String> get requiredParameters => const ['capability'];

  @override
  ToolPreview preview(ToolCall call) => ToolPreview(
    title: 'بررسی قابلیت',
    subtitle: call.str('capability') ?? 'همهٔ قابلیت‌ها',
  );

  @override
  Future<ToolResult> run(ToolCall call, ToolContext context) async {
    final key = call.str('capability');

    if (key == null) {
      final survey = await CapabilityService.survey();
      final ready = survey.where((s) => s.isReady).length;
      return ToolResult.success(
        summary: '$ready از ${survey.length} قابلیت آماده است',
        data: {
          'capabilities': [for (final s in survey) s.toJson()],
        },
        detail: [
          for (final s in survey)
            '${s.isReady ? '✓' : '·'} ${s.capability.label} — '
                '${_stateLabel(s)}',
        ].join('\n'),
      );
    }

    final status = await CapabilityService.resolve(key);
    return ToolResult.success(
      summary: '${status.capability.label}: ${_stateLabel(status)}',
      data: status.toJson(),
      detail: _detailOf(status),
    );
  }

  static String _stateLabel(CapabilityStatus s) => switch (s.state) {
    CapabilityState.builtin => 'آماده — ${s.capability.builtinBy}',
    CapabilityState.available =>
      'نصب است${s.probe?.version == null ? '' : ' (${s.probe!.version})'}',
    CapabilityState.installable => 'نصب نیست — قابل نصب',
    CapabilityState.unavailable => 'در دسترس نیست',
  };

  static String _detailOf(CapabilityStatus s) {
    final buffer = StringBuffer()
      ..writeln(s.capability.label)
      ..writeln(s.capability.description)
      ..writeln()
      ..writeln(_stateLabel(s));
    if (s.probe?.path != null) buffer.writeln(s.probe!.path);
    if (s.provider != null) {
      buffer.writeln('نصب از: ${s.provider!.manager.label}');
      buffer.writeln('بسته: ${s.provider!.packageId}');
    }
    if (s.reason != null) buffer.writeln(s.reason);
    return buffer.toString();
  }
}

class InstallCapabilityTool extends AgentTool {
  const InstallCapabilityTool();

  @override
  String get name => 'install_capability';
  @override
  String get label => 'نصب ابزار';

  @override
  ToolRisk get risk => ToolRisk.execute;

  @override
  String get permission => Perm.toolInstall;

  @override
  String get signature =>
      'install_capability {"capability": "ocr"} '
      '— فقط وقتی check_capability گفته «قابل نصب». از منبع رسمی نصب می‌کند.';

  @override
  Map<String, dynamic> get parameterSchema => const {
    'capability': {
      'type': 'string',
      'enum': [
        'pdf',
        'docx',
        'ocr',
        'document_convert',
        'image_convert',
        'compression',
        'python',
        'node',
        'git',
        'linux',
        'ffmpeg',
      ],
    },
  };

  @override
  List<String> get requiredParameters => const ['capability'];

  @override
  ToolPreview preview(ToolCall call) {
    final key = call.str('capability') ?? '';
    final capability = CapabilityCatalog.find(key);
    final provider = capability?.providers.firstOrNull;

    return ToolPreview(
      title: 'نصب ابزار روی سیستم شما',
      subtitle: capability?.label ?? key,
      body: provider == null
          ? null
          : 'بسته: ${provider.packageId}\n'
                'منبع: ${provider.manager.label}\n'
                'دامنه: کاربر (بدون نیاز به دسترسی مدیر)',
      warnings: [
        if (provider != null)
          'با تأیید این کار، شرایط استفادهٔ ناشر بسته هم پذیرفته می‌شود.',
        if (provider?.manager.mayNeedAdmin ?? false)
          'این روش نصب ممکن است دسترسی مدیر بخواهد.',
        if (provider?.note != null) provider!.note!,
      ],
    );
  }

  @override
  Future<ToolResult> run(ToolCall call, ToolContext context) async {
    final key = call.str('capability');
    if (key == null) {
      return ToolResult.failure('پارامتر capability لازم است.');
    }

    final status = await CapabilityService.resolve(key);

    if (status.isReady) {
      return ToolResult.success(
        summary: '${status.capability.label} از قبل آماده است',
        data: {...status.toJson(), 'installed_now': false},
      );
    }

    if (status.state != CapabilityState.installable) {
      return ToolResult.failure(
        status.reason ?? 'این قابلیت قابل نصب خودکار نیست.',
        data: status.toJson(),
      );
    }

    context.report('نصب ${status.capability.label}…');
    final outcome = await CapabilityService.install(
      status,
      onProgress: context.report,
    );

    if (!outcome.ok) {
      return ToolResult(
        ok: false,
        summary: outcome.message,
        error: outcome.message,
        detail: outcome.log,
        data: {
          'ok': false,
          'capability': key,
          'error': outcome.message,
          if (outcome.exitCode != null) 'exit_code': outcome.exitCode,
        },
      );
    }

    return ToolResult.success(
      summary: outcome.message,
      detail: outcome.log,
      data: {
        'capability': key,
        'installed_now': true,
        'verified': true,
        if (outcome.probe != null) 'tool': outcome.probe!.toJson(),
      },
    );
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
