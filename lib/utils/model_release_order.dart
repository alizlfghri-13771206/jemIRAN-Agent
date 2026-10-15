// Release metadata snapshot from OpenRouter; managed catalogues remain server ordered.
const _preferredIds = <String>[
  'google/gemini-4-argon',
  'google/gemini-3.8-flash',
  'google/gemini-3.7-flash',
  'google/gemini-3.6-flash',
  'google/gemini-3.5-flash-lite',
  'openai/gpt-6-astra',
  'openai/gpt-6.1-sol',
  'openai/gpt-5.6-sol',
  'openai/gpt-5.6-luna-pro',
  'openai/gpt-5.6-luna',
  'openai/gpt-5-mini',
  'openai/gpt-4o-mini',
  'openai/gpt-oss-120b',
  'anthropic/claude-fable-5.1',
  'anthropic/claude-opus-5.5',
  'anthropic/claude-sonnet-5.5',
  'anthropic/claude-haiku-5.5',
  'anthropic/claude-opus-5',
  'anthropic/claude-sonnet-5',
  'anthropic/claude-sonnet-4.6',
];
const _releasedAt = <String, int>{
  'anthropic/claude-fable-5': 1781007515,
  'anthropic/claude-fable-5.1': 1788285838,
  'anthropic/claude-haiku-4.5': 1760547638,
  'anthropic/claude-haiku-5.5': 1791397883,
  'anthropic/claude-opus-5': 1784912544,
  'anthropic/claude-opus-5.5': 1790094732,
  'anthropic/claude-sonnet-4.6': 1771342990,
  'anthropic/claude-sonnet-5': 1782843083,
  'anthropic/claude-sonnet-5.5': 1790618686,
  'deepseek/deepseek-v3.2': 1764594642,
  'deepseek/deepseek-v4-flash-0731': 1785478908,
  'deepseek/deepseek-v4-flash-vision-exp': 1787311563,
  'deepseek/deepseek-v4-pro-0813': 1786549364,
  'deepseek/deepseek-v4.1-flash': 1789021285,
  'dots-studio/dots-3-note-preview:free': 1786680361,
  'google/gemini-2.5-flash-image': 1759870431,
  'google/gemini-3-pro-image': 1781754054,
  'google/gemini-3.1-flash-image': 1781754065,
  'google/gemini-3.5-flash-lite': 1784646726,
  'google/gemini-3.6-flash': 1784646733,
  'google/gemini-3.7-flash': 1786640581,
  'google/gemini-3.8-flash': 1788362056,
  'google/gemini-4-argon': 1791907477,
  'google/gemini-nano-banana-2.1': 1791300825,
  'google/gemma-4-26b-a4b-it:free': 1775227989,
  'meta/muse-spark-1.2': 1785959287,
  'meta/muse-spark-1.3': 1788378359,
  'moonshotai/kimi-k3': 1784215858,
  'nvidia/nemotron-3-super-120b-a12b:free': 1773245239,
  'nvidia/nemotron-3-ultra-550b-a55b:free': 1780551208,
  'openai/gpt-4o-mini': 1721260800,
  'openai/gpt-5-image': 1760447986,
  'openai/gpt-5-image-mini': 1760624583,
  'openai/gpt-5-mini': 1754587407,
  'openai/gpt-5.6-luna': 1783590864,
  'openai/gpt-5.6-luna-pro': 1783590867,
  'openai/gpt-5.6-sol': 1783590850,
  'openai/gpt-5.6-terra': 1783590857,
  'openai/gpt-6-astra': 1788552838,
  'openai/gpt-6-luna-pro': 1790100791,
  'openai/gpt-6-sol': 1790100775,
  'openai/gpt-6.1-sol': 1790702882,
  'openai/gpt-audio': 1768862569,
  'openai/gpt-audio-mini': 1768859419,
  'openai/gpt-oss-120b': 1754414231,
  'poolside/laguna-s-2.1:free': 1784652683,
  'qwen/qwen3.7-flash': 1785190561,
  'qwen/qwen3.8-27b': 1786722910,
  'qwen/qwen3.8-flash': 1787773060,
  'qwen/qwen3.8-max-0902': 1788469704,
  'tencent/hy-mt2-1.8b': 1787231581,
  'tencent/hy3': 1783344048,
  'tencent/hy3-preview': 1776878150,
  'tencent/hy4-preview': 1787897375,
  'x-ai/grok-4.6': 1786548957,
  'x-ai/grok-4.7': 1790007541,
  'xiaomi/mimo-v2.5': 1776874269,
  'xiaomi/mimo-v2.6-flash': 1790021264,
  'xiaomi/mimo-v2.6-pro': 1790021259,
  'z-ai/glm-5.2': 1781631930,
  'z-ai/glm-5.3': 1787086655,
  'z-ai/glm-5.3-flash': 1787752741,
  'z-ai/glm-5.3-flashx': 1789744020,
};

/// Known family priorities, then release date; unknown custom IDs keep their order.
void orderByModelRelease(
  List<Map<String, dynamic>> models,
  String Function(Map<String, dynamic>) modelId,
) {
  String normalized(Map<String, dynamic> model) {
    final id = modelId(model).trim();
    return id.startsWith('gemini-') ? 'google/$id' : id;
  }

  final positions = {for (var i = 0; i < models.length; i++) models[i]: i};
  models.sort((a, b) {
    final ai = normalized(a), bi = normalized(b);
    final ar = _preferredIds.indexOf(ai), br = _preferredIds.indexOf(bi);
    if (ar >= 0 || br >= 0) {
      final rank = (ar < 0 ? 999 : ar).compareTo(br < 0 ? 999 : br);
      if (rank != 0) return rank;
    }
    final release = (_releasedAt[bi] ?? 0).compareTo(_releasedAt[ai] ?? 0);
    if (release != 0) return release;
    return positions[a]!.compareTo(positions[b]!);
  });
}
