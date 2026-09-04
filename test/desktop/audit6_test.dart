import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:jemiran/desktop/agent/core/agent_storage.dart';
import 'package:jemiran/desktop/agent/core/agent_task.dart';
import 'package:jemiran/desktop/agent/core/task_store.dart';
import 'package:jemiran/desktop/agent/policy/agent_policy.dart';
import 'package:jemiran/desktop/agent/skills/agent_skill.dart';
import 'package:jemiran/desktop/agent/tools/agent_tool.dart';
import 'package:jemiran/desktop/agent/tools/filesystem_tools.dart';
import 'package:jemiran/desktop/agent/tools/git_tool.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('زنجیرهٔ taint — بازبینی ششم', () {
    test('نوشتن هم پس از آلودگی تأیید می‌خواهد', () {
      const state = AgentPolicyState(mode: AgentMode.autonomous);
      final call = ToolCall(
        name: 'write_file',
        args: const {'path': 'a.txt', 'content': 'x'},
      );
      expect(
        state.evaluate(tool: WriteFileTool(), call: call).outcome,
        PolicyOutcome.allow,
        reason: 'پیش از آلودگی باید روان باشد',
      );
      expect(
        state
            .evaluate(tool: WriteFileTool(), call: call, tainted: true)
            .outcome,
        PolicyOutcome.ask,
      );
    });

    test('منابع آلوده کامل علامت‌گذاری شده‌اند', () {
      expect(ListDirTool().yieldsUntrustedContent, isTrue);
      expect(FindFilesTool().yieldsUntrustedContent, isTrue);
      expect(GitTool().yieldsUntrustedContent, isTrue);
    });

    test('آلودگی روی Task می‌ماند و از restart جان می‌برد', () {
      final task = AgentTask(goal: 'آزمون')..tainted = true;
      final revived = AgentTask.fromJson(task.toJson());
      expect(revived.tainted, isTrue);
    });
  });

  group('SkillStore — سخت‌سازی بارگذاری', () {
    test('شناسهٔ حاوی مسیر رد می‌شود', () {
      expect(AgentSkill.isSafeId('../../etc/passwd'), isFalse);
      expect(AgentSkill.isSafeId('a/b'), isFalse);
      expect(AgentSkill.isSafeId('..'), isFalse);
      expect(AgentSkill.isSafeId('flutter-build'), isTrue);
    });

    test('شناسهٔ ناامن به slug امن برمی‌گردد', () {
      final skill = AgentSkill.fromJson({
        'id': '../../../../evil',
        'name': 'ساخت فلاتر',
      });
      expect(skill, isNotNull);
      expect(AgentSkill.isSafeId(skill!.id), isTrue);
      expect(skill.id.contains('..'), isFalse);
    });

    test('فیلدهای غول‌آسا هنگام خواندن بریده می‌شوند', () {
      final skill = AgentSkill.fromJson({
        'name': 'x',
        'purpose': 'y' * 5000,
        'patterns': List.generate(500, (i) => 'p$i'),
      });
      expect(
        skill!.purpose.length,
        lessThanOrEqualTo(AgentSkill.maxFieldChars + 1),
      );
      expect(skill.patterns.length, lessThanOrEqualTo(AgentSkill.maxListItems));
    });
  });

  group('TaskStore — نوشتن سریالی', () {
    test('دو ذخیرهٔ پشت‌سرهم و بعد حذف، فایل را برنمی‌گرداند', () async {
      final root = await Directory.systemTemp.createTemp('jemiran_tasks_');
      try {
        AgentStorage.setBaseRootForTesting(root);
        AgentStorage.setAccountScope(
          'audit6_${DateTime.now().microsecondsSinceEpoch}',
        );
        final store = AgentTaskStore.instance;
        final dir = AgentStorage.subdir('tasks')!;
        await dir.create(recursive: true);

        final task = AgentTask(goal: 'هدف');
        store.scheduleSave(task);
        store.scheduleSave(task..note('دوم'));
        await Future<void>.delayed(const Duration(milliseconds: 320));
        await store.delete(task.id);

        await Future<void>.delayed(const Duration(milliseconds: 250));
        final file = File(
          '${dir.path}${Platform.pathSeparator}${task.id}.json',
        );
        expect(
          await file.exists(),
          isFalse,
          reason: 'نوشتنِ در جریان نباید فایل حذف‌شده را بازبسازد',
        );
      } finally {
        AgentStorage.setBaseRootForTesting(null);
        await root.delete(recursive: true);
      }
    });
  });
}
