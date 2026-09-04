import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:jemiran/desktop/agent/byok/byok_adapter.dart';
import 'package:jemiran/desktop/agent/byok/byok_provider.dart';
import 'package:jemiran/desktop/agent/core/model_adapter.dart';
import 'package:jemiran/desktop/agent/network/provider_exception.dart';

const _secret = 'sk-STREAM-SECRET-c40e';

ByokProvider _provider(ByokProviderKind kind) => ByokProvider(
  id: 'p1',
  kind: kind,
  label: kind.label,
  modelId: kind == ByokProviderKind.anthropic
      ? 'claude-sonnet-5'
      : 'gpt-5.6-sol',
);

ByokModelAdapter _sseAdapter(
  ByokProviderKind kind,
  List<String> chunks, {
  void Function(http.BaseRequest request)? onRequest,
}) => ByokModelAdapter(
  provider: _provider(kind),
  maxOutputTokens: 2048,
  readSecret: (_) => _secret,
  client: MockClient.streaming((request, _) async {
    onRequest?.call(request);
    return http.StreamedResponse(
      Stream.fromIterable(chunks.map(utf8.encode)),
      200,
      headers: {'content-type': 'text/event-stream'},
    );
  }),
);

String _openAiDelta(Map<String, dynamic> delta, {String? finish}) {
  final payload = jsonEncode({
    'choices': [
      {'index': 0, 'delta': delta, 'finish_reason': finish},
    ],
  });
  return 'data: $payload\n\n';
}

String _anthropicEvent(String name, Map<String, dynamic> payload) =>
    'event: $name\ndata: ${jsonEncode(payload)}\n\n';

