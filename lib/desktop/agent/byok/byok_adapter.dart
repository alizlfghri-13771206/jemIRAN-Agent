import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import '../network/provider_exception.dart';

import '../core/model_adapter.dart';
import '../tools/agent_tool.dart';
import 'byok_provider.dart';
import 'local_attachments.dart';
import 'secret_vault.dart';

class ByokTestResult {
  const ByokTestResult({required this.ok, required this.message});

  final bool ok;
  final String message;
}

Future<ByokTestResult> testByokProvider(
  ByokProvider provider, {
  required String secret,
  http.Client? client,
  Duration timeout = const Duration(seconds: 20),
}) async {
  final anthropic = provider.wireFormat == ByokWireFormat.anthropicMessages;
  final own = client == null;
  final http10 = client ?? http.Client();
  try {
    final response = await http10
        .get(
          Uri.parse('${provider.effectiveBaseUrl}/models'),
          headers: {
            ...provider.safeHeaders,
            if (anthropic) ...{
              'x-api-key': secret,
              'anthropic-version': '2023-06-01',
            } else
              'authorization': 'Bearer $secret',
          },
        )
        .timeout(timeout);

    if (response.statusCode == 401 || response.statusCode == 403) {
      return const ByokTestResult(ok: false, message: 'کلید پذیرفته نشد.');
    }
    if (response.statusCode >= 400) {
      return ByokTestResult(
        ok: false,
        message: 'ارائه‌دهنده پاسخ ${response.statusCode} داد.',
      );
    }
    try {
      final decoded = jsonDecode(response.body);
      final data = decoded is Map ? decoded['data'] : null;
      if (data is List) {
        final found = data.any(
          (item) => item is Map && item['id']?.toString() == provider.modelId,
        );
        if (!found) {
          return const ByokTestResult(
            ok: false,
            message: 'اتصال برقرار شد، اما مدل انتخاب‌شده پیدا نشد.',
          );
        }
        return const ByokTestResult(
          ok: true,
          message: 'کلید و شناسهٔ مدل تأیید شدند.',
        );
      }
    } catch (_) {}
    return const ByokTestResult(
      ok: false,
      message: 'اتصال برقرار شد، اما فهرست مدل‌ها قابل تأیید نبود.',
    );
  } on TimeoutException {
    return const ByokTestResult(ok: false, message: 'پاسخ به‌موقع نرسید.');
  } catch (_) {
    return const ByokTestResult(ok: false, message: 'اتصال برقرار نشد.');
  } finally {
    if (own) http10.close();
  }
}

class _PartialCall {
  String id = '';
  String name = '';
  final StringBuffer arguments = StringBuffer();
}

class _StreamedReply {
  final StringBuffer text = StringBuffer();
  final Map<int, _PartialCall> calls = {};
  String? finishReason;

  _PartialCall callAt(int index) => calls.putIfAbsent(index, _PartialCall.new);

  List<ToolCall> toolCalls() {
    final indexes = calls.keys.toList()..sort();
    return [
      for (final index in indexes)
        if (calls[index]!.name.isNotEmpty)
          ToolCall(
            id: calls[index]!.id,
            name: calls[index]!.name,
            args: ByokModelAdapter.decodeArgs(
              calls[index]!.arguments.toString(),
            ),
          ),
    ];
  }
}

class ByokConversationState {
  final List<_ConversationExchange> _exchanges = [];
  final List<_SeedMessage> _seedMessages = [];

  void clear() {
    _exchanges.clear();
    _seedMessages.clear();
  }

  void seedTextMessage({required bool isUser, required String text}) {
    if (text.trim().isEmpty) return;
    _seedMessages.add(_SeedMessage(isUser: isUser, text: text));
  }

  List<Map<String, dynamic>> _messagesFor({
    required bool anthropic,
    required _PendingInput pending,
  }) {
    final messages = <Map<String, dynamic>>[];
    for (final message in _seedMessages) {
      messages.add({
        'role': message.isUser ? 'user' : 'assistant',
        'content': message.text,
      });
    }
    for (final exchange in _exchanges) {
      _appendInput(messages, exchange.input, anthropic: anthropic);
      _appendTurn(messages, exchange.turn, anthropic: anthropic);
    }
    _appendInput(messages, pending, anthropic: anthropic);
    return messages;
  }

