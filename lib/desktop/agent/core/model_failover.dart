import 'dart:async';
import 'dart:math';

import '../network/provider_exception.dart';
import 'model_adapter.dart';

enum FailureKind { transient, modelUnusable, retryOnly, rateLimited, fatal }

FailureKind classifyFailure(Object error) {
  if (error is! ApiException) {
    return FailureKind.transient;
  }
  switch (error.code) {
    case 'request_pending':
      return FailureKind.retryOnly;
    case 'model_missing':
      return FailureKind.modelUnusable;
    case 'context_limit':
      return FailureKind.fatal;
  }
  if (error.isUnauthorized) return FailureKind.fatal;
  if (error.isTooLarge) return FailureKind.fatal;
  if (error.isPaymentRequired) return FailureKind.modelUnusable;
  if (error.isForbidden) return FailureKind.modelUnusable;
  if (error.isNoInternet || error.isTimeout || error.statusCode == 425) {
    return FailureKind.retryOnly;
  }
  if (error.statusCode == 429) return FailureKind.rateLimited;
  if (error.isProviderBusy) return FailureKind.transient;
  if (error.statusCode >= 500) return FailureKind.transient;
  return FailureKind.fatal;
}

class FailoverReconnectState {
  const FailoverReconnectState({
    required this.modelKey,
    required this.attempt,
    required this.maxAttempts,
    required this.message,
    this.nextModelKey,
  });

  final String modelKey;

  final int attempt;
  final int maxAttempts;
  final String message;

  final String? nextModelKey;

  bool get canSkip => nextModelKey != null;
}

