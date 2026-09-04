import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jemiran/desktop/agent/core/agent_task.dart';
import 'package:jemiran/desktop/chat/desktop_ai_message.dart';

Widget _wrap(Widget child) => MaterialApp(
  theme: ThemeData.dark(),
  home: Scaffold(body: SingleChildScrollView(child: child)),
);

void main() {
  group('تایمر نشانگر فعالیت', () {
    testWidgets('زمان سپری‌شده نشان داده و هر ثانیه به‌روز می‌شود', (
      tester,
    ) async {
      final start = DateTime(2026, 1, 1, 12);
      var fake = start.add(const Duration(seconds: 5));

      await tester.pumpWidget(
        _wrap(
          DesktopAiLoading(
            phase: AgentPhase.thinking,
            model: 'test/model',
            startedAt: start,
            clock: () => fake,
          ),
        ),
      );
      expect(find.text('5s'), findsOneWidget);

      fake = start.add(const Duration(seconds: 6));
      await tester.pump(const Duration(seconds: 1));
      expect(
        find.text('6s'),
        findsOneWidget,
        reason: 'تیک تایمر باید باعث رندر دوباره شود',
      );
    });

    testWidgets('بیش از یک دقیقه به شکل «۲m 5s» نوشته می‌شود', (tester) async {
      await tester.pumpWidget(
        _wrap(
          DesktopAiLoading(
            phase: AgentPhase.executing,
            model: 'test/model',
            startedAt: DateTime(2026, 1, 1, 12),
            clock: () => DateTime(2026, 1, 1, 12, 2, 5),
          ),
        ),
      );
      expect(find.text('2m 5s'), findsOneWidget);
    });

    testWidgets('بدون زمان شروع، هیچ تایمری نشان داده نمی‌شود', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const DesktopAiLoading(
            phase: AgentPhase.thinking,
            model: 'test/model',
          ),
        ),
      );
      expect(find.textContaining(RegExp(r'^\d+s$')), findsNothing);
    });

    testWidgets('تایمر بعد از dispose متوقف می‌شود', (tester) async {
      await tester.pumpWidget(
        _wrap(
          DesktopAiLoading(
            phase: AgentPhase.thinking,
            model: 'test/model',
            startedAt: DateTime.now(),
          ),
        ),
      );
      await tester.pumpWidget(_wrap(const SizedBox.shrink()));
      await tester.pump(const Duration(seconds: 2));
    });
  });

  group('نام مدل', () {
    testWidgets('مدلِ در حال اجرا نشان داده می‌شود', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const DesktopAiLoading(
            phase: AgentPhase.thinking,
            model: 'z-ai/glm-5.3-flash',
          ),
        ),
      );
      expect(find.textContaining('glm'), findsWidgets);
    });
  });

  group('برچسب فاز', () {
    testWidgets('فاز اجرا با نام عملیات نمایش داده می‌شود', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const DesktopAiLoading(
            phase: AgentPhase.executing,
            model: 'test/model',
            action: 'اجرای فرمان',
          ),
        ),
      );
      expect(find.textContaining('اجرای فرمان'), findsOneWidget);
    });
  });
}