  void _commit(_PendingInput input, ModelTurn turn) {
    _exchanges.add(_ConversationExchange(input: input, turn: turn));
  }

  static void _appendInput(
    List<Map<String, dynamic>> history,
    _PendingInput input, {
    required bool anthropic,
  }) {
    final checkpoint = input.contextCheckpoint;
    if (checkpoint != null && checkpoint.isNotEmpty) {
      history.add({'role': 'user', 'content': checkpoint});
    }

    final results = input.toolResults;
    if (results.isNotEmpty) {
      if (checkpoint != null && checkpoint.isNotEmpty) {
        _appendSyntheticToolCall(history, results, anthropic: anthropic);
      }
      if (anthropic) {
        history.add({
          'role': 'user',
          'content': [
            for (final item in results)
              {
                'type': 'tool_result',
                'tool_use_id': item['tool_call_id'],
                'content': item['content']?.toString() ?? '',
              },
          ],
        });
      } else {
        for (final item in results) {
          history.add({
            'role': 'tool',
            'tool_call_id': item['tool_call_id'],
            'content': item['content']?.toString() ?? '',
          });
        }
      }
      return;
    }

    if (input.files.isEmpty) {
      history.add({'role': 'user', 'content': input.text});
      return;
    }
    if (anthropic) {
      history.add({
        'role': 'user',
        'content': [
          {'type': 'text', 'text': input.text},
          for (final file in input.files)
            if (file.isImage)
              {
                'type': 'image',
                'source': {
                  'type': 'base64',
                  'media_type': file.mime,
                  'data': base64Encode(file.bytes),
                },
              }
            else if (file.mime == 'text/plain')
              {
                'type': 'text',
                'text': utf8.decode(file.bytes, allowMalformed: true),
              }
            else
              {
                'type': 'document',
                'source': {
                  'type': 'base64',
                  'media_type': file.mime,
                  'data': base64Encode(file.bytes),
                },
              },
        ],
      });
      return;
    }
    history.add({
      'role': 'user',
      'content': [
        {'type': 'text', 'text': input.text},
        for (final file in input.files)
          if (file.isImage)
            {
              'type': 'image_url',
              'image_url': {'url': file.dataUrl},
            }
          else
            {
              'type': 'file',
              'file': {'filename': file.name, 'file_data': file.dataUrl},
            },
      ],
    });
  }

  static void _appendSyntheticToolCall(
    List<Map<String, dynamic>> history,
    List<Map<String, dynamic>> results, {
    required bool anthropic,
  }) {
    if (anthropic) {
      history.add({
        'role': 'assistant',
        'content': [
          for (final item in results)
            {
              'type': 'tool_use',
              'id': item['tool_call_id'],
              'name': item['name']?.toString() ?? 'tool',
              'input': item['arguments'] is Map
                  ? Map<String, dynamic>.from(item['arguments'] as Map)
                  : const <String, dynamic>{},
            },
        ],
      });
      return;
    }
    history.add({
      'role': 'assistant',
      'content': null,
      'tool_calls': [
        for (final item in results)
          {
            'id': item['tool_call_id'],
            'type': 'function',
            'function': {
              'name': item['name']?.toString() ?? 'tool',
              'arguments': jsonEncode(item['arguments'] ?? const {}),
            },
          },
      ],
    });
  }

  static void _appendTurn(
    List<Map<String, dynamic>> history,
    ModelTurn turn, {
    required bool anthropic,
  }) {
    final calls = turn.toolCalls ?? const <ToolCall>[];
    if (anthropic) {
      history.add({
        'role': 'assistant',
        'content': [
          if (turn.text.isNotEmpty) {'type': 'text', 'text': turn.text},
          for (final call in calls)
            {
              'type': 'tool_use',
              'id': call.id,
              'name': call.name,
              'input': call.args,
            },
        ],
      });
      return;
    }
    history.add({
      'role': 'assistant',
      'content': turn.text.isEmpty ? null : turn.text,
      if (calls.isNotEmpty)
        'tool_calls': [
          for (final call in calls)
            {
              'id': call.id,
              'type': 'function',
              'function': {
                'name': call.name,
                'arguments': jsonEncode(call.args),
              },
            },
        ],
    });
  }
}

