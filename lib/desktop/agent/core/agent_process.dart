import 'dart:async';
import 'dart:convert';
import 'dart:io';

class AgentProcessResult {
  const AgentProcessResult({
    required this.exitCode,
    required this.stdout,
    required this.stderr,
    this.timedOut = false,
  });

  final int exitCode;
  final String stdout;
  final String stderr;
  final bool timedOut;
}

abstract final class AgentProcess {
  static const timedOutExitCode = 124;

  static Future<void> killTree(Process process) async {
    if (Platform.isWindows) {
      try {
        final result = await Process.run('taskkill.exe', [
          '/PID',
          '${process.pid}',
          '/T',
          '/F',
        ]).timeout(const Duration(seconds: 5));
        if (result.exitCode == 0 || result.exitCode == 128) return;
      } catch (_) {}
    }
    process.kill(ProcessSignal.sigkill);
  }

  static Future<AgentProcessResult> run(
    String executable,
    List<String> arguments, {
    required Duration timeout,
    String? workingDirectory,
    Map<String, String>? environment,
    bool runInShell = false,
    void Function(String line)? onLine,
    bool Function()? isCancelled,
    int maxOutputChars = 20000,
  }) async {
    final process = await Process.start(
      executable,
      arguments,
      workingDirectory: workingDirectory,
      environment: environment,
      runInShell: runInShell,
      includeParentEnvironment: environment == null,
    );

    final out = StringBuffer();
    final err = StringBuffer();

    StreamSubscription<String> pipe(
      Stream<List<int>> source,
      StringBuffer sink,
    ) => source
        .transform(const Utf8Decoder(allowMalformed: true))
        .transform(const LineSplitter())
        .listen((line) {
          if (sink.length < maxOutputChars) sink.writeln(line);
          onLine?.call(line);
        });

    final outSub = pipe(process.stdout, out);
    final errSub = pipe(process.stderr, err);

    var timedOut = false;
    Future<void>? killing;
    void kill() => killing ??= killTree(process);

    Timer? watch;
    if (isCancelled != null) {
      watch = Timer.periodic(const Duration(milliseconds: 250), (t) {
        if (!isCancelled()) return;
        t.cancel();
        kill();
      });
    }

    var exitCode = -1;
    try {
      exitCode = await process.exitCode.timeout(
        timeout,
        onTimeout: () {
          timedOut = true;
          kill();
          return timedOutExitCode;
        },
      );
    } finally {
      watch?.cancel();
      if (killing != null) {
        await killing!.timeout(const Duration(seconds: 8), onTimeout: () {});
        await process.exitCode
            .timeout(const Duration(seconds: 5))
            .catchError((_) => exitCode);
      }
      await outSub.cancel();
      await errSub.cancel();
    }

    return AgentProcessResult(
      exitCode: exitCode,
      stdout: out.toString().trimRight(),
      stderr: err.toString().trimRight(),
      timedOut: timedOut,
    );
  }
}
