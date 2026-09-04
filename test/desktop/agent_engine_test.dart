import 'package:flutter_test/flutter_test.dart';
import 'package:jemiran/desktop/agent/core/agent_engine.dart';
import 'package:jemiran/desktop/agent/core/agent_event.dart';
import 'package:jemiran/desktop/agent/core/agent_protocol.dart';
import 'package:jemiran/desktop/agent/core/agent_task.dart';
import 'package:jemiran/desktop/agent/core/model_adapter.dart';
import 'package:jemiran/desktop/agent/policy/agent_policy.dart';
import 'package:jemiran/desktop/agent/tools/agent_tool.dart';
import 'package:jemiran/desktop/agent/tools/tool_registry.dart';

class _FakeAdapter extends ModelAdapter {
  _FakeAdapter(this.replies);

  final List<String> replies;
  final sent = <String>[];
  var _index = 0;

  @override
  String get modelKey => 'fake';

  @override
  Future<ModelTurn> send(ModelRequest request) async {
    sent.add(request.text);
    final reply = _index < replies.length ? replies[_index++] : 'تمام شد.';
    return ModelTurn(text: reply);
  }
}

class _StructuredAdapter extends ModelAdapter {
  _StructuredAdapter(this.replies);

  final List<ModelTurn> replies;
  final requests = <ModelRequest>[];
  var _index = 0;

  @override
  String get modelKey => 'structured-fake';

  @override
  Future<ModelTurn> send(ModelRequest request) async {
    requests.add(request);
    if (_index >= replies.length) {
      throw StateError('پاسخ ساختگی کافی نیست');
    }
    return replies[_index++];
  }
}

class _ThrowingAdapter extends ModelAdapter {
  @override
  String get modelKey => 'throwing';

  @override
  Future<ModelTurn> send(ModelRequest request) =>
      Future<ModelTurn>.error(StateError('model failed'));
}

class _CancellableAdapter extends ModelAdapter {
  bool cancelled = false;

  @override
  String get modelKey => 'cancellable';

  @override
  Future<ModelTurn> send(ModelRequest request) async =>
      const ModelTurn(text: 'done');

  @override
  Future<bool> cancel() async => cancelled = true;
}

class _EchoTool extends AgentTool {
  _EchoTool({
    this.toolRisk = ToolRisk.read,
    this.toolPermission = 'test.echo',
    this.denyReason,
  });

  final ToolRisk toolRisk;
  final String toolPermission;
  final String? denyReason;

  int calls = 0;

  @override
  String get name => 'echo';
  @override
  String get label => 'اکو';
  @override
  ToolRisk get risk => toolRisk;
  @override
  String get permission => toolPermission;
  @override
  String get signature => 'echo {"text": "..."}';

  @override
  String? hardDeny(ToolCall call) => denyReason;

  @override
  ToolPreview preview(ToolCall call) =>
      ToolPreview(title: 'اکو', subtitle: call.str('text'));

  @override
  Future<ToolResult> run(ToolCall call, ToolContext context) async {
    calls++;
    return ToolResult.success(
      summary: 'اکو شد',
      data: {'echo': call.str('text')},
    );
  }
}

class _AskTool extends AgentTool {
  String? received;

  @override
  String get name => 'ask';
  @override
  String get label => 'پرسش';
  @override
  ToolRisk get risk => ToolRisk.read;
  @override
  String get permission => 'test.ask';
  @override
  String get signature => 'ask {"q": "..."}';

  @override
  ToolPreview preview(ToolCall call) => const ToolPreview(title: 'پرسش');

  @override
  Future<ToolResult> run(ToolCall call, ToolContext context) async {
    received = await context.ask(
      AgentQuestion(text: call.str('q') ?? '؟', options: const ['الف', 'ب']),
    );
    return ToolResult.success(
      summary: 'پاسخ گرفته شد',
      data: {'answer': received},
    );
  }
}

class _CallbackTool extends AgentTool {
  _CallbackTool({required this.onRun});

  final void Function() onRun;
  int calls = 0;

  @override
  String get name => 'echo';
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
  Future<ToolResult> run(ToolCall call, ToolContext context) async {
    calls++;
    onRun();
    return ToolResult.success(summary: 'اکو شد');
  }
}

