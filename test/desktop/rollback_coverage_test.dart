import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jemiran/desktop/agent/core/agent_engine.dart';
import 'package:jemiran/desktop/agent/core/agent_task.dart';
import 'package:jemiran/desktop/agent/core/model_adapter.dart';
import 'package:jemiran/desktop/agent/policy/agent_policy.dart';
import 'package:jemiran/desktop/agent/tools/agent_tool.dart';
import 'package:jemiran/desktop/agent/tools/git_tool.dart';
import 'package:jemiran/desktop/agent/tools/install_package_tool.dart';
import 'package:jemiran/desktop/agent/tools/terminal_tool.dart';
import 'package:jemiran/desktop/agent/tools/tool_registry.dart';
import 'package:jemiran/desktop/agent/widgets/rollback_dialog.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('اعلام پوشش checkpoint', () {
    test('ابزارهای پرخطر صادقانه می‌گویند snapshot نمی‌گیرند', () {
      expect(const RunCommandTool().checkpointsChanges, isFalse);
      expect(const InstallPackageTool().checkpointsChanges, isFalse);
      expect(const GitTool().checkpointsChanges, isFalse);
    });

    test('پیش‌فرض قرارداد، «قابل بازگرداندن» است', () {
      expect(_Plain().checkpointsChanges, isTrue);
    });
  });

  group('شمارش تغییرات بی‌پوشش', () {
    test('اجرای موفقِ ابزار بی‌checkpoint شمرده می‌شود', () async {
      final engine = _engine(ToolRegistry.of([_Untracked()]));
      final task = await engine.run('یک فرمان بزن');

      expect(task.untrackedChanges, 1);
      expect(task.hasUntrackedChanges, isTrue);
      await engine.dispose();
    });

    test('ابزار قابل‌بازگردانی چیزی به شمارنده اضافه نمی‌کند', () async {
      final engine = _engine(ToolRegistry.of([_Tracked()]));
      final task = await engine.run('یک فایل بنویس');

      expect(task.untrackedChanges, 0);
      expect(task.hasUntrackedChanges, isFalse);
      await engine.dispose();
    });

    test('شمارنده بعد از restart هم می‌ماند', () {
      final task = AgentTask(goal: 'کار')..untrackedChanges = 3;
      expect(AgentTask.fromJson(task.toJson()).untrackedChanges, 3);
    });
  });

  group('دیالوگ بازگرداندن', () {
    Future<void> open(WidgetTester tester, AgentTask task) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => showTaskRollbackDialog(context, task),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    testWidgets('وقتی پوشش ناقص است، صریح هشدار می‌دهد', (tester) async {
      final task = AgentTask(goal: 'کار')
        ..changedPaths.add(r'C:\proj\a.dart')
        ..untrackedChanges = 2;
      await open(tester, task);

      expect(find.textContaining('کامل نیست'), findsOneWidget);
      expect(find.textContaining('2 عملیات'), findsOneWidget);
    });

    testWidgets('وقتی همه‌چیز پوشش دارد، هشدار اضافه نمی‌آورد', (tester) async {
      final task = AgentTask(goal: 'کار')..changedPaths.add(r'C:\proj\a.dart');
      await open(tester, task);

      expect(find.textContaining('کامل نیست'), findsNothing);
    });
  });
}

AgentEngine _engine(ToolRegistry registry) => AgentEngine(
  model: _OneCall(),
  registry: registry,
  readPolicy: () => const AgentPolicyState(enabled: true),
  onGrant: (_, _) {},
  requestPermission: (_, _) async => PermissionDecision.allowOnce,
  askQuestion: (_) async => null,
);

class _OneCall extends ModelAdapter {
  int _turn = 0;

  @override
  String get modelKey => 'one';

  @override
  Future<ModelTurn> send(ModelRequest request) async => ModelTurn(
    text: _turn++ == 0
        ? '```jemiran_tool\n{"tool": "act", "args": {}}\n```'
        : 'تمام شد.',
  );
}

class _Plain extends AgentTool {
  @override
  String get name => 'plain';
  @override
  String get label => 'ساده';
  @override
  ToolRisk get risk => ToolRisk.write;
  @override
  String get permission => 'test.plain';
  @override
  String get signature => 'plain {}';

  @override
  ToolPreview preview(ToolCall call) => const ToolPreview(title: 'ساده');

  @override
  Future<ToolResult> run(ToolCall call, ToolContext context) async =>
      ToolResult.success(summary: 'ok');
}

class _Untracked extends AgentTool {
  @override
  String get name => 'act';
  @override
  String get label => 'اجرا';
  @override
  ToolRisk get risk => ToolRisk.execute;
  @override
  String get permission => 'test.act';
  @override
  String get signature => 'act {}';
  @override
  bool get checkpointsChanges => false;

  @override
  ToolPreview preview(ToolCall call) => const ToolPreview(title: 'اجرا');

  @override
  Future<ToolResult> run(ToolCall call, ToolContext context) async =>
      ToolResult.success(summary: 'انجام شد');
}

class _Tracked extends AgentTool {
  @override
  String get name => 'act';
  @override
  String get label => 'نوشتن';
  @override
  ToolRisk get risk => ToolRisk.write;
  @override
  String get permission => 'test.act';
  @override
  String get signature => 'act {}';

  @override
  ToolPreview preview(ToolCall call) => const ToolPreview(title: 'نوشتن');

  @override
  Future<ToolResult> run(ToolCall call, ToolContext context) async =>
      ToolResult.success(
        summary: 'نوشته شد',
        changedPaths: const [r'C:\proj\a.dart'],
      );
}
