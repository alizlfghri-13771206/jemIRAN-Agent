import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'cdp_client.dart';
import 'page_snapshot.dart';

class BrowserSession {
  BrowserSession._(this.scope);

  final String scope;

  static final Map<String, BrowserSession> _sessions = {};

  static BrowserSession of(String scope) =>
      _sessions.putIfAbsent(scope, () => BrowserSession._(scope));

  static Iterable<String> get openScopes => _sessions.entries
      .where((entry) => entry.value.isOpen)
      .map((entry) => entry.key);

  static Future<void> disposeScope(String scope) async {
    final session = _sessions.remove(scope);
    await session?.close();
  }

  static final Object _zoneScopeKey = Object();

  static String get currentScope =>
      Zone.current[_zoneScopeKey] as String? ?? 'default';

  static Future<T> runScoped<T>(String scope, Future<T> Function() body) =>
      runZoned(body, zoneValues: <Object, Object>{_zoneScopeKey: scope});

  static Future<void> disposeAll() async {
    final sessions = _sessions.values.toList();
    _sessions.clear();
    for (final session in sessions) {
      await session.close();
    }
  }

  CdpClient? _client;
  StreamSubscription<CdpEvent>? _requestGuard;
  PageSnapshot? _lastSnapshot;

  final Map<String, _HostVerdict> _hostVerdicts = {};

  static const _allowTtl = Duration(seconds: 30);
  static const _denyTtl = Duration(minutes: 5);

  bool get isOpen => _client != null && !_client!.isClosed;

  PageSnapshot? get lastSnapshot => _lastSnapshot;

  static const _allowedSchemes = {'http', 'https'};

  static String? rejectUrl(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return 'آدرس خالی است.';

    final uri = Uri.tryParse(trimmed);
    if (uri == null) return 'آدرس نامعتبر است.';

    final scheme = uri.scheme.toLowerCase();
    if (scheme.isEmpty) return null;
    if (!_allowedSchemes.contains(scheme)) {
      return 'فقط آدرس‌های http و https مجازند. «$scheme:» اجازه ندارد.';
    }
    if (uri.host.isEmpty) return 'آدرس باید نام میزبان معتبر داشته باشد.';
    if (uri.userInfo.isNotEmpty) {
      return 'قرار دادن نام کاربری یا رمز داخل URL مجاز نیست.';
    }
    final hostReason = _rejectHostLiteral(uri.host);
    if (hostReason != null) return hostReason;
    return null;
  }

  static String normalizeUrl(String raw) {
    final trimmed = raw.trim();
    final uri = Uri.tryParse(trimmed);
    if (uri != null && uri.scheme.isNotEmpty) return trimmed;
    return 'https://$trimmed';
  }

  Future<CdpClient> _ensureClient() async {
    final existing = _client;
    if (existing != null && !existing.isClosed) return existing;
    final client = await CdpClient.launch();
    await client.send('Fetch.enable', {
      'patterns': [
        {'urlPattern': '*', 'requestStage': 'Request'},
      ],
    });
    _requestGuard = client.events
        .where((event) => event.method == 'Fetch.requestPaused')
        .listen((event) => unawaited(_guardRequest(client, event.params)));
    _client = client;
    return client;
  }

  Future<void> _guardRequest(
    CdpClient client,
    Map<String, dynamic> params,
  ) async {
    final requestId = params['requestId']?.toString();
    final request = params['request'];
    final url = request is Map ? request['url']?.toString() : null;
    if (requestId == null || url == null) return;

    try {
      final uri = Uri.tryParse(url);
      final scheme = uri?.scheme.toLowerCase();
      if (uri == null || !_allowedSchemes.contains(scheme)) {
        await client.send('Fetch.failRequest', {
          'requestId': requestId,
          'errorReason': 'BlockedByClient',
        });
        return;
      }
      final rejection = await _rejectNetworkTarget(uri);
      if (rejection != null) {
        await client.send('Fetch.failRequest', {
          'requestId': requestId,
          'errorReason': 'BlockedByClient',
        });
        return;
      }
      await client.send('Fetch.continueRequest', {'requestId': requestId});
    } catch (_) {
      try {
        await client.send('Fetch.failRequest', {
          'requestId': requestId,
          'errorReason': 'BlockedByClient',
        });
      } catch (_) {}
    }
  }

