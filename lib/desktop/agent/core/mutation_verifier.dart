import '../tools/agent_tool.dart';

class MutationVerifier {
  static const mutatingTools = {
    'write_file',
    'append_file',
    'edit_file',
    'move_path',
    'delete_path',
  };

  static const maxPaths = 8;
  static const maxErrorChars = 120;

  final Map<String, String> _failures = {};

  bool get hasFailures => _failures.isNotEmpty;

  void record(ToolCall call, ToolResult result) {
    if (!mutatingTools.contains(call.name)) return;
    final path = _pathOf(call);
    if (path.isEmpty) return;

    if (result.ok) {
      _failures.remove(path);
      return;
    }
    _failures.putIfAbsent(path, () => _clip(result.error ?? result.summary));
  }

  void reset() => _failures.clear();

  String? footer() {
    if (_failures.isEmpty) return null;
    final entries = _failures.entries.take(maxPaths);
    final lines = [
      for (final entry in entries) '• ${entry.key} — ${entry.value}',
    ];
    final extra = _failures.length - lines.length;

    return '⚠ این مسیرها در این نوبت **تغییر نکردند**، صرف‌نظر از هر '
        'ادعایی که در متن بالا آمده باشد:\n${lines.join('\n')}'
        '${extra > 0 ? '\n• و $extra مورد دیگر' : ''}';
  }

  static String _pathOf(ToolCall call) {
    for (final key in const ['path', 'from', 'file']) {
      final value = call.args[key];
      if (value is String && value.trim().isNotEmpty) return value.trim();
    }
    return '';
  }

  static String _clip(String value) {
    final trimmed = value.trim().replaceAll('\n', ' ');
    return trimmed.length <= maxErrorChars
        ? trimmed
        : '${trimmed.substring(0, maxErrorChars)}…';
  }
}
