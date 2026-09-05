import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jemiran/desktop/settings/desktop_settings_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          SystemChannels.platform,
          (call) async => null,
        );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  testWidgets('تنظیمات ویندوز در لپ‌تاپ دو ستونه و بدون overflow است', (
    tester,
  ) async {
    tester.view
      ..physicalSize = const Size(1366, 768)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: DesktopSettingsScreen())),
    );
    await tester.pump();

    expect(find.text('تنظیمات جمیران ایجنت'), findsOneWidget);
    expect(find.text('تنظیمات'), findsOneWidget);
    expect(find.text('تنظیمات مخصوص ویندوز'), findsNothing);
    expect(find.text('jemIRAN.app@gmail.com'), findsOneWidget);
    expect(find.textContaining('ایمیل :'), findsNothing);
    expect(find.byTooltip('کپی ایمیل'), findsOneWidget);
    expect(find.text('مخازن و ریپازیتوری‌ها'), findsOneWidget);
    expect(
      find.text('مخازن و یا ریپوهای مورد استفاده شما تا کنون'),
      findsNothing,
    );
    expect(find.text('به‌روزرسانی و مشاهده'), findsOneWidget);
    expect(find.text('نسخهٔ مستقل ویندوز برای کار روی پروژه‌ها'), findsNothing);
    expect(find.text('معماری ایجنت، مدل‌ها و حریم خصوصی'), findsNothing);
    expect(find.text('روشن'), findsOneWidget);
    expect(find.text('تیره'), findsOneWidget);

    final copyButton = find.widgetWithIcon(
      IconButton,
      Icons.content_copy_rounded,
    );
    expect(copyButton, findsOneWidget);
    await tester.ensureVisible(copyButton);
    await tester.tap(copyButton);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('ایمیل پشتیبانی کپی شد.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
