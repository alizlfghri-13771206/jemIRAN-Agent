import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:jemiran/desktop/agent/core/agent_process.dart';

void main() {
  final onWindows = Platform.isWindows;

  group('مهلت واقعاً فرآیند را می‌کشد', () {
    test(
      'فرآیند خواب بعد از مهلت زنده نمی‌ماند',
      () async {
        if (!onWindows) return;

        final started = DateTime.now();
        final result = await AgentProcess.run('powershell.exe', const [
          '-NoProfile',
          '-NonInteractive',
          '-Command',
          'Start-Sleep -Seconds 60',
        ], timeout: const Duration(seconds: 2));
        final elapsed = DateTime.now().difference(started);

        expect(result.timedOut, isTrue);
        expect(result.exitCode, AgentProcess.timedOutExitCode);
        expect(elapsed.inSeconds, lessThan(20));
      },
      timeout: const Timeout(Duration(seconds: 60)),
    );

    test(
      'فرآیندی که خودش تمام می‌شود، کد خروج واقعی می‌دهد',
      () async {
        if (!onWindows) return;

        final result = await AgentProcess.run('powershell.exe', const [
          '-NoProfile',
          '-NonInteractive',
          '-Command',
          'exit 3',
        ], timeout: const Duration(seconds: 20));

        expect(result.timedOut, isFalse);
        expect(result.exitCode, 3);
      },
      timeout: const Timeout(Duration(seconds: 60)),
    );

    test(
      'خروجی جمع می‌شود و خط‌به‌خط هم پخش می‌شود',
      () async {
        if (!onWindows) return;

        final lines = <String>[];
        final result = await AgentProcess.run(
          'powershell.exe',
          const [
            '-NoProfile',
            '-NonInteractive',
            '-Command',
            r'Write-Output "yek"; Write-Output "do"',
          ],
          timeout: const Duration(seconds: 20),
          onLine: lines.add,
        );

        expect(result.exitCode, 0);
        expect(result.stdout, contains('yek'));
        expect(result.stdout, contains('do'));
        expect(lines, containsAll(<String>['yek', 'do']));
      },
      timeout: const Timeout(Duration(seconds: 60)),
    );

    test(
      'لغو وسط کار، فرآیند را می‌بندد',
      () async {
        if (!onWindows) return;

        var cancelled = false;
        Future<void>.delayed(
          const Duration(seconds: 1),
          () => cancelled = true,
        );

        final started = DateTime.now();
        final result = await AgentProcess.run(
          'powershell.exe',
          const [
            '-NoProfile',
            '-NonInteractive',
            '-Command',
            'Start-Sleep -Seconds 60',
          ],
          timeout: const Duration(seconds: 45),
          isCancelled: () => cancelled,
        );
        final elapsed = DateTime.now().difference(started);

        expect(result.timedOut, isFalse, reason: 'مهلت نبود، لغو بود');
        expect(elapsed.inSeconds, lessThan(20));
      },
      timeout: const Timeout(Duration(seconds: 90)),
    );
  });

  group('قرارداد', () {
    test('کد مهلت از کد خروجِ واقعی متمایز است', () {
      expect(AgentProcess.timedOutExitCode, 124);
      expect(AgentProcess.timedOutExitCode, isNot(0));
      expect(AgentProcess.timedOutExitCode, isNot(-1));
    });
  });
}