class _SeedMessage {
  const _SeedMessage({required this.isUser, required this.text});
  final bool isUser;
  final String text;
}

class _PendingInput {
  const _PendingInput({
    required this.text,
    required this.files,
    required this.toolResults,
    required this.contextCheckpoint,
  });

  factory _PendingInput.fromRequest(ModelRequest request) => _PendingInput(
    text: request.text,
    files: List.unmodifiable(
      LocalAttachmentStore.resolve(request.uploadedRefs),
    ),
    toolResults: List.unmodifiable([
      for (final item in request.toolResults ?? const <Map<String, dynamic>>[])
        Map<String, dynamic>.from(item),
    ]),
    contextCheckpoint: request.contextCheckpoint,
  );

  final String text;
  final List<LocalAttachment> files;
  final List<Map<String, dynamic>> toolResults;
  final String? contextCheckpoint;
}

class _ConversationExchange {
  const _ConversationExchange({required this.input, required this.turn});
  final _PendingInput input;
  final ModelTurn turn;
}

class ByokModelAdapter extends ModelAdapter {
  static const _maxResponseBytes = 8 * 1024 * 1024;
  static const _maxErrorBytes = 256 * 1024;
  static const _maxSseBufferChars = 2 * 1024 * 1024;

  ByokModelAdapter({
    required this.provider,
    required this.maxOutputTokens,
    ByokConversationState? conversation,
    http.Client? client,
    String? Function(String ref)? readSecret,
    this.timeout = const Duration(seconds: 240),
  }) : conversation = conversation ?? ByokConversationState(),
       _client = client ?? http.Client(),
       _readSecret = readSecret ?? SecretVault.read;

  final ByokProvider provider;
  final int maxOutputTokens;
  final Duration timeout;
  final ByokConversationState conversation;
  final http.Client _client;
  final String? Function(String ref) _readSecret;

  bool _cancelled = false;
  Completer<void>? _abort;

  bool _disposed = false;

  bool get _isAnthropic =>
      provider.wireFormat == ByokWireFormat.anthropicMessages;

  @override
  String get modelKey => provider.modelId;

  @override
  Future<void> startFreshSession() async => conversation.clear();

  @override
  Future<bool> cancel() async {
    _cancelled = true;
    final abort = _abort;
    if (abort == null || abort.isCompleted) return false;
    abort.complete();
    return true;
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _cancelled = true;
    final abort = _abort;
    if (abort != null && !abort.isCompleted) abort.complete();
    _client.close();
  }

  String _requireSecret() {
    final secret = _readSecret(provider.secretRef);
    if (secret == null || secret.trim().isEmpty) {
      throw ApiException(
        'کلید «${provider.label}» در دسترس نیست؛ دوباره واردش کن.',
        401,
        code: 'byok_secret_missing',
      );
    }
    return secret.trim();
  }

