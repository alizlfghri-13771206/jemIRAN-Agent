import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../tools/agent_tool.dart';
import '../core/agent_storage.dart';

abstract final class Perm {
  static const filesystemRead = 'filesystem.read';
  static const filesystemWrite = 'filesystem.write';
  static const filesystemCreate = 'filesystem.create';
  static const filesystemDelete = 'filesystem.delete';

  static const terminalExecute = 'terminal.execute';

  static const gitRead = 'git.read';
  static const gitWrite = 'git.write';

  static const browserRead = 'browser.read';
  static const browserInteract = 'browser.interact';
  static const browserSubmit = 'browser.submit';

  static const networkFetch = 'network.fetch';

  static const toolInstall = 'tool.install';
  static const toolExecute = 'tool.execute';

  static const agentAsk = 'agent.ask';

  static const skillRead = 'skill.read';
  static const skillWrite = 'skill.write';
  static const memoryRead = 'memory.read';
  static const memoryWrite = 'memory.write';

  static String label(String id) => switch (id) {
    filesystemRead => 'خواندن فایل',
    filesystemWrite => 'نوشتن فایل',
    filesystemCreate => 'ساخت فایل یا پوشه',
    filesystemDelete => 'حذف فایل یا پوشه',
    terminalExecute => 'اجرای فرمان در ترمینال',
    gitRead => 'خواندن وضعیت Git',
    gitWrite => 'تغییر وضعیت Git',
    browserRead => 'خواندن صفحهٔ وب',
    browserInteract => 'تعامل با صفحهٔ وب',
    browserSubmit => 'ارسال فرم در وب',
    networkFetch => 'درخواست شبکه',
    toolInstall => 'نصب ابزار',
    toolExecute => 'اجرای ابزار نصب‌شده',
    agentAsk => 'پرسش از کاربر',
    skillRead => 'خواندن مهارت‌ها',
    skillWrite => 'ثبت مهارت',
    memoryRead => 'خواندن حافظه',
    memoryWrite => 'به‌یادسپاری',
    _ => id,
  };

  static const alwaysConfirm = {
    filesystemDelete,
    browserSubmit,
    toolInstall,
    terminalExecute,
    memoryWrite,
    skillWrite,
  };

  static const neverSilent = {terminalExecute};
}

enum AgentMode { manual, autonomous, unattended }

enum PermissionDecision {
  allowOnce,

  allowTask,

  allowSession,

  deny;

  bool get isAllow => this != deny;
}

enum PolicyOutcome { allow, ask, deny }

class PolicyVerdict {
  const PolicyVerdict(this.outcome, {this.reason});

  final PolicyOutcome outcome;

  final String? reason;

  static const allow = PolicyVerdict(PolicyOutcome.allow);
  static const ask = PolicyVerdict(PolicyOutcome.ask);
}

class AgentPolicyState {
  const AgentPolicyState({
    this.enabled = true,
    this.mode = AgentMode.manual,
    this.sessionGrants = const {},
    this.taskGrants = const {},
    this.autoApproveReads = true,
  });

  final bool enabled;

  final AgentMode mode;

  final Set<String> sessionGrants;

  final Set<String> taskGrants;

  final bool autoApproveReads;

  bool get isAutonomous =>
      mode == AgentMode.autonomous || mode == AgentMode.unattended;

  bool get isUnattended => mode == AgentMode.unattended;

  AgentPolicyState copyWith({
    bool? enabled,
    AgentMode? mode,
    Set<String>? sessionGrants,
    Set<String>? taskGrants,
    bool? autoApproveReads,
  }) => AgentPolicyState(
    enabled: enabled ?? this.enabled,
    mode: mode ?? this.mode,
    sessionGrants: sessionGrants ?? this.sessionGrants,
    taskGrants: taskGrants ?? this.taskGrants,
    autoApproveReads: autoApproveReads ?? this.autoApproveReads,
  );

  bool hasGrant(String permission) =>
      sessionGrants.contains(permission) || taskGrants.contains(permission);

