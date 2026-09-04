import 'package:flutter_test/flutter_test.dart';
import 'package:jemiran/desktop/agent/core/agent_engine.dart';
import 'package:jemiran/desktop/agent/core/agent_event.dart';
import 'package:jemiran/desktop/agent/core/agent_protocol.dart';
import 'package:jemiran/desktop/agent/core/agent_task.dart';
import 'package:jemiran/desktop/agent/core/model_adapter.dart';
import 'package:jemiran/desktop/agent/policy/agent_policy.dart';
import 'package:jemiran/desktop/agent/tools/agent_tool.dart';
import 'package:jemiran/desktop/agent/tools/tool_registry.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('لغو وسط دستهٔ ابزار', () {
    test('گامِ منتظرِ اجازه «لغو» می‌شود، نه «منتظر» تا ابد', () async {
      late AgentEngine engine;
      engine = AgentEngine(
        model: _ScriptedAdapter([_block('{"tool": "put", "args": {}}')]),
        registry: ToolRegistry.of([_WriteTool()]),
        readPolicy: () => const AgentPolicyState(enabled: true),
        onGrant: (_, _) {},
        requestPermission: (_, _) async {
          engine.cancel();
          return PermissionDecision.deny;
        },
        askQuestion: (_) async => null,
      );

      final task = await engine.run('یک فایل بنویس');

      expect(task.phase, AgentPhase.cancelled);
      expect(
        task.steps.every((step) => step.status.isTerminal),
        isTrue,
        reason: 'هیچ گامی نباید در وضعیت غیرپایانی جا بماند',
      );
      expect(task.steps.single.status, StepStatus.cancelled);
      await engine.dispose();
    });
  });

  group('نقل‌قول پیامِ پاسخ‌داده‌شده', () {
    test('متن پیام قبلی به مدل می‌رسد', () async {
      final adapter = _CapturingAdapter();
      final engine = _engine(adapter);

      await engine.run(
        'این را اصلاح کن',
        replyContext: 'خطای build در main.dart',
      );

      expect(adapter.firstText, contains('خطای build در main.dart'));
      expect(adapter.firstText, contains('پاسخ داده است'));
      await engine.dispose();
    });

    test('بدون پاسخ‌به، هیچ بلوک اضافه‌ای به پرامپت نمی‌چسبد', () async {
      final adapter = _CapturingAdapter();
      final engine = _engine(adapter);

      await engine.run('کار ساده');

      expect(adapter.firstText, isNot(contains('پاسخ داده است')));
      await engine.dispose();
    });

    test('نقل‌قول خیلی بلند بریده می‌شود', () {
      final quote = AgentProtocol.replyQuote('ا' * 5000);
      expect(quote.length, lessThan(1000));
      expect(quote, contains('…'));
    });

    test('نقل‌قول خالی یعنی هیچ بلوکی ساخته نشود', () {
      expect(AgentProtocol.replyQuote(null), isEmpty);
      expect(AgentProtocol.replyQuote('   '), isEmpty);
    });
  });

  group('عنوان گام بعد از بازخوانی از journal', () {
    test('مسیر عملیات از دست نمی‌رود', () {
      final task = AgentTask(goal: 'کار');
      task.steps.add(
        AgentStepRecord(
          call: ToolCall(
            name: 'write_file',
            args: const {'path': 'lib/main.dart'},
          ),
          toolLabel: 'نوشتن فایل',
          risk: ToolRisk.write,
          status: StepStatus.done,
        ),
      );
      final before = task.steps.single.headline;
      expect(before, contains('lib/main.dart'));

      final restored = AgentTask.fromJson(task.toJson());

      expect(restored.steps.single.headline, before);
    });

    test('عنوان دوباره به خودش نمی‌چسبد', () {
      final task = AgentTask(goal: 'کار');
      task.steps.add(
        AgentStepRecord(
          call: ToolCall(name: 'read_file', args: const {'path': 'a.txt'}),
          toolLabel: 'خواندن فایل',
          risk: ToolRisk.read,
          status: StepStatus.done,
        ),
      );
      final once = AgentTask.fromJson(task.toJson());
      final twice = AgentTask.fromJson(once.toJson());
      expect(twice.steps.single.headline, 'خواندن فایل · a.txt');
    });
  });

  group('پاسخ بریده‌شده', () {
    test('سقف طول خروجی، `done` نیست', () async {
      final events = <AgentEvent>[];
      final adapter = _TruncatedAdapter('این جمله وسطش برید و');
      final task = await _engine(adapter, events).run('یک کار');
      await Future<void>.delayed(Duration.zero);

      expect(task.phase, AgentPhase.incomplete);
      expect(task.phase.isResumable, isTrue);
      expect(task.finalAnswer, 'این جمله وسطش برید و');
      expect(
        task.errors.any((e) => e.contains('سقف طول خروجی')),
        isTrue,
        reason: 'دلیلش باید در journal بماند',
      );
      expect(
        events.whereType<RecoverableError>().any(
          (e) => e.message.contains('سقف طول خروجی'),
        ),
        isTrue,
        reason: 'کاربر هم باید ببیند',
      );
      expect(adapter.calls, 1, reason: 'نباید دور اضافهٔ پول‌دار بزند');
    });

    test('پایان طبیعی همچنان `done` است', () async {
      final task = await _engine(_ScriptedAdapter(['تمام شد.'])).run('کار');
      expect(task.phase, AgentPhase.done);
    });

    test('بلوک کنترلیِ نصفه‌مانده به کاربر نشان داده نمی‌شود', () async {
      final task = await _engine(
        _TruncatedAdapter('دارم فایل را می‌نویسم:\n```jemiran_tool\n{"tool"'),
      ).run('کار');
      expect(task.phase, AgentPhase.incomplete);
      expect(task.finalAnswer, 'دارم فایل را می‌نویسم:');
    });
  });
}

