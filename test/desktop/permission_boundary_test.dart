import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:jemiran/desktop/agent/agent_workspace.dart';
import 'package:jemiran/desktop/agent/browser/browser_session.dart';
import 'package:jemiran/desktop/agent/core/agent_storage.dart';
import 'package:jemiran/desktop/agent/policy/agent_policy.dart';
import 'package:jemiran/desktop/agent/tools/agent_tool.dart';
import 'package:jemiran/desktop/agent/tools/filesystem_tools.dart';
import 'package:jemiran/desktop/agent/tools/git_tool.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory temp;
  late Directory project;
  late Directory vault;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    temp = await Directory.systemTemp.createTemp('jemiran_perm');
    project = Directory(p.join(temp.path, 'project'))..createSync();
    vault = Directory(p.join(temp.path, 'vault'))..createSync();
    File(p.join(project.path, 'a.txt')).writeAsStringSync('x');
    File(p.join(vault.path, 'secret.txt')).writeAsStringSync('y');
    await AgentWorkspace.clear();
  });

  tearDown(() async {
    await AgentWorkspace.clear();
    if (temp.existsSync()) temp.deleteSync(recursive: true);
  });

  group('move_path و اجازهٔ حذف', () {
    test('بردن فایل بیرون از منبعِ بدون اجازهٔ حذف رد می‌شود', () async {
      await AgentWorkspace.addDirectory(vault.path, canDelete: false);
      await AgentWorkspace.addDirectory(project.path, canDelete: true);

      const tool = MovePathTool();
      final deny = tool.hardDeny(
        ToolCall(
          name: 'move_path',
          args: {
            'from': p.join(vault.path, 'secret.txt'),
            'to': p.join(project.path, 'secret.txt'),
          },
        ),
      );

      expect(deny, isNotNull);
      expect(deny, contains('حذف'));
    });

    test('تغییر نام داخل همان منبع یک بازچینش است، نه حذف', () async {
      await AgentWorkspace.addDirectory(project.path, canDelete: false);
      const tool = MovePathTool();
      expect(
        tool.hardDeny(
          ToolCall(
            name: 'move_path',
            args: {
              'from': p.join(project.path, 'a.txt'),
              'to': p.join(project.path, 'sub', 'b.txt'),
            },
          ),
        ),
        isNull,
      );
    });

    test('با اجازهٔ حذف، بردن به منبع دیگر مجاز می‌شود', () async {
      await AgentWorkspace.addDirectory(vault.path, canDelete: true);
      await AgentWorkspace.addDirectory(project.path);
      const tool = MovePathTool();
      expect(
        tool.hardDeny(
          ToolCall(
            name: 'move_path',
            args: {
              'from': p.join(vault.path, 'secret.txt'),
              'to': p.join(project.path, 'secret.txt'),
            },
          ),
        ),
        isNull,
      );
    });
  });

  group('Git و مجوزِ کنش', () {
    const git = GitTool();

    test('کنش خواندنی مجوز خواندن می‌خواهد', () {
      expect(
        git.permissionOf(
          ToolCall(name: 'git', args: const {'action': 'status'}),
        ),
        Perm.gitRead,
      );
      expect(
        git.permissionOf(ToolCall(name: 'git', args: const {'action': 'diff'})),
        Perm.gitRead,
      );
    });

    test('کنش نویسنده مجوز نوشتن می‌خواهد', () {
      for (final action in ['checkpoint', 'restore']) {
        expect(
          git.permissionOf(ToolCall(name: 'git', args: {'action': action})),
          Perm.gitWrite,
          reason: action,
        );
      }
    });

    test('restore روی پوشهٔ فقط‌خواندنی رد قطعی می‌شود', () async {
      await AgentWorkspace.addDirectory(project.path, canWrite: false);
      final deny = git.hardDeny(
        ToolCall(
          name: 'git',
          args: {'action': 'restore', 'path': project.path, 'ref': 'a' * 40},
        ),
      );
      expect(deny, isNotNull);
      expect(deny, contains('نوشتن'));
    });

    test('status روی همان پوشهٔ فقط‌خواندنی مجاز می‌ماند', () async {
      await AgentWorkspace.addDirectory(project.path, canWrite: false);
      expect(
        git.hardDeny(
          ToolCall(
            name: 'git',
            args: {'action': 'status', 'path': project.path},
          ),
        ),
        isNull,
      );
    });

    test('اجازهٔ نشستِ خواندن، کنش نویسنده را باز نمی‌کند', () {
      const state = AgentPolicyState(
        mode: AgentMode.autonomous,
        sessionGrants: {Perm.gitRead},
      );
      final verdict = state.evaluate(
        tool: git,
        call: ToolCall(name: 'git', args: const {'action': 'restore'}),
      );
      expect(verdict.outcome, PolicyOutcome.ask);
    });
  });

  group('ایزولاسیون نشست مرورگر', () {
    test('هر scope نشست خودش را دارد', () {
      final a = BrowserSession.of('acc1:work_a');
      final b = BrowserSession.of('acc1:work_b');
      final again = BrowserSession.of('acc1:work_a');

      expect(identical(a, b), isFalse);
      expect(identical(a, again), isTrue, reason: 'همان scope همان نشست');
      expect(a.scope, 'acc1:work_a');
    });

    test('حساب متفاوت یعنی نشست متفاوت', () {
      final one = BrowserSession.of('acc1:work_a');
      final two = BrowserSession.of('acc2:work_a');
      expect(identical(one, two), isFalse);
    });

    test('scope فعال از Zone خوانده می‌شود', () async {
      expect(BrowserSession.currentScope, 'default');
      final seen = await BrowserSession.runScoped(
        'acc1:work_x',
        () async => BrowserSession.currentScope,
      );
      expect(seen, 'acc1:work_x');
      expect(BrowserSession.currentScope, 'default');
    });

    test('کلید scope حساب و Work را با هم دارد', () {
      final key = '${AgentStorage.accountKey}:work_1';
      expect(key, contains(AgentStorage.accountKey));
      expect(key, endsWith('work_1'));
    });
  });
}
