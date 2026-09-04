import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:jemiran/desktop/agent/byok/byok_provider.dart';
import 'package:jemiran/desktop/agent/byok/secret_vault.dart';
import 'package:jemiran/desktop/agent/core/agent_storage.dart';

const _secret = 'sk-STORE-SECRET-e91d';

ByokProvider _provider({String id = 'p1', bool enabled = true}) => ByokProvider(
  id: id,
  kind: ByokProviderKind.openAi,
  label: 'کار روزانه',
  modelId: 'gpt-5.6-sol',
  enabled: enabled,
);

void main() {
  late Directory temp;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('jemiran-byok-store-');
    AgentStorage.setBaseRootForTesting(temp);
    AgentStorage.setAccountScope('store-user@example.com');
    ByokStore.resetForTesting();
  });

  tearDown(() {
    AgentStorage.setBaseRootForTesting(null);
    ByokStore.resetForTesting();
    try {
      temp.deleteSync(recursive: true);
    } catch (_) {}
  });

  group('ذخیره‌گاه ارائه‌دهنده', () {
    test('پیکربندی بعد از restart برمی‌گردد', () {
      ByokStore.save(_provider());
      ByokStore.resetForTesting();

      final loaded = ByokStore.byId('p1');
      expect(loaded, isNotNull);
      expect(loaded!.modelId, 'gpt-5.6-sol');
      expect(loaded.kind, ByokProviderKind.openAi);
    });

    test('فایل پیکربندی هرگز کلید را ندارد', () {
      ByokStore.save(_provider(), secret: _secret);
      final file = File('${AgentStorage.root!.path}/byok_providers.json');
      expect(file.readAsStringSync(), isNot(contains(_secret)));
      expect(ByokStore.exportJson(), isNot(contains(_secret)));
      expect(SecretVault.read('byok:p1'), _secret);
    }, skip: !Platform.isWindows);

    test('حذف ارائه‌دهنده کلیدش را هم می‌برد', () {
      ByokStore.save(_provider(), secret: _secret);
      expect(SecretVault.has('byok:p1'), isTrue);

      ByokStore.remove('p1');
      expect(ByokStore.byId('p1'), isNull);
      expect(SecretVault.has('byok:p1'), isFalse);
    }, skip: !Platform.isWindows);

    test('ارائه‌دهندهٔ بدون کلید «آماده» شمرده نمی‌شود', () {
      ByokStore.save(_provider(id: 'no-key'));
      expect(ByokStore.providers, hasLength(1));
      expect(ByokStore.usable, isEmpty);

      ByokStore.save(_provider(id: 'no-key'), secret: _secret);
      expect(ByokStore.usable, hasLength(1));
    }, skip: !Platform.isWindows);

    test('ارائه‌دهندهٔ غیرفعال در فهرست آماده نیست', () {
      ByokStore.save(_provider(enabled: false));
      expect(ByokStore.usable, isEmpty);
    });

    test('فایل خراب، ورود به برنامه را نمی‌بندد', () {
      File(
        '${AgentStorage.root!.path}/byok_providers.json',
      ).writeAsStringSync('{ این JSON نیست');
      ByokStore.resetForTesting();
      expect(ByokStore.providers, isEmpty);
    });

    test('سقف تعداد ارائه‌دهنده رعایت می‌شود', () {
      for (var i = 0; i < ByokStore.maxProviders; i++) {
        ByokStore.save(_provider(id: 'p$i'));
      }
      expect(
        () => ByokStore.save(_provider(id: 'overflow')),
        throwsA(isA<StateError>()),
      );
    });

    test('آدرس پایه برای ارائه‌دهندهٔ شناخته‌شده پیش‌فرض درست دارد', () {
      expect(_provider().effectiveBaseUrl, 'https://api.openai.com/v1');
      const custom = ByokProvider(
        id: 'c',
        kind: ByokProviderKind.custom,
        label: 'محلی',
        modelId: 'llama',
        baseUrl: 'http://127.0.0.1:11434/v1/',
      );
      expect(custom.effectiveBaseUrl, 'http://127.0.0.1:11434/v1');
    });

    test('قالب سیمی از نوع ارائه‌دهنده مشتق می‌شود', () {
      expect(
        ByokProviderKind.anthropic.wireFormat,
        ByokWireFormat.anthropicMessages,
      );
      for (final kind in const [
        ByokProviderKind.openAi,
        ByokProviderKind.deepSeek,
        ByokProviderKind.openRouter,
        ByokProviderKind.gemini,
        ByokProviderKind.custom,
      ]) {
        expect(kind.wireFormat, ByokWireFormat.openAiCompatible);
      }
    });

    test('نوع ناشناخته به سفارشی برمی‌گردد، نه خطا', () {
      expect(
        ByokProviderKind.parse('provider_from_future'),
        ByokProviderKind.custom,
      );
      expect(ByokProviderKind.parse(null), ByokProviderKind.custom);
    });

    test('کلید مدل BYOK با کلید مدل سرور تصادم نمی‌کند', () {
      final provider = _provider(id: 'p1');
      expect(provider.modelKey, 'byok:p1');
      expect(ByokProvider.isByokKey('byok:p1'), isTrue);
      expect(ByokProvider.isByokKey('anthropic/claude-sonnet-5'), isFalse);
      expect(ByokProvider.isByokKey(null), isFalse);
    });

    test('کلید مدل به همان ارائه‌دهنده برمی‌گردد', () {
      ByokStore.save(_provider(id: 'p1'));
      expect(ByokStore.byModelKey('byok:p1')?.id, 'p1');
      expect(ByokStore.byModelKey('anthropic/claude-sonnet-5'), isNull);
      expect(ByokStore.byModelKey('byok:ناموجود'), isNull);
    });

    test('ردیف فهرست مدل فقط داده‌های محلی لازم را دارد', () {
      final entry = ByokStore.modelEntry(_provider(id: 'p1'));
      expect(entry['key'], 'byok:p1');
      expect(entry['agent_model'], isTrue);
      expect(entry['byok'], isTrue);
      expect(entry['max_context_tokens'], ByokProvider.defaultContextTokens);
      expect(entry['enabled'], isTrue);
      expect(entry.containsKey('can_use'), isFalse);
      expect(entry.containsKey('in_plan'), isFalse);
    });

    test('سقف زمینهٔ دلخواه ذخیره و بازخوانی می‌شود', () {
      ByokStore.save(_provider(id: 'p1').copyWith(contextTokens: 200000));
      ByokStore.resetForTesting();
      expect(ByokStore.byId('p1')!.contextTokens, 200000);
    });

    test('حساب دیگر، فهرست ارائه‌دهندهٔ حساب قبلی را نمی‌بیند', () {
      ByokStore.save(_provider(id: 'a1'));
      expect(ByokStore.providers, hasLength(1));

      AgentStorage.setAccountScope('other-user@example.com');
      expect(
        ByokStore.providers,
        isEmpty,
        reason: 'کش باید با عوض شدن حساب خودکار بی‌اعتبار شود',
      );

      AgentStorage.setAccountScope('store-user@example.com');
      expect(ByokStore.providers, hasLength(1));
    });

    test('JSON رفت‌وبرگشت پایدار است', () {
      const original = ByokProvider(
        id: 'p9',
        kind: ByokProviderKind.deepSeek,
        label: 'دیپ‌سیک',
        modelId: 'deepseek-chat',
        headers: {'x-team': 'jemiran'},
        enabled: false,
      );
      final back = ByokProvider.fromJson(
        jsonDecode(jsonEncode(original.toJson())) as Map<String, dynamic>,
      );
      expect(back.id, original.id);
      expect(back.kind, original.kind);
      expect(back.modelId, original.modelId);
      expect(back.headers, original.headers);
      expect(back.enabled, isFalse);
    });
  });
}