  Future<String?> _rejectNetworkTarget(Uri uri) async {
    final immediate = _rejectHostLiteral(uri.host);
    if (immediate != null) return immediate;

    final host = uri.host.toLowerCase();
    final now = DateTime.now();
    final cached = _hostVerdicts[host];
    if (cached != null && cached.expiresAt.isAfter(now)) {
      return cached.rejection;
    }

    String? remember(String? rejection) {
      _hostVerdicts[host] = _HostVerdict(
        rejection: rejection,
        expiresAt: now.add(rejection == null ? _allowTtl : _denyTtl),
      );
      return rejection;
    }

    try {
      final addresses = await InternetAddress.lookup(
        host,
      ).timeout(const Duration(seconds: 5));
      return remember(
        addresses.isEmpty || addresses.any(_isPrivateAddress)
            ? 'دسترسی مرورگر به شبکهٔ محلی یا آدرس غیرعمومی مجاز نیست.'
            : null,
      );
    } catch (_) {
      return remember('نام میزبان به‌صورت امن resolve نشد.');
    }
  }

  static String? _rejectHostLiteral(String rawHost) {
    final host = rawHost.toLowerCase().replaceAll(RegExp(r'\.$'), '');
    if (host == 'localhost' ||
        host.endsWith('.localhost') ||
        host.endsWith('.local') ||
        host.endsWith('.internal')) {
      return 'دسترسی مرورگر به میزبان محلی مجاز نیست.';
    }
    final address = InternetAddress.tryParse(host);
    if (address != null && _isPrivateAddress(address)) {
      return 'دسترسی مرورگر به IP خصوصی یا محلی مجاز نیست.';
    }
    return null;
  }

  static bool _isPrivateAddress(InternetAddress address) {
    final bytes = address.rawAddress;
    if (address.isLoopback) return true;
    if (bytes.length == 4) {
      final a = bytes[0];
      final b = bytes[1];
      return a == 0 ||
          a == 10 ||
          a == 127 ||
          (a == 100 && b >= 64 && b <= 127) ||
          (a == 169 && b == 254) ||
          (a == 172 && b >= 16 && b <= 31) ||
          (a == 192 && b == 168) ||
          (a == 198 && (b == 18 || b == 19)) ||
          a >= 224;
    }
    if (bytes.length == 16) {
      final allZero = bytes.every((byte) => byte == 0);
      final uniqueLocal = (bytes[0] & 0xfe) == 0xfc;
      final linkLocal = bytes[0] == 0xfe && (bytes[1] & 0xc0) == 0x80;
      final multicast = bytes[0] == 0xff;
      final ipv4Mapped =
          bytes.take(10).every((byte) => byte == 0) &&
          bytes[10] == 0xff &&
          bytes[11] == 0xff;
      if (ipv4Mapped) {
        return _isPrivateAddress(
          InternetAddress.fromRawAddress(bytes.sublist(12)),
        );
      }
      return allZero || uniqueLocal || linkLocal || multicast;
    }
    return true;
  }

  Future<PageSnapshot> open(String rawUrl) async {
    final rejection = rejectUrl(rawUrl);
    if (rejection != null) throw CdpException(rejection);

    final url = normalizeUrl(rawUrl);
    final second = rejectUrl(url);
    if (second != null) throw CdpException(second);

    final networkRejection = await _rejectNetworkTarget(Uri.parse(url));
    if (networkRejection != null) throw CdpException(networkRejection);

    final client = await _ensureClient();
    await client.send('Page.navigate', {'url': url});
    await client.waitForLoad();
    return read();
  }

  Future<PageSnapshot> read() async {
    final client = await _ensureClient();
    final raw = await client.evaluate(kPageSnapshotJs);
    if (raw is! Map) {
      throw const CdpException('خواندن صفحه نتیجهٔ نامعتبر داد.');
    }
    final snapshot = PageSnapshot.fromJson(raw.cast<Object?, Object?>());
    _lastSnapshot = snapshot;
    return snapshot;
  }

  Future<void> click(String ref) async {
    await _actOn(ref, r'''
      el.scrollIntoView({block: 'center'});
      el.click();
      return true;
    ''');
  }

