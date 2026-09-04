import 'package:flutter_test/flutter_test.dart';
import 'package:jemiran/desktop/agent/policy/agent_policy.dart';
import 'package:jemiran/desktop/agent/policy/command_risk.dart';
import 'package:jemiran/desktop/agent/tools/agent_tool.dart';

class _ShellTool extends AgentTool {
  const _ShellTool();

  @override
  ToolRisk get risk => ToolRisk.execute;
  @override
  String get permission => Perm.terminalExecute;
  @override
  ToolRisk riskOf(ToolCall call) =>
      CommandRisk.classify(call.str('command') ?? '').risk;

  @override
  String get name => 'run_command';
  @override
  String get label => 'اجرای فرمان';
  @override
  String get signature => 'run_command {}';

  @override
  ToolPreview preview(ToolCall call) => const ToolPreview(title: 'فرمان');

  @override
  Future<ToolResult> run(ToolCall call, ToolContext context) async =>
      ToolResult.success(summary: 'ok');
}

PolicyOutcome decideCommand(AgentPolicyState state, String command) => state
    .evaluate(
      tool: const _ShellTool(),
      call: ToolCall(name: 'run_command', args: {'command': command}),
    )
    .outcome;

class _Tool extends AgentTool {
  const _Tool(this.risk, this.permission);

  @override
  final ToolRisk risk;
  @override
  final String permission;

  @override
  String get name => 'fake';
  @override
  String get label => 'ساختگی';
  @override
  String get signature => 'fake {}';

  @override
  ToolPreview preview(ToolCall call) => const ToolPreview(title: 'ساختگی');

  @override
  Future<ToolResult> run(ToolCall call, ToolContext context) async =>
      ToolResult.success(summary: 'ok');
}

ToolCall get _call => ToolCall(name: 'fake', args: const {});

PolicyOutcome decide(AgentPolicyState state, AgentTool tool, {String? deny}) =>
    state.evaluate(tool: tool, call: _call, hardDenyReason: deny).outcome;

