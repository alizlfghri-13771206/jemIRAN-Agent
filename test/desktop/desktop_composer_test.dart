import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jemiran/desktop/chat/desktop_composer.dart';
import 'package:jemiran/desktop/theme/desktop_tokens.dart';

void main() {
  test('composer از ستون پاسخ عریض‌تر است و مرکز آن ثابت می‌ماند', () {
    expect(
      WinMetrics.composerMaxWidth,
      greaterThan(WinMetrics.contentMaxWidth),
    );
  });

  testWidgets('دکمهٔ گسترش، فضای واقعی TextInput را باز و بسته می‌کند', (
    tester,
  ) async {
    tester.view
      ..physicalSize = const Size(1280, 800)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final controller = TextEditingController();
    final focusNode = FocusNode();
    addTearDown(controller.dispose);
    addTearDown(focusNode.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(fontFamily: 'vazir'),
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 900,
              child: DesktopComposer(
                controller: controller,
                focusNode: focusNode,
                isLoading: false,
                canSend: false,
                attachmentBusy: false,
                onSend: () {},
                onCancel: () {},
                onAttach: () {},
                onManageResources: () {},
                onSelectProject: (_) {},
                onRemoveResource: (_) {},
              ),
            ),
          ),
        ),
      ),
    );

    expect(tester.widget<TextField>(find.byType(TextField)).expands, isFalse);
    expect(find.byIcon(Icons.open_in_full_rounded), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('desktop_composer_expand')));
    await tester.pumpAndSettle();

    expect(tester.widget<TextField>(find.byType(TextField)).expands, isTrue);
    expect(find.byIcon(Icons.close_fullscreen_rounded), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
