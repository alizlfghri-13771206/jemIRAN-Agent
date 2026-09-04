import '../network/agent_environment.dart';
import '../network/proxy_detector.dart';
import '../policy/agent_policy.dart';
import 'agent_tool.dart';

const _targets = <String, String>{
  'pub.dev': 'بسته‌های دارت و فلاتر',
  'registry.npmjs.org': 'بسته‌های نود',
  'pypi.org': 'بسته‌های پایتون',
  'github.com': 'مخزن‌های گیت',
};

class CheckNetworkTool extends AgentTool {
  const CheckNetworkTool();

  @override
  String get name => 'check_network';
  @override
  String get label => 'بررسی اتصال';

  @override
  ToolRisk get risk => ToolRisk.read;

  @override
  String get permission => Perm.networkFetch;

  @override
  String get signature =>
      'check_network {} '
      '— وقتی فرمانی به‌خاطر شبکه شکست خورد (pub، npm، pip، git) اول این '
      'را بزن. وضعیت پروکسی و دسترسی به مخزن‌ها را می‌دهد.';

  @override
  ToolPreview preview(ToolCall call) =>
      const ToolPreview(title: 'بررسی اتصال به مخزن‌ها');

  @override
  Future<ToolResult> run(ToolCall call, ToolContext context) async {
    final proxy = await AgentEnvironment.resolve();
    context.report(
      proxy == null
          ? 'پروکسی‌ای پیدا نشد — اتصال مستقیم بررسی می‌شود.'
          : 'پروکسی: ${proxy.displayUrl} (${proxy.source})',
    );

    final direct = <String, bool>{};
    final viaProxy = <String, bool>{};

    for (final entry in _targets.entries) {
      final host = entry.key;
      context.report('بررسی $host…');

      direct[host] = await ProxyDetector.canReach(host);

      if (!direct[host]! && proxy != null) {
        viaProxy[host] = await ProxyDetector.canReach(host, through: proxy);
      }
    }

    final reachable = <String>[];
    final blocked = <String>[];
    for (final host in _targets.keys) {
      final ok = direct[host]! || (viaProxy[host] ?? false);
      (ok ? reachable : blocked).add(host);
    }

    final needsProxy = _targets.keys.any(
      (h) => !direct[h]! && (viaProxy[h] ?? false),
    );

    final advice = switch ((blocked.isEmpty, proxy != null, needsProxy)) {
      (true, _, true) =>
        'همه در دسترس‌اند، ولی فقط از راه پروکسی. جمیران پروکسی را به '
            'فرمان‌ها می‌دهد، پس مشکلی نیست.',
      (true, _, _) => 'همهٔ مخزن‌ها مستقیم در دسترس‌اند.',
      (false, false, _) =>
        'هیچ پروکسی‌ای پیدا نشد و این میزبان‌ها بسته‌اند: '
            '${blocked.join('، ')}. کاربر باید ابزار عبور از فیلترینگ را '
            'روشن کند، یا در تنظیمات شبکهٔ جمیران نشانی پروکسی را دستی '
            'وارد کند.',
      (false, true, _) =>
        'پروکسی هست ولی این میزبان‌ها از راه آن هم باز نشدند: '
            '${blocked.join('، ')}. احتمالاً پروکسی قطع است یا این '
            'میزبان‌ها را پوشش نمی‌دهد.',
    };

    return ToolResult.success(
      summary: blocked.isEmpty
          ? 'همهٔ ${_targets.length} مخزن در دسترس است'
          : '${blocked.length} مخزن در دسترس نیست',
      data: {
        'proxy': proxy?.toJson(),
        'proxy_mode': AgentEnvironment.config.mode.name,
        'reachable': reachable,
        'blocked': blocked,
        'requires_proxy': needsProxy,
        'advice': advice,
      },
      detail: [
        proxy == null
            ? 'پروکسی: ندارد'
            : 'پروکسی: ${proxy.displayUrl} — ${proxy.source}',
        '',
        for (final entry in _targets.entries)
          '${direct[entry.key]!
                  ? '✓ مستقیم'
                  : (viaProxy[entry.key] ?? false)
                  ? '✓ از پروکسی'
                  : '✗ بسته'}  '
              '${entry.key}  (${entry.value})',
        '',
        advice,
      ].join('\n'),
    );
  }
}
