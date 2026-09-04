import 'dart:convert';
import 'dart:io';

import '../core/agent_process.dart';
import '../network/agent_environment.dart';

class ProbeResult {
  const ProbeResult({
    required this.command,
    required this.installed,
    this.path,
    this.version,
  });

  final String command;
  final bool installed;

  final String? path;

  final String? version;

  Map<String, dynamic> toJson() => {
    'command': command,
    'installed': installed,
    if (path != null) 'path': path,
    if (version != null) 'version': version,
  };
}

abstract final class ToolProbe {
  static final Map<String, ProbeResult> _cache = {};

  static const _versionFlag = <String, List<String>>{
    'java': ['-version'],
    'tesseract': ['--version'],
    'magick': ['--version'],
    '7z': ['i'],
  };

  static Future<ProbeResult> probe(
    String command, {
    bool refresh = false,
  }) async {
    if (!refresh && _cache.containsKey(command)) return _cache[command]!;

    final result = await _run(command);
    _cache[command] = result;
    return result;
  }

  static Future<List<ProbeResult>> probeAll(
    Iterable<String> commands, {
    bool refresh = false,
  }) => Future.wait(commands.map((c) => probe(c, refresh: refresh)));

  static Future<ProbeResult> _run(String command) async {
    final path = await _locate(command);
    if (path == null) {
      return ProbeResult(command: command, installed: false);
    }

    try {
      final args = _versionFlag[command] ?? const ['--version'];
      final process = await AgentProcess.run(
        path,
        args,
        timeout: const Duration(seconds: 12),
        runInShell: true,
        environment: AgentEnvironment.sanitizedEnvironment(
          Platform.environment,
        ),
      );

      final raw = '${process.stdout}\n${process.stderr}'.trim();
      final firstLine = raw
          .split('\n')
          .map((l) => l.trim())
          .firstWhere((l) => l.isNotEmpty, orElse: () => '');

      return ProbeResult(
        command: command,
        installed: true,
        path: path,
        version: firstLine.isEmpty ? null : firstLine,
      );
    } catch (_) {
      return ProbeResult(command: command, installed: false, path: path);
    }
  }

  static Future<String?> _locate(String command) async {
    try {
      final result = await Process.run(
        'where.exe',
        [command],
        environment: AgentEnvironment.sanitizedEnvironment(
          Platform.environment,
        ),
        includeParentEnvironment: false,
        stdoutEncoding: const Utf8Codec(allowMalformed: true),
      ).timeout(const Duration(seconds: 8));

      if (result.exitCode != 0) return null;
      final line = (result.stdout as String)
          .split('\n')
          .map((l) => l.trim())
          .firstWhere((l) => l.isNotEmpty, orElse: () => '');
      return line.isEmpty ? null : line;
    } catch (_) {
      return null;
    }
  }

  static void clearCache() => _cache.clear();
}
