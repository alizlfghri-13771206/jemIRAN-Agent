import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:jemiran/desktop/agent/agent_workspace.dart';
import 'package:jemiran/desktop/agent/core/agent_storage.dart';
import 'package:jemiran/desktop/agent/core/agent_task.dart';
import 'package:jemiran/desktop/agent/core/checkpoint_store.dart';
import 'package:jemiran/desktop/agent/core/task_store.dart';
import 'package:jemiran/desktop/agent/memory/agent_memory.dart';
import 'package:jemiran/desktop/agent/tools/agent_tool.dart';
import 'package:jemiran/desktop/agent/tools/filesystem_tools.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late Directory temp;
  late Directory workspace;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    temp = await Directory.systemTemp.createTemp('jemiran_agent_store_');
    workspace = await Directory.systemTemp.createTemp('jemiran_workspace_');
    AgentStorage.setBaseRootForTesting(temp);
    AgentStorage.setAccountScope('user-a');
    await AgentWorkspace.clear();
    await AgentWorkspace.addDirectory(workspace.path, canDelete: true);
    await AgentTaskStore.instance.load();
  });

  tearDown(() async {
    await AgentTaskStore.instance.flush();
    AgentStorage.setAccountScope('user-a');
    await AgentWorkspace.load();
    await AgentWorkspace.clear();
    AgentStorage.setBaseRootForTesting(null);
    if (await temp.exists()) await temp.delete(recursive: true);
    if (await workspace.exists()) await workspace.delete(recursive: true);
  });

  test('running tasks become interrupted after a store reload', () async {
    final task = AgentTask(goal: 'ادامهٔ امن')
      ..phase = AgentPhase.executing
      ..currentAction = 'نوشتن فایل';
    AgentTaskStore.instance.scheduleSave(task);
    await AgentTaskStore.instance.flush();

    await AgentTaskStore.instance.load();

    final restored = AgentTaskStore.instance.tasks.single;
    expect(restored.id, task.id);
    expect(restored.phase, AgentPhase.interrupted);
    expect(restored.currentAction, isNull);
    expect(restored.errors.single, contains('نیازمند تأیید کاربر'));
  });

  test('task journal scrubs credentials and does not persist tool args', () {
    final task = AgentTask(goal: 'token=super-secret-value')
      ..steps.add(
        AgentStepRecord(
          call: ToolCall(
            name: 'write_file',
            args: {'path': 'x.txt', 'content': 'password=hunter22'},
          ),
          toolLabel: 'نوشتن',
          risk: ToolRisk.write,
        ),
      );

    final encoded = task.toJson().toString();

    expect(encoded, isNot(contains('super-secret-value')));
    expect(encoded, isNot(contains('hunter22')));
    expect(encoded, isNot(contains('content')));
  });

  test('account identities receive separate storage namespaces', () {
    AgentStorage.setAccountScope('user-a');
    final first = AgentStorage.root!.path;
    AgentStorage.setAccountScope('user-b');
    final second = AgentStorage.root!.path;

    expect(first, isNot(second));
    expect(first, isNot(contains('user-a')));
    expect(second, isNot(contains('user-b')));
  });

  test(
    'pending task write cannot leak into a newly selected account',
    () async {
      AgentStorage.setAccountScope('user-a');
      final firstKey = AgentStorage.accountKey;
      final task = AgentTask(goal: 'account-a-only');
      AgentTaskStore.instance.scheduleSave(task);

      AgentStorage.setAccountScope('user-b');
      final secondKey = AgentStorage.accountKey;
      await AgentTaskStore.instance.flush();

      final first = File(
        '${temp.path}${Platform.pathSeparator}accounts'
        '${Platform.pathSeparator}$firstKey${Platform.pathSeparator}tasks'
        '${Platform.pathSeparator}${task.id}.json',
      );
      final second = File(
        '${temp.path}${Platform.pathSeparator}accounts'
        '${Platform.pathSeparator}$secondKey${Platform.pathSeparator}tasks'
        '${Platform.pathSeparator}${task.id}.json',
      );
      expect(await first.exists(), isTrue);
      expect(await second.exists(), isFalse);
    },
  );

  test('workspace permissions do not leak into another account', () async {
    expect(AgentWorkspace.resources, hasLength(1));

    AgentStorage.setAccountScope('user-b');
    await AgentWorkspace.load();
    expect(AgentWorkspace.resources, isEmpty);

    AgentStorage.setAccountScope('user-a');
    await AgentWorkspace.load();
    expect(AgentWorkspace.resources, hasLength(1));
    expect(AgentWorkspace.isAllowed(workspace.path), isTrue);
  });

  test('project context and session lookup never mix two project paths', () {
    final projectA = '${workspace.path}${Platform.pathSeparator}a';
    final projectB = '${workspace.path}${Platform.pathSeparator}b';
    final taskA = AgentTask(goal: 'رفع باگ الف', projectPath: projectA)
      ..sessionId = 11
      ..finalAnswer = 'تست‌های الف موفق شدند'
      ..changedPaths.add('$projectA${Platform.pathSeparator}a.dart');
    final taskB = AgentTask(goal: 'تغییر پروژه ب', projectPath: projectB)
      ..sessionId = 22
      ..finalAnswer = 'فایل ب ساخته شد';
    AgentTaskStore.instance.scheduleSave(taskA);
    AgentTaskStore.instance.scheduleSave(taskB);

    final contextA = AgentTaskStore.instance.promptSectionForProject(projectA);
    expect(contextA, contains('رفع باگ الف'));
    expect(contextA, contains('a.dart'));
    expect(contextA, isNot(contains('تغییر پروژه ب')));
    expect(AgentTaskStore.instance.projectPathForSession(11), projectA);
    expect(AgentTaskStore.instance.projectPathForSession(22), projectB);
  });

  test('durable memory and task memory respect their lifetimes', () async {
    await MemoryStore.instance.load();
    await MemoryStore.instance.remember(
      scope: MemoryScope.user,
      text: 'ترجیح حساب الف',
    );
    await MemoryStore.instance.remember(
      scope: MemoryScope.task,
      text: 'فقط همین کار',
    );
    MemoryStore.instance.clearEphemeral();
    expect(MemoryStore.instance.all.map((note) => note.text), [
      'ترجیح حساب الف',
    ]);

    AgentStorage.setAccountScope('user-b');
    await MemoryStore.instance.load();
    expect(MemoryStore.instance.all, isEmpty);

    AgentStorage.setAccountScope('user-a');
    await MemoryStore.instance.load();
    expect(MemoryStore.instance.all.single.text, 'ترجیح حساب الف');
  });

  test(
    'file mutation can be rolled back to its exact original content',
    () async {
      AgentStorage.setAccountScope('user-a');
      final file = File('${workspace.path}${Platform.pathSeparator}note.txt');
      await file.writeAsString('before');
      final task = AgentTask(goal: 'edit');
      final tool = WriteFileTool();
      final result = await tool.run(
        ToolCall(
          name: 'write_file',
          args: {'path': file.path, 'content': 'after'},
        ),
        _context(task.id),
      );

      expect(result.ok, isTrue);
      expect(await file.readAsString(), 'after');
      expect(await AgentCheckpointStore.rollback(task.id), 1);
      expect(await file.readAsString(), 'before');
    },
  );

  test('rollback removes a file that the task created', () async {
    AgentStorage.setAccountScope('user-a');
    final file = File('${workspace.path}${Platform.pathSeparator}new.txt');
    final task = AgentTask(goal: 'create');
    final result = await WriteFileTool().run(
      ToolCall(
        name: 'write_file',
        args: {'path': file.path, 'content': 'created'},
      ),
      _context(task.id),
    );

    expect(result.ok, isTrue);
    expect(await file.exists(), isTrue);
    expect(await AgentCheckpointStore.rollback(task.id), 1);
    expect(await file.exists(), isFalse);
  });

  test('missing checkpoint never deletes the current live file', () async {
    final file = File('${workspace.path}${Platform.pathSeparator}safe.txt');
    await file.writeAsString('original');
    const taskId = 'task_missing_snapshot';
    expect(await AgentCheckpointStore.capture(taskId, file.path), isTrue);
    await file.writeAsString('current');

    final snapshot = File(
      '${AgentStorage.root!.path}${Platform.pathSeparator}checkpoints'
      '${Platform.pathSeparator}$taskId${Platform.pathSeparator}snapshot_0',
    );
    await snapshot.delete();

    expect(await AgentCheckpointStore.rollback(taskId), 0);
    expect(await file.readAsString(), 'current');
  });

  test(
    'corrupt checkpoint type never authorizes deleting a live file',
    () async {
      final file = File('${workspace.path}${Platform.pathSeparator}safe2.txt');
      await file.writeAsString('original');
      const taskId = 'task_corrupt_manifest';
      expect(await AgentCheckpointStore.capture(taskId, file.path), isTrue);
      await file.writeAsString('current');

      final manifest = File(
        '${AgentStorage.root!.path}${Platform.pathSeparator}checkpoints'
        '${Platform.pathSeparator}$taskId${Platform.pathSeparator}manifest.json',
      );
      final decoded = jsonDecode(await manifest.readAsString()) as Map;
      final entries = decoded['entries'] as List;
      (entries.single as Map)['type'] = 'unknown';
      await manifest.writeAsString(jsonEncode(decoded), flush: true);

      expect(await AgentCheckpointStore.rollback(taskId), 0);
      expect(await file.readAsString(), 'current');
    },
  );
}

ToolContext _context(String taskId) => ToolContext(
  taskId: taskId,
  isCancelled: () => false,
  report: (_) {},
  ask: (_) async => null,
);
