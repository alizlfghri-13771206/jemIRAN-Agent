import 'package:flutter_test/flutter_test.dart';
import 'package:jemiran/desktop/agent/core/agent_protocol.dart';
import 'package:jemiran/desktop/agent/core/agent_task.dart';
import 'package:jemiran/desktop/agent/tools/agent_tool.dart';
import 'package:jemiran/desktop/agent/tools/tool_registry.dart';

class _EchoTool extends AgentTool {
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
  Future<ToolResult> run(ToolCall call, ToolContext context) async =>
      ToolResult.success(summary: 'اکو شد');
}

void main() {
  final registry = ToolRegistry.of([_EchoTool()]);

  String block(String json) => '```${AgentProtocol.fence}\n$json\n```';

  group('ارجاع بند نقشه', () {
    test('شمارهٔ بند از سطح بالای فراخوان خوانده می‌شود', () {
      final calls = AgentProtocol.parseCalls(
        block('{"tool": "echo", "step": 3, "args": {"text": "x"}}'),
        registry,
      );
      expect(calls.single.stepId, 3);
      expect(calls.single.args.containsKey('step'), isFalse);
    });

    test('شمارهٔ بند از داخل args هم پذیرفته می‌شود', () {
      final calls = AgentProtocol.parseCalls(
        block('{"tool": "echo", "args": {"text": "x", "step_id": 2}}'),
        registry,
      );
      expect(calls.single.stepId, 2);
    });

    test('نبودِ ارجاع یعنی هیچ بندی ادعا نمی‌شود', () {
      final calls = AgentProtocol.parseCalls(
        block('{"tool": "echo", "args": {"text": "x"}}'),
        registry,
      );
      expect(calls.single.stepId, isNull);
    });

    test('ارجاع نامعتبر مثل صفر یا متن، نادیده گرفته می‌شود', () {
      for (final raw in ['0', '-1', '"abc"', 'null']) {
        final calls = AgentProtocol.parseCalls(
          block('{"tool": "echo", "step": $raw, "args": {"text": "x"}}'),
          registry,
        );
        expect(calls.single.stepId, isNull, reason: 'step=$raw');
      }
    });
  });

  group('نقشه', () {
    test('بندها شمارهٔ پایدار ۱-پایه می‌گیرند', () {
      final plan = AgentProtocol.parsePlan(
        '```${AgentProtocol.planFence}\n["اول", "دوم", "سوم"]\n```',
      );
      expect(plan.map((s) => s.id), [1, 2, 3]);
      expect(plan.every((s) => !s.done), isTrue);
    });

    test('journal قدیمی بدون id، شماره را از ترتیب می‌گیرد', () {
      final task = AgentTask.fromJson({
        'id': 't1',
        'goal': 'کار',
        'plan': [
          {'text': 'اول', 'done': true},
          {'text': 'دوم', 'done': false},
        ],
      });
      expect(task.plan.map((s) => s.id), [1, 2]);
      expect(task.plan.first.done, isTrue);
    });
  });

  group('فاز پایانی', () {
    test('incomplete پایانی و قابل ادامه است، ولی done قابل ادامه نیست', () {
      expect(AgentPhase.incomplete.isTerminal, isTrue);
      expect(AgentPhase.incomplete.isResumable, isTrue);
      expect(AgentPhase.done.isResumable, isFalse);
    });

    test('هر فاز پایانی برچسب فارسی مخصوص خودش دارد', () {
      final labels = <String>{
        for (final phase in AgentPhase.values)
          if (phase.isTerminal) phase.label,
      };
      expect(
        labels.length,
        5,
        reason: 'برچسب تکراری یعنی کاربر تفاوت را نمی‌بیند',
      );
    });
  });

  _liveStreamTests();
}

void _liveStreamTests() {
  group('پاک‌سازی متن زنده', () {
    test('بلوک کامل ابزار دیده نمی‌شود', () {
      final out = AgentProtocol.stripLiveControlBlocks(
        'اول فایل را می‌خوانم.\n'
        '```${AgentProtocol.fence}\n{"tool":"read_file","args":{"path":"a"}}\n```\n'
        'بعد ادامه می‌دهم.',
      );
      expect(out, contains('اول فایل را می‌خوانم'));
      expect(out, contains('بعد ادامه می‌دهم'));
      expect(out, isNot(contains('read_file')));
      expect(out, isNot(contains('```')));
    });

    test('بلوکِ نیمه‌رسیده هم دیده نمی‌شود', () {
      final out = AgentProtocol.stripLiveControlBlocks(
        'حالا فصل سه را اضافه می‌کنم:\n'
        '```${AgentProtocol.fence}\n{"tool":"append_file","args":{"path":"x.md","content":"\n## Chapter',
      );
      expect(out, 'حالا فصل سه را اضافه می‌کنم:');
      expect(out, isNot(contains('append_file')));
    });

    test('متن قبل از بلوک هرگز عقب نمی‌رود', () {
      const head = 'یک جملهٔ مقدماتی.';
      var previous = '';
      for (final tail in [
        '',
        '\n```${AgentProtocol.fence}',
        '\n```${AgentProtocol.fence}\n{"tool":"echo"',
        '\n```${AgentProtocol.fence}\n{"tool":"echo","args":{}}\n```',
      ]) {
        final visible = AgentProtocol.stripLiveControlBlocks(head + tail);
        expect(visible.startsWith(previous), isTrue, reason: 'tail=$tail');
        previous = visible;
      }
      expect(previous, head);
    });

    test('بلوک نقشه هم در متن زنده دیده نمی‌شود', () {
      final out = AgentProtocol.stripLiveControlBlocks(
        'نقشه:\n```${AgentProtocol.planFence}\n["الف","ب"]\n```\nشروع می‌کنم.',
      );
      expect(out, isNot(contains('الف')));
      expect(out, contains('شروع می‌کنم'));
    });

    test('متن معمولی و بلوک کد عادی دست‌نخورده می‌مانند', () {
      const text = 'این کد را ببین:\n```dart\nvoid main() {}\n```\nتمام.';
      expect(AgentProtocol.stripLiveControlBlocks(text), text);
    });
  });
}
