import 'package:flutter_test/flutter_test.dart';
import 'package:jemiran/desktop/agent/core/agent_engine.dart';
import 'package:jemiran/desktop/agent/core/agent_event.dart';
import 'package:jemiran/desktop/agent/core/agent_protocol.dart';
import 'package:jemiran/desktop/agent/core/agent_task.dart';
import 'package:jemiran/desktop/agent/core/model_adapter.dart';
import 'package:jemiran/desktop/agent/policy/agent_policy.dart';
import 'package:jemiran/desktop/agent/tools/agent_tool.dart';
import 'package:jemiran/desktop/agent/tools/tool_registry.dart';

class _BulkTool extends AgentTool {
  _BulkTool({this.payloadChars = 0});

  final int payloadChars;
  int calls = 0;

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
  Future<ToolResult> run(ToolCall call, ToolContext context) async {
    calls++;
    return ToolResult.success(
      summary: 'اکو شد',
      data: {'blob': 'x' * payloadChars},
    );
  }
}

class _FatSchemaTool extends AgentTool {
  _FatSchemaTool(this.index);

  final int index;

  @override
  String get name => 'fat_$index';
  @override
  String get label => 'ابزار بزرگ';
  @override
  ToolRisk get risk => ToolRisk.read;
  @override
  String get permission => 'test.fat';
  @override
  String get signature => 'fat_$index {}';

  @override
  Map<String, dynamic> get parameterSchema => {
    for (var i = 0; i < 30; i++)
      'field_$i': {'type': 'string', 'description': 'x' * 90},
  };

  @override
  ToolPreview preview(ToolCall call) => const ToolPreview(title: 'بزرگ');

  @override
  Future<ToolResult> run(ToolCall call, ToolContext context) async =>
      ToolResult.success(summary: 'ok', data: {'blob': 'y' * 9000});
}

class _SessionCountingAdapter extends ModelAdapter {
  _SessionCountingAdapter(this.replies);

  final List<String> replies;
  final sent = <String>[];
  final requests = <ModelRequest>[];
  int freshSessions = 0;
  var _index = 0;

  @override
  String get modelKey => 'fake';

  @override
  Future<void> startFreshSession() async => freshSessions++;

  @override
  Future<ModelTurn> send(ModelRequest request) async {
    requests.add(request);
    sent.add(request.text);
    final reply = _index < replies.length ? replies[_index++] : 'تمام شد.';
    return ModelTurn(text: reply, sessionId: 7);
  }
}

class _StructuredSessionCountingAdapter extends ModelAdapter {
  _StructuredSessionCountingAdapter(this.replies);

  final List<ModelTurn> replies;
  final requests = <ModelRequest>[];
  int freshSessions = 0;
  var _index = 0;

  @override
  String get modelKey => 'anthropic/claude-opus-5';

  @override
  Future<void> startFreshSession() async => freshSessions++;

  @override
  Future<ModelTurn> send(ModelRequest request) async {
    requests.add(request);
    if (_index >= replies.length) throw StateError('پاسخ ساختاری کافی نیست');
    return replies[_index++];
  }
}

String _toolBlock(String json) => '```jemiran_tool\n$json\n```';

({AgentEngine engine, List<AgentEvent> events}) _build(
  ModelAdapter adapter,
  ToolRegistry registry, {
  AgentMode mode = AgentMode.autonomous,
}) {
  final events = <AgentEvent>[];
  final engine = AgentEngine(
    model: adapter,
    registry: registry,
    readPolicy: () => AgentPolicyState(enabled: true, mode: mode),
    onGrant: (_, _) {},
    requestPermission: (_, _) async => PermissionDecision.allowOnce,
    askQuestion: (_) async => null,
  );
  engine.events.listen(events.add);
  return (engine: engine, events: events);
}

Future<void> _flush() => Future<void>.delayed(Duration.zero);

