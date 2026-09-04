import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:jemiran/desktop/agent/core/agent_storage.dart';
import 'package:jemiran/desktop/agent/core/agent_task.dart';
import 'package:jemiran/desktop/agent/core/task_store.dart';
import 'package:jemiran/desktop/agent/core/work_session_store.dart';

Future<Directory> _scoped(String tag) async {
  final root = await Directory.systemTemp.createTemp('jemiran_$tag');
  AgentStorage.setBaseRootForTesting(root);
  AgentStorage.setAccountScope('$tag${DateTime.now().microsecondsSinceEpoch}');
  return root;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('آلودگی در سطح Work', () {
    test('پیام بعدیِ همان Work آلودگی را به ارث می‌برد', () {
      final work = WorkSession(
        id: 'w1',
        title: 'کار',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      expect(work.tainted, isFalse);
      work.tainted = true;

      final fresh = AgentTask(goal: 'پیام دوم');
      if (work.tainted) fresh.tainted = true;
      expect(fresh.tainted, isTrue);
    });

    test('آلودگی Work از restart جان می‌برد', () {
      final work = WorkSession(
        id: 'w2',
        title: 'کار',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      )..tainted = true;
      expect(WorkSession.fromJson(work.toJson()).tainted, isTrue);
    });
  });

  group('صفِ سریالِ نوشتن', () {
    test('ذخیرهٔ فوریِ در جریان، Work حذف‌شده را برنمی‌گرداند', () async {
      final root = await _scoped('work_race_');
      try {
        final store = WorkSessionStore.instance;
        await store.load();
        final work = await store.create();

        final a = store.save(work..title = 'یک', immediate: true);
        final b = store.save(work..title = 'دو', immediate: true);
        await store.delete(work.id);
        await Future.wait([a, b]);

        final dir = AgentStorage.subdir('works')!;
        final file = File(
          '${dir.path}${Platform.pathSeparator}${work.id}.json',
        );
        expect(
          await file.exists(),
          isFalse,
          reason: 'نوشتنِ در جریان نباید Work حذف‌شده را بازبسازد',
        );
      } finally {
        AgentStorage.setBaseRootForTesting(null);
        await root.delete(recursive: true);
      }
    });

    test('flush نوشتنِ در جریان را هم پوشش می‌دهد', () async {
      final root = await _scoped('work_flush_');
      try {
        final store = WorkSessionStore.instance;
        await store.load();
        final work = await store.create();

        store.save(work..title = 'نهایی');
        await store.flush();

        final dir = AgentStorage.subdir('works')!;
        final file = File(
          '${dir.path}${Platform.pathSeparator}${work.id}.json',
        );
        expect(await file.exists(), isTrue);
        expect(await file.readAsString(), contains('نهایی'));
      } finally {
        AgentStorage.setBaseRootForTesting(null);
        await root.delete(recursive: true);
      }
    });

    test('ترتیب نوشتن‌های Task حفظ می‌شود', () async {
      final root = await _scoped('task_order_');
      try {
        final store = AgentTaskStore.instance;
        final dir = AgentStorage.subdir('tasks')!;
        await dir.create(recursive: true);

        final task = AgentTask(goal: 'هدف');
        store.scheduleSave(task..note('اول'));
        store.scheduleSave(task..note('دوم'));
        store.scheduleSave(task..note('سوم'));
        await store.flush();

        final file = File(
          '${dir.path}${Platform.pathSeparator}${task.id}.json',
        );
        expect(await file.exists(), isTrue);
        expect(
          await file.readAsString(),
          contains('سوم'),
          reason: 'آخرین نوشتن باید برنده باشد، نه یک نوشتنِ عقب‌مانده',
        );
      } finally {
        AgentStorage.setBaseRootForTesting(null);
        await root.delete(recursive: true);
      }
    });
  });
}