void main() {
  group('stream — قالب OpenAI', () {
    test('متن تکه‌تکه زنده تحویل می‌شود', () async {
      final adapter = _sseAdapter(ByokProviderKind.openAi, [
        _openAiDelta({'content': 'سلام '}),
        _openAiDelta({'content': 'دنیا'}),
        _openAiDelta(const {}, finish: 'stop'),
        'data: [DONE]\n\n',
      ]);

      final pieces = <String>[];
      final turn = await adapter.send(
        ModelRequest(text: 'x', onDelta: pieces.add),
      );

      expect(pieces, ['سلام ', 'دنیا']);
      expect(turn.text, 'سلام دنیا');
      expect(turn.finishReason, 'stop');
    });

    test('stream فقط وقتی روشن می‌شود که delta خواسته شده باشد', () async {
      late http.BaseRequest streaming;
      final withDelta = _sseAdapter(ByokProviderKind.openAi, [
        _openAiDelta(const {'content': 'ok'}, finish: 'stop'),
      ], onRequest: (request) => streaming = request);
      await withDelta.send(ModelRequest(text: 'x', onDelta: (_) {}));
      final streamBody =
          jsonDecode((streaming as http.Request).body) as Map<String, dynamic>;
      expect(streamBody['stream'], isTrue);
      expect(streaming.headers['accept'], 'text/event-stream');

      late http.Request plain;
      final withoutDelta = ByokModelAdapter(
        provider: _provider(ByokProviderKind.openAi),
        maxOutputTokens: 2048,
        readSecret: (_) => _secret,
        client: MockClient((request) async {
          plain = request;
          return http.Response(
            jsonEncode({
              'choices': [
                {
                  'finish_reason': 'stop',
                  'message': {'content': 'ok'},
                },
              ],
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );
      await withoutDelta.send(const ModelRequest(text: 'x'));
      final plainBody = jsonDecode(plain.body) as Map<String, dynamic>;
      expect(plainBody.containsKey('stream'), isFalse);
    });

    test('آرگومان ابزار از چند تکه سرِ هم می‌شود', () async {
      final adapter = _sseAdapter(ByokProviderKind.openAi, [
        _openAiDelta({
          'tool_calls': [
            {
              'index': 0,
              'id': 'call_1',
              'function': {'name': 'read_file', 'arguments': '{"pa'},
            },
          ],
        }),
        _openAiDelta({
          'tool_calls': [
            {
              'index': 0,
              'function': {'arguments': 'th":"a.txt"}'},
            },
          ],
        }),
        _openAiDelta(const {}, finish: 'tool_calls'),
        'data: [DONE]\n\n',
      ]);

      final pieces = <String>[];
      final turn = await adapter.send(
        ModelRequest(text: 'x', onDelta: pieces.add),
      );

      expect(turn.toolCalls, hasLength(1));
      expect(turn.toolCalls!.single.args['path'], 'a.txt');
      expect(pieces, isEmpty);
    });

    test('چند فراخوان درهم‌بافته با index از هم جدا می‌مانند', () async {
      final adapter = _sseAdapter(ByokProviderKind.openAi, [
        _openAiDelta({
          'tool_calls': [
            {
              'index': 0,
              'id': 'c0',
              'function': {'name': 'read_file', 'arguments': '{"path":'},
            },
            {
              'index': 1,
              'id': 'c1',
              'function': {'name': 'find_files', 'arguments': '{"q":'},
            },
          ],
        }),
        _openAiDelta({
          'tool_calls': [
            {
              'index': 1,
              'function': {'arguments': '"b"}'},
            },
            {
              'index': 0,
              'function': {'arguments': '"a.txt"}'},
            },
          ],
        }),
        _openAiDelta(const {}, finish: 'tool_calls'),
      ]);

      final turn = await adapter.send(ModelRequest(text: 'x', onDelta: (_) {}));
      expect(turn.toolCalls, hasLength(2));
      expect(turn.toolCalls![0].name, 'read_file');
      expect(turn.toolCalls![0].args['path'], 'a.txt');
      expect(turn.toolCalls![1].name, 'find_files');
      expect(turn.toolCalls![1].args['q'], 'b');
    });
  });

  group('stream — قالب Anthropic', () {
    test('متن و tool_use از رویدادهای نام‌دار ساخته می‌شوند', () async {
      final adapter = _sseAdapter(ByokProviderKind.anthropic, [
        _anthropicEvent('content_block_start', {
          'index': 0,
          'content_block': {'type': 'text'},
        }),
        _anthropicEvent('content_block_delta', {
          'index': 0,
          'delta': {'type': 'text_delta', 'text': 'می‌خوانم'},
        }),
        _anthropicEvent('content_block_start', {
          'index': 1,
          'content_block': {
            'type': 'tool_use',
            'id': 'toolu_1',
            'name': 'read_file',
          },
        }),
        _anthropicEvent('content_block_delta', {
          'index': 1,
          'delta': {'type': 'input_json_delta', 'partial_json': '{"path"'},
        }),
        _anthropicEvent('content_block_delta', {
          'index': 1,
          'delta': {'type': 'input_json_delta', 'partial_json': ':"b.txt"}'},
        }),
        _anthropicEvent('message_delta', {
          'delta': {'stop_reason': 'tool_use'},
        }),
        _anthropicEvent('message_stop', const {}),
      ]);

      final pieces = <String>[];
      final turn = await adapter.send(
        ModelRequest(text: 'x', onDelta: pieces.add),
      );

      expect(pieces, ['می‌خوانم']);
      expect(turn.text, 'می‌خوانم');
      expect(turn.finishReason, 'tool_use');
      expect(turn.toolCalls!.single.id, 'toolu_1');
      expect(turn.toolCalls!.single.args['path'], 'b.txt');
    });

    test('رویداد error در میانهٔ stream به خطا تبدیل می‌شود', () async {
      final adapter = _sseAdapter(ByokProviderKind.anthropic, [
        _anthropicEvent('error', {
          'error': {'message': 'سقف نرخ'},
        }),
      ]);
      await expectLater(
        adapter.send(ModelRequest(text: 'x', onDelta: (_) {})),
        throwsA(isA<ApiException>()),
      );
    });
  });

  group('استحکام پارسر', () {
    test('CRLF شکسته روی مرز دو تکه، مرز رویداد را گم نمی‌کند', () async {
      final event = _openAiDelta(const {
        'content': 'سلام',
      }, finish: 'stop').replaceAll('\n', '\r\n');
      final cut = event.indexOf('\r\n\r\n') + 1;
      final adapter = _sseAdapter(ByokProviderKind.openAi, [
        event.substring(0, cut),
        event.substring(cut),
      ]);

      final pieces = <String>[];
      await adapter.send(ModelRequest(text: 'x', onDelta: pieces.add));
      expect(pieces, ['سلام']);
    });

    test('کامنت SSE و JSON خراب نادیده گرفته می‌شوند', () async {
      final adapter = _sseAdapter(ByokProviderKind.openAi, [
        ': OPENROUTER PROCESSING\n\n',
        'data: {این JSON نیست\n\n',
        _openAiDelta(const {'content': 'خوب'}, finish: 'stop'),
      ]);

      final pieces = <String>[];
      final turn = await adapter.send(
        ModelRequest(text: 'x', onDelta: pieces.add),
      );
      expect(pieces, ['خوب']);
      expect(turn.text, 'خوب');
    });

    test('پاسخ stream هم به تاریخچه اضافه می‌شود', () async {
      final bodies = <Map<String, dynamic>>[];
      final adapter = ByokModelAdapter(
        provider: _provider(ByokProviderKind.openAi),
        maxOutputTokens: 2048,
        readSecret: (_) => _secret,
        client: MockClient.streaming((request, bodyStream) async {
          bodies.add(
            jsonDecode(await bodyStream.bytesToString())
                as Map<String, dynamic>,
          );
          return http.StreamedResponse(
            Stream.fromIterable(
              [
                _openAiDelta(const {'content': 'ok'}, finish: 'stop'),
              ].map(utf8.encode),
            ),
            200,
          );
        }),
      );

      await adapter.send(ModelRequest(text: 'یک', onDelta: (_) {}));
      await adapter.send(ModelRequest(text: 'دو', onDelta: (_) {}));

      final messages = (bodies.last['messages'] as List).cast<Map>();
      expect(messages, hasLength(3));
      expect(messages[1]['role'], 'assistant');
      expect(messages[1]['content'], 'ok');
    });
  });
}