class FailoverModelAdapter extends ModelAdapter {
  FailoverModelAdapter({
    required List<String> chain,
    required this.create,
    int? initialSessionId,
    this.maxAttemptsPerModel = 3,
    this.maxRecoveryAttempts = 10,
    this.maxRecoveryDuration = const Duration(minutes: 3),
    this.retryDelay = const Duration(milliseconds: 900),
    this.defaultCooldown = const Duration(seconds: 60),
    this.onNotice,
    this.onSwitched,
    this.onReconnect,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now,
       assert(chain.isNotEmpty, 'زنجیرهٔ مدل نمی‌تواند خالی باشد'),
       _chain = List.unmodifiable(chain),
       _lastSessionId = initialSessionId;

  final List<String> _chain;

  final ModelAdapter Function(String modelKey, int? sessionId) create;

  final int maxAttemptsPerModel;

  final int maxRecoveryAttempts;

  final Duration maxRecoveryDuration;

  final Duration retryDelay;

  final void Function(String message)? onNotice;

  final void Function(String from, String to)? onSwitched;

  final void Function(FailoverReconnectState? state)? onReconnect;

  int _index = 0;
  int _attemptGroup = 0;

  int? _lastSessionId;
  ModelAdapter? _active;
  String? _activeKey;
  bool _cancelled = false;

  Completer<void>? _skipSignal;
  bool _skipRequested = false;

  final Set<String> _burned = {};

  final DateTime Function() _now;

  final Duration defaultCooldown;

  final Map<String, DateTime> _cooldownUntil = {};

  bool _isCoolingDown(String key) {
    final until = _cooldownUntil[key];
    if (until == null) return false;
    if (_now().isBefore(until)) return true;
    _cooldownUntil.remove(key);
    return false;
  }

  void _rewindToPreferred() {
    for (var i = 0; i < _index; i++) {
      final key = _chain[i];
      if (_burned.contains(key) || _isCoolingDown(key)) continue;
      onNotice?.call('«$key» دوباره در دسترس است؛ ادامه با همان.');
      _index = i;
      return;
    }
  }

  @override
  String get modelKey => _chain[_index];

  bool get hasSwitched => _index > 0;

  bool get canSkipToNextModel => _nextUsableIndex(_index + 1) != null;

  void skipToNextModel() {
    if (!canSkipToNextModel) return;
    _skipRequested = true;
    final signal = _skipSignal;
    if (signal != null && !signal.isCompleted) signal.complete();
  }

  Future<void> _interruptibleDelay(Duration duration) async {
    if (_skipRequested) return;
    final signal = Completer<void>();
    _skipSignal = signal;
    try {
      await Future.any([Future<void>.delayed(duration), signal.future]);
    } finally {
      if (identical(_skipSignal, signal)) _skipSignal = null;
    }
  }

  Future<ModelAdapter> _adapterFor(String key) async {
    if (_activeKey == key && _active != null) return _active!;
    await _active?.dispose();
    _active = null;
    _activeKey = null;
    final adapter = create(key, _lastSessionId);
    _active = adapter;
    _activeKey = key;
    return adapter;
  }

  @override
  Future<ModelTurn> send(ModelRequest request) async {
    _cancelled = false;
    _skipRequested = false;
    _rewindToPreferred();

    try {
      return await _sendAcrossChain(request);
    } finally {
      onReconnect?.call(null);
    }
  }

  Future<ModelTurn> _sendAcrossChain(ModelRequest request) async {
    Object? lastError;

    for (var m = _index; m < _chain.length; m++) {
      final key = _chain[m];
      if (_burned.contains(key)) continue;

      _index = m;
      _skipRequested = false;

      final ModelAdapter adapter;
      try {
        adapter = await _adapterFor(key);
      } catch (error) {
        lastError = error;
        _burned.add(key);
        final next = _nextUsableIndex(m + 1);
        onNotice?.call(
          next == null
              ? '«$key» دیگر قابل استفاده نیست و مدل دیگری در مسیر '
                    'اولویت شما نمانده.'
              : '«$key» دیگر قابل استفاده نیست. ادامه با «${_chain[next]}».',
        );
        if (next != null) onSwitched?.call(key, _chain[next]);
        continue;
      }

      final idempotencyKey =
          '${RequestIds.next()}_${_attemptGroup++}_${_entropy()}';

      var transientAttempts = 0;
      var recoveryAttempts = 0;
      Stopwatch? recoveryClock;
      for (;;) {
        if (_cancelled) throw StateError('لغو شد');

        try {
          request.onAttemptStart?.call();
          final turn = await adapter.send(
            request.withIdempotencyKey(idempotencyKey),
          );
          _lastSessionId = turn.sessionId ?? _lastSessionId;
          onReconnect?.call(null);
          return turn;
        } catch (error) {
          if (_cancelled) rethrow;
          lastError = error;
          final kind = classifyFailure(error);

          if (kind == FailureKind.fatal) rethrow;

          if (kind == FailureKind.modelUnusable) {
            _burned.add(key);
            break;
          }

          if (_skipRequested) break;

          if (kind == FailureKind.retryOnly) {
            recoveryClock ??= Stopwatch()..start();
            recoveryAttempts++;
            final outOfTime = recoveryClock.elapsed >= maxRecoveryDuration;
            if (recoveryAttempts >= maxRecoveryAttempts || outOfTime) {
              if (outOfTime) {
                final hasNext = _nextUsableIndex(m + 1) != null;
                onNotice?.call(
                  hasNext
                      ? 'اتصال در ${maxRecoveryDuration.inMinutes} دقیقه '
                            'برنگشت؛ مدل بعدی امتحان می‌شود.'
                      : 'اتصال در ${maxRecoveryDuration.inMinutes} دقیقه '
                            'برنگشت و مدل دیگری برای امتحان نمانده.',
                );
              }
              break;
            }
            _announceReconnect(
              key: key,
              attempt: recoveryAttempts,
              maxAttempts: maxRecoveryAttempts,
              message:
                  'اتصال برقرار نشد؛ تلاش مجدد '
                  '${recoveryAttempts + 1} از $maxRecoveryAttempts…',
            );
            await _interruptibleDelay(_recoveryDelay(recoveryAttempts));
            if (_skipRequested) break;
            continue;
          }

          transientAttempts++;
          final isLastAttempt = transientAttempts >= maxAttemptsPerModel;
          if (kind == FailureKind.rateLimited && isLastAttempt) {
            final wait =
                (error is ApiException ? error.retryAfter : null) ??
                defaultCooldown;
            _cooldownUntil[key] = _now().add(wait);
          }
          if (!isLastAttempt) {
            final limited = kind == FailureKind.rateLimited;
            _announceReconnect(
              key: key,
              attempt: transientAttempts,
              maxAttempts: maxAttemptsPerModel,
              message: limited
                  ? 'این مدل روی سقف ارائه‌دهنده است؛ تلاش '
                        '${transientAttempts + 1} از $maxAttemptsPerModel…'
                  : 'پاسخ نگرفتم؛ تلاش '
                        '${transientAttempts + 1} از $maxAttemptsPerModel…',
            );
            await _interruptibleDelay(
              limited
                  ? (error is ApiException ? error.retryAfter : null) ??
                        _rateLimitDelay(transientAttempts)
                  : retryDelay * transientAttempts,
            );
            if (_skipRequested) break;
          } else {
            break;
          }
        }
      }

      final next = _nextUsableIndex(m + 1);
      if (next != null) {
        onSwitched?.call(key, _chain[next]);
        onNotice?.call(
          _skipRequested
              ? 'به درخواست شما، ادامه با «${_chain[next]}».'
              : '«$key» جواب نداد. ادامه با «${_chain[next]}».',
        );
      } else if (_skipRequested) {
        onNotice?.call('مدل دیگری در مسیر اولویت شما باقی نمانده است.');
      }
    }

    throw lastError ?? const ApiException('هیچ مدلی پاسخ نداد.', 0);
  }

  void _announceReconnect({
    required String key,
    required int attempt,
    required int maxAttempts,
    required String message,
  }) {
    onNotice?.call(message);
    onReconnect?.call(
      FailoverReconnectState(
        modelKey: key,
        attempt: attempt,
        maxAttempts: maxAttempts,
        message: message,
        nextModelKey: _nextUsableIndexKey(),
      ),
    );
  }

  String? _nextUsableIndexKey() {
    final next = _nextUsableIndex(_index + 1);
    return next == null ? null : _chain[next];
  }

  static Duration _rateLimitDelay(int attempt) {
    final seconds = (4 << (attempt - 1).clamp(0, 3)).clamp(4, 30);
    final jitter = _random.nextInt((seconds * 250).clamp(1, 1 << 30));
    return Duration(seconds: seconds, milliseconds: jitter);
  }

  Duration _recoveryDelay(int attempt) {
    final multiplier = 1 << (attempt - 1).clamp(0, 5).toInt();
    final millis = (retryDelay.inMilliseconds * multiplier)
        .clamp(0, 30000)
        .toInt();
    return Duration(milliseconds: millis);
  }

  static final _random = Random.secure();

  static String _entropy() {
    final high = _random.nextInt(1 << 32);
    final low = _random.nextInt(1 << 32);
    return '${high.toRadixString(36)}${low.toRadixString(36)}';
  }

  int? _nextUsableIndex(int from) {
    for (var i = from; i < _chain.length; i++) {
      if (!_burned.contains(_chain[i])) return i;
    }
    return null;
  }

  @override
  Future<void> startFreshSession() async {
    _lastSessionId = null;
    await _active?.startFreshSession();
  }

  @override
  Future<bool> cancel() async {
    _cancelled = true;
    return await _active?.cancel() ?? false;
  }

  @override
  Future<void> dispose() async {
    await _active?.dispose();
    _active = null;
    _activeKey = null;
  }
}

List<String> buildFailoverChain({
  required String speaker,
  required List<String> members,
}) {
  final rest = members.where((m) => m != speaker).toList();

  return [speaker, ...rest];
}
