import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:jemiran/desktop/agent/core/agent_storage.dart';
import 'package:jemiran/desktop/agent/core/context_budget.dart';
import 'package:jemiran/desktop/agent/core/tool_output_budget.dart';
import 'package:jemiran/desktop/agent/tools/agent_tool.dart';

const _free = ContextBudget(
  maxContextTokens: 16000,
  reservedOutputTokens: 2048,
);

ToolCall _call(String name) => ToolCall(id: 'c', name: name, args: const {});

void main() {
  late Directory temp;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('jemiran-spill-');
    AgentStorage.setBaseRootForTesting(temp);
    AgentStorage.setAccountScope('budget@example.com');
    ToolOutputBudget.resetPruneForTesting();
  });

  tearDown(() {
    AgentStorage.setBaseRootForTesting(null);
    try {
      temp.deleteSync(recursive: true);
    } catch (_) {}
  });

  group('لایهٔ ۲ — سرریز یک نتیجه', () {
    test('نتیجهٔ بزرگ به فایل می‌رود و پیش‌نما جایش می‌ماند', () {
      final budget = ToolOutputBudget(_free);
      final huge = ToolResult.success(
        summary: 'دیف',
        data: {'diff': 'x' * 200000},
        detail: 'x' * 200000,
      );

      final bounded = budget.apply(_call('git'), huge);
      expect(bounded.spilled, isTrue);
      expect(bounded.result.encode(), isNot(contains('x' * 1000)));
      expect(bounded.result.detail, contains('read_file'));
      expect(File(bounded.path!).existsSync(), isTrue);
    });

    test('نتیجهٔ کوچک اصلاً دست نمی‌خورد', () {
      final budget = ToolOutputBudget(_free);
      final small = ToolResult.success(
        summary: 'ok',
        data: {'text': 'سلام'},
        detail: 'سلام',
      );
      final bounded = budget.apply(_call('git'), small);
      expect(bounded.spilled, isFalse);
      expect(bounded.result.encode(), contains('سلام'));
    });

    test('read_file هرگز سرریز نمی‌شود', () {
      final budget = ToolOutputBudget(_free);
      final huge = ToolResult.success(
        summary: 'فایل',
        data: {'content': 'y' * 200000},
      );
      final bounded = budget.apply(_call('read_file'), huge);
      expect(bounded.spilled, isFalse);
      expect(budget.usedTokens, greaterThan(1000));
    });

    test('راز پیش از نوشتن روی دیسک پاک می‌شود', () {
      final budget = ToolOutputBudget(_free);
      const payload = 'AWS_SECRET_ACCESS_KEY=wJalrLEAKvalue123';
      final leaky = ToolResult.success(
        summary: 'خروجی',
        data: {'out': '${'z' * 100000}\n$payload'},
        detail: '${'z' * 100000}\n$payload',
      );
      final bounded = budget.apply(_call('run_command'), leaky);
      final onDisk = File(bounded.path!).readAsStringSync();
      expect(onDisk, isNot(contains('wJalrLEAKvalue123')));
    });

    test('آستانه با پنجرهٔ مدل مقیاس می‌گیرد', () {
      const amazing = ContextBudget(
        maxContextTokens: 192000,
        reservedOutputTokens: 12288,
      );
      final result = ToolResult.success(
        summary: 's',
        data: {'out': 'w' * 60000},
      );

      expect(
        ToolOutputBudget(_free).apply(_call('git'), result).spilled,
        isTrue,
      );
      expect(
        ToolOutputBudget(amazing).apply(_call('git'), result).spilled,
        isFalse,
      );
    });
  });

  group('لایهٔ ۳ — سقف تجمیعی نوبت', () {
    test('چند نتیجهٔ متوسط که با هم از سقف رد می‌شوند، سرریز می‌کنند', () {
      final budget = ToolOutputBudget(_free);
      var spills = 0;
      for (var i = 0; i < 6; i++) {
        final bounded = budget.apply(
          _call('search_files'),
          ToolResult.success(summary: 's$i', data: {'out': 'q' * 9000}),
        );
        if (bounded.spilled) spills++;
      }
      expect(spills, greaterThan(0), reason: 'سقف نوبت باید فعال شود');
      expect(budget.usedTokens, lessThanOrEqualTo(budget.turnCapTokens));
    });

    test('بودجه بین نوبت‌ها صفر می‌شود', () {
      final budget = ToolOutputBudget(_free);
      budget.apply(
        _call('git'),
        ToolResult.success(summary: 's', data: {'out': 'r' * 40000}),
      );
      expect(budget.usedTokens, greaterThan(0));
      budget.reset();
      expect(budget.usedTokens, 0);
    });
  });
}
