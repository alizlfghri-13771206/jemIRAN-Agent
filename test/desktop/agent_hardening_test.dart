import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:jemiran/desktop/agent/agent_workspace.dart';
import 'package:jemiran/desktop/agent/core/agent_engine.dart';
import 'package:jemiran/desktop/agent/core/agent_event.dart';
import 'package:jemiran/desktop/agent/core/agent_protocol.dart';
import 'package:jemiran/desktop/agent/core/agent_storage.dart';
import 'package:jemiran/desktop/agent/core/agent_task.dart';
import 'package:jemiran/desktop/agent/core/checkpoint_store.dart';
import 'package:jemiran/desktop/agent/core/model_adapter.dart';
import 'package:jemiran/desktop/agent/core/task_store.dart';
import 'package:jemiran/desktop/agent/core/work_session_store.dart';
import 'package:jemiran/desktop/agent/policy/agent_policy.dart';
import 'package:jemiran/desktop/agent/tools/agent_tool.dart';
import 'package:jemiran/desktop/agent/tools/filesystem_tools.dart';
import 'package:jemiran/desktop/agent/tools/terminal_tool.dart';
import 'package:jemiran/desktop/agent/tools/tool_registry.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('انتهای خروجی ترمینال', () {
    test('وقتی خروجی از سقف بیشتر شد، آخرِ آن می‌ماند نه اولش', () {
      final buffer = TailBuffer(200);
      for (var i = 0; i < 500; i++) {
        buffer.add('line-$i');
      }
      final text = buffer.render();

      expect(text, contains('line-499'));
      expect(text, isNot(contains('line-0\n')));
      expect(text, startsWith('…('));
    });

    test('خروجی کوتاه‌تر از سقف دست‌نخورده و بدون هشدار برمی‌گردد', () {
      final buffer = TailBuffer(200)
        ..add('first')
        ..add('second');
      expect(buffer.render(), 'first\nsecond');
    });

    test('یک خط بسیار بلند کل سقف را نمی‌بلعد', () {
      final buffer = TailBuffer(50)
        ..add('x' * 5000)
        ..add('پیام پایانی');
      final text = buffer.render();
      expect(text, contains('پیام پایانی'));
      expect(text.length, lessThan(400));
    });
  });

  group('قرارداد ابزار', () {
    test('بلوک نتیجه هرگز به‌عنوان فراخوان ابزار خوانده نمی‌شود', () {
      final registry = ToolRegistry.of([_EchoTool()]);
      const reply =
          '```jemiran_tool_result\n{"tool": "echo", "result": {"ok": true}}\n```';

      expect(AgentProtocol.hasCalls(reply), isFalse);
      expect(AgentProtocol.parseCalls(reply, registry), isEmpty);
      expect(AgentProtocol.hasInvalidCalls(reply, registry), isFalse);
    });

    test('فراخوان درست هنوز خوانده می‌شود', () {
      final registry = ToolRegistry.of([_EchoTool()]);
      const reply =
          '```jemiran_tool\n{"tool": "echo", "args": {"text": "a"}}\n```';
      expect(AgentProtocol.parseCalls(reply, registry).single.name, 'echo');
    });

    test('یادآوری قرارداد در هر بستهٔ نتیجه تکرار می‌شود', () {
      final envelope = AgentProtocol.resultEnvelope([
        (
          call: ToolCall(name: 'echo', args: const {}),
          result: ToolResult.success(summary: 'ok'),
        ),
      ]);
      expect(envelope, contains(AgentProtocol.contractReminder));
    });
  });

  group('شناسهٔ یکتا', () {
    test('چند فراخوان در یک لحظه شناسهٔ یکسان نمی‌گیرند', () {
      final ids = <String>{
        for (var i = 0; i < 200; i++) ToolCall(name: 'echo', args: const {}).id,
      };
      expect(ids, hasLength(200));
    });

    test('سؤال‌های پشت‌سرهم هم شناسهٔ یکتا دارند', () {
      final ids = <String>{
        for (var i = 0; i < 200; i++) AgentQuestion(text: 'q').id,
      };
      expect(ids, hasLength(200));
    });
  });

  group('پیشرفت نقشه', () {
    test('بدون ارجاع صریح، هیچ بندی تیک نمی‌خورد', () async {
      final tool = _EchoTool();
      final adapter = _ScriptedAdapter([
        '```jemiran_plan\n["الف", "ب", "ج"]\n```\nشروع می‌کنم.'
            '${_toolBlock('{"tool": "echo", "args": {"text": "1"}}')}'
            '${_toolBlock('{"tool": "echo", "args": {"text": "2"}}')}',
        'تمام شد.',
      ]);
      final events = <AgentEvent>[];
      final engine = _engine(adapter, ToolRegistry.of([tool]), events);

      final task = await engine.run('کار سه‌مرحله‌ای');
      await Future<void>.delayed(Duration.zero);

      expect(tool.calls, 2);
      expect(events.whereType<PlanUpdated>(), hasLength(1));
      expect(task.plan.every((step) => !step.done), isTrue);
      expect(task.phase, AgentPhase.incomplete);
    });

    test('فقط بندی که مدل ارجاع داده کامل می‌شود', () async {
      final tool = _EchoTool();
      final adapter = _ScriptedAdapter([
        '```jemiran_plan\n["الف", "ب", "ج"]\n```\nشروع می‌کنم.'
            '${_toolBlock('{"tool": "echo", "step": 1, "args": {"text": "1"}}')}'
            '${_toolBlock('{"tool": "echo", "step": 3, "args": {"text": "2"}}')}',
        'تمام شد.',
      ]);
      final events = <AgentEvent>[];
      final engine = _engine(adapter, ToolRegistry.of([tool]), events);

      final task = await engine.run('کار سه‌مرحله‌ای');
      await Future<void>.delayed(Duration.zero);

      expect(task.plan[0].done, isTrue);
      expect(task.plan[1].done, isFalse, reason: 'بند ۲ ارجاع نگرفت');
      expect(task.plan[2].done, isTrue);
      expect(events.whereType<PlanUpdated>(), hasLength(2));
    });

    test('ارجاع به بند ناموجود هیچ بندی را کامل نمی‌کند', () async {
      final tool = _EchoTool();
      final adapter = _ScriptedAdapter([
        '```jemiran_plan\n["الف", "ب"]\n```\nشروع.'
            '${_toolBlock('{"tool": "echo", "step": 9, "args": {"text": "1"}}')}',
        'تمام شد.',
      ]);
      final events = <AgentEvent>[];
      final engine = _engine(adapter, ToolRegistry.of([tool]), events);

      final task = await engine.run('ارجاع خارج از محدوده');
      await Future<void>.delayed(Duration.zero);

      expect(task.plan.every((step) => !step.done), isTrue);
      expect(events.whereType<PlanUpdated>(), hasLength(1));
    });
  });

  group('فاز راستی‌آزمایی', () {
    test(
      'دورِ فقط‌خواندنی بعد از تغییر دیسک، verifying اعلام می‌شود',
      () async {
        final adapter = _ScriptedAdapter([
          _toolBlock('{"tool": "put", "args": {"text": "1"}}'),
          _toolBlock('{"tool": "echo", "args": {"text": "check"}}'),
          'تمام شد.',
        ]);
        final events = <AgentEvent>[];
        final engine = _engine(
          adapter,
          ToolRegistry.of([_EchoTool(), _WriteTool()]),
          events,
        );

        await engine.run('بنویس و بررسی کن');
        await Future<void>.delayed(Duration.zero);

        final phases = events
            .whereType<PhaseChanged>()
            .map((event) => event.phase)
            .toList();
        expect(phases, contains(AgentPhase.executing));
        expect(phases, contains(AgentPhase.verifying));
      },
    );

    test('دورِ فقط‌خواندنی بدون هیچ تغییری هنوز executing است', () async {
      final adapter = _ScriptedAdapter([
        _toolBlock('{"tool": "echo", "args": {"text": "1"}}'),
        'تمام شد.',
      ]);
      final events = <AgentEvent>[];
      final engine = _engine(adapter, ToolRegistry.of([_EchoTool()]), events);

      await engine.run('فقط بخوان');
      await Future<void>.delayed(Duration.zero);

      final phases = events
          .whereType<PhaseChanged>()
          .map((event) => event.phase)
          .toList();
      expect(phases, isNot(contains(AgentPhase.verifying)));
    });
  });

  group('ابزار فایل', () {
    late Directory workspace;
    late Directory storage;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      storage = await Directory.systemTemp.createTemp('jemiran_hard_store_');
      workspace = await Directory.systemTemp.createTemp('jemiran_hard_ws_');
      AgentStorage.setBaseRootForTesting(storage);
      AgentStorage.setAccountScope('hardening-test');
      await AgentWorkspace.clear();
      await AgentWorkspace.addDirectory(workspace.path);
    });

    tearDown(() async {
      await AgentWorkspace.clear();
      AgentStorage.setBaseRootForTesting(null);
      if (await storage.exists()) await storage.delete(recursive: true);
      if (await workspace.exists()) await workspace.delete(recursive: true);
    });

    test(
      'ویرایش فایلِ غیر UTF-8 خطای روشن می‌دهد و فایل را خراب نمی‌کند',
      () async {
        final file = File(p.join(workspace.path, 'legacy.txt'));
        final original = [0x73, 0x61, 0x6c, 0xff, 0xfe, 0x61, 0x6d];
        await file.writeAsBytes(original);

        final result = await const EditFileTool().run(
          ToolCall(
            name: 'edit_file',
            args: const {'path': 'legacy.txt', 'old': 'sal', 'new': 'SAL'},
          ),
          _context('task_hardening_1'),
        );

        expect(result.ok, isFalse);
        expect(result.error, contains('UTF-8'));
        expect(await file.readAsBytes(), original);
      },
    );

    test('افزودن به فایل غیر UTF-8 هم بی‌صدا خرابش نمی‌کند', () async {
      final file = File(p.join(workspace.path, 'legacy.log'));
      final original = [0x41, 0xc0, 0x80, 0x42];
      await file.writeAsBytes(original);

      final result = await const AppendFileTool().run(
        ToolCall(
          name: 'append_file',
          args: const {'path': 'legacy.log', 'content': 'x'},
        ),
        _context('task_hardening_2'),
      );

      expect(result.ok, isFalse);
      expect(await file.readAsBytes(), original);
    });

    test('ویرایش فایل سالم همچنان کار می‌کند', () async {
      final file = File(p.join(workspace.path, 'note.txt'));
      await file.writeAsString('سلام دنیا');

      final result = await const EditFileTool().run(
        ToolCall(
          name: 'edit_file',
          args: const {'path': 'note.txt', 'old': 'دنیا', 'new': 'جمیران'},
        ),
        _context('task_hardening_3'),
      );

      expect(result.ok, isTrue);
      expect(await file.readAsString(), 'سلام جمیران');
    });

    test(
      'جست‌وجو داخل node_modules و .git نمی‌رود ولی بقیه را پیدا می‌کند',
      () async {
        File(
          p.join(workspace.path, 'main.dart'),
        ).writeAsStringSync('void main');
        final noise = Directory(p.join(workspace.path, 'node_modules', 'pkg'))
          ..createSync(recursive: true);
        File(p.join(noise.path, 'index.dart')).writeAsStringSync('void main');
        final git = Directory(p.join(workspace.path, '.git'))..createSync();
        File(p.join(git.path, 'config.dart')).writeAsStringSync('void main');

        final result = await const FindFilesTool().run(
          ToolCall(name: 'find_files', args: const {'pattern': '*.dart'}),
          _context('task_hardening_4'),
        );

        final files = (result.data['files'] as List).cast<String>();
        expect(files, hasLength(1));
        expect(files.single, contains('main.dart'));
      },
    );

    test('انتقال به مقصد بیرون از منابع، پیش از پرسیدن رد می‌شود', () async {
      final outside = await Directory.systemTemp.createTemp('jemiran_out_');
      addTearDown(() async {
        if (await outside.exists()) await outside.delete(recursive: true);
      });
      File(p.join(workspace.path, 'a.txt')).writeAsStringSync('x');

      final deny = const MovePathTool().hardDeny(
        ToolCall(
          name: 'move_path',
          args: {'from': 'a.txt', 'to': p.join(outside.path, 'a.txt')},
        ),
      );

      expect(deny, isNotNull);
      expect(deny, contains('بیرون از منابع مجاز'));
    });
  });

  group('نگهداری فضای دیسک', () {
    late Directory storage;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      storage = await Directory.systemTemp.createTemp('jemiran_sweep_');
      AgentStorage.setBaseRootForTesting(storage);
      AgentStorage.setAccountScope('sweep-test');
    });

    tearDown(() async {
      AgentStorage.setBaseRootForTesting(null);
      if (await storage.exists()) await storage.delete(recursive: true);
    });

    test('snapshot بی‌صاحب پاک می‌شود و snapshot زنده می‌ماند', () async {
      final root = AgentStorage.subdir('checkpoints')!;
      final orphan = Directory(p.join(root.path, 'task_orphan'))
        ..createSync(recursive: true);
      final live = Directory(p.join(root.path, 'task_live'))
        ..createSync(recursive: true);

      await AgentCheckpointStore.sweep(
        knownTaskIds: {'task_live'},
        resumableTaskIds: {'task_live'},
      );

      expect(orphan.existsSync(), isFalse);
      expect(live.existsSync(), isTrue);
    });
  });

  group('مهاجرت Work', () {
    late Directory storage;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      storage = await Directory.systemTemp.createTemp('jemiran_migrate_');
      AgentStorage.setBaseRootForTesting(storage);
      AgentStorage.setAccountScope('migrate-test');
      await AgentTaskStore.instance.load();
      await WorkSessionStore.instance.load();
    });

    tearDown(() async {
      await WorkSessionStore.instance.flush();
      await AgentTaskStore.instance.flush();
      AgentStorage.setBaseRootForTesting(null);
      if (await storage.exists()) await storage.delete(recursive: true);
    });

    test('Task تازهٔ یک Work بعد از restart، Work تکراری نمی‌سازد', () async {
      final work = await WorkSessionStore.instance.create();
      work.transportSessionId = 77;
      await WorkSessionStore.instance.save(work, immediate: true);

      final task = AgentTask(goal: 'یک کار واقعی')
        ..sessionId = 77
        ..phase = AgentPhase.done;
      AgentTaskStore.instance.scheduleSave(task);
      await AgentTaskStore.instance.flush();

      await AgentTaskStore.instance.load();
      await WorkSessionStore.instance.load();
      final afterFirstRestart = WorkSessionStore.instance.works.length;

      await AgentTaskStore.instance.load();
      await WorkSessionStore.instance.load();

      expect(WorkSessionStore.instance.works, hasLength(afterFirstRestart));
      expect(afterFirstRestart, 1);
    });
  });
}

String _toolBlock(String json) => '```jemiran_tool\n$json\n```';

ToolContext _context(String taskId) => ToolContext(
  taskId: taskId,
  isCancelled: () => false,
  report: (_) {},
  ask: (_) async => null,
);

AgentEngine _engine(
  ModelAdapter adapter,
  ToolRegistry registry,
  List<AgentEvent> events,
) {
  final engine = AgentEngine(
    model: adapter,
    registry: registry,
    readPolicy: () => const AgentPolicyState(enabled: true),
    onGrant: (_, _) {},
    requestPermission: (_, _) async => PermissionDecision.allowOnce,
    askQuestion: (_) async => null,
  );
  engine.events.listen(events.add);
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
  String get signature => 'put {"text": "..."}';

  @override
  ToolPreview preview(ToolCall call) => const ToolPreview(title: 'نوشتن');

  @override
  Future<ToolResult> run(ToolCall call, ToolContext context) async =>
      ToolResult.success(
        summary: 'نوشته شد',
        changedPaths: const ['virtual/output.txt'],
      );
}

class _EchoTool extends AgentTool {
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
    return ToolResult.success(summary: 'اکو شد');
  }
}
