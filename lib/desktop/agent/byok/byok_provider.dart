import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../core/agent_storage.dart';
import 'secret_vault.dart';

enum ByokWireFormat { openAiCompatible, anthropicMessages }

enum ByokProviderKind {
  anthropic(
    'Anthropic',
    'https://api.anthropic.com/v1',
    ByokWireFormat.anthropicMessages,
  ),
  openAi(
    'OpenAI',
    'https://api.openai.com/v1',
    ByokWireFormat.openAiCompatible,
  ),
  deepSeek(
    'DeepSeek',
    'https://api.deepseek.com/v1',
    ByokWireFormat.openAiCompatible,
  ),
  openRouter(
    'OpenRouter',
    'https://openrouter.ai/api/v1',
    ByokWireFormat.openAiCompatible,
  ),
  gemini(
    'Google Gemini',
    'https://generativelanguage.googleapis.com/v1beta/openai',
    ByokWireFormat.openAiCompatible,
  ),
  custom('سفارشی', '', ByokWireFormat.openAiCompatible);

  const ByokProviderKind(this.label, this.defaultBaseUrl, this.wireFormat);

  final String label;
  final String defaultBaseUrl;
  final ByokWireFormat wireFormat;

  static ByokProviderKind parse(String? raw) => values.firstWhere(
    (kind) => kind.name == raw,
    orElse: () => ByokProviderKind.custom,
  );
}

class ByokProvider {
  const ByokProvider({
    required this.id,
    required this.kind,
    required this.label,
    required this.modelId,
    this.baseUrl,
    this.headers = const {},
    this.enabled = true,
    this.contextTokens = defaultContextTokens,
    this.maxOutputTokens = defaultOutputTokens,
  });

  static const defaultContextTokens = 128000;
  static const defaultOutputTokens = 8192;

  final String id;
  final ByokProviderKind kind;
  final String label;

  final String modelId;

  final String? baseUrl;

  final Map<String, String> headers;

  Map<String, String> get safeHeaders => Map.unmodifiable(
    Map.fromEntries(
      headers.entries.where((entry) {
        final name = entry.key.trim().toLowerCase();
        return name != 'authorization' &&
            name != 'proxy-authorization' &&
            name != 'x-api-key' &&
            name != 'cookie' &&
            name != 'set-cookie';
      }),
    ),
  );

  final bool enabled;

  final int contextTokens;

  final int maxOutputTokens;

  ByokWireFormat get wireFormat => kind.wireFormat;

  String get modelKey => '$keyPrefix$id';

  static const keyPrefix = 'byok:';

  static bool isByokKey(String? key) =>
      key != null && key.startsWith(keyPrefix);

  String get effectiveBaseUrl {
    final custom = baseUrl?.trim();
    if (kind == ByokProviderKind.custom &&
        custom != null &&
        custom.isNotEmpty) {
      if (!isAllowedBaseUrl(custom)) {
        throw StateError('آدرس ارائه‌دهنده معتبر یا امن نیست.');
      }
      return custom.endsWith('/')
          ? custom.substring(0, custom.length - 1)
          : custom;
    }
    return kind.defaultBaseUrl;
  }

  static bool isAllowedBaseUrl(String raw) {
    final uri = Uri.tryParse(raw);
    if (uri == null ||
        !uri.hasScheme ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        (uri.scheme != 'https' && uri.scheme != 'http')) {
      return false;
    }
    if (uri.scheme == 'https') return true;
    final host = uri.host.toLowerCase();
    return host == 'localhost' || host == '127.0.0.1' || host == '::1';
  }

  String get secretRef => 'byok:$id';

  bool get hasSecret => SecretVault.read(secretRef)?.trim().isNotEmpty == true;

  static String maskSecret(String secret) {
    final trimmed = secret.trim();
    if (trimmed.length <= 8) return '••••';
    return '${trimmed.substring(0, 4)}••••${trimmed.substring(trimmed.length - 4)}';
  }

