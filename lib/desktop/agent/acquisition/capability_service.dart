import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../core/agent_process.dart';
import '../network/agent_environment.dart';
import 'capability_catalog.dart';
import 'tool_probe.dart';

enum CapabilityState { builtin, available, installable, unavailable }

class CapabilityStatus {
  const CapabilityStatus({
    required this.capability,
    required this.state,
    this.provider,
    this.probe,
    this.reason,
  });

  final Capability capability;
  final CapabilityState state;

  final CapabilityProvider? provider;

  final ProbeResult? probe;

  final String? reason;

  bool get isReady =>
      state == CapabilityState.builtin || state == CapabilityState.available;

  Map<String, dynamic> toJson() => {
    'capability': capability.key,
    'label': capability.label,
    'state': state.name,
    'ready': isReady,
    if (capability.builtinBy != null) 'provided_by': capability.builtinBy,
    if (probe != null) 'tool': probe!.toJson(),
    if (provider != null) ...{
      'install_via': provider!.manager.command,
      'package': provider!.packageId,
    },
    if (reason != null) 'reason': reason,
  };
}

class InstallOutcome {
  const InstallOutcome({
    required this.ok,
    required this.message,
    this.exitCode,
    this.log = '',
    this.probe,
  });

  final bool ok;
  final String message;
  final int? exitCode;
  final String log;

  final ProbeResult? probe;
}

abstract final class CapabilityService {
  static Future<CapabilityStatus> resolve(String key) async {
    final capability = CapabilityCatalog.find(key);
    if (capability == null) {
      return CapabilityStatus(
        capability: Capability(key: key, label: key, description: 'ناشناخته'),
        state: CapabilityState.unavailable,
        reason:
            'قابلیت «$key» شناخته‌شده نیست. قابلیت‌های موجود: '
            '${CapabilityCatalog.keys.join('، ')}',
      );
    }

    if (capability.isBuiltin) {
      return CapabilityStatus(
        capability: capability,
        state: CapabilityState.builtin,
      );
    }

    for (final command in capability.existingCommands) {
      final probe = await ToolProbe.probe(command);
      if (probe.installed) {
        return CapabilityStatus(
          capability: capability,
          state: CapabilityState.available,
          probe: probe,
        );
      }
    }

    for (final provider in capability.providers) {
      final manager = await ToolProbe.probe(provider.manager.command);
      if (manager.installed) {
        return CapabilityStatus(
          capability: capability,
          state: CapabilityState.installable,
          provider: provider,
        );
      }
    }

    return CapabilityStatus(
      capability: capability,
      state: CapabilityState.unavailable,
      reason: capability.providers.isEmpty
          ? 'راه نصب خودکاری برای این قابلیت تعریف نشده.'
          : 'مدیر بستهٔ لازم روی این سیستم نیست، پس نصب خودکار ممکن نیست.',
    );
  }

  static Future<List<CapabilityStatus>> survey() =>
      Future.wait(CapabilityCatalog.keys.map(resolve));

  static Future<InstallOutcome> install(
    CapabilityStatus status, {
    void Function(String line)? onProgress,
    Duration timeout = const Duration(minutes: 10),
  }) async {
    if (status.isReady) {
      return InstallOutcome(
        ok: true,
        probe: status.probe,
        message: status.state == CapabilityState.builtin
            ? '${status.capability.label} از قبل در دسترس است '
                  '(${status.capability.builtinBy}). نصبی لازم نیست.'
            : '${status.capability.label} از قبل نصب است'
                  '${status.probe?.version == null ? '' : ' — ${status.probe!.version}'}.',
      );
    }

    final provider = status.provider;
    if (provider == null) {
      return InstallOutcome(
        ok: false,
        message: status.reason ?? 'راه نصب معتبری برای این قابلیت وجود ندارد.',
      );
    }

    final args = provider.manager.installArgs(provider.packageId);
    onProgress?.call('${provider.manager.command} ${args.join(' ')}');

    final log = StringBuffer();
    Process process;
    try {
      process = await Process.start(
        provider.manager.command,
        args,
        runInShell: true,
        environment: await AgentEnvironment.build(),
        includeParentEnvironment: false,
      );
    } on ProcessException catch (e) {
      return InstallOutcome(
        ok: false,
        message: 'اجرای ${provider.manager.command} ممکن نشد: ${e.message}',
      );
    }

    StreamSubscription<String> pipe(Stream<List<int>> source) => source
        .transform(const Utf8Decoder(allowMalformed: true))
        .transform(const LineSplitter())
        .listen((line) {
          if (log.length < 20000) log.writeln(line);
          onProgress?.call(line);
        });

    final outSub = pipe(process.stdout);
    final errSub = pipe(process.stderr);

    int exitCode;
    try {
      exitCode = await process.exitCode.timeout(timeout);
    } on TimeoutException {
      await AgentProcess.killTree(process);
      await process.exitCode
          .timeout(const Duration(seconds: 5))
          .catchError((_) => -1);
      await outSub.cancel();
      await errSub.cancel();
      return InstallOutcome(
        ok: false,
        message: 'نصب بیش از حد طول کشید و متوقف شد.',
        log: log.toString(),
      );
    }

    await outSub.cancel();
    await errSub.cancel();

    final probe = await ToolProbe.probe(provider.verifyCommand, refresh: true);

    if (!probe.installed) {
      return InstallOutcome(
        ok: false,
        exitCode: exitCode,
        log: log.toString(),
        probe: probe,
        message: exitCode == 0
            ? 'نصب بدون خطا تمام شد ولی «${provider.verifyCommand}» هنوز اجرا '
                  'نمی‌شود. معمولاً یعنی باید پنجرهٔ جدیدی باز شود تا PATH '
                  'تازه خوانده شود.'
            : 'نصب ناموفق بود (کد $exitCode).',
      );
    }

    return InstallOutcome(
      ok: true,
      exitCode: exitCode,
      log: log.toString(),
      probe: probe,
      message: 'نصب شد و بررسی شد: ${probe.version ?? provider.verifyCommand}',
    );
  }
}