  Future<void> fill(String ref, String value) async {
    await _actOn(ref, '''
      el.scrollIntoView({block: 'center'});
      el.focus();
      const setter = Object.getOwnPropertyDescriptor(
        el.tagName === 'TEXTAREA'
          ? window.HTMLTextAreaElement.prototype
          : window.HTMLInputElement.prototype,
        'value'
      );
      if (setter && setter.set) {
        setter.set.call(el, ${jsonEncode(value)});
      } else {
        el.value = ${jsonEncode(value)};
      }
      el.dispatchEvent(new Event('input', {bubbles: true}));
      el.dispatchEvent(new Event('change', {bubbles: true}));
      return true;
    ''');
  }

  Future<void> selectOption(String ref, String value) async {
    await _actOn(ref, '''
      const wanted = ${jsonEncode(value)};
      let matched = false;
      for (const option of el.options) {
        if (option.value === wanted || option.text.trim() === wanted) {
          el.value = option.value;
          matched = true;
          break;
        }
      }
      if (!matched) throw new Error('گزینه پیدا نشد: ' + wanted);
      el.dispatchEvent(new Event('change', {bubbles: true}));
      return true;
    ''');
  }

  Future<void> setChecked(String ref, bool checked) async {
    await _actOn(ref, '''
      el.scrollIntoView({block: 'center'});
      if (el.checked !== $checked) el.click();
      return true;
    ''');
  }

  Future<void> scroll(String direction) async {
    final client = await _ensureClient();
    final amount = direction == 'up'
        ? '-window.innerHeight'
        : 'window.innerHeight';
    await client.evaluate(
      '(() => { window.scrollBy(0, $amount * 0.85); return true; })()',
    );
  }

  Future<PageSnapshot> submit(String ref) async {
    await _actOn(ref, r'''
      const form = el.tagName === 'FORM' ? el : (el.form || el.closest('form'));
      if (form) {
        if (typeof form.requestSubmit === 'function') form.requestSubmit();
        else form.submit();
      } else {
        el.click();
      }
      return true;
    ''');
    final client = await _ensureClient();
    await client.waitForLoad();
    return read();
  }

  Future<void> back() async {
    final client = await _ensureClient();
    await client.evaluate('(() => { history.back(); return true; })()');
    await client.waitForLoad();
  }

  Future<String> screenshot(String directory) async {
    final client = await _ensureClient();
    final result = await client.send('Page.captureScreenshot', {
      'format': 'png',
    });
    final data = result['data'];
    if (data is! String) throw const CdpException('گرفتن عکس صفحه ناموفق بود.');

    final file = File(
      p.join(directory, 'page_${DateTime.now().millisecondsSinceEpoch}.png'),
    );
    await file.parent.create(recursive: true);
    await file.writeAsBytes(base64Decode(data));
    return file.path;
  }

  Future<List<({String label, String value})>> formValues(
    String formRef,
  ) async {
    final snapshot = await read();
    final form = snapshot.forms.where((f) => f.ref == formRef).firstOrNull;
    final fields = form == null
        ? snapshot.elements.where((e) => e.isTextInput || e.tag == 'select')
        : snapshot.elements.where((e) => form.fieldRefs.contains(e.ref));

    return [
      for (final field in fields)
        if (field.type != 'password' && (field.shownValue ?? '').isNotEmpty)
          (label: field.label, value: field.shownValue!),
    ];
  }

  Future<Object?> _actOn(String ref, String body) async {
    final client = await _ensureClient();
    final index = _indexOf(ref);
    if (index == null) {
      throw CdpException(
        'شناسهٔ «$ref» معتبر نیست. اول صفحه را با read_page بخوان.',
      );
    }

    return client.evaluate('''
      (() => {
        const refs = window.__jemiranRefs;
        if (!refs) throw new Error('صفحه دوباره بارگذاری شده؛ باید دوباره خوانده شود.');
        const el = refs[$index];
        if (!el || !el.isConnected) {
          throw new Error('المان دیگر روی صفحه نیست؛ باید دوباره خوانده شود.');
        }
        $body
      })()
    ''');
  }

  static int? _indexOf(String ref) {
    if (!ref.startsWith('ref_')) return null;
    return int.tryParse(ref.substring(4));
  }

  Future<void> close() async {
    await _requestGuard?.cancel();
    _requestGuard = null;
    await _client?.dispose();
    _client = null;
    _lastSnapshot = null;
    _hostVerdicts.clear();
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}

class _HostVerdict {
  const _HostVerdict({required this.rejection, required this.expiresAt});

  final String? rejection;
  final DateTime expiresAt;
}