void main() {
  group('فشرده‌سازی زمینه', () {
    test('گفت‌وگوی طولانی نشست تازه با خلاصه می‌سازد', () async {
      final tool = _BulkTool(payloadChars: 12000);
      final adapter = _SessionCountingAdapter([
        '```jemiran_plan\n["گام یک","گام دو"]\n```'
            '${_toolBlock('{"tool":"read_file","args":{"text":"a"}}')}',
        _toolBlock('{"tool":"read_file","args":{"text":"b"}}'),
        _toolBlock('{"tool":"read_file","step":1,"args":{"text":"c"}}'),
        _toolBlock('{"tool":"read_file","step":2,"args":{"text":"d"}}'),
        'کار تمام شد.',
      ]);
      final h = _build(adapter, ToolRegistry.of([tool]));

      final task = await h.engine.run('یک کار طولانی');
      await _flush();

      expect(
        adapter.freshSessions,
        greaterThan(0),
        reason: 'باید حداقل یک بار نشست از نو ساخته شود',
      );

      final compacted = adapter.sent.firstWhere(
        (text) => text.contains('خلاصهٔ فشرده‌شدهٔ کار'),
        orElse: () => '',
      );
      expect(compacted, isNotEmpty, reason: 'خلاصه باید فرستاده شده باشد');
      expect(compacted, contains('حالت ایجنت جمیران فعال است'));
      expect(compacted, contains('یک کار طولانی'));
      expect(compacted, contains('read_file'), reason: 'فهرست ابزارها');

      expect(task.phase, AgentPhase.done);
    });

    test('گفت‌وگوی کوتاه اصلاً فشرده نمی‌شود', () async {
      final tool = _BulkTool();
      final adapter = _SessionCountingAdapter([
        _toolBlock('{"tool":"read_file","args":{"text":"a"}}'),
        'تمام.',
      ]);
      final h = _build(adapter, ToolRegistry.of([tool]));

      await h.engine.run('کار کوتاه');
      await _flush();

      expect(adapter.freshSessions, 0);
      expect(
        adapter.sent.any((t) => t.contains('خلاصهٔ فشرده‌شدهٔ کار')),
        isFalse,
      );
    });

    test(
      'زنجیرهٔ native هنگام داشتن tool result هم checkpoint می‌شود',
      () async {
        final tool = _BulkTool(payloadChars: 14000);
        ToolCall call(String id) =>
            ToolCall(id: id, name: 'read_file', args: {'text': id});
        final adapter = _StructuredSessionCountingAdapter([
          ModelTurn(text: '', sessionId: 7, toolCalls: [call('call_a')]),
          ModelTurn(text: '', sessionId: 7, toolCalls: [call('call_b')]),
          ModelTurn(text: '', sessionId: 8, toolCalls: [call('call_c')]),
          const ModelTurn(text: 'تمام شد.', sessionId: 8),
        ]);
        final h = _build(adapter, ToolRegistry.of([tool]));

        final task = await h.engine.run('کار native طولانی');
        await _flush();

        expect(adapter.freshSessions, greaterThan(0));
        final compacted = adapter.requests.firstWhere(
          (request) => request.contextCheckpoint != null,
        );
        expect(compacted.toolResults, isNotEmpty);
        expect(compacted.contextCheckpoint, contains('خلاصهٔ فشرده‌شدهٔ کار'));
        expect(compacted.contextCheckpoint, contains('کار native طولانی'));
        expect(
          adapter.requests.map((request) => request.cacheSessionId).toSet(),
          {task.id},
          reason: 'compaction نباید sticky cache همان Task را عوض کند',
        );
        expect(task.phase, AgentPhase.done);
      },
    );

    test('آستانه هزینهٔ ثابتِ تعریف ابزارها را کسر می‌کند', () async {
      Future<int> freshSessionsFor(ToolRegistry registry) async {
        final adapter = _SessionCountingAdapter([
          _toolBlock('{"tool":"${registry.available.first.name}","args":{}}'),
          _toolBlock('{"tool":"${registry.available.first.name}","args":{}}'),
          'تمام.',
        ]);
        final h = _build(adapter, registry);
        await h.engine.run('کار با بار متوسط');
        await _flush();
        return adapter.freshSessions;
      }

      final lean = await freshSessionsFor(
        ToolRegistry.of([_BulkTool(payloadChars: 9000)]),
      );
      final heavy = await freshSessionsFor(
        ToolRegistry.of([for (var i = 0; i < 12; i++) _FatSchemaTool(i)]),
      );

      expect(lean, 0, reason: 'با رجیستری سبک هنوز جا هست');
      expect(
        heavy,
        greaterThan(0),
        reason: 'تعریف ابزارها هم بخشی از context است و باید شمرده شود',
      );
    });

    test('برآورد توکن با مقیاس سرور می‌خواند', () {
      expect(AgentProtocol.estimatedTokens(''), 0);
      expect(AgentProtocol.estimatedTokens('a' * 400), 125);
      expect(AgentProtocol.estimatedTokens('ک' * 400), 250);
    });

    test('خلاصه فقط واقعیت ثبت‌شده را می‌نویسد', () {
      final task = AgentTask(goal: 'ساخت پروژه')
        ..plan.addAll([
          PlanStep('گام یک', id: 1, done: true),
          PlanStep('گام دو', id: 2),
        ])
        ..changedPaths.add('lib/main.dart')
        ..note('یک خطای نمونه');

      final summary = AgentProtocol.compactionSummary(task);

      expect(summary, contains('ساخت پروژه'));
      expect(summary, contains('✓ 1. گام یک'));
      expect(summary, contains('□ 2. گام دو'));
      expect(summary, contains('lib/main.dart'));
      expect(summary, contains('یک خطای نمونه'));
      expect(summary, contains('دوباره اجرا نکن'));
    });
  });

  group('دروازهٔ کار ناتمام', () {
    test('جواب نهایی زودهنگام یک بار برگردانده می‌شود', () async {
      final tool = _BulkTool();
      final adapter = _SessionCountingAdapter([
        '```jemiran_plan\n["گام یک","گام دو"]\n```'
            '${_toolBlock('{"tool":"read_file","step":1,"args":{"text":"a"}}')}',
        'خب، کار تمام شد.',
        _toolBlock('{"tool":"read_file","step":2,"args":{"text":"b"}}'),
        'حالا واقعاً تمام شد.',
      ]);
      final h = _build(adapter, ToolRegistry.of([tool]));

      final task = await h.engine.run('کار دومرحله‌ای');
      await _flush();

      final nudge = adapter.sent.firstWhere(
        (text) => text.contains('هنوز بند ناتمام هست'),
        orElse: () => '',
      );
      expect(nudge, isNotEmpty);
      expect(nudge, contains('2. گام دو'));

      expect(task.plan.every((step) => step.done), isTrue);
      expect(task.phase, AgentPhase.done);
      expect(tool.calls, 2);
    });

    test('اگر مدل باز هم اصرار کند، حرفش پذیرفته می‌شود', () async {
      final tool = _BulkTool();
      final adapter = _SessionCountingAdapter([
        '```jemiran_plan\n["گام یک","گام دو"]\n```'
            '${_toolBlock('{"tool":"read_file","step":1,"args":{"text":"a"}}')}',
        'تمام شد.',
        'گفتم که تمام شد.',
      ]);
      final h = _build(adapter, ToolRegistry.of([tool]));

      final task = await h.engine.run('کار دومرحله‌ای');
      await _flush();

      final nudges = adapter.sent
          .where((t) => t.contains('هنوز بند ناتمام هست'))
          .length;
      expect(nudges, 1);
      expect(task.phase, AgentPhase.incomplete);
      expect(task.plan[1].done, isFalse);
      expect(
        task.errors.any((e) => e.contains('بند نقشه تیک نخورده')),
        isTrue,
        reason: 'علتِ ناتمام ماندن باید در journal ثبت شود',
      );
    });

    test('نقشهٔ کامل هیچ یادآوری نمی‌سازد', () async {
      final tool = _BulkTool();
      final adapter = _SessionCountingAdapter([
        '```jemiran_plan\n["تنها گام"]\n```'
            '${_toolBlock('{"tool":"read_file","step":1,"args":{"text":"a"}}')}',
        'تمام شد.',
      ]);
      final h = _build(adapter, ToolRegistry.of([tool]));

      await h.engine.run('کار تک‌مرحله‌ای');
      await _flush();

      expect(
        adapter.sent.any((t) => t.contains('هنوز بند ناتمام هست')),
        isFalse,
      );
    });

    test('بدون نقشه، دروازه اصلاً فعال نمی‌شود', () async {
      final tool = _BulkTool();
      final adapter = _SessionCountingAdapter(['جواب مستقیم بدون نقشه.']);
      final h = _build(adapter, ToolRegistry.of([tool]));

      final task = await h.engine.run('یک سؤال ساده');
      await _flush();

      expect(adapter.sent, hasLength(1));
      expect(task.phase, AgentPhase.done);
    });
  });
}
