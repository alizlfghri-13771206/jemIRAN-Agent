import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jemiran/desktop/shell/desktop_state.dart';
import 'package:jemiran/desktop/shell/sidebar_resize_handle.dart';
import 'package:jemiran/desktop/theme/desktop_tokens.dart';
import 'package:shared_preferences/shared_preferences.dart';

Widget _harness(ProviderContainer container) => UncontrolledProviderScope(
  container: container,
  child: MaterialApp(
    home: Scaffold(
      body: Directionality(
        textDirection: TextDirection.ltr,
        child: Consumer(
          builder: (context, ref, _) => Row(
            children: [
              SizedBox(width: ref.watch(sidebarWidthProvider)),
              const SidebarResizeHandle(isDark: true),
              const Expanded(child: SizedBox()),
            ],
          ),
        ),
      ),
    ),
  ),
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('کشیدن دستگیره عرض را عوض می‌کند', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await tester.pumpWidget(_harness(container));

    expect(container.read(sidebarWidthProvider), WinMetrics.sidebarWidth);

    await tester.drag(find.byType(SidebarResizeHandle), const Offset(60, 0));
    await tester.pumpAndSettle();

    expect(
      container.read(sidebarWidthProvider),
      greaterThan(WinMetrics.sidebarWidth),
    );
  });

  testWidgets('عرض از حدهای امن بیرون نمی‌زند', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await tester.pumpWidget(_harness(container));

    final notifier = container.read(sidebarWidthProvider.notifier);

    notifier.set(10);
    expect(container.read(sidebarWidthProvider), SidebarWidthNotifier.minWidth);

    notifier.set(5000);
    expect(container.read(sidebarWidthProvider), SidebarWidthNotifier.maxWidth);
    await tester.pumpAndSettle();
  });

  test('reset عرض را به پیش‌فرض برمی‌گرداند و ذخیره می‌کند', () async {
    SharedPreferences.setMockInitialValues({});
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final notifier = container.read(sidebarWidthProvider.notifier);
    notifier.set(400);
    expect(container.read(sidebarWidthProvider), 400);

    notifier.reset();
    expect(container.read(sidebarWidthProvider), WinMetrics.sidebarWidth);

    await notifier.persist();
    final prefs = await SharedPreferences.getInstance();
    expect(
      prefs.getDouble('desktop_sidebar_width_v1'),
      WinMetrics.sidebarWidth,
    );
  });

  test('عرض ذخیره‌شده در اجرای بعدی برمی‌گردد', () async {
    SharedPreferences.setMockInitialValues({'desktop_sidebar_width_v1': 360.0});
    final container = ProviderContainer();
    addTearDown(container.dispose);

    expect(container.read(sidebarWidthProvider), WinMetrics.sidebarWidth);
    await Future<void>.delayed(Duration.zero);
    expect(container.read(sidebarWidthProvider), 360.0);
  });

  test('مقدار ذخیره‌شدهٔ خارج از حد هم clamp می‌شود', () async {
    SharedPreferences.setMockInitialValues({
      'desktop_sidebar_width_v1': 9000.0,
    });
    final container = ProviderContainer();
    addTearDown(container.dispose);

    container.read(sidebarWidthProvider);
    await Future<void>.delayed(Duration.zero);
    expect(container.read(sidebarWidthProvider), SidebarWidthNotifier.maxWidth);
  });
}
