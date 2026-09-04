import 'package:flutter/material.dart';
import 'package:jemiran/desktop/agent/core/agent_task.dart';
import 'package:jemiran/desktop/agent/widgets/agent_bidi.dart';
import 'package:jemiran/desktop/agent/tools/agent_tool.dart';
import 'package:jemiran/desktop/theme/desktop_tokens.dart';
import 'package:jemiran/desktop/theme/win_controls.dart';
import 'package:jemiran/themes/colors.dart';
import 'package:jemiran/themes/jemiran_design.dart';

IconData agentToolIcon(String tool) => switch (tool) {
  'list_dir' => Icons.folder_open_rounded,
  'read_file' => Icons.description_outlined,
  'file_info' => Icons.info_outline_rounded,
  'find_files' => Icons.travel_explore_rounded,
  'search_files' => Icons.search_rounded,
  'write_file' => Icons.edit_document,
  'append_file' => Icons.playlist_add_rounded,
  'edit_file' => Icons.find_replace_rounded,
  'make_dir' => Icons.create_new_folder_outlined,
  'move_path' => Icons.drive_file_move_outlined,
  'delete_path' => Icons.delete_outline_rounded,
  'run_command' => Icons.terminal_rounded,
  'git' => Icons.account_tree_outlined,
  'ask_user' => Icons.help_outline_rounded,
  _ => Icons.build_outlined,
};

String agentRiskLabel(ToolRisk risk) => switch (risk) {
  ToolRisk.read => 'خواندن',
  ToolRisk.write => 'نوشتن',
  ToolRisk.network => 'شبکه',
  ToolRisk.execute => 'اجرا',
  ToolRisk.destructive => 'غیرقابل برگشت',
};

class ToolCallCard extends StatefulWidget {
  const ToolCallCard({super.key, required this.step});

  final AgentStepRecord step;

  @override
  State<ToolCallCard> createState() => _ToolCallCardState();
}

