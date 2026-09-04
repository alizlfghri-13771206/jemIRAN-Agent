import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jemiran/desktop/agent/core/agent_task.dart';
import 'package:jemiran/desktop/chat/desktop_ai_message.dart';
import 'package:jemiran/model/message.dart';
import 'package:jemiran/themes/jemiran_design.dart';
import 'package:jemiran/ui/screens/chat_room/widgets/model_config.dart';

void main() {
  setUp(() {
    ModelConfig.ingest(const [
      {'key': 'deepseek/deepseek-v3.2', 'label': 'DeepSeek V3.2'},
      {'key': 'qwen/qwen3-coder', 'label': 'Qwen3 Coder'},
    ]);
  });

  testWidgets('پاسخ AI دسکتاپ بدون bubble، آواتار، مدل و ساعت است', (
    tester,
  ) async {
    final message = Message(
      id: 'message-without-timestamp',
      text: 'این پاسخ آزاد و تمام‌عرض است.',
      isUser: false,
      aiSource: 'deepseek_v32',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 780,
            child: DesktopAiMessage(
              message: message,
              typingMessageId: null,
              isLoading: false,
              isSelecting: false,
              onReply: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(DesktopAiMessage), findsOneWidget);
    expect(find.byType(JBubble), findsNothing);
    expect(find.text('DeepSeek V3.2'), findsNothing);
    expect(find.byType(Image), findsNothing, reason: 'آواتار مدل نباید باشد');
    expect(find.textContaining('این پاسخ آزاد'), findsOneWidget);
  });

  testWidgets('حالت انتظار سه نقطه، وضعیت واقعی و فونت وزیر دارد', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 780,
            child: DesktopAiLoading(
              phase: AgentPhase.thinking,
              model: 'deepseek/deepseek-v3.2',
            ),
          ),
        ),
      ),
    );

    expect(find.text('· در حال فکر کردن'), findsOneWidget);
    expect(find.text('DeepSeek V3.2'), findsOneWidget);
    expect(find.text('در حال تحلیل'), findsNothing);
    expect(find.textContaining('در حال تفکر'), findsNothing);
    expect(find.byType(JTypingDots), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byType(JBubble), findsNothing);
    expect(find.byType(Image), findsNothing);

    final status = tester.widget<Text>(find.text('· در حال فکر کردن'));
    expect(status.style?.fontFamily, 'vazir');
    expect(
      tester.getTopLeft(find.byType(JTypingDots)).dx,
      lessThan(10),
      reason: 'Loading باید در لبهٔ چپ فضای پیام قرار بگیرد.',
    );
  });

  testWidgets('متن loading از عملیات واقعی موتور می‌آید', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: DesktopAiLoading(
            phase: AgentPhase.executing,
            model: 'qwen/qwen3-coder',
            action: 'خواندن فایل · lib/main.dart',
          ),
        ),
      ),
    );

    expect(find.text('· در حال خواندن فایل · lib/main.dart'), findsOneWidget);
    expect(find.text('Qwen3 Coder'), findsOneWidget);
    expect(find.byType(JTypingDots), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });
}
