import 'dart:io';

import 'package:jemiran/desktop/agent/byok/byok_adapter.dart';
import 'package:jemiran/desktop/agent/byok/byok_provider.dart';
import 'package:jemiran/desktop/agent/byok/secret_vault.dart';
import 'package:jemiran/desktop/agent/core/agent_storage.dart';
import 'package:jemiran/desktop/agent/core/model_adapter.dart';
import 'package:jemiran/desktop/agent/core/model_failover.dart';
import 'package:jemiran/desktop/agent/network/provider_exception.dart';

int _passed = 0;
int _failed = 0;

void check(String name, bool ok, [String? detail]) {
  if (ok) {
    _passed++;
    stdout.writeln('  OK   $name${detail == null ? '' : '  ($detail)'}');
  } else {
    _failed++;
    stdout.writeln('  FAIL $name${detail == null ? '' : '  ->  $detail'}');
  }
}

const _deadKey = 'byok:byok_removed_provider';
const _probeTools = <Map<String, dynamic>>[
  {
    'type': 'function',
    'function': {
      'name': 'release_probe',
      'description': 'ابزار آزمایشی که در این درخواست نباید فراخوانی شود.',
      'parameters': {
        'type': 'object',
        'properties': <String, dynamic>{},
        'additionalProperties': false,
      },
    },
  },
];

ModelAdapter _create(String modelKey, int? sessionId) {
  final byok = ByokStore.byModelKey(modelKey);
  if (byok == null) {
    throw ApiException(
      'ارائه‌دهندهٔ این مدل دیگر تنظیم نیست؛ در تنظیمات دوباره اضافه‌اش کن.',
      403,
      code: 'model_missing',
    );
  }
  return ByokModelAdapter(
    provider: byok,
    maxOutputTokens: byok.maxOutputTokens,
  );
}

Future<void> main() async {
  AgentStorage.setAccountScope('windows-local');
  ByokStore.load();

  stdout.writeln('\n[1] ذخیره‌گاه ارائه‌دهنده');
  final providers = ByokStore.providers;
  final usable = ByokStore.usable;
  check('گاوصندوق روی این سیستم پشتیبانی می‌شود', SecretVault.isSupported);
  check(
    'ارائه‌دهنده ثبت شده',
    providers.isNotEmpty,
    '${providers.length} مورد',
  );
  check('ارائه‌دهندهٔ آماده وجود دارد', usable.isNotEmpty, '${usable.length}');
  if (usable.isEmpty) {
    stdout.writeln('\nهیچ ارائه‌دهندهٔ آماده‌ای نیست؛ ادامه ممکن نیست.');
    exit(1);
  }

  final live = usable.first;
  stdout.writeln(
    '      ${live.kind.label} / ${live.modelId} / کلید مدل: ${live.modelKey}',
  );
  check('کلید در گاوصندوق باز می‌شود', live.hasSecret);
  check(
    'کلید مدل به همان ارائه‌دهنده برمی‌گردد',
    ByokStore.byModelKey(live.modelKey)?.id == live.id,
  );

  stdout.writeln('\n[2] کلیدِ مردهٔ همان خطای گزارش‌شده');
  check(
    'کلید مرده هنوز به هیچ ارائه‌دهنده‌ای نمی‌رسد',
    ByokStore.byModelKey(_deadKey) == null,
  );
  var threw = false;
  try {
    _create(_deadKey, null);
  } on ApiException catch (error) {
    threw = true;
    check(
      'خطا خواندنی است، نه «Bad state»',
      !error.toString().startsWith('Bad state') &&
          error.code == 'model_missing',
      error.toString(),
    );
    check(
      'دسته‌بندی‌اش «این مدل قابل استفاده نیست» است',
      classifyFailure(error) == FailureKind.modelUnusable,
    );
  }
  check('ساختن درگاه برای کلید مرده استثنا می‌دهد', threw);

  stdout.writeln('\n[3] زنجیرهٔ failover با کلید مرده در ابتدا');
  final notices = <String>[];
  final switches = <String>[];
  final failover = FailoverModelAdapter(
    chain: [_deadKey, live.modelKey],
    retryDelay: Duration.zero,
    create: _create,
    onNotice: notices.add,
    onSwitched: (from, to) => switches.add('$from > $to'),
  );

  final deltas = StringBuffer();
  ModelTurn? turn;
  Object? failure;
  try {
    turn = await failover.send(
      ModelRequest(
        text: 'فقط و فقط بنویس: سلام. هیچ چیز دیگری ننویس.',
        tools: _probeTools,
        onDelta: deltas.write,
      ),
    );
  } catch (error) {
    failure = error;
  }

  check('نوبت با وجود کلید مرده شکست نخورد', failure == null, '$failure');
  check('به مدل سالم سوییچ شد', switches.isNotEmpty, switches.join(' | '));
  check('کاربر از سوییچ باخبر شد', notices.isNotEmpty, notices.join(' | '));

  stdout.writeln('\n[4] درخواست واقعی به ارائه‌دهندهٔ خودِ کاربر');
  check('پاسخ خالی نیست', (turn?.text ?? '').trim().isNotEmpty);
  check('استریم زنده کار کرد', deltas.isNotEmpty, '${deltas.length} نویسه');
  if (turn != null) {
    stdout.writeln('      پاسخ: ${turn.text.trim()}');
  }
  stdout.writeln('\n[5] نوبت دوم روی همان نشست');
  try {
    final second = await failover.send(
      const ModelRequest(text: 'حالا فقط بنویس: خداحافظ.'),
    );
    check('نوبت دوم هم جواب گرفت', second.text.trim().isNotEmpty);
    stdout.writeln('      پاسخ: ${second.text.trim()}');
  } catch (error) {
    check('نوبت دوم هم جواب گرفت', false, '$error');
  }
  await failover.dispose();

  if (usable.length > 1) {
    stdout.writeln('\n[6] بررسی مستقیم سایر ارائه‌دهنده‌های ثبت‌شده');
    for (final candidate in usable.skip(1)) {
      final adapter = ByokModelAdapter(
        provider: candidate,
        maxOutputTokens: candidate.maxOutputTokens,
      );
      try {
        final candidateTurn = await adapter.send(
          const ModelRequest(
            text: 'فقط و فقط بنویس: سلام. هیچ چیز دیگری ننویس.',
            tools: _probeTools,
          ),
        );
        check(
          '${candidate.label} با schema ابزار پاسخ می‌دهد',
          candidateTurn.text.trim().isNotEmpty,
          candidateTurn.text.trim(),
        );
      } catch (error) {
        final detail = error is ApiException
            ? '$error (HTTP ${error.statusCode}${error.code == null ? '' : ', code=${error.code}'})'
            : '$error';
        check('${candidate.label} با schema ابزار پاسخ می‌دهد', false, detail);
      } finally {
        await adapter.dispose();
      }
    }
  }

  stdout.writeln('\n$_passed موفق، $_failed ناموفق');
  exit(_failed == 0 ? 0 : 1);
}
