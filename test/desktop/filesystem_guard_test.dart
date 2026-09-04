import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:jemiran/desktop/agent/agent_workspace.dart';
import 'package:jemiran/desktop/agent/core/agent_storage.dart';
import 'package:jemiran/desktop/agent/tools/agent_tool.dart';
import 'package:jemiran/desktop/agent/tools/filesystem_tools.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory temp;
  late Directory real;
  late Directory storage;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    temp = await Directory.systemTemp.createTemp('jemiran_fs_guard');
    storage = Directory(p.join(temp.path, 'storage'))..createSync();
    AgentStorage.setBaseRootForTesting(storage);
    real = Directory(p.join(temp.path, 'real'))..createSync();
    File(p.join(real.path, 'keep.txt')).writeAsStringSync('salam');
    await AgentWorkspace.clear();
  });

  tearDown(() async {
    await AgentWorkspace.clear();
    AgentStorage.setBaseRootForTesting(null);
    if (temp.existsSync()) temp.deleteSync(recursive: true);
  });

  Link? linkTo(String target, String at) {
    final link = Link(at);
    try {
      link.createSync(target);
    } on FileSystemException {
      return null;
    }
    return link;
  }

  test('حذف ریشه از راه نام مستعار هم رد می‌شود', () async {
    await AgentWorkspace.addDirectory(real.path, canDelete: true);
    final alias = linkTo(real.path, p.join(temp.path, 'alias'));
    if (alias == null) return;

    final result = await const DeletePathTool().run(
      ToolCall(
        name: 'delete_path',
        args: {'path': alias.path, 'recursive': true},
      ),
      _context(),
    );

    expect(result.ok, isFalse);
    expect(result.error, contains('ریشه'));
    expect(Directory(real.path).existsSync(), isTrue);
    expect(File(p.join(real.path, 'keep.txt')).existsSync(), isTrue);
  });

  test('جابه‌جا کردن ریشه هم رد می‌شود', () async {
    await AgentWorkspace.addDirectory(real.path);
    final result = await const MovePathTool().run(
      ToolCall(
        name: 'move_path',
        args: {'from': real.path, 'to': p.join(real.path, 'moved')},
      ),
      _context(),
    );

    expect(result.ok, isFalse);
    expect(result.error, contains('ریشه'));
    expect(Directory(real.path).existsSync(), isTrue);
  });

  test('مسیر گزارش‌شدهٔ ابزار همان مسیر واقعی است، نه نام مستعار', () async {
    await AgentWorkspace.addDirectory(real.path);
    final alias = linkTo(real.path, p.join(temp.path, 'alias'));
    if (alias == null) return;

    final result = await const WriteFileTool().run(
      ToolCall(
        name: 'write_file',
        args: {'path': p.join(alias.path, 'new.txt'), 'content': 'x'},
      ),
      _context(),
    );

    expect(result.ok, isTrue);
    expect(File(p.join(real.path, 'new.txt')).existsSync(), isTrue);
    expect(
      result.changedPaths.single,
      AgentWorkspace.canonical(p.join(real.path, 'new.txt')),
    );
    expect(result.changedPaths.single, isNot(contains('alias')));
  });

  test('limit منفی به‌جای خطای خام، خروجی خالی می‌دهد', () async {
    await AgentWorkspace.addDirectory(real.path);
    final result = await const ReadFileTool().run(
      ToolCall(name: 'read_file', args: {'path': 'keep.txt', 'limit': -5}),
      _context(),
    );

    expect(result.ok, isTrue);
    expect(result.data['content'], '');
  });
}

ToolContext _context() => ToolContext(
  taskId: 'task_fs_guard',
  isCancelled: () => false,
  report: (_) {},
  ask: (_) async => null,
);