  @override
  Future<ModelTurn> send(ModelRequest request) async {
    _cancelled = false;
    final secret = _requireSecret();
    final pending = _PendingInput.fromRequest(request);
    final history = conversation._messagesFor(
      anthropic: _isAnthropic,
      pending: pending,
    );

    final wantsStream = request.onDelta != null;
    final body = _isAnthropic
        ? _anthropicBody(request, history)
        : _openAiBody(request, history);
    if (wantsStream) body['stream'] = true;

    final uri = Uri.parse(
      '${provider.effectiveBaseUrl}'
      '${_isAnthropic ? '/messages' : '/chat/completions'}',
    );
    final abort = Completer<void>();
    _abort = abort;
    final httpRequest =
        http.AbortableRequest('POST', uri, abortTrigger: abort.future)
          ..headers.addAll({
            'content-type': 'application/json',
            if (wantsStream) 'accept': 'text/event-stream',
            ...provider.safeHeaders,
            if (_isAnthropic) ...{
              'x-api-key': secret,
              'anthropic-version': '2023-06-01',
            } else
              'authorization': 'Bearer $secret',
          })
          ..body = jsonEncode(body);

    try {
      late http.StreamedResponse response;
      try {
        response = await _client.send(httpRequest).timeout(timeout);
      } on TimeoutException {
        if (!abort.isCompleted) abort.complete();
        throw const ApiException('پاسخ ارائه‌دهنده به‌موقع نرسید.', 504);
      } catch (_) {
        if (_cancelled) throw StateError('لغو شد');
        throw const ApiException('اتصال به ارائه‌دهنده برقرار نشد.', 0);
      }

      if (response.statusCode < 200 || response.statusCode >= 300) {
        final raw = await _readLimitedBody(response, _maxErrorBytes);
        throw ApiException(
          _errorMessage(raw, response.statusCode),
          response.statusCode,
          retryAfter: ApiException.parseRetryAfter(response.headers),
        );
      }

      if (!wantsStream) {
        final raw = await _readLimitedBody(response, _maxResponseBytes);
        final decoded = jsonDecode(raw);
        if (decoded is! Map) {
          throw const ApiException('پاسخ ارائه‌دهنده قابل خواندن نبود.', 502);
        }
        final map = Map<String, dynamic>.from(decoded);
        final turn = _isAnthropic ? _readAnthropic(map) : _readOpenAi(map);
        if (turn.text.isNotEmpty) request.onDelta?.call(turn.text);
        conversation._commit(pending, turn);
        return turn;
      }

      final reply = await _consumeSse(response, request.onDelta!);
      if (_cancelled) throw StateError('لغو شد');
      final turn = _isAnthropic
          ? _finishAnthropic(reply)
          : _finishOpenAi(reply);
      conversation._commit(pending, turn);
      return turn;
    } finally {
      if (identical(_abort, abort)) _abort = null;
    }
  }

  Future<_StreamedReply> _consumeSse(
    http.StreamedResponse response,
    void Function(String delta) onDelta,
  ) async {
    final reply = _StreamedReply();
    var buffer = '';

    void handleBlock(String block) {
      String? name;
      final data = StringBuffer();
      for (final line in block.split('\n')) {
        final trimmed = line.trimRight();
        if (trimmed.isEmpty || trimmed.startsWith(':')) continue;
        if (trimmed.startsWith('event:')) {
          name = trimmed.substring(6).trim();
        } else if (trimmed.startsWith('data:')) {
          data.write(trimmed.substring(5).trim());
        }
      }
      final raw = data.toString();
      if (raw.isEmpty || raw == '[DONE]') return;
      Object? payload;
      try {
        payload = jsonDecode(raw);
      } catch (_) {
        return;
      }
      if (payload is! Map) return;
      final map = Map<String, dynamic>.from(payload);
      if (_isAnthropic) {
        _handleAnthropicEvent(name, map, reply, onDelta);
      } else {
        _handleOpenAiEvent(map, reply, onDelta);
      }
    }

    try {
      await for (final chunk
          in response.stream.transform(utf8.decoder).timeout(timeout)) {
        if (_cancelled) break;
        buffer = (buffer + chunk).replaceAll('\r\n', '\n');
        if (buffer.length > _maxSseBufferChars) {
          throw const ApiException('پاسخ ارائه‌دهنده بیش از حد بزرگ بود.', 502);
        }
        final blocks = buffer.split('\n\n');
        buffer = blocks.removeLast();
        for (final block in blocks) {
          handleBlock(block);
        }
      }
      if (buffer.trim().isNotEmpty) handleBlock(buffer);
    } on TimeoutException {
      final abort = _abort;
      if (abort != null && !abort.isCompleted) abort.complete();
      throw const ApiException('پاسخ ارائه‌دهنده به‌موقع نرسید.', 504);
    } on ApiException {
      rethrow;
    } catch (_) {
      throw const ApiException('ارتباط وسط پاسخ قطع شد.', 0);
    }
    return reply;
  }

