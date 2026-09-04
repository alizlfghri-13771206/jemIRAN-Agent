import 'dart:async';
import 'dart:convert';
import 'dart:io';

class DetectedProxy {
  const DetectedProxy({
    required this.host,
    required this.port,
    required this.source,
    this.scheme = 'http',
    this.username,
    this.password,
  });

  final String host;
  final int port;

  final String source;

  final String scheme;

  final String? username;
  final String? password;

  bool get needsAuth => password != null && password!.isNotEmpty;

  String get url => needsAuth
      ? '$scheme://${Uri.encodeComponent(username ?? '')}:${Uri.encodeComponent(password!)}@$host:$port'
      : '$scheme://$host:$port';

  String get displayUrl => '$scheme://$host:$port';

  Map<String, dynamic> toJson() => {
    'url': displayUrl,
    'host': host,
    'port': port,
    'source': source,
  };

  @override
  bool operator ==(Object other) =>
      other is DetectedProxy && other.host == host && other.port == port;

  @override
  int get hashCode => Object.hash(host, port);
}

abstract final class ProxyDetector {
  static const _commonPorts = [
    10809,
    2080,
    2081,
    7890,
    7891,
    8889,
    20171,
    8080,
    3067,
  ];

  static Future<DetectedProxy?> systemProxy() async {
    try {
      final enabled = await _regValue('ProxyEnable');
      if (enabled == null || enabled.endsWith('0x0')) return null;

      final server = await _regValue('ProxyServer');
      if (server == null || server.isEmpty) return null;

      return _parseServer(server, 'پروکسی ویندوز');
    } catch (_) {
      return null;
    }
  }

  static DetectedProxy? _parseServer(String raw, String source) {
    var value = raw.trim();

    if (value.contains('=')) {
      final parts = value.split(';');
      String? picked;
      for (final part in parts) {
        final kv = part.split('=');
        if (kv.length != 2) continue;
        if (kv[0].trim() == 'https') {
          picked = kv[1].trim();
          break;
        }
        if (kv[0].trim() == 'http') picked ??= kv[1].trim();
      }
      if (picked == null) return null;
      value = picked;
    }

    value = value.replaceFirst(RegExp(r'^\w+://'), '');
    final colon = value.lastIndexOf(':');
    if (colon <= 0) return null;

    final host = value.substring(0, colon).trim();
    final port = int.tryParse(value.substring(colon + 1).trim());
    if (host.isEmpty || port == null) return null;

    return DetectedProxy(host: host, port: port, source: source);
  }

  static Future<String?> _regValue(String name) async {
    final result = await Process.run('reg', [
      'query',
      r'HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings',
      '/v',
      name,
    ], stdoutEncoding: const Utf8Codec(allowMalformed: true));

    if (result.exitCode != 0) return null;

    for (final line in (result.stdout as String).split('\n')) {
      if (!line.contains(name)) continue;
      final parts = line.trim().split(RegExp(r'\s{2,}|\t'));
      if (parts.length >= 3) return parts.last.trim();
    }
    return null;
  }

  static Future<DetectedProxy?> probeLocalPorts({
    Duration timeout = const Duration(milliseconds: 250),
  }) async {
    for (final port in _commonPorts) {
      if (await _isListening(port, timeout)) {
        return DetectedProxy(
          host: '127.0.0.1',
          port: port,
          source: 'پروکسی محلی روی پورت $port',
        );
      }
    }
    return null;
  }

  static Future<bool> _isListening(int port, Duration timeout) async {
    try {
      final socket = await Socket.connect('127.0.0.1', port, timeout: timeout);
      socket.destroy();
      return true;
    } catch (_) {
      return false;
    }
  }

  static Future<DetectedProxy?> detect() async =>
      await systemProxy() ?? await probeLocalPorts();

  static Future<bool> canReach(
    String host, {
    int port = 443,
    DetectedProxy? through,
    Duration timeout = const Duration(seconds: 6),
  }) async {
    Socket? socket;
    try {
      if (through == null) {
        socket = await Socket.connect(host, port, timeout: timeout);
        return true;
      }

      socket = await Socket.connect(
        through.host,
        through.port,
        timeout: timeout,
      );
      socket.write('CONNECT $host:$port HTTP/1.1\r\nHost: $host:$port\r\n\r\n');
      await socket.flush();

      final first = await socket.first.timeout(timeout);
      final response = const Utf8Decoder(allowMalformed: true).convert(first);
      return response.contains(' 200 ');
    } catch (_) {
      return false;
    } finally {
      socket?.destroy();
    }
  }
}
