import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jemiran/desktop/chat/desktop_user_message.dart';
import 'package:jemiran/model/message.dart';
import 'package:jemiran/themes/jemiran_design.dart';

void main() {
  Future<void> pumpMessage(
    WidgetTester tester,
    String text, {
    double width = 724,
    VoidCallback? onResend,
  }) {
    return tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topCenter,
            child: SizedBox(
              width: width,
              child: DesktopUserMessage(
                message: Message(
                  id: '1787338440000000',
                  text: text,
                  isUser: true,
                ),
                onResend: onResend,
              ),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('پیام کوتاه جمع‌وجور و در سمت راست ستون گفتگو است', (
    tester,
  ) async {
    await pumpMessage(tester, 'بازش کن اپ رو');

    final surface = find.byKey(const ValueKey('desktop_user_bubble_surface'));
    final bubbleRect = tester.getRect(surface);
    final hostRect = tester.getRect(find.byType(DesktopUserMessage));

    expect(find.byType(JBubble), findsNothing);
    expect(bubbleRect.width, lessThan(hostRect.width * .5));
    expect(bubbleRect.right, closeTo(hostRect.right, .01));
    expect(bubbleRect.height, lessThan(90));
  });

  testWidgets('فونت پیام دقیقاً یک واحد از حباب موبایل کوچک‌تر است', (
    tester,
  ) async {
    await pumpMessage(tester, 'متن آزمایشی');

    final text = tester.widget<Text>(find.text('متن آزمایشی'));
    expect(desktopUserMessageFontSize, 14);
    expect(text.style?.fontSize, desktopUserMessageFontSize);
    expect(text.style?.fontFamily, 'vazir');
  });

  testWidgets('پیام بلند از سقف ۷۶ درصد فضای گفتگو عبور نمی‌کند', (
    tester,
  ) async {
    await pumpMessage(
      tester,
      List.filled(8, 'این یک پیام طولانی برای بررسی عرض حباب است').join(' '),
    );

    final bubbleRect = tester.getRect(
      find.byKey(const ValueKey('desktop_user_bubble_surface')),
    );
    final hostRect = tester.getRect(find.byType(DesktopUserMessage));

    expect(bubbleRect.width, lessThanOrEqualTo(hostRect.width * .76 + .01));
    expect(tester.takeException(), isNull);
  });

  testWidgets('اکشن‌های کوچک کپی و ارسال دوباره زیر حباب حاضرند', (
    tester,
  ) async {
    var resent = false;
    await pumpMessage(tester, 'دوباره بفرست', onResend: () => resent = true);

    expect(find.byIcon(Icons.copy_rounded), findsOneWidget);
    expect(find.byIcon(Icons.refresh_rounded), findsOneWidget);
    await tester.tap(find.byIcon(Icons.refresh_rounded));
    await tester.pump();
    expect(resent, isTrue);
  });
}
