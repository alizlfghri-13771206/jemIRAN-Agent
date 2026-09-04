import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:jemiran/desktop/agent/byok/byok_adapter.dart';
import 'package:jemiran/desktop/agent/byok/byok_provider.dart';
import 'package:jemiran/desktop/agent/core/model_adapter.dart';

const _secret = 'sk-LIFECYCLE-9f21';

class _CountingClient extends http.BaseClient {
  int closeCount = 0;
  int sendCount = 0;
  bool closed = false;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (closed) {
      throw StateError('Client is already closed');
    }
    sendCount++;
    final body = jsonEncode({
      'choices': [
        {
          'index': 0,
          'message': {'role': 'assistant', 'content': 'سلام'},
          'finish_reason': 'stop',
        },
      ],
    });
    return http.StreamedResponse(
      Stream.value(utf8.encode(body)),
      200,
      headers: {'content-type': 'application/json'},
    );
  }

  @override
  void close() {
    closeCount++;
    closed = true;
  }
}

class _BlockingClient extends http.BaseClient {
  final started = Completer<void>();
  bool aborted = false;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (request is! http.AbortableRequest || request.abortTrigger == null) {
      throw StateError('درخواست باید در سطح انتقال قابل لغو باشد');
    }
    started.complete();
    await request.abortTrigger;
    aborted = true;
    throw http.RequestAbortedException(request.url);
  }
}

ByokModelAdapter _adapter(http.Client client) => ByokModelAdapter(
  provider: ByokProvider(
    id: 'p1',
    kind: ByokProviderKind.openAi,
    label: 'OpenAI',
    modelId: 'gpt-5.6-sol',
  ),
  maxOutputTokens: 512,
  readSecret: (_) => _secret,
  client: client,
);

void main() {
  group('چرخهٔ عمر کلاینت BYOK', () {
    test('لغو بدون انتقال فعال، آداپتور را برای نوبت بعدی نمی‌کُشد', () async {
      final client = _CountingClient();
      final adapter = _adapter(client);

      expect(await adapter.cancel(), isFalse);
      expect(client.closeCount, 0, reason: 'لغو نباید کلاینت را ببندد');

      final turn = await adapter.send(ModelRequest(text: 'سلام'));
      expect(turn.text, 'سلام');
      expect(client.sendCount, 1);
    });

    test('لغو، انتقال HTTP فعال را واقعاً قطع می‌کند', () async {
      final client = _BlockingClient();
      final adapter = _adapter(client);
      final pending = adapter.send(const ModelRequest(text: 'سلام'));
      final expectation = expectLater(pending, throwsA(isA<StateError>()));
      await client.started.future;

      expect(await adapter.cancel(), isTrue);
      await expectation;
      expect(client.aborted, isTrue);
      expect(await adapter.cancel(), isFalse);
    });

    test('dispose کلاینت را می‌بندد و دوباره‌بستن بی‌خطر است', () async {
      final client = _CountingClient();
      final adapter = _adapter(client);

      await adapter.send(ModelRequest(text: 'سلام'));
      await adapter.dispose();
      expect(client.closeCount, 1);

      await adapter.dispose();
      expect(client.closeCount, 1, reason: 'dispose باید idempotent باشد');
    });
  });
}
