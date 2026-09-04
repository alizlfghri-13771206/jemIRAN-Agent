import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jemiran/desktop/agent/agent_workspace.dart';
import 'package:jemiran/desktop/agent/core/agent_storage.dart';
import 'package:jemiran/desktop/agent/core/agent_task.dart';
import 'package:jemiran/desktop/agent/core/checkpoint_store.dart';
import 'package:jemiran/desktop/agent/tools/agent_tool.dart';
import 'package:jemiran/desktop/agent/tools/docx_tool.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late Directory storage;
  late Directory workspace;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    storage = await Directory.systemTemp.createTemp('jemiran_docx_store_');
    workspace = await Directory.systemTemp.createTemp(
      'jemiran_docx_workspace_',
    );
    AgentStorage.setBaseRootForTesting(storage);
    AgentStorage.setAccountScope('docx-test');
    await AgentWorkspace.clear();
    await AgentWorkspace.addDirectory(workspace.path);
  });

  tearDown(() async {
    await AgentWorkspace.clear();
    AgentStorage.setBaseRootForTesting(null);
    if (await storage.exists()) await storage.delete(recursive: true);
    if (await workspace.exists()) await workspace.delete(recursive: true);
  });

  test('یک DOCX واقعی با متن انگلیسی و XML امن می‌سازد', () async {
    final task = AgentTask(goal: 'Word story');
    final result = await const MakeDocxTool().run(
      ToolCall(
        name: 'make_docx',
        args: {
          'output': 'story',
          'title': 'The Fox & the Moon',
          'content': 'Once upon a time <near> the silver river.\n\nThe end.',
          'author': 'Jemiran Agent',
          'rtl': false,
        },
      ),
      _context(task.id),
    );

    expect(result.ok, isTrue);
    final file = File('${workspace.path}${Platform.pathSeparator}story.docx');
    expect(await file.exists(), isTrue);
    final bytes = await file.readAsBytes();
    expect(bytes.take(2), [0x50, 0x4b]);

    final archive = ZipDecoder().decodeBytes(bytes);
    final names = archive.files.map((entry) => entry.name).toSet();
    expect(
      names,
      containsAll(<String>{
        '[Content_Types].xml',
        '_rels/.rels',
        'word/document.xml',
        'word/styles.xml',
        'docProps/core.xml',
      }),
    );
    expect(names, isNot(contains('word/vbaProject.bin')));
    final document = utf8.decode(
      archive.findFile('word/document.xml')!.content,
    );
    expect(document, contains('Once upon a time'));
    expect(document, contains('The Fox &amp; the Moon'));
    expect(document, contains('&lt;near&gt;'));
  });

  test('فایل ساخته‌شده با rollback پاک می‌شود', () async {
    final task = AgentTask(goal: 'rollback Word');
    final result = await const MakeDocxTool().run(
      ToolCall(
        name: 'make_docx',
        args: {'output': 'temporary.docx', 'content': 'Temporary story.'},
      ),
      _context(task.id),
    );
    expect(result.ok, isTrue);
    final file = File(
      '${workspace.path}${Platform.pathSeparator}temporary.docx',
    );
    expect(await file.exists(), isTrue);
    expect(await AgentCheckpointStore.rollback(task.id), 1);
    expect(await file.exists(), isFalse);
  });

  test('مسیر بیرون از پوشهٔ مجاز رد می‌شود', () {
    final outside =
        '${Directory.systemTemp.path}${Platform.pathSeparator}outside.docx';
    final reason = const MakeDocxTool().hardDeny(
      ToolCall(name: 'make_docx', args: {'output': outside, 'content': 'No.'}),
    );
    expect(reason, contains('بیرون از منابع مجاز'));
  });
}

ToolContext _context(String taskId) => ToolContext(
  taskId: taskId,
  isCancelled: () => false,
  report: (_) {},
  ask: (_) async => null,
);
