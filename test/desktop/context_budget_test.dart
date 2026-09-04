import 'package:flutter_test/flutter_test.dart';
import 'package:jemiran/desktop/agent/core/agent_engine.dart';
import 'package:jemiran/desktop/agent/core/agent_protocol.dart';
import 'package:jemiran/desktop/agent/core/context_budget.dart';
import 'package:jemiran/desktop/agent/core/model_adapter.dart';
import 'package:jemiran/desktop/agent/policy/agent_policy.dart';
import 'package:jemiran/desktop/agent/tools/agent_tool.dart';
import 'package:jemiran/desktop/agent/tools/tool_registry.dart';

class _BulkTool extends AgentTool {
  _BulkTool({required this.payloadChars});

  final int payloadChars;

  @override
  String get name => 'read_file';
  @override
  String get label => 'اکو';
  @override
  ToolRisk get risk => ToolRisk.read;
  @override
  String get permission => 'test.echo';
  @override
  String get signature => 'echo {"text": "..."}';

  @override
  ToolPreview preview(ToolCall call) => const ToolPreview(title: 'اکو');

  @override
  Future<ToolResult> run(ToolCall call, ToolContext context) async =>
      ToolResult.success(summary: 'اکو شد', data: {'blob': 'x' * payloadChars});
}

class _SessionCountingAdapter extends ModelAdapter {
  _SessionCountingAdapter(this.replies);

  final List<String> replies;
  int freshSessions = 0;
  var _index = 0;

  @override
  String get modelKey => 'fake';

  @override
  Future<void> startFreshSession() async => freshSessions++;

  @override
  Future<ModelTurn> send(ModelRequest request) async {
    final reply = _index < replies.length ? replies[_index++] : 'تمام شد.';
    return ModelTurn(text: reply, sessionId: 7);
  }
}

String _toolBlock(String json) => '```jemiran_tool\n$json\n```';

Future<int> _compactionsWith(ContextBudget? budget) async {
  final adapter = _SessionCountingAdapter([
    '```jemiran_plan\n["گام یک","گام دو"]\n```'
        '${_toolBlock('{"tool":"read_file","args":{"text":"a"}}')}',
    _toolBlock('{"tool":"read_file","args":{"text":"b"}}'),
    _toolBlock('{"tool":"read_file","args":{"text":"c"}}'),
    _toolBlock('{"tool":"read_file","args":{"text":"d"}}'),
    _toolBlock('{"tool":"read_file","step":1,"args":{"text":"e"}}'),
    _toolBlock('{"tool":"read_file","step":2,"args":{"text":"f"}}'),
    'کار تمام شد.',
  ]);
  final engine = AgentEngine(
    model: adapter,
    registry: ToolRegistry.of([_BulkTool(payloadChars: 12000)]),
    readPolicy: () =>
        AgentPolicyState(enabled: true, mode: AgentMode.autonomous),
    onGrant: (_, _) {},
    requestPermission: (_, _) async => PermissionDecision.allowOnce,
    askQuestion: (_) async => null,
    readContextBudget: budget == null ? null : () => budget,
  );
  await engine.run('یک کار طولانی');
  await Future<void>.delayed(Duration.zero);
  return adapter.freshSessions;
}

