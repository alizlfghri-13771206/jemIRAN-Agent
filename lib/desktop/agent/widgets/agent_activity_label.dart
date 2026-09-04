import 'package:jemiran/desktop/agent/core/agent_task.dart';

String agentActivityLabel(AgentPhase phase, {String? action}) {
  final currentAction = action?.trim();
  final hasAction = currentAction != null && currentAction.isNotEmpty;

  return switch (phase) {
    AgentPhase.idle => 'آماده',
    AgentPhase.thinking => 'در حال فکر کردن',
    AgentPhase.planning => 'در حال برنامه‌ریزی',
    AgentPhase.awaitingAnswer => 'منتظر پاسخ شما',
    AgentPhase.awaitingPermission =>
      hasAction ? 'منتظر اجازه برای $currentAction' : 'منتظر اجازه شما',
    AgentPhase.executing =>
      hasAction ? 'در حال $currentAction' : 'در حال اجرای عملیات',
    AgentPhase.observing => 'در حال بررسی نتیجه',
    AgentPhase.verifying => 'در حال راستی‌آزمایی',
    AgentPhase.interrupted => 'کار متوقف شده است',
    AgentPhase.incomplete => 'کار ناتمام ماند',
    AgentPhase.done => 'انجام شد',
    AgentPhase.failed => 'انجام کار ناموفق بود',
    AgentPhase.cancelled => 'لغو شد',
  };
}