String _block(String json) => '```jemiran_tool\n$json\n```';

AgentEngine _engine(ModelAdapter adapter, [List<AgentEvent>? events]) {
  final engine = AgentEngine(
    model: adapter,
    registry: ToolRegistry.of([_WriteTool()]),
    readPolicy: () => const AgentPolicyState(enabled: true),
    onGrant: (_, _) {},
    requestPermission: (_, _) async => PermissionDecision.allowOnce,
    askQuestion: (_) async => null,
  );
  if (events != null) engine.events.listen(events.add);
  return engine;
}

class _ScriptedAdapter extends ModelAdapter {
  _ScriptedAdapter(this.replies);

  final List<String> replies;
  int _index = 0;

  @override
  String get modelKey => 'scripted';

  @override
  Future<ModelTurn> send(ModelRequest request) async =>
      ModelTurn(text: _index < replies.length ? replies[_index++] : 'تمام شد.');
}

class _TruncatedAdapter extends ModelAdapter {
  _TruncatedAdapter(this.text);

  final String text;
  int calls = 0;

  @override
  String get modelKey => 'truncated';

  @override
  Future<ModelTurn> send(ModelRequest request) async {
    calls++;
    return ModelTurn(text: text, finishReason: 'length');
  }
}

class _CapturingAdapter extends ModelAdapter {
  String? firstText;

  @override
  String get modelKey => 'capturing';

  @override
  Future<ModelTurn> send(ModelRequest request) async {
    firstText ??= request.text;
    return const ModelTurn(text: 'تمام شد.');
  }
}

class _WriteTool extends AgentTool {
  @override
  String get name => 'put';
  @override
  String get label => 'نوشتن';
  @override
  ToolRisk get risk => ToolRisk.write;
  @override
  String get permission => 'test.put';
  @override
  String get signature => 'put {}';

  @override
  ToolPreview preview(ToolCall call) => const ToolPreview(title: 'نوشتن');

  @override
  Future<ToolResult> run(ToolCall call, ToolContext context) async =>
      ToolResult.success(summary: 'نوشته شد');
}
