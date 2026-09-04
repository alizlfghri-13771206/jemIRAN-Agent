import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jemiran/desktop/agent/widgets/agent_home.dart';
import 'package:jemiran/riverpod/user_notifier.dart';

void main() {
  testWidgets('خانه ایجنت نام سرور و توضیح لوکال را وسط‌چین نشان می‌دهد', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          userProvider.overrideWith(
            (ref) => UserNotifier()..setUsername('علی'),
          ),
        ],
        child: const MaterialApp(home: Scaffold(body: AgentHome())),
      ),
    );

    final title = tester.widget<Text>(
      find.text('سلام علی، به جمیران ایجنت خوش اومدی'),
    );
    final description = tester.widget<Text>(
      find.textContaining('تمامی اطلاعات شما از جمله پروژه‌ها'),
    );

    expect(title.textAlign, TextAlign.center);
    expect(description.textAlign, TextAlign.center);
    expect(find.text('بررسی پروژه'), findsNothing);
    expect(find.text('رفع خطای build'), findsNothing);
    expect(find.text('اجرای تست'), findsNothing);
    expect(find.text('مرور تغییرات'), findsNothing);
  });
}