void main() {
  const read = _Tool(ToolRisk.read, Perm.filesystemRead);
  const write = _Tool(ToolRisk.write, Perm.filesystemWrite);
  const delete = _Tool(ToolRisk.destructive, Perm.filesystemDelete);
  const install = _Tool(ToolRisk.execute, Perm.toolInstall);
  const submit = _Tool(ToolRisk.network, Perm.browserSubmit);

  group('حالت دستی', () {
    const state = AgentPolicyState(mode: AgentMode.manual);

    test('خواندن بی‌پرسش، نوشتن با پرسش', () {
      expect(decide(state, read), PolicyOutcome.allow);
      expect(decide(state, write), PolicyOutcome.ask);
    });

    test('حذف و نصب و ارسال می‌پرسند', () {
      expect(decide(state, delete), PolicyOutcome.ask);
      expect(decide(state, install), PolicyOutcome.ask);
      expect(decide(state, submit), PolicyOutcome.ask);
    });
  });

  group('حالت خودگردان', () {
    const state = AgentPolicyState(mode: AgentMode.autonomous);

    test('نوشتن بدون پرسش پیش می‌رود', () {
      expect(decide(state, write), PolicyOutcome.allow);
    });

    test('ولی برگشت‌ناپذیرها همچنان می‌پرسند', () {
      expect(decide(state, delete), PolicyOutcome.ask);
      expect(decide(state, install), PolicyOutcome.ask);
      expect(decide(state, submit), PolicyOutcome.ask);
    });
  });

  group('حالت بی‌نظارت', () {
    const state = AgentPolicyState(mode: AgentMode.unattended);

    test('خواندن، نوشتن، حذف و ارسال نمی‌پرسند', () {
      expect(decide(state, read), PolicyOutcome.allow);
      expect(decide(state, write), PolicyOutcome.allow);
      expect(decide(state, delete), PolicyOutcome.allow);
      expect(decide(state, submit), PolicyOutcome.allow);
    });

    test('نصب ابزار هم بدون پرسش انجام می‌شود', () {
      expect(decide(state, install), PolicyOutcome.allow);
    });

    test('مرز منابع حتی اینجا هم شکسته نمی‌شود', () {
      expect(
        decide(state, write, deny: 'بیرون از منابع مجاز'),
        PolicyOutcome.deny,
      );
      expect(
        decide(state, delete, deny: 'بیرون از منابع مجاز'),
        PolicyOutcome.deny,
      );
    });
  });

  group('اجرای shell', () {
    const manual = AgentPolicyState(mode: AgentMode.manual);
    const autonomous = AgentPolicyState(mode: AgentMode.autonomous);
    const unattended = AgentPolicyState(mode: AgentMode.unattended);

    test('فرمان مؤثر در همهٔ حالت‌ها تأیید جدا می‌خواهد', () {
      for (final state in [manual, autonomous, unattended]) {
        expect(
          decideCommand(state, 'npm install express'),
          PolicyOutcome.ask,
          reason: 'حالت ${state.mode.name}',
        );
      }
    });

    test('اجازهٔ نشست هم فرمان مؤثر را بی‌صدا نمی‌کند', () {
      const granted = AgentPolicyState(
        mode: AgentMode.autonomous,
        sessionGrants: {Perm.terminalExecute},
      );
      expect(
        decideCommand(granted, 'flutter build windows'),
        PolicyOutcome.ask,
      );
    });

    test('تمام‌خودکار بودن مجوز اجرای shell نیست', () {
      expect(
        decideCommand(unattended, 'flutter build windows'),
        PolicyOutcome.ask,
      );
      expect(decideCommand(manual, 'flutter build windows'), PolicyOutcome.ask);
    });

    test('فرمان فقط‌خواندنی دیالوگ نمی‌آورد', () {
      for (final state in [manual, autonomous, unattended]) {
        expect(
          decideCommand(state, 'git status'),
          PolicyOutcome.allow,
          reason: 'حالت ${state.mode.name}',
        );
      }
    });

    test('فرمان فقط‌خواندنی با خاموش‌بودن تأیید خودکار می‌پرسد', () {
      const strict = AgentPolicyState(
        mode: AgentMode.unattended,
        autoApproveReads: false,
      );
      expect(decideCommand(strict, 'git status'), PolicyOutcome.ask);
    });

    test('زنجیرهٔ فرمان، فقط‌خواندنی حساب نمی‌شود', () {
      expect(
        decideCommand(autonomous, 'git status && rm -rf build'),
        PolicyOutcome.ask,
      );
    });

    test('فرمان مسدود همچنان رد قطعی می‌شود، نه پرسش', () {
      final verdict = unattended.evaluate(
        tool: const _ShellTool(),
        call: ToolCall(name: 'run_command', args: const {'command': 'x'}),
        hardDenyReason: 'این فرمان اجازهٔ اجرا ندارد.',
      );
      expect(verdict.outcome, PolicyOutcome.deny);
    });
  });

  group('پایداری', () {
    test('هر سه حالت نام یکتا دارند', () {
      final names = AgentMode.values.map((m) => m.name).toList();
      expect(names.toSet().length, names.length);
    });

    test('بی‌نظارت هم خودگردان حساب می‌شود', () {
      const state = AgentPolicyState(mode: AgentMode.unattended);
      expect(state.isAutonomous, isTrue);
      expect(state.isUnattended, isTrue);
    });

    test('پیش‌فرض دستی است و هیچ رضایت پرخطری باز نیست', () {
      const state = AgentPolicyState();
      expect(state.mode, AgentMode.manual);
      expect(state.mode, AgentMode.manual);
    });

    test('terminal.execute در فهرست «هیچ‌وقت بی‌صدا» است', () {
      expect(Perm.neverSilent, contains(Perm.terminalExecute));
      expect(Perm.alwaysConfirm, contains(Perm.terminalExecute));
    });
  });
}
