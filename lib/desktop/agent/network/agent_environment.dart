import 'dart:io';

import 'proxy_detector.dart';

enum ProxyMode { auto, manual, off }

class AgentNetworkConfig {
  const AgentNetworkConfig({
    this.mode = ProxyMode.auto,
    this.manualUrl,
    this.pubMirror,
    this.npmRegistry,
    this.pipIndex,
  });

  final ProxyMode mode;

  final String? manualUrl;

  final String? pubMirror;
  final String? npmRegistry;
  final String? pipIndex;

  AgentNetworkConfig copyWith({
    ProxyMode? mode,
    String? manualUrl,
    String? pubMirror,
    String? npmRegistry,
    String? pipIndex,
    bool clearManual = false,
    bool clearMirrors = false,
  }) => AgentNetworkConfig(
    mode: mode ?? this.mode,
    manualUrl: clearManual ? null : (manualUrl ?? this.manualUrl),
    pubMirror: clearMirrors ? null : (pubMirror ?? this.pubMirror),
    npmRegistry: clearMirrors ? null : (npmRegistry ?? this.npmRegistry),
    pipIndex: clearMirrors ? null : (pipIndex ?? this.pipIndex),
  );
}

abstract final class AgentEnvironment {
  static AgentNetworkConfig config = const AgentNetworkConfig();

  static DetectedProxy? lastResolved;

  static const _noProxy = 'localhost,127.0.0.1,::1,169.254.0.0/16';

  static const _proxyKeys = [
    'HTTP_PROXY',
    'http_proxy',
    'HTTPS_PROXY',
    'https_proxy',
    'ALL_PROXY',
    'all_proxy',
    'npm_config_proxy',
    'npm_config_https_proxy',
  ];

  static const _inheritedKeys = {
    'PATH',
    'PATHEXT',
    'SYSTEMROOT',
    'WINDIR',
    'SYSTEMDRIVE',
    'COMSPEC',
    'TEMP',
    'TMP',
    'USERPROFILE',
    'HOMEDRIVE',
    'HOMEPATH',
    'APPDATA',
    'LOCALAPPDATA',
    'PROGRAMDATA',
    'PROGRAMFILES',
    'PROGRAMFILES(X86)',
    'PROGRAMW6432',
    'OS',
    'PROCESSOR_ARCHITECTURE',
    'NUMBER_OF_PROCESSORS',
    'USERNAME',
    'LANG',
    'LC_ALL',
    'JAVA_HOME',
    'ANDROID_HOME',
    'ANDROID_SDK_ROOT',
    'FLUTTER_ROOT',
    'PUB_CACHE',
  };

  static Future<DetectedProxy?> resolve() async {
    switch (config.mode) {
      case ProxyMode.off:
        lastResolved = null;
        return null;

      case ProxyMode.manual:
        final parsed = _parseUrl(config.manualUrl);
        lastResolved = parsed;
        return parsed;

      case ProxyMode.auto:
        lastResolved = await ProxyDetector.detect();
        return lastResolved;
    }
  }

  static DetectedProxy? _parseUrl(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    final uri = Uri.tryParse(raw.trim());
    if (uri == null || uri.host.isEmpty) return null;
    final scheme = uri.scheme.toLowerCase();
    if (!const {'http', 'https', 'socks5'}.contains(scheme) ||
        uri.userInfo.isNotEmpty) {
      return null;
    }
    final port = uri.hasPort ? uri.port : 8080;
    return DetectedProxy(
      host: uri.host,
      port: port,
      scheme: scheme,
      source: 'تنظیم دستی',
    );
  }

  static Future<Map<String, String>> build({
    Map<String, String>? parentEnvironment,
  }) async {
    final parent = parentEnvironment ?? Platform.environment;
    final env = sanitizedEnvironment(parent);
    final proxy = await resolve();

    if (proxy != null) {
      final url = proxy.url;
      for (final key in _proxyKeys) {
        env[key] = url;
      }

      env['NO_PROXY'] = _noProxy;
      env['no_proxy'] = _noProxy;
      env['npm_config_noproxy'] = _noProxy;
    } else if (config.mode == ProxyMode.auto) {
      for (final key in [
        ..._proxyKeys,
        'NO_PROXY',
        'no_proxy',
        'npm_config_noproxy',
      ]) {
        final inherited = parent[key];
        if (inherited != null && inherited.trim().isNotEmpty) {
          env[key] = inherited;
        }
      }
    }

    final pub = config.pubMirror?.trim();
    if (pub != null && pub.isNotEmpty) {
      env['PUB_HOSTED_URL'] = pub;
      env['FLUTTER_STORAGE_BASE_URL'] = pub;
    }
    final npm = config.npmRegistry?.trim();
    if (npm != null && npm.isNotEmpty) env['npm_config_registry'] = npm;

    final pip = config.pipIndex?.trim();
    if (pip != null && pip.isNotEmpty) {
      env['PIP_INDEX_URL'] = pip;
    }

    return env;
  }

  static Map<String, String> sanitizedEnvironment(Map<String, String> source) {
    final env = <String, String>{};
    for (final entry in source.entries) {
      if (_inheritedKeys.contains(entry.key.toUpperCase())) {
        env[entry.key] = entry.value;
      }
    }
    return env;
  }

  static bool get manualUrlIsValid =>
      config.mode != ProxyMode.manual || _parseUrl(config.manualUrl) != null;

  static Future<Map<String, dynamic>> describe() async {
    final proxy = await resolve();
    return {
      'mode': config.mode.name,
      'proxy': proxy?.toJson(),
      if (!manualUrlIsValid)
        'warning': 'نشانی پروکسی دستی نامعتبر است، پس هیچ پروکسی‌ای اعمال نشد.',
      if (config.pubMirror != null) 'pub_mirror': config.pubMirror,
      if (config.npmRegistry != null) 'npm_registry': config.npmRegistry,
      if (config.pipIndex != null) 'pip_index': config.pipIndex,
    };
  }

  static Future<Map<String, bool>> repositoryHealth() async {
    const hosts = ['pub.dev', 'pypi.org', 'registry.npmjs.org', 'github.com'];
    final statuses = await Future.wait([
      for (final host in hosts) _canReach(host, 443),
    ]);
    return {for (var i = 0; i < hosts.length; i++) hosts[i]: statuses[i]};
  }

  static Future<bool> _canReach(String host, int port) async {
    try {
      final socket = await Socket.connect(
        host,
        port,
        timeout: const Duration(seconds: 8),
      );
      socket.destroy();
      return true;
    } catch (_) {
      return false;
    }
  }
}
