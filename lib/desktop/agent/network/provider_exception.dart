import 'dart:math';

class ApiException implements Exception {
  const ApiException(
    this.message,
    this.statusCode, {
    this.code,
    this.retryAfter,
  });

  final String message;
  final int statusCode;
  final String? code;
  final Duration? retryAfter;

  static Duration? parseRetryAfter(Map<String, String> headers) {
    final raw = headers['retry-after'] ?? headers['Retry-After'];
    final seconds = int.tryParse((raw ?? '').trim());
    if (seconds == null || seconds <= 0) return null;
    return Duration(seconds: seconds.clamp(1, 300));
  }

  @override
  String toString() => message;

  bool get isUnauthorized => statusCode == 401;
  bool get isForbidden => statusCode == 403;
  bool get isPaymentRequired => statusCode == 402;
  bool get isProviderBusy => statusCode == 429 || statusCode == 503;
  bool get isTimeout => statusCode == 504;
  bool get isNoInternet => statusCode == 0;
  bool get isTooLarge => statusCode == 413;
}

class RequestIds {
  static final _random = Random.secure();

  static String next() {
    final now = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    final high = _random.nextInt(1 << 32).toRadixString(36);
    final low = _random.nextInt(1 << 32).toRadixString(36);
    return 'req_${now}_$high$low';
  }
}
