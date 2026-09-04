import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:jemiran/desktop/agent/byok/byok_provider.dart';
import 'package:jemiran/desktop/agent/core/agent_storage.dart';
import 'package:jemiran/desktop/models/desktop_models_notifier.dart';

const _secret = 'sk-OFFLINE-VISIBILITY-71c3';

ByokProvider _provider() => ByokProvider(
  id: 'p1',
  kind: ByokProviderKind.openAi,
  label: 'کلید شخصی من',
  modelId: 'gpt-5.6-sol',
);

void main() {
  late Directory temp;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('jemiran-byok-visibility-');
    AgentStorage.setBaseRootForTesting(temp);
    AgentStorage.setAccountScope('offline-user@example.com');
    ByokStore.resetForTesting();
  });

  tearDown(() {
    AgentStorage.setBaseRootForTesting(null);
    ByokStore.resetForTesting();
    try {
      temp.deleteSync(recursive: true);
    } catch (_) {}
  });

  test(
    'مدل BYOK فقط از پیکربندی محلی در فهرست دیده می‌شود',
    () {
      ByokStore.save(_provider(), secret: _secret);

      final notifier = DesktopModelsNotifier();
      expect(notifier.state.models, isEmpty);

      notifier.refreshByokModels();

      expect(
        notifier.state.models.any((m) => m['byok'] == true),
        isTrue,
        reason: 'مدل با کلید شخصی فقط به پیکربندی محلی گره می‌خورد',
      );
    },
    skip: !Platform.isWindows,
  );

  test('تازه‌سازی BYOK وضعیت خطای قبلی را پاک نمی‌کند', () {
    ByokStore.save(_provider(), secret: _secret);

    final notifier = DesktopModelsNotifier();
    notifier.setErrorForTesting('کاتالوگ در دسترس نیست');

    notifier.refreshByokModels();

    expect(notifier.state.error, 'کاتالوگ در دسترس نیست');
    expect(notifier.state.models.any((m) => m['byok'] == true), isTrue);
  }, skip: !Platform.isWindows);
}