class _LifecycleTool extends AgentTool {
  _LifecycleTool({
    required this.toolName,
    this.toolRisk = ToolRisk.read,
    this.denyReason,
    this.throwOnRun = false,
  });

  final String toolName;
  final ToolRisk toolRisk;
  final String? denyReason;
  final bool throwOnRun;
  int calls = 0;

  @override
  String get name => toolName;
  @override
  String get label => toolName;
  @override
  ToolRisk get risk => toolRisk;
  @override
  String get permission => 'test.$toolName';
  @override
  String get signature => '$toolName {}';

  @override
  String? hardDeny(ToolCall call) => denyReason;

  @override
  ToolPreview preview(ToolCall call) => ToolPreview(title: toolName);

  @override
  Future<ToolResult> run(ToolCall call, ToolContext context) async {
    calls++;
    if (throwOnRun) throw StateError('native boom');
    return ToolResult.success(
      summary: 'native ok',
      data: {'payload': call.str('text')},
    );
  }
}

String _toolBlock(String json) => '```jemiran_tool\n$json\n```';

Future<void> _flush() => Future<void>.delayed(Duration.zero);

({AgentEngine engine, List<AgentEvent> events, List<String> permissionAsks})
_build({
  required ModelAdapter adapter,
  required ToolRegistry registry,
  AgentPolicyState policy = const AgentPolicyState(enabled: true),
  PermissionDecision decision = PermissionDecision.allowOnce,
  String? answer,
}) {
  final events = <AgentEvent>[];
  final asks = <String>[];

  final engine = AgentEngine(
    model: adapter,
    registry: registry,
    readPolicy: () => policy,
    onGrant: (_, _) {},
    requestPermission: (step, preview) async {
      asks.add(step.call.name);
      return decision;
    },
    askQuestion: (question) async => answer,
  );
  engine.events.listen(events.add);
  return (engine: engine, events: events, permissionAsks: asks);
}