  ByokProvider copyWith({
    String? label,
    String? modelId,
    String? baseUrl,
    Map<String, String>? headers,
    bool? enabled,
    int? contextTokens,
    int? maxOutputTokens,
  }) => ByokProvider(
    id: id,
    kind: kind,
    label: label ?? this.label,
    modelId: modelId ?? this.modelId,
    baseUrl: baseUrl ?? this.baseUrl,
    headers: headers ?? this.headers,
    enabled: enabled ?? this.enabled,
    contextTokens: contextTokens ?? this.contextTokens,
    maxOutputTokens: maxOutputTokens ?? this.maxOutputTokens,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'kind': kind.name,
    'label': label,
    'model_id': modelId,
    if (baseUrl != null && baseUrl!.isNotEmpty) 'base_url': baseUrl,
    if (safeHeaders.isNotEmpty) 'headers': safeHeaders,
    'enabled': enabled,
    'context_tokens': contextTokens,
    'max_output_tokens': maxOutputTokens,
  };

  factory ByokProvider.fromJson(Map<String, dynamic> json) => ByokProvider(
    id: json['id'] as String? ?? '',
    kind: ByokProviderKind.parse(json['kind'] as String?),
    label: json['label'] as String? ?? '',
    modelId: json['model_id'] as String? ?? '',
    baseUrl: json['base_url'] as String?,
    headers:
        (json['headers'] as Map?)?.map(
          (key, value) => MapEntry(key.toString(), value.toString()),
        ) ??
        const {},
    enabled: json['enabled'] != false,
    contextTokens:
        (json['context_tokens'] as num?)?.toInt() ?? defaultContextTokens,
    maxOutputTokens:
        (json['max_output_tokens'] as num?)?.toInt() ?? defaultOutputTokens,
  );
}

abstract final class ByokStore {
  static const _fileName = 'byok_providers.json';
  static const maxProviders = 12;

  static List<ByokProvider> _cache = const [];
  static bool _loaded = false;

  static String _cachedAccount = '';

  static List<ByokProvider> get providers {
    if (!_loaded || _cachedAccount != AgentStorage.accountKey) load();
    return List.unmodifiable(_cache);
  }

  static List<ByokProvider> get usable =>
      providers.where((item) => item.enabled && item.hasSecret).toList();

  static File? _file() {
    final root = AgentStorage.root;
    if (root == null) return null;
    return File(p.join(root.path, _fileName));
  }

  static void load() {
    _loaded = true;
    _cachedAccount = AgentStorage.accountKey;
    try {
      final file = _file();
      if (file == null) {
        _cache = const [];
        return;
      }
      final backup = File('${file.path}.bak');
      if (!file.existsSync() && backup.existsSync()) {
        backup.renameSync(file.path);
      }
      if (!file.existsSync()) {
        _cache = const [];
        return;
      }
      final decoded = jsonDecode(file.readAsStringSync());
      if (decoded is! List) {
        _cache = const [];
        return;
      }
      _cache = decoded
          .whereType<Map>()
          .map((item) => ByokProvider.fromJson(Map<String, dynamic>.from(item)))
          .where((item) => item.id.isNotEmpty && item.modelId.isNotEmpty)
          .take(maxProviders)
          .toList(growable: false);
    } catch (_) {
      _cache = const [];
    }
  }

  static void _persist() {
    final file = _file();
    if (file == null) return;
    final temp = File(
      '${file.path}.${DateTime.now().microsecondsSinceEpoch}.tmp',
    );
    final backup = File('${file.path}.bak');
    temp.writeAsStringSync(
      jsonEncode([for (final item in _cache) item.toJson()]),
      flush: true,
    );
    try {
      if (backup.existsSync()) backup.deleteSync();
      if (file.existsSync()) file.renameSync(backup.path);
      temp.renameSync(file.path);
      if (backup.existsSync()) backup.deleteSync();
    } catch (_) {
      if (!file.existsSync() && backup.existsSync()) {
        backup.renameSync(file.path);
      }
      rethrow;
    } finally {
      if (temp.existsSync()) temp.deleteSync();
    }
  }