  PolicyVerdict evaluate({
    required AgentTool tool,
    required ToolCall call,
    String? hardDenyReason,
    bool tainted = false,
  }) {
    if (hardDenyReason != null) {
      return PolicyVerdict(PolicyOutcome.deny, reason: hardDenyReason);
    }

    final risk = tool.riskOf(call);
    final permission = tool.permissionOf(call);

    if (risk == ToolRisk.read) {
      if (hasGrant(permission)) return PolicyVerdict.allow;
      return autoApproveReads ? PolicyVerdict.allow : PolicyVerdict.ask;
    }

    if (tainted && risk != ToolRisk.read && !isUnattended) {
      return PolicyVerdict.ask;
    }

    if (Perm.neverSilent.contains(permission)) {
      return PolicyVerdict.ask;
    }

    if (Perm.alwaysConfirm.contains(permission) ||
        risk == ToolRisk.destructive) {
      if (!isUnattended) return PolicyVerdict.ask;
      return PolicyVerdict.allow;
    }

    if (hasGrant(permission)) return PolicyVerdict.allow;

    if (isAutonomous) {
      return PolicyVerdict.allow;
    }

    return PolicyVerdict.ask;
  }
}

class AgentPolicyNotifier extends Notifier<AgentPolicyState> {
  static const _autoReadKey = 'desktop_agent_auto_read_v1';
  static const _modeKey = 'desktop_agent_mode_v1';
  static const _installKey = 'desktop_agent_unattended_install_v1';
  static const _shellKey = 'desktop_agent_unattended_shell_v1';
  String get _scopedAutoReadKey => '${_autoReadKey}_${AgentStorage.accountKey}';
  String get _scopedModeKey => '${_modeKey}_${AgentStorage.accountKey}';
  String get _scopedInstallKey => '${_installKey}_${AgentStorage.accountKey}';
  String get _scopedShellKey => '${_shellKey}_${AgentStorage.accountKey}';

  @override
  AgentPolicyState build() => const AgentPolicyState();

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final scopedAutoRead = prefs.getBool(_scopedAutoReadKey);
      final legacyAutoRead = prefs.getBool(_autoReadKey);
      final scopedMode = prefs.getString(_scopedModeKey);
      final legacyMode = prefs.getString(_modeKey);
      state = state.copyWith(
        enabled: true,
        autoApproveReads: scopedAutoRead ?? legacyAutoRead ?? true,
        mode: _modeFrom(scopedMode ?? legacyMode),
        sessionGrants: const {},
        taskGrants: const {},
      );
      if (scopedAutoRead == null && legacyAutoRead != null) {
        await prefs.setBool(_scopedAutoReadKey, legacyAutoRead);
        await prefs.remove(_autoReadKey);
      }
      if (scopedMode == null && legacyMode != null) {
        await prefs.setString(_scopedModeKey, legacyMode);
        await prefs.remove(_modeKey);
      }
      await prefs.remove(_installKey);
      await prefs.remove(_shellKey);
      await prefs.remove(_scopedInstallKey);
      await prefs.remove(_scopedShellKey);
    } catch (_) {}
  }

  static AgentMode _modeFrom(String? raw) => AgentMode.values.firstWhere(
    (mode) => mode.name == raw,
    orElse: () => AgentMode.manual,
  );

  Future<void> setAutoApproveReads(bool value) async {
    state = state.copyWith(autoApproveReads: value);
    await _write((p) => p.setBool(_scopedAutoReadKey, value));
  }

  Future<void> setMode(AgentMode mode) async {
    state = state.copyWith(mode: mode);
    await _write((p) => p.setString(_scopedModeKey, mode.name));
  }

  Future<void> _write(Future<void> Function(SharedPreferences) op) async {
    try {
      await op(await SharedPreferences.getInstance());
    } catch (_) {}
  }

  void grantForSession(String permission) {
    state = state.copyWith(sessionGrants: {...state.sessionGrants, permission});
  }

  void grantForTask(String permission) {
    state = state.copyWith(taskGrants: {...state.taskGrants, permission});
  }

  void clearTaskGrants() {
    if (state.taskGrants.isEmpty) return;
    state = state.copyWith(taskGrants: const {});
  }

  void revokeAll() =>
      state = state.copyWith(sessionGrants: const {}, taskGrants: const {});
}

final agentPolicyProvider =
    NotifierProvider<AgentPolicyNotifier, AgentPolicyState>(
      AgentPolicyNotifier.new,
    );
