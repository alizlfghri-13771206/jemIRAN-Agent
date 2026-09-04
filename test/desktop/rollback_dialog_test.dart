import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jemiran/desktop/agent/core/agent_task.dart';
import 'package:jemiran/desktop/agent/widgets/rollback_dialog.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  AgentTask taskWithChanges() =>
      AgentTask(goal: 'اصلاح تست‌ها')
        ..changedPaths.addAll([r'C:\proj\lib\a.dart', r'C:\proj\lib\b.dart']);

  Future<void> open(WidgetTester tester, AgentTask task, List<bool> box) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              box.add(await showTaskRollbackDialog(context, task));
            },
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('فهرست مسیرهایی که برمی‌گردند نشان داده می‌شود', (tester) async {
    await open(tester, taskWithChanges(), []);

    expect(find.textContaining('a.dart'), findsOneWidget);
    expect(find.textContaining('b.dart'), findsOneWidget);
    expect(find.textContaining('2 مسیر'), findsOneWidget);
  });

  testWidgets('انصراف یعنی «نه»، نه یک بازگشتِ مبهم', (tester) async {
    final outcome = <bool>[];
    await open(tester, taskWithChanges(), outcome);
    await tester.tap(find.text('انصراف'));
    await tester.pumpAndSettle();

    expect(outcome.single, isFalse);
  });

  testWidgets('بستن دیالوگ با کلیک بیرون هم «نه» است', (tester) async {
    final outcome = <bool>[];
    await open(tester, taskWithChanges(), outcome);
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();

    expect(outcome.single, isFalse);
  });

  testWidgets('تأیید صریح همان را برمی‌گرداند', (tester) async {
    final outcome = <bool>[];
    await open(tester, taskWithChanges(), outcome);
    await tester.tap(find.text('بله، برگردان'));
    await tester.pumpAndSettle();

    expect(outcome.single, isTrue);
  });
}
