import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:jemiran/desktop/chat/session_title_coordinator.dart';

void main() {
  test('sidebar فقط بعد از ذخیره موفق عنوان تازه می‌شود', () async {
    final coordinator = SessionTitleCoordinator();
    final gate = Completer<void>();
    var refreshes = 0;

    final result = coordinator.generate(
      sessionId: 7,
      request: () => gate.future,
      onChanged: () => refreshes++,
    );

    expect(refreshes, 0);
    gate.complete();
    expect(await result, isTrue);
    expect(refreshes, 1);
  });

  test('شکست موقت عنوان‌گذاری اجازه تلاش دوباره می‌دهد', () async {
    final coordinator = SessionTitleCoordinator();
    var attempts = 0;
    var refreshes = 0;

    final first = await coordinator.generate(
      sessionId: 9,
      request: () async {
        attempts++;
        throw StateError('temporary');
      },
      onChanged: () => refreshes++,
    );
    final second = await coordinator.generate(
      sessionId: 9,
      request: () async => attempts++,
      onChanged: () => refreshes++,
    );

    expect(first, isFalse);
    expect(second, isTrue);
    expect(attempts, 2);
    expect(refreshes, 1);
  });
}
