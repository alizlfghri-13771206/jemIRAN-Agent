import 'package:flutter_test/flutter_test.dart';
import 'package:jemiran/desktop/agent/core/agent_engine.dart';
import 'package:jemiran/desktop/agent/core/agent_task.dart';
import 'package:jemiran/desktop/agent/core/model_adapter.dart';
import 'package:jemiran/desktop/agent/core/model_failover.dart';
import 'package:jemiran/desktop/agent/policy/agent_policy.dart';
import 'package:jemiran/desktop/agent/tools/tool_registry.dart';
import 'package:jemiran/desktop/agent/network/provider_exception.dart';

class _OverflowAdapter extends ModelAdapter {
  _OverflowAdapter({required this.failUntil, this.code = 'context_limit'});

  final int failUntil;

  final String? code;

  int calls = 0;
  int freshSessions = 0;
  final sent = <String>[];

  @override
  String get modelKey => 'fake';

  @override
  Future<void> startFreshSession() async => freshSessions++;

  @override
  Future<ModelTurn> send(ModelRequest request) async {
    calls++;
    sent.add(request.text);
    if (calls <= failUntil) {
      throw ApiException(
        'حجم context از سقف امن مدل بیشتر است.',
        413,
        code: code,
      );
    }
    return const ModelTurn(text: 'کار تمام شد.', sessionId: 7);
  }
}

AgentEngine _engine(_OverflowAdapter adapter) => AgentEngine(
  model: adapter,
  registry: ToolRegistry.of(const []),
  readPolicy: () => AgentPolicyState(enabled: true, mode: AgentMode.autonomous),
  onGrant: (_, _) {},
  requestPermission: (_, _) async => PermissionDecision.allowOnce,
  askQuestion: (_) async => null,
);

void main() {
  test(
    'سرریز زمینه Task را نمی‌کشد؛ فشرده می‌کند و یک بار دوباره می‌فرستد',
    () async {
      final adapter = _OverflowAdapter(failUntil: 1);
      final task = await _engine(adapter).run('یک کار');

      expect(task.phase, AgentPhase.done);
      expect(adapter.calls, 2, reason: 'یک شکست، بعد یک تلاش موفق');
      expect(adapter.freshSessions, 1, reason: 'نشست باید از نو ساخته شود');

      expect(adapter.sent.last, contains('خلاصهٔ فشرده‌شدهٔ کار'));
      expect(adapter.sent.last, contains('یک کار'));
    },
  );

  test('اگر بعد از فشرده‌سازی هم سرریز بود، حلقه نمی‌سازد', () async {
    final adapter = _OverflowAdapter(failUntil: 99);
    final task = await _engine(adapter).run('یک کار');

    expect(task.phase, AgentPhase.failed);
    expect(adapter.calls, 2, reason: 'دقیقاً یک بار بازیابی، نه بیشتر');
  });

  test('۴۱۳ خالی هم بازیابی می‌شود، نه اینکه Task را بکشد', () async {
    final adapter = _OverflowAdapter(failUntil: 1, code: null);
    final task = await _engine(adapter).run('یک کار');

    expect(task.phase, AgentPhase.done);
    expect(adapter.calls, 2);
    expect(adapter.freshSessions, 1);
  });

  test('عوض کردن مدل، سرریز زمینه را حل نمی‌کند', () {
    expect(
      classifyFailure(
        const ApiException('حجم زیاد', 413, code: 'context_limit'),
      ),
      FailureKind.fatal,
    );
  });
}
