import 'dart:io';
import 'dart:math' as math;

import 'package:path/path.dart' as p;

import '../tools/agent_tool.dart';
import 'agent_protocol.dart';
import 'agent_storage.dart';
import 'context_budget.dart';

class BoundedToolResult {
  const BoundedToolResult({
    required this.result,
    required this.spilled,
    this.path,
  });

  final ToolResult result;

  final bool spilled;

  final String? path;
}

class ToolOutputBudget {
  ToolOutputBudget(this.budget);

  final ContextBudget budget;

  static const perResultShare = 0.15;

  static const perTurnShare = 0.30;

  static const floorTokens = 400;

  static const retentionHours = 24;

  static const neverSpill = {'read_file', 'ask_user'};

  int _usedTokens = 0;
  int get usedTokens => _usedTokens;

  int get perResultCapTokens => math.max(
    floorTokens,
    (budget.usableInputTokens * perResultShare).floor(),
  );

  int get turnCapTokens => math.max(
    floorTokens * 2,
    (budget.usableInputTokens * perTurnShare).floor(),
  );

  void reset() => _usedTokens = 0;

  BoundedToolResult apply(ToolCall call, ToolResult result) {
    final encoded = result.encode();
    final tokens = AgentProtocol.estimatedTokens(encoded);

    if (neverSpill.contains(call.name)) {
      _usedTokens += tokens;
      return BoundedToolResult(result: result, spilled: false);
    }

    final overPerResult = tokens > perResultCapTokens;
    final overTurn = _usedTokens + tokens > turnCapTokens;
    if (!overPerResult && !overTurn) {
      _usedTokens += tokens;
      return BoundedToolResult(result: result, spilled: false);
    }

    final source = (result.detail ?? '').isNotEmpty ? result.detail! : encoded;
    final previewTokens = math.min(perResultCapTokens, 300);
    final preview = _clipToTokens(source, previewTokens);

    final path = _spill(call.name, source);
    final note = path == null
        ? '$preview\n\n— خروجی کامل برای رعایت سقف زمینه بریده شد.'
        : '$preview\n\n'
              '— خروجی کامل (${source.length} نویسه) برای رعایت سقف زمینه '
              'در این فایل ذخیره شد:\n$path\n'
              'اگر بخش دیگری لازم داری با `read_file` همین مسیر را بخوان.';

    final bounded = ToolResult.success(
      summary: result.summary,
      data: {
        'ok': result.ok,
        'truncated': true,
        'full_output_path': ?path,
        'preview': preview,
      },
      detail: note,
    );
    _usedTokens += AgentProtocol.estimatedTokens(bounded.encode());
    return BoundedToolResult(
      result: bounded,
      spilled: path != null,
      path: path,
    );
  }

  static String _clipToTokens(String text, int maxTokens) {
    if (text.length <= maxTokens) return text;
    final guess = math.max(1, (maxTokens * 2 / 1.25).floor());
    if (guess >= text.length) return text;
    return '${text.substring(0, guess)}\n…(بریده شد)';
  }

  static Directory? _dir() {
    final root = AgentStorage.root;
    if (root == null) return null;
    final dir = Directory(p.join(root.path, 'tool_output'));
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir;
  }

  static bool _pruned = false;

  String? _spill(String toolName, String content) {
    try {
      final dir = _dir();
      if (dir == null) return null;
      if (!_pruned) {
        _pruned = true;
        _prune(dir);
      }
      final file = File(
        p.join(
          dir.path,
          '${toolName}_${DateTime.now().microsecondsSinceEpoch}.txt',
        ),
      );
      file.writeAsStringSync(SecretScrubber.scrub(content), flush: true);
      return file.path;
    } catch (_) {
      return null;
    }
  }

  static void _prune(Directory dir) {
    try {
      final deadline = DateTime.now().subtract(
        const Duration(hours: retentionHours),
      );
      for (final entity in dir.listSync()) {
        if (entity is! File) continue;
        if (entity.statSync().modified.isBefore(deadline)) entity.deleteSync();
      }
    } catch (_) {}
  }

  static void resetPruneForTesting() => _pruned = false;
}
