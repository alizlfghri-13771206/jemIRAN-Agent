import '../tools/agent_tool.dart';

class ModelRequest {
  const ModelRequest({
    required this.text,
    this.uploadedRefs,
    this.idempotencyKey,
    this.onDelta,
    this.onAttemptStart,
    this.tools,
    this.toolResults,
    this.contextCheckpoint,
    this.cacheSessionId,
  });

  final List<Map<String, dynamic>>? tools;

  final List<Map<String, dynamic>>? toolResults;

  final String? contextCheckpoint;

  final String? cacheSessionId;

  final void Function()? onAttemptStart;

  final String text;

  final List<String>? uploadedRefs;

  final String? idempotencyKey;

  final void Function(String delta)? onDelta;

  ModelRequest withIdempotencyKey(String key) => ModelRequest(
    text: text,
    uploadedRefs: uploadedRefs,
    idempotencyKey: key,
    onDelta: onDelta,
    onAttemptStart: onAttemptStart,
    tools: tools,
    toolResults: toolResults,
    contextCheckpoint: contextCheckpoint,
    cacheSessionId: cacheSessionId,
  );
}

class ModelTurn {
  const ModelTurn({
    required this.text,
    this.imageUrl,
    this.sessionId,
    this.toolCalls,
    this.finishReason,
  });

  final String text;

  final List<ToolCall>? toolCalls;

  final String? finishReason;

  final String? imageUrl;

  final int? sessionId;
}

abstract class ModelAdapter {
  String get modelKey;

  bool get keepsHistory => true;

  Future<ModelTurn> send(ModelRequest request);

  Future<void> startFreshSession() async {}

  Future<void> dispose() async {}

  Future<bool> cancel() async => false;
}