  void _handleOpenAiEvent(
    Map<String, dynamic> payload,
    _StreamedReply reply,
    void Function(String delta) onDelta,
  ) {
    final choice = (payload['choices'] as List?)?.firstOrNull;
    if (choice is! Map) return;
    final finish = choice['finish_reason'];
    if (finish is String && finish.isNotEmpty) reply.finishReason = finish;

    final delta = choice['delta'];
    if (delta is! Map) return;

    final piece = delta['content'];
    if (piece is String && piece.isNotEmpty) {
      reply.text.write(piece);
      onDelta(piece);
    }

    final calls = delta['tool_calls'];
    if (calls is! List) return;
    for (final item in calls) {
      if (item is! Map) continue;
      final index = (item['index'] as num?)?.toInt() ?? 0;
      final partial = reply.callAt(index);
      final id = item['id'];
      if (id is String && id.isNotEmpty) partial.id = id;
      final fn = item['function'];
      if (fn is! Map) continue;
      final name = fn['name'];
      if (name is String && name.isNotEmpty) partial.name = name;
      final args = fn['arguments'];
      if (args is String) partial.arguments.write(args);
    }
  }

  void _handleAnthropicEvent(
    String? name,
    Map<String, dynamic> payload,
    _StreamedReply reply,
    void Function(String delta) onDelta,
  ) {
    switch (name) {
      case 'content_block_start':
        final index = (payload['index'] as num?)?.toInt() ?? 0;
        final block = payload['content_block'];
        if (block is Map && block['type'] == 'tool_use') {
          final partial = reply.callAt(index)
            ..id = block['id']?.toString() ?? ''
            ..name = block['name']?.toString() ?? '';
          partial.arguments.clear();
        }
      case 'content_block_delta':
        final index = (payload['index'] as num?)?.toInt() ?? 0;
        final delta = payload['delta'];
        if (delta is! Map) return;
        switch (delta['type']) {
          case 'text_delta':
            final piece = delta['text'];
            if (piece is String && piece.isNotEmpty) {
              reply.text.write(piece);
              onDelta(piece);
            }
          case 'input_json_delta':
            final piece = delta['partial_json'];
            if (piece is String) reply.callAt(index).arguments.write(piece);
        }
      case 'message_delta':
        final delta = payload['delta'];
        if (delta is Map) {
          final stop = delta['stop_reason'];
          if (stop is String && stop.isNotEmpty) reply.finishReason = stop;
        }
      case 'error':
        final error = payload['error'];
        throw ApiException(
          error is Map
              ? error['message']?.toString() ?? 'ارائه‌دهنده خطا داد.'
              : 'ارائه‌دهنده خطا داد.',
          502,
        );
    }
  }

  ModelTurn _finishOpenAi(_StreamedReply reply) {
    final calls = reply.toolCalls();
    final text = reply.text.toString();
    return ModelTurn(
      text: text,
      toolCalls: calls.isEmpty ? null : calls,
      finishReason: reply.finishReason,
    );
  }

  ModelTurn _finishAnthropic(_StreamedReply reply) {
    final calls = reply.toolCalls();
    final text = reply.text.toString();
    return ModelTurn(
      text: text,
      toolCalls: calls.isEmpty ? null : calls,
      finishReason: reply.finishReason,
    );
  }

  Map<String, dynamic> _openAiBody(
    ModelRequest request,
    List<Map<String, dynamic>> history,
  ) => {
    'model': provider.modelId,
    'messages': history,
    if (provider.kind == ByokProviderKind.openAi)
      'max_completion_tokens': maxOutputTokens
    else
      'max_tokens': maxOutputTokens,
    if (request.tools != null && request.tools!.isNotEmpty)
      'tools': [
        for (final tool in request.tools!)
          {'type': 'function', 'function': _functionDefinition(tool)},
      ],
  };

  Map<String, dynamic> _anthropicBody(
    ModelRequest request,
    List<Map<String, dynamic>> history,
  ) => {
    'model': provider.modelId,
    'messages': history,
    'max_tokens': maxOutputTokens,
    if (request.tools != null && request.tools!.isNotEmpty)
      'tools': [
        for (final tool in request.tools!) _anthropicToolDefinition(tool),
      ],
  };

