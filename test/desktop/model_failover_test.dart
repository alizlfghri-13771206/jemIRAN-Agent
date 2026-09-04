import 'package:flutter_test/flutter_test.dart';
import 'package:jemiran/desktop/agent/core/model_adapter.dart';
import 'package:jemiran/desktop/agent/core/model_failover.dart';
import 'package:jemiran/desktop/agent/network/provider_exception.dart';

class _FakeAdapter extends ModelAdapter {
  _FakeAdapter(this.key, {this.failures = 0, this.error});

  final String key;

  final int failures;

  bool alwaysFail = false;

  final Object? error;

  int calls = 0;
  final List<String?> seenKeys = [];

  @override
  String get modelKey => key;

  @override
  Future<ModelTurn> send(ModelRequest request) async {
    calls++;
    seenKeys.add(request.idempotencyKey);
    if (alwaysFail || calls <= failures) {
      throw error ?? const ApiException('شلوغ', 503);
    }
    return ModelTurn(text: 'پاسخ از $key', sessionId: 7);
  }
}

void main() {
  _cooldownTests();
  const noDelay = Duration.zero;

  group('classifyFailure', () {
    test('سرور شلوغ گذراست', () {
      expect(
        classifyFailure(const ApiException('', 503)),
        FailureKind.transient,
      );
      expect(
        classifyFailure(const ApiException('', 500)),
        FailureKind.transient,
      );
    });

    test('سقف نرخ ارائه‌دهنده ردهٔ خودش را دارد', () {
      expect(
        classifyFailure(const ApiException('', 429)),
        FailureKind.rateLimited,
      );
    });

    test('قطع اتصال، تایم‌اوت و pending فقط با همان شناسه تکرار می‌شوند', () {
      expect(
        classifyFailure(const ApiException('', 504)),
        FailureKind.retryOnly,
      );
      expect(classifyFailure(const ApiException('', 0)), FailureKind.retryOnly);
      expect(
        classifyFailure(const ApiException('', 425)),
        FailureKind.retryOnly,
      );
    });

    test('خطای پرداخت یا دسترسی یعنی این ارائه‌دهنده کار نمی‌کند', () {
      expect(
        classifyFailure(const ApiException('', 402)),
        FailureKind.modelUnusable,
      );
      expect(
        classifyFailure(const ApiException('', 403)),
        FailureKind.modelUnusable,
      );
    });

    test('کلید مدلی که ارائه‌دهنده‌اش نیست، فقط همان مدل را می‌سوزاند', () {
      expect(
        classifyFailure(const ApiException('نیست', 403, code: 'model_missing')),
        FailureKind.modelUnusable,
      );
    });

    test('نشست منقضی با عوض کردن مدل حل نمی‌شود', () {
      expect(classifyFailure(const ApiException('', 401)), FailureKind.fatal);
      expect(classifyFailure(const ApiException('', 413)), FailureKind.fatal);
    });
  });

  group('FailoverModelAdapter', () {
    test('وقتی مدل اول جواب می‌دهد، هرگز سراغ بعدی نمی‌رود', () async {
      final made = <String, _FakeAdapter>{};
      final adapter = FailoverModelAdapter(
        chain: const ['ارزان', 'گران'],
        retryDelay: noDelay,
        create: (key, _) => made[key] = _FakeAdapter(key),
      );

      for (var i = 0; i < 5; i++) {
        final turn = await adapter.send(const ModelRequest(text: 'سلام'));
        expect(turn.text, 'پاسخ از ارزان');
      }

      expect(adapter.modelKey, 'ارزان');
      expect(adapter.hasSwitched, isFalse);
      expect(
        made.containsKey('گران'),
        isFalse,
        reason: 'مدل دوم نباید ساخته شود',
      );
    });

    test('خطای گذرا با همان مدل تکرار می‌شود، نه با مدل بعدی', () async {
      final made = <String, _FakeAdapter>{};
      final adapter = FailoverModelAdapter(
        chain: const ['اول', 'دوم'],
        retryDelay: noDelay,
        create: (key, _) =>
            made[key] = _FakeAdapter(key, failures: key == 'اول' ? 2 : 0),
      );

      final turn = await adapter.send(const ModelRequest(text: 'سلام'));

      expect(turn.text, 'پاسخ از اول');
      expect(made['اول']!.calls, 3, reason: 'دو شکست و بعد موفقیت');
      expect(adapter.hasSwitched, isFalse);
    });

    test('بعد از پر شدن سقف تلاش، مدل بعدی امتحان می‌شود', () async {
      final made = <String, _FakeAdapter>{};
      final notices = <String>[];
      final switches = <String>[];
      final adapter = FailoverModelAdapter(
        chain: const ['خراب', 'سالم'],
        maxAttemptsPerModel: 3,
        retryDelay: noDelay,
        onNotice: notices.add,
        onSwitched: (from, to) => switches.add('$from>$to'),
        create: (key, _) =>
            made[key] = _FakeAdapter(key, failures: key == 'خراب' ? 99 : 0),
      );

      final turn = await adapter.send(const ModelRequest(text: 'سلام'));

      expect(turn.text, 'پاسخ از سالم');
      expect(made['خراب']!.calls, 3, reason: 'دقیقاً سقف تلاش، نه بیشتر');
      expect(adapter.modelKey, 'سالم');
      expect(switches, ['خراب>سالم']);
      expect(
        notices.any((n) => n.contains('خراب') && n.contains('سالم')),
        isTrue,
        reason: 'کاربر باید بفهمد مدل عوض شده',
      );
    });

    test('خطای پرداخت فوراً مدل را عوض می‌کند، بدون تکرار بیهوده', () async {
      final made = <String, _FakeAdapter>{};
      final adapter = FailoverModelAdapter(
        chain: const ['گران', 'رایگان'],
        retryDelay: noDelay,
        create: (key, _) => made[key] = _FakeAdapter(
          key,
          failures: key == 'گران' ? 99 : 0,
          error: key == 'گران' ? const ApiException('پول کم', 402) : null,
        ),
      );

      final turn = await adapter.send(const ModelRequest(text: 'سلام'));

      expect(turn.text, 'پاسخ از رایگان');
      expect(
        made['گران']!.calls,
        1,
        reason: 'تکرار درخواستی که قطعاً ۴۰۲ می‌دهد فقط وقت تلف کردن است',
      );
    });

    test('خطای کشنده اصلاً مدل را عوض نمی‌کند', () async {
      final made = <String, _FakeAdapter>{};
      final adapter = FailoverModelAdapter(
        chain: const ['اول', 'دوم'],
        retryDelay: noDelay,
        create: (key, _) => made[key] = _FakeAdapter(
          key,
          failures: 99,
          error: const ApiException('نشست منقضی', 401),
        ),
      );

      await expectLater(
        adapter.send(const ModelRequest(text: 'سلام')),
        throwsA(isA<ApiException>()),
      );

      expect(made['اول']!.calls, 1);
      expect(made.containsKey('دوم'), isFalse);
    });

    test('تلاش دوبارهٔ یک مدل شناسهٔ یکسان می‌فرستد', () async {
      final made = <String, _FakeAdapter>{};
      final adapter = FailoverModelAdapter(
        chain: const ['اول'],
        retryDelay: noDelay,
        create: (key, _) => made[key] = _FakeAdapter(key, failures: 2),
      );

      await adapter.send(const ModelRequest(text: 'سلام'));

      final keys = made['اول']!.seenKeys;
      expect(keys.length, 3);
      expect(keys.toSet().length, 1, reason: 'هر سه تلاش یک شناسه دارند');
      expect(keys.first, isNotNull);
    });

    test('مدل بعدی شناسهٔ تازه می‌گیرد', () async {
      final made = <String, _FakeAdapter>{};
      final adapter = FailoverModelAdapter(
        chain: const ['خراب', 'سالم'],
        maxAttemptsPerModel: 2,
        retryDelay: noDelay,
        create: (key, _) =>
            made[key] = _FakeAdapter(key, failures: key == 'خراب' ? 99 : 0),
      );

      await adapter.send(const ModelRequest(text: 'سلام'));

      expect(
        made['سالم']!.seenKeys.first,
        isNot(made['خراب']!.seenKeys.first),
        reason: 'وگرنه ممکن است پاسخ کش‌شدهٔ مدل شکست‌خورده برگردد',
      );
    });

    test('نشست بین مدل‌ها حفظ می‌شود', () async {
      final made = <String, _FakeAdapter>{};
      final seenSessions = <int?>[];
      final adapter = FailoverModelAdapter(
        chain: const ['اول', 'دوم'],
        maxAttemptsPerModel: 1,
        retryDelay: noDelay,
        create: (key, sessionId) {
          seenSessions.add(sessionId);
          return made[key] = _FakeAdapter(key);
        },
      );

      await adapter.send(const ModelRequest(text: 'اول'));
      expect(adapter.modelKey, 'اول');

      made['اول']!.alwaysFail = true;
      await adapter.send(const ModelRequest(text: 'دوم'));

      expect(adapter.modelKey, 'دوم');
      expect(seenSessions.first, isNull, reason: 'اولی هنوز نشستی نداشت');
      expect(
        seenSessions.last,
        7,
        reason: 'مدل دوم باید همان نشست را ادامه بدهد',
      );
    });

    test(
      'قطع اینترنت تا ده بار با همان مدل و همان شناسه بازیابی می‌شود',
      () async {
        final made = <String, _FakeAdapter>{};
        final adapter = FailoverModelAdapter(
          chain: const ['اصلی', 'پشتیبان'],
          retryDelay: noDelay,
          create: (key, _) => made[key] = _FakeAdapter(
            key,
            failures: key == 'اصلی' ? 5 : 0,
            error: key == 'اصلی'
                ? const ApiException('اینترنت قطع است', 0)
                : null,
          ),
        );

        final turn = await adapter.send(const ModelRequest(text: 'ادامه'));

        expect(turn.text, 'پاسخ از اصلی');
        expect(made['اصلی']!.calls, 6);
        expect(made['اصلی']!.seenKeys.toSet().length, 1);
        expect(made.containsKey('پشتیبان'), isFalse);
      },
    );

    test('ده تلاش اتصال با همان شناسه، و تازه بعدش مدل بعدی', () async {
      final made = <String, _FakeAdapter>{};
      final adapter = FailoverModelAdapter(
        chain: const ['اصلی', 'پشتیبان'],
        retryDelay: noDelay,
        create: (key, _) => made[key] = _FakeAdapter(
          key,
          failures: 99,
          error: const ApiException('اینترنت قطع است', 0),
        ),
      );

      await expectLater(
        adapter.send(const ModelRequest(text: 'ادامه')),
        throwsA(isA<ApiException>()),
      );

      expect(made['اصلی']!.calls, 10);
      expect(
        made['اصلی']!.seenKeys.toSet().length,
        1,
        reason: 'ده تلاش اتصال نباید ده شناسهٔ متفاوت بسازد',
      );
      expect(made['پشتیبان']!.calls, 10);
      expect(
        made['پشتیبان']!.seenKeys.toSet().length,
        1,
        reason: 'مدل بعدی شناسهٔ تازهٔ خودش را دارد، ولی فقط یکی',
      );
      expect(
        made['اصلی']!.seenKeys.first == made['پشتیبان']!.seenKeys.first,
        isFalse,
        reason: 'شناسهٔ مدل دوم باید تازه باشد تا پاسخ کش‌شده برنگردد',
      );
    });

    test('عضو مردهٔ زنجیره نوبت را نمی‌کشد؛ مدل بعدی امتحان می‌شود', () async {
      final notices = <String>[];
      final switches = <String>[];
      final adapter = FailoverModelAdapter(
        chain: const ['حذف‌شده', 'سالم'],
        retryDelay: noDelay,
        onNotice: notices.add,
        onSwitched: (from, to) => switches.add('$from>$to'),
        create: (key, _) {
          if (key == 'حذف‌شده') {
            throw const ApiException(
              'ارائه‌دهندهٔ این مدل دیگر تنظیم نیست.',
              403,
              code: 'model_missing',
            );
          }
          return _FakeAdapter(key);
        },
      );

      final turn = await adapter.send(const ModelRequest(text: 'سلام'));

      expect(turn.text, 'پاسخ از سالم');
      expect(adapter.modelKey, 'سالم');
      expect(switches, ['حذف‌شده>سالم']);
      expect(notices.any((text) => text.contains('حذف‌شده')), isTrue);
    });

    test('عضو مرده دوباره امتحان نمی‌شود', () async {
      var attempts = 0;
      final adapter = FailoverModelAdapter(
        chain: const ['حذف‌شده', 'سالم'],
        retryDelay: noDelay,
        create: (key, _) {
          if (key == 'حذف‌شده') {
            attempts++;
            throw const ApiException('نیست', 403, code: 'model_missing');
          }
          return _FakeAdapter(key);
        },
      );

      await adapter.send(const ModelRequest(text: 'یک'));
      await adapter.send(const ModelRequest(text: 'دو'));

      expect(attempts, 1, reason: 'کلید مرده یک بار می‌سوزد و تمام');
    });

    test('وقتی همهٔ اعضا مرده‌اند، خطای خواندنی بیرون می‌آید', () async {
      final adapter = FailoverModelAdapter(
        chain: const ['حذف‌شده'],
        retryDelay: noDelay,
        create: (key, _) => throw const ApiException(
          'ارائه‌دهندهٔ این مدل دیگر تنظیم نیست؛ در تنظیمات دوباره اضافه‌اش کن.',
          403,
          code: 'model_missing',
        ),
      );

      await expectLater(
        adapter.send(const ModelRequest(text: 'سلام')),
        throwsA(
          isA<ApiException>().having(
            (error) => error.toString(),
            'متن',
            contains('در تنظیمات دوباره اضافه‌اش کن'),
          ),
        ),
      );
    });
  });

  group('buildFailoverChain', () {
    test('انتخاب اصلی همیشه اول است', () {
      final chain = buildFailoverChain(
        speaker: 'رایگان',
        members: const ['رایگان', 'متوسط', 'گران'],
      );
      expect(chain.first, 'رایگان');
    });

    test('بقیه دقیقاً با اولویت کاربر حفظ می‌شوند', () {
      final chain = buildFailoverChain(
        speaker: 'رایگان',
        members: const ['رایگان', 'متوسط', 'گران'],
      );
      expect(chain, ['رایگان', 'متوسط', 'گران']);
    });

    test('هیچ مدلی بیرون از میزگرد وارد زنجیره نمی‌شود', () {
      final chain = buildFailoverChain(
        speaker: 'متوسط',
        members: const ['متوسط', 'رایگان'],
      );
      expect(chain, ['متوسط', 'رایگان']);
      expect(chain.contains('گران'), isFalse);
    });

    test('مدل گوینده حتی پیش از reconcile زنجیره را خالی نمی‌گذارد', () {
      final chain = buildFailoverChain(
        speaker: 'انتخاب کاربر',
        members: const [],
      );
      expect(chain, ['انتخاب کاربر']);
    });

    test('میزگرد تک‌عضوی زنجیرهٔ تک‌عضوی می‌دهد', () {
      final chain = buildFailoverChain(
        speaker: 'گران',
        members: const ['گران'],
      );
      expect(chain, ['گران']);
    });
  });

  group('بودجهٔ زمانی بازیابی', () {
    test('تایم‌اوتِ کند، مسیر بازیابی را با سقف زمان می‌بندد', () async {
      final made = <String, _SlowFailingAdapter>{};
      final notices = <String>[];
      final adapter = FailoverModelAdapter(
        chain: const ['کند', 'سالم'],
        retryDelay: noDelay,
        maxRecoveryAttempts: 10,
        maxRecoveryDuration: const Duration(milliseconds: 120),
        onNotice: notices.add,
        create: (key, _) => made[key] = _SlowFailingAdapter(
          key,
          delay: key == 'کند'
              ? const Duration(milliseconds: 50)
              : Duration.zero,
          fail: key == 'کند',
        ),
      );

      final turn = await adapter.send(const ModelRequest(text: 'سلام'));

      expect(turn.text, 'پاسخ از سالم');
      expect(
        made['کند']!.calls,
        lessThan(10),
        reason: 'سقف زمان باید قبل از سقف تعداد فعال شود',
      );
      expect(notices.any((n) => n.contains('دقیقه برنگشت')), isTrue);
    });

    test(
      'وقتی مدل بعدی وجود ندارد، وعدهٔ امتحانِ مدل بعدی داده نمی‌شود',
      () async {
        final notices = <String>[];
        final adapter = FailoverModelAdapter(
          chain: const ['تنها'],
          retryDelay: noDelay,
          maxRecoveryAttempts: 10,
          maxRecoveryDuration: const Duration(milliseconds: 60),
          onNotice: notices.add,
          create: (key, _) => _SlowFailingAdapter(
            key,
            delay: const Duration(milliseconds: 40),
            fail: true,
          ),
        );

        await expectLater(
          adapter.send(const ModelRequest(text: 'سلام')),
          throwsA(isA<ApiException>()),
        );

        expect(
          notices.any((n) => n.contains('برنگشت')),
          isTrue,
          reason: 'کاربر باید بفهمد بودجهٔ زمانی تمام شد',
        );
        expect(
          notices.any((n) => n.contains('مدل بعدی امتحان می‌شود')),
          isFalse,
          reason: 'مدل بعدی‌ای وجود ندارد؛ این وعده دروغ است',
        );
      },
    );

    test('بازیابیِ سریع همچنان تا سقف تعداد ادامه می‌دهد', () async {
      final made = <String, _SlowFailingAdapter>{};
      final adapter = FailoverModelAdapter(
        chain: const ['کند'],
        retryDelay: noDelay,
        maxRecoveryAttempts: 4,
        maxRecoveryDuration: const Duration(seconds: 30),
        create: (key, _) => made[key] = _SlowFailingAdapter(
          key,
          delay: Duration.zero,
          fail: true,
        ),
      );

      await expectLater(
        adapter.send(const ModelRequest(text: 'سلام')),
        throwsA(isA<ApiException>()),
      );
      expect(made['کند']!.calls, 4);
    });
  });

  group('نشست بعد از فشرده‌سازی', () {
    test('مدل بعدی نشستِ دورانداخته را دوباره زنده نمی‌کند', () async {
      final seenSessions = <int?>[];
      final first = _FakeAdapter('first')..alwaysFail = true;
      final second = _FakeAdapter('second');
      final failover = FailoverModelAdapter(
        chain: const ['first', 'second'],
        initialSessionId: 42,
        create: (key, sessionId) {
          seenSessions.add(sessionId);
          return key == 'first' ? first : second;
        },
        maxAttemptsPerModel: 1,
        retryDelay: Duration.zero,
      );

      await failover.startFreshSession();
      await failover.send(const ModelRequest(text: 'ادامهٔ فشرده‌شده'));

      expect(
        seenSessions,
        everyElement(isNull),
        reason: 'هیچ مدلی نباید نشست دورانداخته را بگیرد',
      );
    });

    test('بدون فشرده‌سازی، نشست جاری به مدل بعدی می‌رسد', () async {
      final seenSessions = <int?>[];
      final first = _FakeAdapter('first')..alwaysFail = true;
      final second = _FakeAdapter('second');
      final failover = FailoverModelAdapter(
        chain: const ['first', 'second'],
        initialSessionId: 42,
        create: (key, sessionId) {
          seenSessions.add(sessionId);
          return key == 'first' ? first : second;
        },
        maxAttemptsPerModel: 1,
        retryDelay: Duration.zero,
      );

      await failover.send(const ModelRequest(text: 'سلام'));

      expect(seenSessions, [42, 42]);
    });
  });
}

