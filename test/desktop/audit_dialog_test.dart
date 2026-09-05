import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jemiran/desktop/agent/audit/audit_dialog.dart';
import 'package:jemiran/desktop/agent/audit/audit_log.dart';
import 'package:jemiran/desktop/agent/core/agent_storage.dart';

Future<void> _open(WidgetTester tester) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => showAuditLogDialog(context),
              child: const Text('باز کن'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('باز کن'));
  await tester.pumpAndSettle();
}

void main() {
  late Directory temp;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('jemiran-audit-ui-');
    AgentStorage.setBaseRootForTesting(temp);
    AgentStorage.setAccountScope('audit-ui@example.com');
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

  testWidgets('دفتر خالی پیام روشن می‌دهد', (tester) async {
    await _open(tester);
    expect(find.text('تاریخچه فعالیت'), findsOneWidget);
    expect(find.text('ردیفی پیدا نشد.'), findsOneWidget);
  });

  testWidgets('ردیف‌ها با ابزار و هدف نشان داده می‌شوند', (tester) async {
    AuditLog.record(
      AuditKind.tool,
      model: 'anthropic/claude-opus-5',
      fields: {'tool': 'run_command', 'target': 'flutter test', 'ok': true},
    );
    await _open(tester);

    expect(find.text('run_command'), findsOneWidget);
    expect(find.text('flutter test'), findsOneWidget);
    expect(find.text('anthropic/claude-opus-5'), findsOneWidget);
  });

  testWidgets('جست‌وجو ردیف‌های نامرتبط را کنار می‌گذارد', (tester) async {
    AuditLog.record(AuditKind.tool, fields: {'tool': 'git', 'target': 'push'});
    AuditLog.record(
      AuditKind.tool,
      fields: {'tool': 'run_command', 'target': 'npm test'},
    );
    await _open(tester);
    expect(find.text('git'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'npm');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(find.text('git'), findsNothing);
    expect(find.text('run_command'), findsOneWidget);
  });

  testWidgets('کلیدی که ایجنت دیده، در نما ظاهر نمی‌شود', (tester) async {
    AuditLog.record(
      AuditKind.tool,
      fields: {
        'tool': 'run_command',
        'target': 'curl -H "Authorization: Bearer sk-UI-LEAK-4471"',
      },
    );
    await _open(tester);

    final texts = tester
        .widgetList<Text>(find.byType(Text))
        .map((widget) => widget.data ?? '')
        .join(' | ');
    expect(texts, isNot(contains('sk-UI-LEAK-4471')));
    expect(texts, contains('«حذف‌شده»'));
  });

  testWidgets('خروجیِ دفتر خالی، پنجرهٔ فایل باز نمی‌کند', (tester) async {
    await _open(tester);
    await tester.tap(find.text('دریافت خروجی فعالیت‌ها'));
    await tester.pumpAndSettle();
    expect(find.text('چیزی برای خروجی گرفتن نیست.'), findsOneWidget);
  });
}
