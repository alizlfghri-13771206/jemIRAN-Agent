import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jemiran/desktop/agent/byok/byok_provider.dart';
import 'package:jemiran/desktop/agent/byok/byok_settings_card.dart';
import 'package:jemiran/desktop/agent/core/agent_storage.dart';

const _secret = 'sk-UI-SECRET-a71f';

Widget _host() => const ProviderScope(
  child: MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(child: ByokSettingsCard(isDark: false)),
    ),
  ),
);

void main() {
  late Directory temp;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('jemiran-byok-ui-');
    AgentStorage.setBaseRootForTesting(temp);
    AgentStorage.setAccountScope('ui-user@example.com');
    ByokStore.resetForTesting();
  });

  tearDown(() {
    AgentStorage.setBaseRootForTesting(null);
    ByokStore.resetForTesting();
    try {
      temp.deleteSync(recursive: true);
    } catch (_) {}
  });

  testWidgets('وقتی چیزی ثبت نشده، حالت خالی نشان داده می‌شود', (tester) async {
    await tester.pumpWidget(_host());
    expect(find.text('افزودن کلیدهای API'), findsOneWidget);
    expect(find.text('هنوز ارائه‌دهنده‌ای اضافه نکرده‌ای.'), findsOneWidget);
  });

  testWidgets('ارائه‌دهندهٔ ثبت‌شده با نشان «مستقیم» می‌آید', (tester) async {
    ByokStore.save(
      const ByokProvider(
        id: 'p1',
        kind: ByokProviderKind.anthropic,
        label: 'کلاد شخصی',
        modelId: 'claude-sonnet-5',
      ),
    );
    await tester.pumpWidget(_host());

    expect(find.text('کلاد شخصی'), findsOneWidget);
    expect(find.text('مستقیم'), findsOneWidget);
  });

  testWidgets('نبودِ کلید صریح اعلام می‌شود، نه اینکه وسط کار لو برود', (
    tester,
  ) async {
    ByokStore.save(
      const ByokProvider(
        id: 'p1',
        kind: ByokProviderKind.openAi,
        label: 'بدون کلید',
        modelId: 'gpt-5.6-sol',
      ),
    );
    await tester.pumpWidget(_host());
    expect(find.textContaining('کلید ندارد'), findsOneWidget);
  });

  testWidgets('کلید ذخیره‌شده هرگز در متن رابط ظاهر نمی‌شود', (tester) async {
    ByokStore.save(
      const ByokProvider(
        id: 'p1',
        kind: ByokProviderKind.openAi,
        label: 'با کلید',
        modelId: 'gpt-5.6-sol',
      ),
      secret: _secret,
    );
    await tester.pumpWidget(_host());

    final texts = tester
        .widgetList<Text>(find.byType(Text))
        .map((widget) => widget.data ?? '')
        .join(' | ');
    expect(texts, isNot(contains(_secret)));
    expect(texts, isNot(contains('UI-SECRET')));
    expect(find.textContaining('کلید ندارد'), findsNothing);
  }, skip: !Platform.isWindows);

  testWidgets('خاموش کردن کلید، ارائه‌دهنده را از فهرست آماده بیرون می‌برد', (
    tester,
  ) async {
    ByokStore.save(
      const ByokProvider(
        id: 'p1',
        kind: ByokProviderKind.openAi,
        label: 'کار',
        modelId: 'gpt-5.6-sol',
      ),
    );
    await tester.pumpWidget(_host());

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();

    expect(ByokStore.byId('p1')!.enabled, isFalse);
    expect(ByokStore.usable, isEmpty);
  });

  testWidgets('دیالوگ افزودن باز می‌شود و بدون شناسهٔ مدل ذخیره نمی‌کند', (
    tester,
  ) async {
    await tester.pumpWidget(_host());
    await tester.tap(find.text('افزودن'));
    await tester.pumpAndSettle();

    expect(find.text('افزودن API-KEY جدید'), findsOneWidget);

    await tester.tap(find.text('ذخیره'));
    await tester.pumpAndSettle();

    expect(find.text('شناسهٔ مدل لازم است.'), findsOneWidget);
    expect(ByokStore.providers, isEmpty, reason: 'نباید چیزی ثبت شده باشد');
  });

  testWidgets('امتحان کلید بدون کلید، به شبکه نمی‌رود', (tester) async {
    await tester.pumpWidget(_host());
    await tester.tap(find.text('افزودن'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('امتحان کلید'));
    await tester.pumpAndSettle();

    expect(find.text('اول کلید را وارد کن.'), findsOneWidget);
  });
}