class _SlowFailingAdapter extends ModelAdapter {
  _SlowFailingAdapter(this.key, {required this.delay, required this.fail});

  final String key;
  final Duration delay;
  final bool fail;
  int calls = 0;

  @override
  String get modelKey => key;

  @override
  Future<ModelTurn> send(ModelRequest request) async {
    calls++;
    if (delay > Duration.zero) await Future<void>.delayed(delay);
    if (fail) throw const ApiException('مهلت تمام شد', 504);
    return ModelTurn(text: 'پاسخ از $key', sessionId: 7);
  }
}

class _RateLimitedAdapter extends ModelAdapter {
  _RateLimitedAdapter(this.key, {this.retryAfter});

  final String key;
  final Duration? retryAfter;

  bool limited = true;
  int calls = 0;

  @override
  String get modelKey => key;

  @override
  Future<ModelTurn> send(ModelRequest request) async {
    calls++;
    if (limited) {
      throw ApiException('سقف نرخ', 429, retryAfter: retryAfter);
    }
    return ModelTurn(text: 'پاسخ از $key', sessionId: 7);
  }
}

void _cooldownTests() {
  group('سقف نرخ گذراست، نه دائمی', () {
    test(
      'بعد از پایان مهلت، نوبت بعدی به مدل انتخابی کاربر برمی‌گردد',
      () async {
        final first = _RateLimitedAdapter('first');
        final second = _RateLimitedAdapter('second')..limited = false;
        var clock = DateTime(2026, 1, 1, 12);

        final failover = FailoverModelAdapter(
          chain: const ['first', 'second'],
          create: (key, _) => key == 'first' ? first : second,
          maxAttemptsPerModel: 1,
          retryDelay: Duration.zero,
          defaultCooldown: const Duration(seconds: 60),
          now: () => clock,
        );

        final firstTurn = await failover.send(const ModelRequest(text: 'یک'));
        expect(
          firstTurn.text,
          'پاسخ از second',
          reason: 'باید موقتاً جابه‌جا شود',
        );

        first.limited = false;
        clock = clock.add(const Duration(seconds: 30));
        final during = await failover.send(const ModelRequest(text: 'دو'));
        expect(during.text, 'پاسخ از second', reason: 'داخل مهلت نباید برگردد');

        clock = clock.add(const Duration(seconds: 31));
        final after = await failover.send(const ModelRequest(text: 'سه'));
        expect(
          after.text,
          'پاسخ از first',
          reason: 'انتخاب اصلی کاربر باید خودکار برگردد',
        );
      },
    );

    test('مهلت اعلام‌شدهٔ سرور بر حدس پیش‌فرض مقدم است', () async {
      final first = _RateLimitedAdapter(
        'first',
        retryAfter: const Duration(seconds: 5),
      );
      final second = _RateLimitedAdapter('second')..limited = false;
      var clock = DateTime(2026, 1, 1, 12);

      final failover = FailoverModelAdapter(
        chain: const ['first', 'second'],
        create: (key, _) => key == 'first' ? first : second,
        maxAttemptsPerModel: 1,
        retryDelay: Duration.zero,
        defaultCooldown: const Duration(minutes: 30),
        now: () => clock,
      );

      await failover.send(const ModelRequest(text: 'یک'));
      first.limited = false;
      clock = clock.add(const Duration(seconds: 6));

      final after = await failover.send(const ModelRequest(text: 'دو'));
      expect(
        after.text,
        'پاسخ از first',
        reason: 'باید مهلت پنج‌ثانیه‌ای سرور را رعایت کند، نه سی دقیقه',
      );
    });

    test('ارائه‌دهندهٔ غیرقابل استفاده برخلاف سقف نرخ برنمی‌گردد', () async {
      var firstCalls = 0;
      final second = _RateLimitedAdapter('second')..limited = false;
      var clock = DateTime(2026, 1, 1, 12);

      final failover = FailoverModelAdapter(
        chain: const ['first', 'second'],
        create: (key, _) {
          if (key == 'second') return second;
          return _CountingUnusableAdapter(() => firstCalls++);
        },
        maxAttemptsPerModel: 1,
        retryDelay: Duration.zero,
        now: () => clock,
      );

      await failover.send(const ModelRequest(text: 'یک'));
      final callsAfterFirst = firstCalls;
      clock = clock.add(const Duration(hours: 2));
      await failover.send(const ModelRequest(text: 'دو'));

      expect(
        firstCalls,
        callsAfterFirst,
        reason: 'مدل سوخته حتی بعد از دو ساعت هم دوباره امتحان نمی‌شود',
      );
    });
  });
}

class _CountingUnusableAdapter extends ModelAdapter {
  _CountingUnusableAdapter(this.onCall);

  final void Function() onCall;

  @override
  String get modelKey => 'first';

  @override
  Future<ModelTurn> send(ModelRequest request) async {
    onCall();
    throw const ApiException('اعتبار API کافی نیست', 402);
  }
}
