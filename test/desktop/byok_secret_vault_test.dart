import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:jemiran/desktop/agent/byok/secret_vault.dart';
import 'package:jemiran/desktop/agent/core/agent_storage.dart';

void main() {
  late Directory temp;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('jemiran-byok-');
    AgentStorage.setBaseRootForTesting(temp);
    AgentStorage.setAccountScope('user-a@example.com');
  });

  tearDown(() {
    AgentStorage.setBaseRootForTesting(null);
    try {
      temp.deleteSync(recursive: true);
    } catch (_) {}
  });

  group('گاوصندوق کلید', () {
    test('کلید ذخیره و برگردانده می‌شود', () {
      SecretVault.write('anthropic', 'sk-ant-تست-۱۲۳');
      expect(SecretVault.read('anthropic'), 'sk-ant-تست-۱۲۳');
      expect(SecretVault.has('anthropic'), isTrue);
    }, skip: !Platform.isWindows);

    test('کلید خام هرگز روی دیسک نمی‌نشیند', () {
      const secret = 'sk-ant-VERY-SECRET-DO-NOT-LEAK-9f3a';
      SecretVault.write('anthropic', secret);

      final needle = secret.codeUnits;
      var scanned = 0;
      for (final entity in temp.listSync(recursive: true)) {
        if (entity is! File) continue;
        scanned++;
        final bytes = entity.readAsBytesSync();
        expect(
          _contains(bytes, needle),
          isFalse,
          reason: 'کلید خام در ${entity.path} پیدا شد',
        );
      }
      expect(scanned, greaterThan(0), reason: 'باید دست‌کم یک فایل نوشته شود');
    }, skip: !Platform.isWindows);

    test(
      'حساب دیگر روی همان ویندوز نمی‌تواند رازِ حساب اول را بخواند',
      () {
        SecretVault.write('shared-ref', 'راز-حساب-اول');
        expect(SecretVault.read('shared-ref'), 'راز-حساب-اول');

        AgentStorage.setAccountScope('user-b@example.com');
        expect(
          SecretVault.read('shared-ref'),
          isNull,
          reason: 'حساب دوم فضای خودش را دارد و نباید چیزی ببیند',
        );
      },
      skip: !Platform.isWindows,
    );

    test(
      'ciphertext دستکاری‌شده به‌جای پرتاب خطا، null می‌دهد',
      () {
        SecretVault.write('openai', 'sk-openai-۱');
        final file = File('${AgentStorage.root!.path}/byok_secrets.json');
        file.writeAsStringSync('{"openai":"bm90LXZhbGlkLWNpcGhlcnRleHQ="}');
        expect(SecretVault.read('openai'), isNull);
      },
      skip: !Platform.isWindows,
    );

    test('حذف و پاک‌سازی کامل کار می‌کنند', () {
      SecretVault.write('a', 'کلید-الف');
      SecretVault.write('b', 'کلید-ب');
      expect(SecretVault.refs(), {'a', 'b'});

      SecretVault.delete('a');
      expect(SecretVault.read('a'), isNull);
      expect(SecretVault.read('b'), 'کلید-ب');

      SecretVault.clear();
      expect(SecretVault.refs(), isEmpty);
      expect(SecretVault.read('b'), isNull);
    }, skip: !Platform.isWindows);

    test(
      'روی پلتفرم بدون ذخیره‌سازی امن، به متن ساده عقب‌نشینی نمی‌کند',
      () {
        expect(
          () => SecretVault.write('x', 'راز'),
          throwsA(isA<UnsupportedError>()),
        );
      },
      skip: Platform.isWindows,
    );
  });
}

bool _contains(List<int> haystack, List<int> needle) {
  if (needle.isEmpty || haystack.length < needle.length) return false;
  outer:
  for (var i = 0; i <= haystack.length - needle.length; i++) {
    for (var j = 0; j < needle.length; j++) {
      if (haystack[i + j] != needle[j]) continue outer;
    }
    return true;
  }
  return false;
}
