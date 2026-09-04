import 'package:flutter_test/flutter_test.dart';
import 'package:jemiran/desktop/agent/core/agent_engine.dart';
import 'package:jemiran/desktop/agent/core/agent_event.dart';
import 'package:jemiran/desktop/agent/core/agent_task.dart';
import 'package:jemiran/desktop/agent/core/model_adapter.dart';
import 'package:jemiran/desktop/agent/core/mutation_verifier.dart';
import 'package:jemiran/desktop/agent/policy/agent_policy.dart';
import 'package:jemiran/desktop/agent/tools/agent_tool.dart';
import 'package:jemiran/desktop/agent/tools/tool_registry.dart';

ToolCall _call(String name, String path) =>
    ToolCall(id: 'c', name: name, args: {'path': path});

class _FailingWriteTool extends AgentTool {
  const _FailingWriteTool();

  @override
  String get name => 'write_file';
  @override
  String get label => 'نوشتن فایل';
  @override
  ToolRisk get risk => ToolRisk.write;
  @override
  String get permission => 'fs.write';
  @override
  String get signature => 'write_file {"path": "..."}';

  @override
  ToolPreview preview(ToolCall call) => const ToolPreview(title: 'نوشتن');

  @override
  Future<ToolResult> run(ToolCall call, ToolContext context) async =>
      ToolResult.failure('دسترسی به مسیر رد شد');
}

class _ScriptedAdapter extends ModelAdapter {
  _ScriptedAdapter(this.replies);
  final List<String> replies;
  var _i = 0;

  @override
  String get modelKey => 'fake';

  @override
  Future<ModelTurn> send(ModelRequest request) async => ModelTurn(
    text: _i < replies.length ? replies[_i++] : 'تمام.',
    sessionId: 1,
  );
}

void _engineTests() {
  test(
    'وقتی مدل موفقیت ادعا می‌کند ولی نوشتن شکست خورده، کاربر پانویس می‌بیند',
    () async {
      final adapter = _ScriptedAdapter([
        '```jemiran_tool\n{"tool":"write_file","args":{"path":"lib/a.dart"}}\n```',
        'فایل lib/a.dart با موفقیت اصلاح شد.',
      ]);
      final events = <AgentEvent>[];
      final engine = AgentEngine(
        model: adapter,
        registry: ToolRegistry.of(const [_FailingWriteTool()]),
        readPolicy: () =>
            AgentPolicyState(enabled: true, mode: AgentMode.autonomous),
        onGrant: (_, _) {},
        requestPermission: (_, _) async => PermissionDecision.allowOnce,
        askQuestion: (_) async => null,
      );
      engine.events.listen(events.add);

      final task = await engine.run('فایل را عوض کن');
      await Future<void>.delayed(Duration.zero);

      final said = events.whereType<AssistantSaid>().last.text;
      expect(said, contains('lib/a.dart'));
      expect(said, contains('تغییر نکرد'));
      expect(task.phase, AgentPhase.done);
    },
  );

  test('نوشتن موفق هیچ پانویسی نمی‌سازد', () async {
    final adapter = _ScriptedAdapter(['کاری لازم نبود.']);
    final events = <AgentEvent>[];
    final engine = AgentEngine(
      model: adapter,
      registry: ToolRegistry.of(const []),
      readPolicy: () =>
          AgentPolicyState(enabled: true, mode: AgentMode.autonomous),
      onGrant: (_, _) {},
      requestPermission: (_, _) async => PermissionDecision.allowOnce,
      askQuestion: (_) async => null,
    );
    engine.events.listen(events.add);

    await engine.run('یک کار');
    await Future<void>.delayed(Duration.zero);
    expect(
      events.whereType<AssistantSaid>().last.text,
      isNot(contains('تغییر نکرد')),
    );
  });
}

void main() {
  _engineTests();
  group('راستی‌آزمای تغییر فایل', () {
    test('نوشتن ناموفق ثبت می‌شود و در پانویس می‌آید', () {
      final verifier = MutationVerifier();
      verifier.record(
        _call('write_file', 'lib/a.dart'),
        ToolResult.failure('دسترسی رد شد'),
      );

      expect(verifier.hasFailures, isTrue);
      final footer = verifier.footer()!;
      expect(footer, contains('lib/a.dart'));
      expect(footer, contains('دسترسی رد شد'));
      expect(footer, contains('تغییر نکرد'));
    });

    test('موفقیتِ بعدی روی همان مسیر، رکورد را پاک می‌کند', () {
      final verifier = MutationVerifier();
      verifier.record(
        _call('write_file', 'lib/a.dart'),
        ToolResult.failure('مسیر وجود ندارد'),
      );
      verifier.record(
        _call('write_file', 'lib/a.dart'),
        ToolResult.success(summary: 'نوشته شد'),
      );

      expect(verifier.hasFailures, isFalse);
      expect(verifier.footer(), isNull);
    });

    test('اولین خطا نگه داشته می‌شود، نه آخرین', () {
      final verifier = MutationVerifier();
      verifier.record(
        _call('write_file', 'lib/a.dart'),
        ToolResult.failure('اجازهٔ نوشتن ندارید'),
      );
      verifier.record(
        _call('write_file', 'lib/a.dart'),
        ToolResult.failure('خطای بعدی و بی‌ربط'),
      );

      final footer = verifier.footer()!;
      expect(footer, contains('اجازهٔ نوشتن ندارید'));
      expect(footer, isNot(contains('خطای بعدی')));
    });

    test('ابزار فقط‌خواندنی اصلاً ردیابی نمی‌شود', () {
      final verifier = MutationVerifier();
      verifier.record(
        _call('read_file', 'lib/a.dart'),
        ToolResult.failure('فایل نیست'),
      );
      expect(verifier.hasFailures, isFalse);
    });

    test('همهٔ ابزارهای تغییردهنده پوشش دارند', () {
      final verifier = MutationVerifier();
      for (final name in const [
        'write_file',
        'append_file',
        'edit_file',
        'move_path',
        'delete_path',
      ]) {
        verifier.record(_call(name, 'p/$name'), ToolResult.failure('خطا'));
      }
      expect(verifier.footer(), contains('p/edit_file'));
      expect(verifier.footer(), contains('p/delete_path'));
    });

    test('پانویس سقف دارد تا خودش زمینه را نبلعد', () {
      final verifier = MutationVerifier();
      for (var i = 0; i < 50; i++) {
        verifier.record(
          _call('write_file', 'lib/file_$i.dart'),
          ToolResult.failure('خطای طولانی ${'x' * 500}'),
        );
      }
      expect(verifier.footer()!.length, lessThan(2000));
    });

    test('پاک شدن بین نوبت‌ها', () {
      final verifier = MutationVerifier();
      verifier.record(_call('write_file', 'a'), ToolResult.failure('خطا'));
      verifier.reset();
      expect(verifier.hasFailures, isFalse);
    });
  });
}