  static void save(ByokProvider provider, {String? secret}) {
    if (!_loaded || _cachedAccount != AgentStorage.accountKey) load();
    final previous = _cache;
    final previousSecret = SecretVault.read(provider.secretRef);
    final next = [..._cache];
    final index = next.indexWhere((item) => item.id == provider.id);
    if (index >= 0) {
      next[index] = provider;
    } else {
      if (next.length >= maxProviders) {
        throw StateError('حداکثر $maxProviders ارائه‌دهنده قابل ثبت است.');
      }
      next.add(provider);
    }
    final newSecret = secret?.trim();
    try {
      if (newSecret != null && newSecret.isNotEmpty) {
        SecretVault.write(provider.secretRef, newSecret);
      }
      _cache = List.unmodifiable(next);
      _persist();
    } catch (_) {
      _cache = previous;
      if (newSecret != null && newSecret.isNotEmpty) {
        if (previousSecret == null) {
          SecretVault.delete(provider.secretRef);
        } else {
          SecretVault.write(provider.secretRef, previousSecret);
        }
      }
      rethrow;
    }
  }

  static void remove(String id) {
    if (!_loaded || _cachedAccount != AgentStorage.accountKey) load();
    final target = _cache.where((item) => item.id == id).firstOrNull;
    if (target == null) return;
    final previous = _cache;
    final previousSecret = SecretVault.read(target.secretRef);
    try {
      _cache = List.unmodifiable(_cache.where((item) => item.id != id));
      _persist();
      SecretVault.delete(target.secretRef);
    } catch (error, stackTrace) {
      _cache = previous;
      try {
        _persist();
      } catch (_) {}
      if (previousSecret != null) {
        SecretVault.write(target.secretRef, previousSecret);
      }
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  static ByokProvider? byId(String id) =>
      providers.where((item) => item.id == id).firstOrNull;

  static ByokProvider? byModelKey(String? modelKey) {
    if (!ByokProvider.isByokKey(modelKey)) return null;
    return byId(modelKey!.substring(ByokProvider.keyPrefix.length));
  }

  static String _modelCompany(ByokProvider provider) {
    final prefix = provider.modelId.split('/').first;
    const companies = {
      'google': 'Google',
      'openai': 'OpenAI',
      'anthropic': 'Anthropic',
      'deepseek': 'DeepSeek',
      'x-ai': 'xAI',
      'nvidia': 'NVIDIA',
      'meta': 'Meta',
      'qwen': 'Qwen',
      'tencent': 'Tencent',
      'xiaomi': 'Xiaomi',
      'z-ai': 'Z.ai',
    };
    if (provider.kind == ByokProviderKind.gemini) return 'Google';
    return companies[prefix] ?? provider.kind.label;
  }

  static Map<String, dynamic> modelEntry(ByokProvider provider) => {
    'key': provider.modelKey,
    'label': provider.label.isEmpty ? provider.modelId : provider.label,
    'company': _modelCompany(provider),
    if (const {
      'google/gemini-4-argon',
      'gemini-4-argon',
    }.contains(provider.modelId.trim()))
      'icon': 'progemini',
    'agent_model': true,
    'enabled': provider.enabled,
    'locked': false,
    'byok': true,
    'max_context_tokens': provider.contextTokens,
    'max_output_tokens': provider.maxOutputTokens,
  };

  static void clear() {
    _cache = const [];
    _loaded = true;
    final file = _file();
    if (file != null && file.existsSync()) file.deleteSync();
    SecretVault.clear();
  }

  static void resetForTesting() {
    _cache = const [];
    _loaded = false;
    _cachedAccount = '';
  }

  static String exportJson() => jsonEncode({
    'version': 1,
    'providers': [for (final item in providers) item.toJson()],
  });
}