class _ToolCallCardState extends State<ToolCallCard> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final step = widget.step;
    final detail = step.result?.detail;
    final canOpen = detail != null && detail.trim().isNotEmpty;
    final running = step.status == StepStatus.running;

    final (
      Color accent,
      IconData statusIcon,
      String statusText,
    ) = switch (step.status) {
      StepStatus.awaitingPermission => (
        JSurface.muted(isDark),
        Icons.schedule_rounded,
        'در انتظار تأیید شما',
      ),
      StepStatus.running => (
        JColor.primary(isDark),
        Icons.autorenew_rounded,
        'در حال اجرا',
      ),
      StepStatus.done => (
        isDark ? DarkColors.success : LightColors.success,
        Icons.check_rounded,
        step.result?.summary ?? 'انجام شد',
      ),
      StepStatus.failed => (
        isDark ? DarkColors.danger : LightColors.danger,
        Icons.error_outline_rounded,
        step.result?.summary ?? 'ناموفق',
      ),
      StepStatus.denied => (
        isDark ? DarkColors.warning : LightColors.warning,
        Icons.block_rounded,
        step.refusal ?? 'اجازه داده نشد',
      ),
      StepStatus.blocked => (
        isDark ? DarkColors.danger : LightColors.danger,
        Icons.shield_outlined,
        step.refusal ?? 'طبق سیاست اجازه ندارد',
      ),
      StepStatus.cancelled => (
        JSurface.muted(isDark),
        Icons.stop_circle_outlined,
        'لغو شد',
      ),
    };

    final liveTail = running && step.progress.isNotEmpty
        ? step.progress.length <= 4
              ? step.progress.join('\n')
              : step.progress.sublist(step.progress.length - 4).join('\n')
        : null;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: WinSpace.xs),
        child: Container(
          decoration: BoxDecoration(
            color: WinSurface.card(isDark),
            borderRadius: BorderRadius.circular(WinRadius.card),
            border: Border.all(color: WinSurface.hairline(isDark)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              WinHoverable(
                radius: WinRadius.card,
                onTap: canOpen ? () => setState(() => _open = !_open) : null,
                padding: const EdgeInsets.symmetric(
                  horizontal: WinSpace.md,
                  vertical: WinSpace.md,
                ),
                child: Row(
                  children: [
                    Container(
                      height: 26,
                      width: 26,
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: isDark ? .16 : .10),
                        borderRadius: BorderRadius.circular(WinRadius.control),
                      ),
                      child: Icon(
                        agentToolIcon(step.call.name),
                        size: 14,
                        color: accent,
                      ),
                    ),
                    const SizedBox(width: WinSpace.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                step.toolLabel,
                                style: TextStyle(
                                  fontSize: WinText.bodySm,
                                  fontWeight: FontWeight.w800,
                                  color: JSurface.text(isDark),
                                ),
                              ),
                              if (step.total > 1) ...[
                                const SizedBox(width: WinSpace.sm),
                                Text(
                                  AgentBidi.ltr('${step.index}/${step.total}'),
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                    color: JSurface.muted(isDark),
                                  ),
                                ),
                              ],
                              if (step.duration != null) ...[
                                const SizedBox(width: WinSpace.sm),
                                Text(
                                  AgentBidi.ltr(
                                    '${step.duration!.inMilliseconds} ms',
                                  ),
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: JSurface.muted(isDark),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 3),
                          Text(
                            AgentBidi.ltr(_subtitle(step)),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            textDirection: TextDirection.ltr,
                            textAlign: TextAlign.right,
                            style: TextStyle(
                              fontSize: 11.5,
                              height: 1.5,
                              fontFamily: WinMono.family,
                              fontFamilyFallback: WinMono.fallback,
                              color: JSurface.muted(isDark),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: WinSpace.sm),
                    if (running)
                      SizedBox(
                        height: 14,
                        width: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 1.8,
                          valueColor: AlwaysStoppedAnimation(accent),
                        ),
                      )
                    else
                      Icon(statusIcon, size: 15, color: accent),
                    if (canOpen) ...[
                      const SizedBox(width: WinSpace.xs),
                      Icon(
                        _open
                            ? Icons.keyboard_arrow_up_rounded
                            : Icons.keyboard_arrow_down_rounded,
                        size: 17,
                        color: JSurface.muted(isDark),
                      ),
                    ],
                  ],
                ),
              ),
              if (statusText.isNotEmpty && step.status != StepStatus.running)
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    WinSpace.md,
                    0,
                    WinSpace.md,
                    WinSpace.md,
                  ),
                  child: Text(
                    AgentBidi.sentence(statusText),
                    style: TextStyle(
                      fontSize: 11,
                      color: accent.withValues(alpha: .95),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              if (liveTail != null) ...[
                const WinSeam(),
                Padding(
                  padding: const EdgeInsets.all(WinSpace.md),
                  child: Directionality(
                    textDirection: TextDirection.ltr,
                    child: Text(
                      liveTail,
                      maxLines: 4,
                      overflow: TextOverflow.ellipsis,
                      textDirection: TextDirection.ltr,
                      textAlign: TextAlign.left,
                      style: TextStyle(
                        fontSize: 11,
                        height: 1.6,
                        fontFamily: WinMono.family,
                        fontFamilyFallback: WinMono.fallback,
                        color: JSurface.muted(isDark),
                      ),
                    ),
                  ),
                ),
              ],
              if (_open && canOpen) ...[
                const WinSeam(),
                Container(
                  constraints: const BoxConstraints(maxHeight: 320),
                  padding: const EdgeInsets.all(WinSpace.md),
                  child: Directionality(
                    textDirection: TextDirection.ltr,
                    child: WinScrollbar(
                      child: SingleChildScrollView(
                        child: SelectableText(
                          detail,
                          textDirection: TextDirection.ltr,
                          textAlign: TextAlign.left,
                          style: TextStyle(
                            fontSize: 11.5,
                            height: 1.65,
                            fontFamily: WinMono.family,
                            fontFamilyFallback: WinMono.fallback,
                            color: JSurface.secondary(isDark),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  static String _subtitle(AgentStepRecord step) {
    final call = step.call;
    final from = call.str('from');
    final to = call.str('to');
    if (from != null && to != null) return '$from  →  $to';
    return call.str('command') ??
        call.str('path') ??
        call.str('question') ??
        call.str('query') ??
        call.str('pattern') ??
        call.str('url') ??
        call.str('action') ??
        '—';
  }
}

class AgentThinkingRow extends StatelessWidget {
  const AgentThinkingRow({super.key, required this.label, this.detail});

  final String label;

  final String? detail;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: WinSpace.sm),
      child: Row(
        children: [
          SizedBox(
            height: 13,
            width: 13,
            child: CircularProgressIndicator(
              strokeWidth: 1.6,
              valueColor: AlwaysStoppedAnimation(JColor.primary(isDark)),
            ),
          ),
          const SizedBox(width: WinSpace.md),
          Flexible(
            child: Text(
              detail == null ? label : '$label — $detail',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: WinText.bodySm,
                fontWeight: FontWeight.w600,
                color: JSurface.muted(isDark),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