void main() {
  group('بودجهٔ زمینه', () {
    test('پیکربندی ناقص به پیش‌فرض محافظه‌کارانه برمی‌گردد', () {
      expect(ContextBudget.fallback.maxContextTokens, 16000);
      expect(ContextBudget.fallback.reservedOutputTokens, 4096);
    });

    test('سقف مؤثر از پیکربندی محلی خوانده می‌شود', () {
      final budget = ContextBudget.fromModelConfig({
        'key': 'x',
        'max_context_tokens': 192000,
        'max_output_tokens': 32000,
        'default_output_tokens': 12288,
      });
      expect(budget.maxContextTokens, 192000);
      expect(budget.reservedOutputTokens, 12288);
    });

    test('فضای پاسخ پیش‌فرض مدل بر سقف خروجی مقدم است', () {
      final budget = ContextBudget.fromModelConfig({
        'key': 'x',
        'max_context_tokens': 192000,
        'max_output_tokens': 32000,
        'default_output_tokens': 12288,
      });
      expect(budget.reservedOutputTokens, 12288);
    });

    test('نبود مقدار پیش‌فرض از سقف خروجی استفاده می‌کند', () {
      final budget = ContextBudget.fromModelConfig({
        'key': 'x',
        'max_context_tokens': 96000,
        'max_output_tokens': 20000,
      });
      expect(budget.reservedOutputTokens, 20000);
    });

    test('پیکربندی ناقص به پیش‌فرض محافظه‌کارانه برمی‌گردد', () {
      expect(
        ContextBudget.fromModelConfig({'key': 'x'}),
        ContextBudget.fallback,
      );
      expect(
        ContextBudget.fromModelConfig({'key': 'x', 'max_context_tokens': 0}),
        ContextBudget.fallback,
      );
    });

    test('فضای پاسخ هرگز بیشتر از نیمی از کل زمینه رزرو نمی‌شود', () {
      final budget = ContextBudget.fromModelConfig({
        'max_context_tokens': 8000,
        'max_output_tokens': 8000,
      });
      expect(budget.reservedOutputTokens, lessThanOrEqualTo(4000));
    });

    test('پنجرهٔ بزرگ‌تر، آستانهٔ بزرگ‌تر می‌دهد', () {
      const free = ContextBudget(
        maxContextTokens: 16000,
        reservedOutputTokens: 2048,
      );
      const amazing = ContextBudget(
        maxContextTokens: 192000,
        reservedOutputTokens: 12288,
      );
      expect(
        amazing.compactionThresholdTokens(),
        greaterThan(free.compactionThresholdTokens() * 10),
      );
    });

    test('هزینهٔ schema ابزارها از بودجه کسر می‌شود', () {
      const budget = ContextBudget(
        maxContextTokens: 96000,
        reservedOutputTokens: 8192,
      );
      final bare = budget.compactionThresholdTokens();
      final withTools = budget.compactionThresholdTokens(
        toolSchemaTokens: 5000,
      );
      expect(withTools, lessThan(bare));
      expect(bare - withTools, 4000);
    });

    test('رجیستری بزرگ نمی‌تواند آستانه را به صفر برساند', () {
      const budget = ContextBudget(
        maxContextTokens: 16000,
        reservedOutputTokens: 4096,
      );
      expect(
        budget.compactionThresholdTokens(toolSchemaTokens: 999999),
        ContextBudget.minThresholdTokens,
      );
    });

    test('آستانهٔ پلن رایگان جا برای پاسخ باقی می‌گذارد', () {
      const free = ContextBudget(
        maxContextTokens: 16000,
        reservedOutputTokens: 2048,
      );
      final threshold = free.compactionThresholdTokens();
      expect(threshold + free.reservedOutputTokens, lessThan(16000));

      final legacyEquivalent = AgentProtocol.estimatedTokens('ا' * 24000);
      expect(
        threshold,
        lessThan(legacyEquivalent),
        reason: 'آستانهٔ تازه باید از ثابتِ ناامن قبلی محافظه‌کارانه‌تر باشد',
      );
    });
  });

  group('اثر بودجه روی موتور', () {
    test('بودجهٔ بزرگ همان گفت‌وگو را کمتر فشرده می‌کند', () async {
      final withFallback = await _compactionsWith(null);
      final withAmazing = await _compactionsWith(
        const ContextBudget(
          maxContextTokens: 192000,
          reservedOutputTokens: 12288,
        ),
      );

      expect(
        withFallback,
        greaterThan(0),
        reason: 'پلن تنگ باید فشرده‌سازی را ببیند',
      );
      expect(
        withAmazing,
        0,
        reason: 'کاربری که ظرفیت ۱۹۲هزار توکنی خریده نباید اینجا فشرده شود',
      );
    });
  });
}
