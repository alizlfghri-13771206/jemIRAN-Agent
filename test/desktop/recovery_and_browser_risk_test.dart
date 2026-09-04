import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:jemiran/desktop/agent/browser/page_snapshot.dart';
import 'package:jemiran/desktop/agent/core/agent_storage.dart';
import 'package:jemiran/desktop/agent/core/agent_task.dart';
import 'package:jemiran/desktop/agent/core/task_store.dart';
import 'package:jemiran/desktop/agent/tools/agent_tool.dart';
import 'package:jemiran/desktop/agent/tools/browser_tools.dart';
import 'package:path/path.dart' as p;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('بازیابی نوشتنِ نیمه‌تمام', () {
    late Directory temp;

    setUp(() async {
      temp = await Directory.systemTemp.createTemp('jemiran_recover');
    });

    tearDown(() {
      if (temp.existsSync()) temp.deleteSync(recursive: true);
    });

    test('فایلی که فقط در .bak مانده برمی‌گردد', () async {
      File(
        p.join(temp.path, 'task_a.json.bak'),
      ).writeAsStringSync('{"id":"a"}');

      expect(await AgentStorage.recoverInterruptedWrites(temp), 1);
      expect(File(p.join(temp.path, 'task_a.json')).existsSync(), isTrue);
      expect(File(p.join(temp.path, 'task_a.json.bak')).existsSync(), isFalse);
    });

    test('وقتی هدف سالم است، backup فقط پاک می‌شود', () async {
      File(p.join(temp.path, 'task_b.json')).writeAsStringSync('{"v":2}');
      File(p.join(temp.path, 'task_b.json.bak')).writeAsStringSync('{"v":1}');

      expect(await AgentStorage.recoverInterruptedWrites(temp), 0);
      expect(
        File(p.join(temp.path, 'task_b.json')).readAsStringSync(),
        '{"v":2}',
      );
      expect(File(p.join(temp.path, 'task_b.json.bak')).existsSync(), isFalse);
    });

    test('journal بعد از قطع برق واقعاً بازخوانی می‌شود', () async {
      AgentStorage.setBaseRootForTesting(temp);
      addTearDown(() => AgentStorage.setBaseRootForTesting(null));

      final dir = AgentStorage.subdir('tasks')!;
      final task = AgentTask(goal: 'کار نجات‌یافته');
      File(
        p.join(dir.path, '${task.id}.json.bak'),
      ).writeAsStringSync(jsonEncode(task.toJson()));

      await AgentTaskStore.instance.load();
      expect(AgentTaskStore.instance.byId(task.id)?.goal, 'کار نجات‌یافته');
    });
  });

  group('خطر کلیک در مرورگر', () {
    PageSnapshot snapshotWith(String label) => PageSnapshot(
      url: 'https://example.com',
      title: 'نمونه',
      text: '',
      elements: [PageElement(ref: 'ref_1', tag: 'button', label: label)],
      forms: const [],
    );

    test('دکمهٔ برگشت‌ناپذیر تشخیص داده می‌شود', () {
      for (final label in const [
        'حذف حساب',
        'پرداخت نهایی',
        'اجازه دادن',
        'Delete repository',
        'Authorize',
        'Confirm purchase',
      ]) {
        expect(
          BrowserActTool.clickLooksIrreversible(snapshotWith(label), 'ref_1'),
          isTrue,
          reason: label,
        );
      }
    });

    test('دکمهٔ معمولی برگشت‌ناپذیر شمرده نمی‌شود', () {
      for (final label in const ['جست‌وجو', 'بعدی', 'Search', 'Next page']) {
        expect(
          BrowserActTool.clickLooksIrreversible(snapshotWith(label), 'ref_1'),
          isFalse,
          reason: label,
        );
      }
    });

    test('کنش غیر از کلیک، خطرش بالا نمی‌رود', () {
      const tool = BrowserActTool();
      final typing = ToolCall(
        name: 'browser_act',
        args: const {'action': 'type', 'ref': 'ref_1', 'text': 'x'},
      );
      expect(tool.riskOf(typing), ToolRisk.network);
    });

    test('بدون snapshot، حدس زده نمی‌شود', () {
      expect(BrowserActTool.clickLooksIrreversible(null, 'ref_1'), isFalse);
      expect(
        BrowserActTool.clickLooksIrreversible(snapshotWith('حذف'), null),
        isFalse,
      );
    });
  });
}
