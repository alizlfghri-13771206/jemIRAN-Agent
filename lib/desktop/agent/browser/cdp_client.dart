import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../network/agent_environment.dart';
import 'chrome_locator.dart';

class CdpException implements Exception {
  const CdpException(this.message);
  final String message;

  @override
  String toString() => message;
}

class CdpClient {
  CdpClient._(this._process, this._socket, this._profileDir) {
    _subscription = _socket.listen(
      _onMessage,
      onDone: () => _failPending('اتصال مرورگر بسته شد.'),
      onError: (Object error) => _failPending('خطای اتصال مرورگر: $error'),
    );
  }

  final Process _process;
  final WebSocket _socket;
  final Directory _profileDir;

  String get profilePath => _profileDir.path;

  late final StreamSubscription<dynamic> _subscription;
  final Map<int, Completer<Map<String, dynamic>>> _pending = {};
  final StreamController<CdpEvent> _events = StreamController.broadcast();

  int _nextId = 1;
  bool _closed = false;

  Stream<CdpEvent> get events => _events.stream;

  bool get isClosed => _closed;

  static Future<CdpClient> launch({
    bool headless = false,
    Duration timeout = const Duration(seconds: 25),
  }) async {
    final binary = ChromeLocator.find();
    if (binary == null) {
      throw const CdpException(
        'هیچ مرورگر کروم یا اِج روی این سیستم پیدا نشد.',
      );
    }

    final port = await _freePort();
    final profileDir = await Directory.systemTemp.createTemp(
      'jemiran_agent_browser_',
    );

    final proxy = await AgentEnvironment.resolve();
    final proxyArg = proxy == null || proxy.needsAuth ? null : proxy.displayUrl;

    final process = await Process.start(
      binary.path,
      [
        '--remote-debugging-port=$port',
        '--user-data-dir=${profileDir.path}',
        '--no-first-run',
        '--no-default-browser-check',
        '--disable-extensions',
        '--disable-background-networking',
        if (proxyArg != null) '--proxy-server=$proxyArg',
        if (proxyArg != null) '--proxy-bypass-list=localhost;127.0.0.1;[::1]',
        if (headless) '--headless=new',
        'about:blank',
      ],
      environment: AgentEnvironment.sanitizedEnvironment(Platform.environment),
      includeParentEnvironment: false,
    );

    try {
      final wsUrl = await _waitForPageSocket(port, timeout);
      final socket = await WebSocket.connect(wsUrl);
      final client = CdpClient._(process, socket, profileDir);
      await client._enableDomains();
      return client;
    } catch (e) {
      process.kill();
      try {
        if (await profileDir.exists()) await profileDir.delete(recursive: true);
      } catch (_) {}
      throw CdpException('اتصال به مرورگر برقرار نشد: $e');
    }
  }

  Future<void> _enableDomains() async {
    await send('Page.enable');
    await send('Runtime.enable');
    await send('Page.setLifecycleEventsEnabled', {'enabled': true});
  }

  void _failPending(String reason) {
    _closed = true;
    final waiting = _pending.values.toList();
    _pending.clear();
    for (final completer in waiting) {
      if (!completer.isCompleted) {
        completer.completeError(CdpException(reason));
      }
    }
  }

  Future<Map<String, dynamic>> send(
    String method, [
    Map<String, dynamic>? params,
  ]) async {
    if (_closed) throw const CdpException('اتصال مرورگر بسته شده است.');

    final id = _nextId++;
    final completer = Completer<Map<String, dynamic>>();
    _pending[id] = completer;

    _socket.add(jsonEncode({'id': id, 'method': method, 'params': ?params}));

    try {
      return await completer.future.timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          _pending.remove(id);
          throw CdpException('مرورگر به «$method» پاسخ نداد.');
        },
      );
    } finally {
      _pending.remove(id);
    }
  }

  Future<Object?> evaluate(String expression) async {
    final result = await send('Runtime.evaluate', {
      'expression': expression,
      'returnByValue': true,
      'awaitPromise': true,
      'userGesture': true,
    });

    final exception = result['exceptionDetails'];
    if (exception != null) {
      final text = (exception as Map)['text'] ?? 'خطای جاوااسکریپت';
      throw CdpException('اجرای اسکریپت در صفحه شکست خورد: $text');
    }
    return (result['result'] as Map?)?['value'];
  }

  void _onMessage(dynamic raw) {
    if (raw is! String) return;
    Map<String, dynamic> message;
    try {
      message = jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return;
    }

    final id = message['id'];
    if (id is int) {
      final completer = _pending.remove(id);
      if (completer == null || completer.isCompleted) return;

      final error = message['error'];
      if (error != null) {
        completer.completeError(
          CdpException((error as Map)['message']?.toString() ?? 'خطای مرورگر'),
        );
      } else {
        completer.complete(
          Map<String, dynamic>.from(message['result'] as Map? ?? const {}),
        );
      }
      return;
    }

    final method = message['method'];
    if (method is String) {
      _events.add(
        CdpEvent(
          method,
          Map<String, dynamic>.from(message['params'] as Map? ?? const {}),
        ),
      );
    }
  }

  Future<void> waitForLoad({
    Duration timeout = const Duration(seconds: 15),
  }) async {
    try {
      await events
          .firstWhere(
            (e) =>
                e.method == 'Page.lifecycleEvent' &&
                (e.params['name'] == 'networkAlmostIdle' ||
                    e.params['name'] == 'load'),
          )
          .timeout(timeout);
    } on TimeoutException {
      return;
    }
  }

  Future<void> dispose() async {
    _closed = true;
    await _subscription.cancel();
    await _events.close();
    try {
      await _socket.close();
    } catch (_) {}
    _process.kill();
    try {
      await _process.exitCode.timeout(const Duration(seconds: 5));
    } catch (_) {}
    try {
      if (await _profileDir.exists()) {
        await _profileDir.delete(recursive: true);
      }
    } catch (_) {}
  }

  static Future<int> _freePort() async {
    final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = socket.port;
    await socket.close();
    return port;
  }

  static Future<String> _waitForPageSocket(int port, Duration timeout) async {
    final deadline = DateTime.now().add(timeout);
    final http = HttpClient();

    try {
      while (DateTime.now().isBefore(deadline)) {
        try {
          final request = await http.get('127.0.0.1', port, '/json/list');
          final response = await request.close();
          final body = await response.transform(utf8.decoder).join();
          final targets = jsonDecode(body);

          if (targets is List) {
            for (final t in targets) {
              if (t is Map &&
                  t['type'] == 'page' &&
                  t['webSocketDebuggerUrl'] is String) {
                return t['webSocketDebuggerUrl'] as String;
              }
            }
          }
        } catch (_) {}
        await Future<void>.delayed(const Duration(milliseconds: 250));
      }
    } finally {
      http.close(force: true);
    }

    throw const CdpException('مرورگر در زمان مقرر آماده نشد.');
  }
}

class CdpEvent {
  const CdpEvent(this.method, this.params);
  final String method;
  final Map<String, dynamic> params;
}
