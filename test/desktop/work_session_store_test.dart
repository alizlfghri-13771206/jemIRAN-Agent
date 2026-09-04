import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:jemiran/desktop/agent/agent_workspace.dart';
import 'package:jemiran/desktop/agent/core/agent_storage.dart';
import 'package:jemiran/desktop/agent/core/task_store.dart';
import 'package:jemiran/desktop/agent/core/work_session_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory storage;
  late Directory project;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    storage = await Directory.systemTemp.createTemp('jemiran_work_store_');
    project = await Directory.systemTemp.createTemp('jemiran_work_project_');
    AgentStorage.setBaseRootForTesting(storage);
    AgentStorage.setAccountScope('work-user-a');
    await AgentTaskStore.instance.load();
    await WorkSessionStore.instance.load();
  });

  tearDown(() async {
    await WorkSessionStore.instance.flush();
    AgentStorage.setBaseRootForTesting(null);
    if (await storage.exists()) await storage.delete(recursive: true);
    if (await project.exists()) await project.delete(recursive: true);
  });

  test(
    'Work با timeline، مسیر، منابع و transport id بعد از restart برمی‌گردد',
    () async {
      final resource = AgentResource(
        path: project.path,
        kind: ResourceKind.directory,
        canWrite: true,
      );
      final work = await WorkSessionStore.instance.create(
        projectPath: project.path,
        resources: [resource],
      );
      work
        ..title = 'پروژهٔ تست'
        ..transportSessionId = 42
        ..modelKey = 'coder-model'
        ..timeline = [
          {
            'kind': 'message',
            'message': {'id': 'm1', 'text': 'سلام', 'isUser': true},
          },
        ];
      await WorkSessionStore.instance.save(work, immediate: true);
      await WorkSessionStore.instance.flush();

      await WorkSessionStore.instance.load();
      final restored = WorkSessionStore.instance.byId(work.id)!;

      expect(restored.title, 'پروژهٔ تست');
      expect(restored.transportSessionId, 42);
      expect(restored.modelKey, 'coder-model');
      expect(restored.projectPath, project.path);
      expect(restored.resources.single.path, project.path);
      expect(restored.timeline.single['kind'], 'message');
    },
  );

  test('pin ماندگار است و Work سنجاق‌شده بالاتر از تاریخچه می‌آید', () async {
    final first = await WorkSessionStore.instance.create();
    final second = await WorkSessionStore.instance.create();

    await WorkSessionStore.instance.togglePin(first.id);
    await WorkSessionStore.instance.load();

    expect(WorkSessionStore.instance.works.first.id, first.id);
    expect(WorkSessionStore.instance.byId(first.id)!.pinned, isTrue);
    expect(WorkSessionStore.instance.byId(second.id)!.pinned, isFalse);
  });

  test('حذف Work هرگز پوشه یا فایل واقعی پروژه را حذف نمی‌کند', () async {
    final marker = File('${project.path}${Platform.pathSeparator}keep.txt');
    await marker.writeAsString('keep');
    final work = await WorkSessionStore.instance.create(
      projectPath: project.path,
      resources: [
        AgentResource(
          path: project.path,
          kind: ResourceKind.directory,
          canWrite: true,
        ),
      ],
    );

    await WorkSessionStore.instance.delete(work.id);

    expect(WorkSessionStore.instance.byId(work.id), isNull);
    expect(await marker.readAsString(), 'keep');
  });

  test('نوشتن debounce شدهٔ حساب A وارد فضای حساب B نمی‌شود', () async {
    AgentStorage.setAccountScope('work-user-a');
    final keyA = AgentStorage.accountKey;
    final work = await WorkSessionStore.instance.create();
    work.title = 'فقط حساب A';
    WorkSessionStore.instance.save(work);

    AgentStorage.setAccountScope('work-user-b');
    final keyB = AgentStorage.accountKey;
    await WorkSessionStore.instance.flush();

    final fileA = File(
      '${storage.path}${Platform.pathSeparator}accounts'
      '${Platform.pathSeparator}$keyA${Platform.pathSeparator}works'
      '${Platform.pathSeparator}${work.id}.json',
    );
    final fileB = File(
      '${storage.path}${Platform.pathSeparator}accounts'
      '${Platform.pathSeparator}$keyB${Platform.pathSeparator}works'
      '${Platform.pathSeparator}${work.id}.json',
    );
    expect(await fileA.exists(), isTrue);
    expect(await fileB.exists(), isFalse);
  });
}
