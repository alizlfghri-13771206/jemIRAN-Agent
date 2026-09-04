import 'package:flutter_test/flutter_test.dart';
import 'package:jemiran/desktop/agent/core/agent_protocol.dart';
import 'package:jemiran/desktop/agent/core/agent_task.dart';
import 'package:jemiran/desktop/agent/tools/agent_tool.dart';

AgentStepRecord _step({
  required String tool,
  required Map<String, dynamic> args,
  required ToolResult result,
  StepStatus status = StepStatus.done,
}) {
  final record = AgentStepRecord(
    call: ToolCall(name: tool, args: args),
    toolLabel: tool,
    risk: ToolRisk.read,
    permission: '$tool.perm',
  );
  record.status = status;
  record.result = result;
  return record;
}

void main() {
  group('لنگر در خلاصهٔ فشرده‌سازی', () {
    test('خواندن فایل، مسیر و چند خط اول را نگه می‌دارد', () {
      final task = AgentTask(id: 't1', goal: 'کار');
      task.steps.add(
        _step(
          tool: 'read_file',
          args: {'path': 'lib/main.dart'},
          result: ToolResult.success(
            summary: 'خوانده شد',
            data: {'content': 'void main() {\nrunApp(App());\n}'},
            detail: 'void main() {\nrunApp(App());\n}',
          ),
        ),
      );

      final summary = AgentProtocol.compactionSummary(task);
      expect(summary, contains('lib/main.dart'));
      expect(summary, contains('void main()'));
    });

    test('فرمان، کد خروج و دُم خطا را نگه می‌دارد', () {
      final task = AgentTask(id: 't1', goal: 'کار');
      task.steps.add(
        _step(
          tool: 'run_command',
          args: {'command': 'flutter test'},
          status: StepStatus.failed,
          result: ToolResult.failure('۲ تست شکست خورد: expected 5 got 3'),
        ),
      );

      final summary = AgentProtocol.compactionSummary(task);
      expect(summary, contains('flutter test'));
      expect(summary, contains('expected 5 got 3'));
    });

    test('لنگرها نقل‌قول‌اند، نه تفسیر مدل', () {
      final task = AgentTask(id: 't1', goal: 'کار');
      task.steps.add(
        _step(
          tool: 'read_file',
          args: {'path': 'a.txt'},
          result: ToolResult.success(summary: 's', detail: 'متن دقیق فایل'),
        ),
      );
      final summary = AgentProtocol.compactionSummary(task);
      expect(summary, contains('متن دقیق فایل'));
    });

    test('لنگرها سقف دارند و خودشان زمینه را نمی‌بلعند', () {
      final task = AgentTask(id: 't1', goal: 'کار');
      for (var i = 0; i < 40; i++) {
        task.steps.add(
          _step(
            tool: 'read_file',
            args: {'path': 'file_$i.dart'},
            result: ToolResult.success(summary: 's', detail: 'x' * 5000),
          ),
        );
      }
      final summary = AgentProtocol.compactionSummary(task);
      expect(
        AgentProtocol.estimatedTokens(summary),
        lessThan(1600),
        reason: 'خلاصه باید کسر کوچکی از بودجهٔ پلن رایگان بماند',
      );
    });

    test('گام بدون نتیجه خلاصه را خراب نمی‌کند', () {
      final task = AgentTask(id: 't1', goal: 'کار');
      task.steps.add(
        _step(
          tool: 'read_file',
          args: {'path': 'a.txt'},
          result: ToolResult.success(summary: 's'),
          status: StepStatus.running,
        ),
      );
      expect(() => AgentProtocol.compactionSummary(task), returnsNormally);
    });
  });
}