  static Map<String, dynamic> _functionDefinition(Map<String, dynamic> tool) {
    final nested = tool['function'];
    final source = nested is Map
        ? Map<String, dynamic>.from(nested)
        : Map<String, dynamic>.from(tool);
    final name = source['name']?.toString().trim() ?? '';
    if (!RegExp(r'^[A-Za-z0-9_-]{1,64}$').hasMatch(name)) {
      throw StateError(
        'تعریف ابزار نامعتبر است: نام ابزار باید ۱ تا ۶۴ نویسهٔ انگلیسی، عدد، خط تیره یا زیرخط باشد.',
      );
    }

    final rawParameters = source['parameters'];
    final parameters = rawParameters is Map
        ? Map<String, dynamic>.from(rawParameters)
        : <String, dynamic>{'type': 'object', 'properties': const {}};
    parameters.putIfAbsent('type', () => 'object');

    final description = source['description']?.toString().trim();
    return {
      'name': name,
      if (description != null && description.isNotEmpty)
        'description': description,
      'parameters': parameters,
      if (source['strict'] is bool) 'strict': source['strict'],
    };
  }

  static Map<String, dynamic> _anthropicToolDefinition(
    Map<String, dynamic> tool,
  ) {
    final function = _functionDefinition(tool);
    return {
      'name': function['name'],
      if (function['description'] != null)
        'description': function['description'],
      'input_schema': function['parameters'],
    };
  }

  ModelTurn _readOpenAi(Map<String, dynamic> json) {
    final choice = (json['choices'] as List?)?.firstOrNull;
    final message = choice is Map ? choice['message'] : null;
    final text = message is Map ? message['content']?.toString() ?? '' : '';
    final rawCalls = message is Map ? message['tool_calls'] : null;

    final calls = <ToolCall>[];
    if (rawCalls is List) {
      for (final item in rawCalls) {
        if (item is! Map) continue;
        final fn = item['function'];
        if (fn is! Map) continue;
        calls.add(
          ToolCall(
            id: item['id']?.toString() ?? '',
            name: fn['name']?.toString() ?? '',
            args: decodeArgs(fn['arguments']),
          ),
        );
      }
    }
    return ModelTurn(
      text: text,
      toolCalls: calls.isEmpty ? null : calls,
      finishReason: choice is Map ? choice['finish_reason']?.toString() : null,
    );
  }

  ModelTurn _readAnthropic(Map<String, dynamic> json) {
    final content = json['content'];
    final buffer = StringBuffer();
    final calls = <ToolCall>[];
    if (content is List) {
      for (final block in content) {
        if (block is! Map) continue;
        switch (block['type']) {
          case 'text':
            buffer.write(block['text']?.toString() ?? '');
          case 'tool_use':
            calls.add(
              ToolCall(
                id: block['id']?.toString() ?? '',
                name: block['name']?.toString() ?? '',
                args: block['input'] is Map
                    ? Map<String, dynamic>.from(block['input'] as Map)
                    : const {},
              ),
            );
        }
      }
    }
    return ModelTurn(
      text: buffer.toString(),
      toolCalls: calls.isEmpty ? null : calls,
      finishReason: json['stop_reason']?.toString(),
    );
  }

  static Map<String, dynamic> decodeArgs(Object? raw) {
    if (raw is Map) return Map<String, dynamic>.from(raw);
    if (raw is String && raw.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) return Map<String, dynamic>.from(decoded);
      } catch (_) {}
    }
    return const {};
  }

  static Future<String> _readLimitedBody(
    http.StreamedResponse response,
    int maxBytes,
  ) async {
    final bytes = <int>[];
    await for (final chunk in response.stream) {
      if (bytes.length + chunk.length > maxBytes) {
        throw const ApiException('پاسخ ارائه‌دهنده بیش از حد بزرگ بود.', 502);
      }
      bytes.addAll(chunk);
    }
    return utf8.decode(bytes, allowMalformed: true);
  }

  static String _errorMessage(String raw, int statusCode) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        final error = decoded['error'];
        if (error is Map) {
          return _clipError(
            error['message']?.toString() ?? 'درخواست انجام نشد.',
          );
        }
        if (error is String) return _clipError(error);
      }
    } catch (_) {}
    return 'ارائه‌دهنده درخواست را رد کرد ($statusCode).';
  }

  static String _clipError(String value) =>
      value.length <= 1000 ? value : '${value.substring(0, 1000)}…';
}