void main() {
  group('حلقهٔ پایه', () {
    test('پاسخ بدون ابزار یعنی کار تمام است', () async {
      final adapter = _FakeAdapter(['سلام، این جواب نهایی است.']);
      final h = _build(
        adapter: adapter,
        registry: ToolRegistry.of([_EchoTool()]),
      );

      final task = await h.engine.run('یک سؤال ساده');

      expect(task.phase, AgentPhase.done);
      expect(task.finalAnswer, contains('جواب نهایی'));
      expect(task.steps, isEmpty);
      expect(adapter.sent, hasLength(1));
      expect(adapter.sent.first, contains('حالت ایجنت جمیران فعال است'));
      expect(adapter.sent.first, contains('یک سؤال ساده'));
    });

    test('ابزار اجرا می‌شود و نتیجه به مدل برمی‌گردد', () async {
      final tool = _EchoTool();
      final adapter = _FakeAdapter([
        _toolBlock('{"tool": "echo", "args": {"text": "سلام"}}'),
        'کار تمام شد.',
      ]);
      final h = _build(adapter: adapter, registry: ToolRegistry.of([tool]));

      final task = await h.engine.run('اکو کن');

      expect(tool.calls, 1);
      expect(task.steps, hasLength(1));
      expect(task.steps.single.status, StepStatus.done);
      expect(task.phase, AgentPhase.done);

      expect(adapter.sent, hasLength(2));
      expect(adapter.sent[1], contains('نتیجهٔ اجرای ابزارها'));
      expect(adapter.sent[1], contains('سلام'));
    });

    test('چند فراخوان در یک پاسخ همگی اجرا می‌شوند', () async {
      final tool = _EchoTool();
      final adapter = _FakeAdapter([
        _toolBlock('{"tool": "echo", "args": {"text": "یک"}}') +
            _toolBlock('{"tool": "echo", "args": {"text": "دو"}}'),
        'تمام.',
      ]);
      final h = _build(adapter: adapter, registry: ToolRegistry.of([tool]));

      final task = await h.engine.run('دوتا اکو');

      expect(tool.calls, 2);
      expect(task.steps, hasLength(2));
      expect(task.steps.first.index, 1);
      expect(task.steps.first.total, 2);
    });

    test('نقشهٔ کار خوانده و ثبت می‌شود', () async {
      final adapter = _FakeAdapter([
        '```jemiran_plan\n["الف", "ب"]\n```\nشروع می‌کنم.',
      ]);
      final h = _build(
        adapter: adapter,
        registry: ToolRegistry.of([_EchoTool()]),
      );

      final task = await h.engine.run('کاری بکن');

      await _flush();
      expect(task.plan.map((s) => s.text), ['الف', 'ب']);
      expect(h.events.whereType<PlanUpdated>(), hasLength(1));
    });
  });

  group('چرخهٔ ساختاری ابزار', () {
    test('batch بزرگ‌تر از کانال نتیجه پیش از هر اجرا repair می‌شود', () async {
      final tool = _LifecycleTool(toolName: 'native_limited');
      final adapter = _StructuredAdapter([
        ModelTurn(
          text: '',
          finishReason: 'tool_calls',
          toolCalls: List.generate(
            AgentProtocol.maxToolCallsPerTurn + 1,
            (index) => ToolCall(
              id: 'call_over_$index',
              name: tool.name,
              args: const {},
            ),
          ),
        ),
        const ModelTurn(text: 'فراخوان‌ها را کوچک کردم.'),
      ]);
      final h = _build(adapter: adapter, registry: ToolRegistry.of([tool]));

      final task = await h.engine.run('batch را امن اجرا کن');

      expect(task.phase, AgentPhase.done);
      expect(tool.calls, 0, reason: 'batch نیمه‌کاره نباید اثر جانبی بسازد');
      expect(adapter.requests, hasLength(2));
      expect(adapter.requests[1].toolResults, isNull);
      expect(adapter.requests[1].text, contains('هیچ عملیاتی اجرا نشد'));
    });

    test(
      'برای هر فراخوان native دقیقاً یک نتیجهٔ هم‌شناسه برمی‌گردد',
      () async {
        final ok = _LifecycleTool(toolName: 'native_ok');
        final blocked = _LifecycleTool(
          toolName: 'native_blocked',
          toolRisk: ToolRisk.write,
          denyReason: 'رد قطعی policy',
        );
        final denied = _LifecycleTool(
          toolName: 'native_denied',
          toolRisk: ToolRisk.write,
        );
        final failing = _LifecycleTool(
          toolName: 'native_failing',
          throwOnRun: true,
        );
        final adapter = _StructuredAdapter([
          ModelTurn(
            text: '',
            finishReason: 'tool_calls',
            toolCalls: [
              ToolCall(
                id: 'call_ok',
                name: ok.name,
                args: const {'text': 'RAW_NATIVE_SECRET'},
              ),
              ToolCall(
                id: 'call_unknown',
                name: 'native_missing',
                args: const {},
              ),
              ToolCall(id: 'call_blocked', name: blocked.name, args: const {}),
              ToolCall(id: 'call_denied', name: denied.name, args: const {}),
              ToolCall(id: 'call_failing', name: failing.name, args: const {}),
            ],
          ),
          const ModelTurn(text: 'کار تمام شد.'),
        ]);
        final h = _build(
          adapter: adapter,
          registry: ToolRegistry.of([ok, blocked, denied, failing]),
          decision: PermissionDecision.deny,
        );

        final task = await h.engine.run('چرخه را کامل کن');

        expect(task.phase, AgentPhase.done);
        expect(ok.calls, 1);
        expect(blocked.calls, 0);
        expect(denied.calls, 0);
        expect(failing.calls, 1);
        expect(task.steps.map((step) => step.status), [
          StepStatus.done,
          StepStatus.blocked,
          StepStatus.denied,
          StepStatus.failed,
        ]);

        expect(adapter.requests, hasLength(2));
        final results = adapter.requests[1].toolResults!;
        expect(results, hasLength(5));
        expect(results.map((result) => result['tool_call_id']), [
          'call_ok',
          'call_unknown',
          'call_blocked',
          'call_denied',
          'call_failing',
        ]);
        expect(
          results.map((result) => result['tool_call_id']).toSet(),
          hasLength(5),
          reason: 'هر فراخوان native باید دقیقاً یک پاسخ داشته باشد',
        );
        expect(results[0]['content'], contains('RAW_NATIVE_SECRET'));
        expect(results[1]['content'], contains('ابزار ناشناخته'));
        expect(results[2]['content'], contains('رد قطعی policy'));
        expect(results[3]['content'], contains('کاربر اجازه نداد'));
        expect(results[4]['content'], contains('native boom'));

        expect(adapter.requests[1].text, isNot(contains('RAW_NATIVE_SECRET')));
        expect(adapter.requests[1].text, contains('کانال ساختاری'));
        expect(adapter.requests[1].text, isNot(contains('کاربر اجازه نداد')));
      },
    );

    for (final scenario in <({String name, ModelTurn repairTurn})>[
      (name: 'پاسخ خالی', repairTurn: const ModelTurn(text: '')),
      (
        name: 'فراخوان متنی خراب',
        repairTurn: const ModelTurn(text: '```jemiran_tool\n{خراب}\n```'),
      ),
    ]) {
      test(
        'نتیجهٔ native پس از ${scenario.name} دوباره ارسال نمی‌شود',
        () async {
          final tool = _LifecycleTool(toolName: 'native_once');
          final adapter = _StructuredAdapter([
            ModelTurn(
              text: '',
              finishReason: 'tool_calls',
              toolCalls: [
                ToolCall(
                  id: 'call_once',
                  name: tool.name,
                  args: const {'text': 'once'},
                ),
              ],
            ),
            scenario.repairTurn,
            const ModelTurn(text: 'تمام شد.'),
          ]);
          final h = _build(adapter: adapter, registry: ToolRegistry.of([tool]));

          await h.engine.run('یک بار اجرا کن');

          expect(adapter.requests, hasLength(3));
          expect(adapter.requests[1].toolResults, hasLength(1));
          expect(
            adapter.requests[2].toolResults,
            isNull,
            reason: 'نتیجهٔ مصرف‌شده نباید در پیام ترمیم تکرار شود',
          );
        },
      );
    }

    test('نتیجهٔ native در nudge نقشهٔ ناتمام دوباره ارسال نمی‌شود', () async {
      final tool = _LifecycleTool(toolName: 'native_plan');
      final adapter = _StructuredAdapter([
        ModelTurn(
          text: '```jemiran_plan\n["بند باز"]\n```',
          finishReason: 'tool_calls',
          toolCalls: [
            ToolCall(
              id: 'call_plan',
              name: tool.name,
              args: const {'text': 'once'},
            ),
          ],
        ),
        const ModelTurn(text: 'تمام شد.'),
        const ModelTurn(text: 'واقعاً تمام شد.'),
      ]);
      final h = _build(adapter: adapter, registry: ToolRegistry.of([tool]));

      final task = await h.engine.run('نقشه را اجرا کن');

      expect(task.phase, AgentPhase.incomplete);
      expect(adapter.requests, hasLength(3));
      expect(adapter.requests[1].toolResults, hasLength(1));
      expect(adapter.requests[2].toolResults, isNull);
      expect(adapter.requests[2].text, contains('ناتمام'));
    });
  });

  group('اجازه‌ها', () {
    test('حالت دستی برای نوشتن اجازه می‌گیرد', () async {
      final tool = _EchoTool(toolRisk: ToolRisk.write);
      final adapter = _FakeAdapter([
        _toolBlock('{"tool": "echo", "args": {"text": "x"}}'),
        'تمام.',
      ]);
      final h = _build(
        adapter: adapter,
        registry: ToolRegistry.of([tool]),
        policy: const AgentPolicyState(enabled: true, mode: AgentMode.manual),
      );

      await h.engine.run('بنویس');

      expect(h.permissionAsks, ['echo']);
      expect(tool.calls, 1);
    });

    test('رد کردن کاربر ابزار را اجرا نمی‌کند و به مدل خبر می‌دهد', () async {
      final tool = _EchoTool(toolRisk: ToolRisk.write);
      final adapter = _FakeAdapter([
        _toolBlock('{"tool": "echo", "args": {"text": "x"}}'),
        'باشه، کار دیگری می‌کنم.',
      ]);
      final h = _build(
        adapter: adapter,
        registry: ToolRegistry.of([tool]),
        decision: PermissionDecision.deny,
      );

      final task = await h.engine.run('بنویس');

      expect(tool.calls, 0);
      expect(task.steps.single.status, StepStatus.denied);
      expect(adapter.sent[1], contains('کاربر اجازه نداد'));
    });

    test('حالت خودگردان برای نوشتن نمی‌پرسد', () async {
      final tool = _EchoTool(toolRisk: ToolRisk.write);
      final adapter = _FakeAdapter([
        _toolBlock('{"tool": "echo", "args": {"text": "x"}}'),
        'تمام.',
      ]);
      final h = _build(
        adapter: adapter,
        registry: ToolRegistry.of([tool]),
        policy: const AgentPolicyState(
          enabled: true,
          mode: AgentMode.autonomous,
        ),
      );

      await h.engine.run('بنویس');

      expect(h.permissionAsks, isEmpty);
      expect(tool.calls, 1);
    });

    test('حالت خودگردان برای عملیات غیرقابل‌برگشت باز هم می‌پرسد', () async {
      final tool = _EchoTool(toolRisk: ToolRisk.destructive);
      final adapter = _FakeAdapter([
        _toolBlock('{"tool": "echo", "args": {"text": "x"}}'),
        'تمام.',
      ]);
      final h = _build(
        adapter: adapter,
        registry: ToolRegistry.of([tool]),
        policy: const AgentPolicyState(
          enabled: true,
          mode: AgentMode.autonomous,
        ),
      );

      await h.engine.run('حذف کن');

      expect(h.permissionAsks, ['echo'], reason: 'بند ۷: خودگردان ≠ نامحدود');
    });

    test('اجازهٔ نشست هم جلوی پرسیدنِ حذف را نمی‌گیرد', () async {
      final tool = _EchoTool(
        toolRisk: ToolRisk.destructive,
        toolPermission: Perm.filesystemDelete,
      );
      final adapter = _FakeAdapter([
        _toolBlock('{"tool": "echo", "args": {"text": "x"}}'),
        'تمام.',
      ]);
      final h = _build(
        adapter: adapter,
        registry: ToolRegistry.of([tool]),
        policy: const AgentPolicyState(
          enabled: true,
          mode: AgentMode.autonomous,
          sessionGrants: {Perm.filesystemDelete},
        ),
      );

      await h.engine.run('حذف کن');

      expect(h.permissionAsks, ['echo']);
    });

    test('رد قطعی Policy اصلاً دیالوگ نشان نمی‌دهد', () async {
      final tool = _EchoTool(
        toolRisk: ToolRisk.write,
        denyReason: 'مسیر بیرون از منابع مجاز است.',
      );
      final adapter = _FakeAdapter([
        _toolBlock('{"tool": "echo", "args": {"text": "x"}}'),
        'باشه.',
      ]);
      final h = _build(adapter: adapter, registry: ToolRegistry.of([tool]));

      final task = await h.engine.run('بنویس');

      expect(h.permissionAsks, isEmpty, reason: 'پرسیدن یعنی راه دور زدن دادن');
      expect(tool.calls, 0);
      expect(task.steps.single.status, StepStatus.blocked);
      expect(adapter.sent[1], contains('بیرون از منابع مجاز'));
    });
  });

  group('پرسش از کاربر', () {
    test('پاسخ کاربر به ابزار و بعد به مدل می‌رسد', () async {
      final tool = _AskTool();
      final adapter = _FakeAdapter([
        _toolBlock('{"tool": "ask", "args": {"q": "کدام پروژه؟"}}'),
        'ممنون.',
      ]);
      final h = _build(
        adapter: adapter,
        registry: ToolRegistry.of([tool]),
        answer: 'الف',
      );

      final task = await h.engine.run('شروع کن');

      expect(tool.received, 'الف');
      expect(task.conversation, hasLength(1));
      expect(task.conversation.single.answer, 'الف');
      expect(adapter.sent[1], contains('الف'));
      await _flush();
      expect(h.events.whereType<QuestionAsked>(), hasLength(1));
    });

    test('بی‌پاسخ ماندن به مدل گفته می‌شود', () async {
      final tool = _AskTool();
      final adapter = _FakeAdapter([
        _toolBlock('{"tool": "ask", "args": {"q": "؟"}}'),
        'باشه.',
      ]);
      final h = _build(
        adapter: adapter,
        registry: ToolRegistry.of([tool]),
        answer: null,
      );

      await h.engine.run('شروع کن');

      expect(tool.received, isNull);
      expect(adapter.sent[1], contains('"answer":null'));
    });
  });

  group('مرزها', () {
    test('فراخوان خراب خودکار اصلاح و سپس اجرا می‌شود', () async {
      final tool = _EchoTool();
      final adapter = _FakeAdapter([
        '```jemiran_tool\n{خراب}\n```',
        _toolBlock('{"tool":"echo","args":{"text":"اصلاح شد"}}'),
        'تمام شد.',
      ]);
      final h = _build(adapter: adapter, registry: ToolRegistry.of([tool]));

      final task = await h.engine.run('ابزار بزن');
      await _flush();

      expect(task.phase, AgentPhase.done);
      expect(tool.calls, 1);
      expect(adapter.sent[1], contains('خطای قالب فراخوان ابزار'));
      expect(adapter.sent[1], contains('echo'));
      expect(
        h.events.whereType<RecoverableError>().single.message,
        contains('اصلاح خودکار'),
      );
      expect(
        h.events.whereType<AssistantSaid>().map((event) => event.text).join(),
        isNot(contains('{خراب}')),
      );
    });

    test('سه فراخوان خراب بدون اجرای عملیات متوقف می‌شوند', () async {
      final tool = _EchoTool();
      final adapter = _FakeAdapter(
        List.filled(3, '```jemiran_tool\n{خراب}\n```'),
      );
      final h = _build(adapter: adapter, registry: ToolRegistry.of([tool]));

      final task = await h.engine.run('ابزار بزن');
      await _flush();

      expect(task.phase, AgentPhase.failed);
      expect(tool.calls, 0);
      expect(task.steps, isEmpty);
      expect(adapter.sent, hasLength(3));
      expect(
        h.events.whereType<RecoverableError>().last.message,
        contains('هیچ عملیاتی اجرا نشد'),
      );
    });

    test('شکست مدل قبل از TaskFinished فاز failed اعلام می‌کند', () async {
      final h = _build(
        adapter: _ThrowingAdapter(),
        registry: ToolRegistry.of([_EchoTool()]),
      );

      final task = await h.engine.run('شکست بده');
      await _flush();

      expect(task.phase, AgentPhase.failed);
      final failedIndex = h.events.indexWhere(
        (event) => event is PhaseChanged && event.phase == AgentPhase.failed,
      );
      final finishedIndex = h.events.indexWhere(
        (event) => event is TaskFinished && event.error != null,
      );
      expect(failedIndex, greaterThanOrEqualTo(0));
      expect(finishedIndex, greaterThan(failedIndex));
    });

    test('dispose درخواست مدل را cancel می‌کند', () async {
      final adapter = _CancellableAdapter();
      final h = _build(
        adapter: adapter,
        registry: ToolRegistry.of([_EchoTool()]),
      );

      await h.engine.dispose();

      expect(adapter.cancelled, isTrue);
    });

    test('سقف دور رعایت می‌شود و کاربر خبردار می‌شود', () async {
      final tool = _EchoTool();
      final adapter = _FakeAdapter(
        List.filled(40, _toolBlock('{"tool": "echo", "args": {"text": "x"}}')),
      );
      final h = _build(adapter: adapter, registry: ToolRegistry.of([tool]));

      final task = await h.engine.run('حلقهٔ بی‌پایان');

      await _flush();
      expect(task.round, AgentProtocolLimits.manual);
      expect(tool.calls, AgentProtocolLimits.manual);
      final last = h.events.whereType<AssistantSaid>().last;
      expect(last.text, contains('سقف'));

      expect(task.phase, AgentPhase.incomplete);
      expect(task.phase.isResumable, isTrue);
    });

    test('سقف دور، بندهای نقشه را کامل اعلام نمی‌کند', () async {
      final tool = _EchoTool();
      final adapter = _FakeAdapter([
        '```${AgentProtocol.planFence}\n["اول", "دوم", "سوم"]\n```\n'
            '${_toolBlock('{"tool": "echo", "args": {"text": "x"}}')}',
        ...List.filled(
          40,
          _toolBlock('{"tool": "echo", "args": {"text": "x"}}'),
        ),
      ]);
      final h = _build(adapter: adapter, registry: ToolRegistry.of([tool]));

      final task = await h.engine.run('حلقهٔ بی‌پایان با نقشه');

      await _flush();
      expect(task.plan, hasLength(3));
      expect(
        task.plan.every((step) => !step.done),
        isTrue,
        reason: 'بند نقشه فقط با ارجاع صریح مدل کامل می‌شود',
      );
    });

    test('بند نقشه فقط با ارجاع صریح همان شماره کامل می‌شود', () async {
      final tool = _EchoTool();
      final adapter = _FakeAdapter([
        '```${AgentProtocol.planFence}\n["اول", "دوم", "سوم"]\n```\n'
            '${_toolBlock('{"tool": "echo", "step": 2, "args": {"text": "x"}}')}',
        'تمام شد.',
      ]);
      final h = _build(adapter: adapter, registry: ToolRegistry.of([tool]));

      final task = await h.engine.run('کار با ارجاع بند');

      await _flush();
      expect(task.plan[0].done, isFalse);
      expect(task.plan[1].done, isTrue, reason: 'فقط بند ۲ ارجاع داده شد');
      expect(task.plan[2].done, isFalse);
      expect(task.phase, AgentPhase.incomplete);
    });

    test('لغو، ادامهٔ کار را متوقف می‌کند', () async {
      late final AgentEngine engine;
      final tool = _CallbackTool(onRun: () => engine.cancel());
      final adapter = _FakeAdapter(
        List.filled(10, _toolBlock('{"tool": "echo", "args": {"text": "x"}}')),
      );
      final h = _build(adapter: adapter, registry: ToolRegistry.of([tool]));
      engine = h.engine;

      final task = await h.engine.run('کار طولانی');

      expect(task.phase, AgentPhase.cancelled);
      expect(tool.calls, 1, reason: 'بعد از لغو نباید دور بعدی اجرا شود');
    });

    test('حالت غیرایجنتی هیچ ابزاری اجرا نمی‌کند', () async {
      final tool = _EchoTool();
      final adapter = _FakeAdapter([
        _toolBlock('{"tool": "echo", "args": {"text": "x"}}'),
      ]);
      final h = _build(adapter: adapter, registry: ToolRegistry.of([tool]));

      final task = await h.engine.run('سلام', agentMode: false);

      expect(tool.calls, 0);
      expect(task.steps, isEmpty);
      expect(adapter.sent.single, 'سلام');
    });

    test(
      'retry همان Task را از checkpoint ادامه می‌دهد و گام موفق را تکرار نمی‌کند',
      () async {
        final previous = AgentTask(goal: 'ساخت پروژه')
          ..phase = AgentPhase.failed
          ..steps.add(
            AgentStepRecord(
              call: ToolCall(name: 'echo', args: const {'text': 'انجام‌شده'}),
              toolLabel: 'اکو',
              risk: ToolRisk.read,
              status: StepStatus.done,
            ),
          )
          ..changedPaths.add('done.txt')
          ..note('قطع اتصال');
        final adapter = _FakeAdapter(['ادامه کامل شد.']);
        final h = _build(
          adapter: adapter,
          registry: ToolRegistry.of([_EchoTool()]),
        );

        final resumed = await h.engine.run(previous.goal, resumeTask: previous);

        expect(resumed, same(previous));
        expect(resumed.retryCount, 1);
        expect(resumed.phase, AgentPhase.done);
        expect(resumed.steps, hasLength(1));
        expect(adapter.sent.single, contains('عملیات موفق'));
        expect(adapter.sent.single, contains('✓ اکو'));
        expect(adapter.sent.single, contains('دوباره اجرا نکن'));
      },
    );
  });
}

abstract final class AgentProtocolLimits {
  static const manual = 12;
}
