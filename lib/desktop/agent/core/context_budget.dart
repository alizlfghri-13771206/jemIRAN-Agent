import 'dart:convert';
import 'dart:math' as math;

import 'agent_protocol.dart';

class ContextBudget {
  const ContextBudget({
    required this.maxContextTokens,
    required this.reservedOutputTokens,
  });

  static const fallback = ContextBudget(
    maxContextTokens: 16000,
    reservedOutputTokens: 4096,
  );

  final int maxContextTokens;
  final int reservedOutputTokens;

  static const compactionRatio = 0.80;
  static const safetyMarginRatio = 0.05;

  static const minThresholdTokens = 2000;

  factory ContextBudget.fromModelConfig(Map<String, dynamic> model) {
    final context = (model['max_context_tokens'] as num?)?.toInt();
    final output =
        (model['default_output_tokens'] as num?)?.toInt() ??
        (model['max_output_tokens'] as num?)?.toInt();
    if (context == null || context <= 0) return fallback;
    return ContextBudget(
      maxContextTokens: context,
      reservedOutputTokens: math.max(
        512,
        math.min(output ?? fallback.reservedOutputTokens, context ~/ 2),
      ),
    );
  }

  int get usableInputTokens {
    final margin = (maxContextTokens * safetyMarginRatio).ceil();
    return math.max(0, maxContextTokens - reservedOutputTokens - margin);
  }

  int compactionThresholdTokens({int toolSchemaTokens = 0}) {
    final available = usableInputTokens - toolSchemaTokens;
    return math.max(minThresholdTokens, (available * compactionRatio).floor());
  }

  static const toolEnvelopeTokens = 8;

  int thresholdForTools(List<Map<String, dynamic>>? tools) =>
      compactionThresholdTokens(
        toolSchemaTokens: tools == null || tools.isEmpty
            ? 0
            : AgentProtocol.estimatedTokens(jsonEncode(tools)) +
                  tools.length * toolEnvelopeTokens,
      );

  @override
  String toString() =>
      'ContextBudget(context: $maxContextTokens, output: $reservedOutputTokens)';

  @override
  bool operator ==(Object other) =>
      other is ContextBudget &&
      other.maxContextTokens == maxContextTokens &&
      other.reservedOutputTokens == reservedOutputTokens;

  @override
  int get hashCode => Object.hash(maxContextTokens, reservedOutputTokens);
}
