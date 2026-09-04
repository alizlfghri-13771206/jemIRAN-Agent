import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:jemiran/desktop/agent/audit/audit_log.dart';
import 'package:jemiran/desktop/agent/audit/audit_recorder.dart';
import 'package:jemiran/desktop/agent/core/agent_event.dart';
import 'package:jemiran/desktop/agent/core/agent_storage.dart';
import 'package:jemiran/desktop/agent/core/agent_task.dart';
import 'package:jemiran/desktop/agent/tools/agent_tool.dart';

AgentStepRecord _step({
  String tool = 'run_command',
  String target = 'flutter test',
  bool ok = true,
}) {
  final record = AgentStepRecord(
    call: ToolCall(id: 's1', name: tool, args: {'command': target}),
    toolLabel: 'ترمینال',
    risk: ToolRisk.execute,
    permission: 'terminal.execute',
  );
  record.status = StepStatus.done;
  record.result = ok
      ? ToolResult.success(summary: target)
      : ToolResult.failure('شکست خورد');
  return record;
}

void main() {
  late Directory temp;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('jemiran-audit-');
    AgentStorage.setBaseRootForTesting(temp);
    AgentStorage.setAccountScope('audit-user@example.com');
    AuditLog.enabled = true;
    AuditLog.maxActiveBytes = 2 * 1024 * 1024;
    AuditLog.clear();
  });

  tearDown(() {
    AgentStorage.setBaseRootForTesting(null);
    try {
      temp.deleteSync(recursive: true);
    } catch (_) {}
  });

  group('دفتر ثبت', () {
    test('ردیف نوشته و تازه‌ترین اول خوانده می‌شود', () {
      AuditLog.record(AuditKind.tool, task: 't1', fields: {'tool': 'اول'});
      AuditLog.record(AuditKind.tool, task: 't1', fields: {'tool': 'دوم'});

      final entries = AuditLog.read();
      expect(entries, hasLength(2));
      expect(entries.first.fields['tool'], 'دوم');
      expect(entries.first.taskId, 't1');
    });

    test('راز پیش از نوشتن روی دیسک پاک می‌شود', () {
      AuditLog.record(
        AuditKind.tool,
        fields: {
          'target': 'curl -H "Authorization: Bearer sk-LEAK-123456789"',
          'other': 'api_key=super-secret-value-9f3a',
        },
      );

      final raw = File(
        '${AgentStorage.root!.path}/audit/audit.jsonl',
      ).readAsStringSync();
      expect(raw, isNot(contains('sk-LEAK-123456789')));
      expect(raw, isNot(contains('super-secret-value-9f3a')));
      expect(raw, contains('«حذف‌شده»'));
    });

    test('مقدار خیلی بلند بریده می‌شود', () {
      AuditLog.record(AuditKind.tool, fields: {'target': 'x' * 5000});
      final value = AuditLog.read().single.fields['target'] as String;
      expect(value.length, lessThan(700));
      expect(value, endsWith('…'));
    });

    test('خط ناقصِ ناشی از خاموشی ناگهانی فقط رد می‌شود', () {
      AuditLog.record(AuditKind.tool, fields: {'tool': 'سالم'});
      final file = File('${AgentStorage.root!.path}/audit/audit.jsonl');
      file.writeAsStringSync(
        '{"ts":123,"kind":"tool","to',
        mode: FileMode.append,
      );

      final entries = AuditLog.read();
      expect(entries, hasLength(1));
      expect(entries.single.fields['tool'], 'سالم');
    });

    test('فیلتر بر اساس دسته، Task و متن کار می‌کند', () {
      AuditLog.record(
        AuditKind.tool,
        task: 'a',
        fields: {'target': 'git push'},
      );
      AuditLog.record(
        AuditKind.tool,
        task: 'b',
        fields: {'target': 'npm test'},
      );
      AuditLog.record(AuditKind.permission, task: 'a', fields: {'tool': 'x'});

      expect(AuditLog.read(kinds: {AuditKind.permission}), hasLength(1));
      expect(AuditLog.read(taskId: 'a'), hasLength(2));
      expect(AuditLog.read(contains: 'npm'), hasLength(1));
      expect(AuditLog.read(kinds: {AuditKind.tool}, taskId: 'a'), hasLength(1));
    });

    test('سقف حجم واقعاً اعمال می‌شود و فایل بی‌مرز رشد نمی‌کند', () {
      final dir = Directory('${AgentStorage.root!.path}/audit');
      AuditLog.maxActiveBytes = 4 * 1024;
      final chunk = 'y' * 400;
      for (var i = 0; i < 20 * (AuditLog.maxRotatedFiles + 2); i++) {
        AuditLog.record(AuditKind.tool, fields: {'target': chunk});
      }

      final files = dir.listSync().whereType<File>().toList();
      expect(
        files.length,
        lessThanOrEqualTo(AuditLog.maxRotatedFiles + 1),
        reason: 'فایل فعال + حداکثر ${AuditLog.maxRotatedFiles} فایل چرخیده',
      );
      for (final file in files) {
        expect(
          file.lengthSync(),
          lessThan(AuditLog.maxActiveBytes * 2),
          reason: 'هیچ فایلی نباید خیلی از سقف رد شود',
        );
      }
    });

    test('خروجی به ترتیب زمانی و بدون راز است', () {
      AuditLog.record(AuditKind.tool, fields: {'target': 'اول'});
      AuditLog.record(AuditKind.tool, fields: {'target': 'token=abcdef123456'});

      final exported = AuditLog.exportJsonl();
      final lines = const LineSplitter().convert(exported);
      expect(lines, hasLength(2));
      expect(jsonDecode(lines.first)['target'], 'اول');
      expect(exported, isNot(contains('abcdef123456')));
    });

    test('پاک کردن، مسیر خروج از حساب را کامل می‌بندد', () {
      AuditLog.record(AuditKind.tool, fields: {'target': 'چیزی'});
      AuditLog.clear();
      expect(AuditLog.read(), isEmpty);
    });
  });

  group('شناسهٔ همبستگی', () {
    test('هر ردیف شناسهٔ Task دارد، نه فقط شروع و پایان', () {
      final recorder = AuditRecorder(modelKey: 'm1');
      final task = AgentTask(id: 'task-42', goal: 'یک کار');

      recorder.onEvent(TaskStarted(task));
      recorder.onEvent(StepFinished(_step()));
      recorder.onEvent(
        PermissionRequested(_step(), const ToolPreview(title: 'اجرای فرمان')),
      );
      recorder.onEvent(ContextCompacted(round: 2, reason: 'threshold'));
      recorder.onEvent(ModelSwitched(from: 'm1', to: 'm2', reason: 'no_reply'));
      recorder.onEvent(RecoverableError('یک خطای معمولی'));
      recorder.onEvent(TaskFinished(task));

      final entries = AuditLog.read();
      expect(entries, hasLength(7));
      for (final entry in entries) {
        expect(
          entry.taskId,
          'task-42',
          reason: 'ردیف «${entry.kind}» بدون شناسهٔ Task قابل ربط دادن نیست',
        );
      }
    });
  });

  group('پاک‌سازی راز', () {
    test('سرآیند Authorization خودِ توکن را هم می‌برد، نه فقط طرح را', () {
      for (final scheme in const ['Bearer', 'Basic', 'Token']) {
        final scrubbed = SecretScrubber.scrub(
          'curl -H "Authorization: $scheme sk-LEAK-987654321"',
        );
        expect(scrubbed, isNot(contains('sk-LEAK-987654321')));
      }
      expect(
        SecretScrubber.scrub('Authorization: sk-BARE-123456'),
        isNot(contains('sk-BARE-123456')),
      );
    });

    test('کلید داخل گیومه و کلید مرکب هم پاک می‌شوند', () {
      for (final leak in const [
        '{"token":"abcdefghijklmnop"}',
        '{ "password" : "hunter2hunter2" }',
        "{'session_id': 'abc12345'}",
        'AWS_SECRET_ACCESS_KEY=wJalrXUtnFEMISECRETKEY',
        'DB_PASSWORD=p4ssw0rd-value',
      ]) {
        final scrubbed = SecretScrubber.scrub(leak);
        expect(scrubbed, contains('«حذف‌شده»'), reason: leak);
        for (final needle in const [
          'abcdefghijklmnop',
          'hunter2hunter2',
          'abc12345',
          'wJalrXUtnFEMISECRETKEY',
          'p4ssw0rd-value',
        ]) {
          expect(scrubbed, isNot(contains(needle)), reason: leak);
        }
      }
    });

    test('متن بی‌خطر که تصادفاً کلمهٔ حساس دارد، دست‌نخورده می‌ماند', () {
      for (final safe in const [
        'the secret sauce is good',
        'git commit -m "fix token parsing"',
        'flutter test --no-pub test/desktop',
      ]) {
        expect(SecretScrubber.scrub(safe), safe);
      }
    });

    test('روی ورودی بزرگ درجه‌دو نمی‌شود', () {
      final watch = Stopwatch()..start();
      SecretScrubber.scrub('z' * 200000);
      expect(
        watch.elapsedMilliseconds,
        lessThan(5000),
        reason: 'پاک‌سازی باید خطی بماند، نه درجه‌دو',
      );
    });

    test('اعتبارنامهٔ داخل URL همچنان پاک می‌شود', () {
      expect(
        SecretScrubber.scrub('https://user:p4ssw0rd@example.com/repo.git'),
        isNot(contains('p4ssw0rd')),
      );
      const plain = 'https://example.com/a/b';
      expect(SecretScrubber.scrub(plain), plain);
    });

    test('متن عادی بی‌دلیل حذف نمی‌شود', () {
      const plain = 'flutter test --no-pub test/desktop';
      expect(SecretScrubber.scrub(plain), plain);
    });
  });

  group('پل رویداد به دفتر', () {
    test('اجرای ابزار با هدف و نتیجه ثبت می‌شود', () {
      AuditRecorder(
        modelKey: 'anthropic/claude-opus-5',
      ).onEvent(StepFinished(_step()));

      final entry = AuditLog.read().single;
      expect(entry.kind, 'tool');
      expect(entry.model, 'anthropic/claude-opus-5');
      expect(entry.fields['tool'], 'run_command');
      expect(entry.fields['permission'], 'terminal.execute');
      expect(entry.fields['risk'], 'execute');
      expect(entry.fields['ok'], isTrue);
    });

    test('دسته‌بندی از رویداد تایپ‌دار می‌آید، نه از متن فارسی رابط', () {
      final recorder = AuditRecorder(modelKey: 'm1');
      recorder.onEvent(ContextCompacted(round: 3, reason: 'threshold'));
      recorder.onEvent(ModelSwitched(from: 'm1', to: 'm2', reason: 'no_reply'));
      recorder.onEvent(RecoverableError('یک خطای معمولی'));

      expect(AuditLog.read(kinds: {AuditKind.compaction}), hasLength(1));
      expect(AuditLog.read(kinds: {AuditKind.modelSwitch}), hasLength(1));
      expect(AuditLog.read(kinds: {AuditKind.error}), hasLength(1));

      final switched = AuditLog.read(kinds: {AuditKind.modelSwitch}).single;
      expect(switched.fields['from'], 'm1');
      expect(switched.fields['to'], 'm2');
    });

    test('متن فارسی رابط دیگر هیچ ردیفی را دسته‌بندی نمی‌کند', () {
      AuditRecorder(modelKey: 'm1').onEvent(
        RecoverableError('گفت‌وگو طولانی شد؛ در حال فشرده‌سازی زمینه…'),
      );
      expect(AuditLog.read(kinds: {AuditKind.compaction}), isEmpty);
      expect(AuditLog.read(kinds: {AuditKind.error}), hasLength(1));
    });

    test('رویدادهای پرتکرار و نمایشی ثبت نمی‌شوند', () {
      final recorder = AuditRecorder(modelKey: 'm1');
      recorder.onEvent(AssistantDelta('تکه'));
      recorder.onEvent(StepProgress('s1', 'خط خروجی ترمینال'));
      expect(AuditLog.read(), isEmpty);
    });

    test('خاموش بودن دفتر هیچ ردی نمی‌گذارد', () {
      AuditLog.enabled = false;
      AuditRecorder(modelKey: 'm1').onEvent(StepFinished(_step()));
      AuditLog.enabled = true;
      expect(AuditLog.read(), isEmpty);
    });
  });
}
