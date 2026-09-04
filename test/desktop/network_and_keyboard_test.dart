import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jemiran/desktop/agent/network/agent_environment.dart';
import 'package:jemiran/desktop/agent/network/proxy_detector.dart';
import 'package:jemiran/desktop/shell/keyboard_guard.dart';

void main() {
  group('محیط شبکهٔ فرآیندها', () {
    tearDown(() => AgentEnvironment.config = const AgentNetworkConfig());

    test('پروکسی دستی در همهٔ نام‌های متغیر نوشته می‌شود', () async {
      AgentEnvironment.config = const AgentNetworkConfig(
        mode: ProxyMode.manual,
        manualUrl: 'http://127.0.0.1:10809',
      );

      final env = await AgentEnvironment.build();

      for (final key in const [
        'HTTP_PROXY',
        'http_proxy',
        'HTTPS_PROXY',
        'https_proxy',
        'ALL_PROXY',
        'all_proxy',
        'npm_config_proxy',
        'npm_config_https_proxy',
      ]) {
        expect(
          env[key],
          'http://127.0.0.1:10809',
          reason: '$key تنظیم نشده — ابزاری که این را می‌خواند شکست می‌خورد',
        );
      }
    });

    test('میزبان محلی هرگز از پروکسی رد نمی‌شود', () async {
      AgentEnvironment.config = const AgentNetworkConfig(
        mode: ProxyMode.manual,
        manualUrl: 'http://127.0.0.1:10809',
      );

      final env = await AgentEnvironment.build();
      expect(env['NO_PROXY'], contains('localhost'));
      expect(env['NO_PROXY'], contains('127.0.0.1'));
      expect(env['no_proxy'], contains('localhost'));
    });

    test('حالت خاموش متغیرهای ارثی را هم پاک می‌کند', () async {
      AgentEnvironment.config = const AgentNetworkConfig(mode: ProxyMode.off);

      final env = await AgentEnvironment.build();
      expect(env.containsKey('HTTP_PROXY'), isFalse);
      expect(env.containsKey('http_proxy'), isFalse);
      expect(env.containsKey('npm_config_proxy'), isFalse);
    });

    test('نشانی دستی نامعتبر بی‌صدا به پروکسی محیط برنمی‌گردد', () async {
      AgentEnvironment.config = const AgentNetworkConfig(
        mode: ProxyMode.manual,
        manualUrl: 'یک چیز بی‌معنی',
      );

      final env = await AgentEnvironment.build();
      expect(env.containsKey('HTTP_PROXY'), isFalse);
      expect(AgentEnvironment.manualUrlIsValid, isFalse);

      final described = await AgentEnvironment.describe();
      expect(
        described['warning'],
        isNotNull,
        reason: 'کاربر باید بفهمد نشانی‌اش پذیرفته نشده',
      );
    });

    test('آینه‌ها فقط وقتی کاربر تنظیم کند نوشته می‌شوند', () async {
      AgentEnvironment.config = const AgentNetworkConfig(mode: ProxyMode.off);
      var env = await AgentEnvironment.build();
      expect(env.containsKey('PUB_HOSTED_URL'), isFalse);
      expect(env.containsKey('npm_config_registry'), isFalse);

      AgentEnvironment.config = const AgentNetworkConfig(
        mode: ProxyMode.off,
        pubMirror: 'https://example.test',
        pipIndex: 'https://pypi.example.test/simple',
      );
      env = await AgentEnvironment.build();
      expect(env['PUB_HOSTED_URL'], 'https://example.test');
      expect(env['FLUTTER_STORAGE_BASE_URL'], 'https://example.test');
      expect(
        env.containsKey('PIP_TRUSTED_HOST'),
        isFalse,
        reason: 'نباید بررسی گواهی TLS برای آینه غیرفعال شود',
      );
    });

    test('PATH و بقیهٔ محیط دست‌نخورده می‌مانند', () async {
      AgentEnvironment.config = const AgentNetworkConfig(mode: ProxyMode.off);
      final env = await AgentEnvironment.build();
      final hasPath = env.keys.any((k) => k.toUpperCase() == 'PATH');
      expect(hasPath, isTrue);
    });

    test('در حالت خودکار، پروکسیِ ارث‌رسیده از شِل به فرزند می‌رسد', () async {
      AgentEnvironment.config = const AgentNetworkConfig(mode: ProxyMode.auto);
      final env = await AgentEnvironment.build(
        parentEnvironment: const {
          'PATH': r'C:\tools',
          'HTTP_PROXY': 'http://127.0.0.1:10809',
          'http_proxy': 'http://127.0.0.1:10809',
        },
      );

      expect(env.containsKey('HTTP_PROXY'), isTrue);
      expect(env['HTTP_PROXY'], isNotEmpty);
    });

    test('در حالت خاموش، پروکسیِ ارث‌رسیده حذف می‌شود', () async {
      AgentEnvironment.config = const AgentNetworkConfig(mode: ProxyMode.off);
      final env = await AgentEnvironment.build(
        parentEnvironment: const {
          'PATH': r'C:\tools',
          'HTTP_PROXY': 'http://127.0.0.1:10809',
        },
      );

      expect(env.containsKey('HTTP_PROXY'), isFalse);
      expect(env['PATH'], r'C:\tools');
    });

    test('secretهای محیط والد به ابزارها ارث داده نمی‌شوند', () {
      final env = AgentEnvironment.sanitizedEnvironment({
        'PATH': r'C:\tools',
        'TEMP': r'C:\temp',
        'OPENAI_API_KEY': 'secret',
        'JEMIRAN_TOKEN': 'secret',
        'NODE_OPTIONS': r'--require C:\evil.js',
      });

      expect(env['PATH'], r'C:\tools');
      expect(env['TEMP'], r'C:\temp');
      expect(env.containsKey('OPENAI_API_KEY'), isFalse);
      expect(env.containsKey('JEMIRAN_TOKEN'), isFalse);
      expect(env.containsKey('NODE_OPTIONS'), isFalse);
    });

    test('طرح ناامن یا credential داخل proxy URL پذیرفته نمی‌شود', () {
      for (final url in const [
        'ftp://proxy.example.test:21',
        'http://user:pass@proxy.example.test:8080',
      ]) {
        AgentEnvironment.config = AgentNetworkConfig(
          mode: ProxyMode.manual,
          manualUrl: url,
        );
        expect(AgentEnvironment.manualUrlIsValid, isFalse, reason: url);
      }
    });

    test('بلیت پروکسی در محیط استفاده می‌شود اما در گزارش نشت نمی‌کند', () {
      const proxy = DetectedProxy(
        host: 'proxy.example.test',
        port: 8000,
        source: 'test',
        username: 'jemiran',
        password: 'secret-ticket',
      );

      expect(proxy.url, contains('secret-ticket'));
      expect(proxy.toJson().toString(), isNot(contains('secret-ticket')));
      expect(proxy.displayUrl, 'http://proxy.example.test:8000');
    });
  });

  group('مهار باگ صفحه‌کلید ویندوز', () {
    FlutterErrorDetails details(
      String message, {
      String library = 'services library',
    }) => FlutterErrorDetails(exception: message, library: library);

    test('همان assert شناخته‌شده تشخیص داده می‌شود', () {
      expect(
        WindowsKeyboardGuard.matchesForTest(
          details(
            "A KeyDownEvent is dispatched, but the state shows that the "
            "physical key is already pressed. Failed assertion: "
            "'!_pressedKeys.containsKey(event.physicalKey)'",
          ),
        ),
        isTrue,
      );
    });

    test('خطای دیگرِ همان کتابخانه بلعیده نمی‌شود', () {
      expect(
        WindowsKeyboardGuard.matchesForTest(
          details('PlatformException: channel unavailable'),
        ),
        isFalse,
      );
      expect(
        WindowsKeyboardGuard.matchesForTest(
          details('A KeyDownEvent is dispatched'),
        ),
        isFalse,
        reason: 'فقط بخشی از نشانه‌ها کافی نیست',
      );
    });

    test('خطای کتابخانهٔ دیگر بلعیده نمی‌شود', () {
      expect(
        WindowsKeyboardGuard.matchesForTest(
          details(
            "KeyDownEvent already pressed _pressedKeys",
            library: 'widgets library',
          ),
        ),
        isFalse,
      );
    });
  });
}
