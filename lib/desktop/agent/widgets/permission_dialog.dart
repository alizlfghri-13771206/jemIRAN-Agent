import 'package:flutter/material.dart';
import 'package:jemiran/desktop/agent/core/agent_task.dart';
import 'package:jemiran/desktop/agent/policy/agent_policy.dart';
import 'package:jemiran/desktop/agent/tools/agent_tool.dart';
import 'package:jemiran/desktop/agent/widgets/tool_call_card.dart';
import 'package:jemiran/desktop/theme/desktop_tokens.dart';
import 'package:jemiran/desktop/theme/win_controls.dart';
import 'package:jemiran/themes/colors.dart';
import 'package:jemiran/themes/jemiran_design.dart';

Future<PermissionDecision> showAgentPermissionDialog(
  BuildContext context,
  AgentStepRecord step,
  ToolPreview preview, {
  String? origin,
}) async {
  final decision = await showDialog<PermissionDecision>(
    context: context,
    barrierDismissible: false,
    builder: (_) =>
        _PermissionDialog(step: step, preview: preview, origin: origin),
  );
  return decision ?? PermissionDecision.deny;
}

class _PermissionDialog extends StatelessWidget {
  const _PermissionDialog({
    required this.step,
    required this.preview,
    this.origin,
  });

  final AgentStepRecord step;
  final ToolPreview preview;

  final String? origin;

  bool get _irreversible =>
      step.risk == ToolRisk.destructive ||
      Perm.alwaysConfirm.contains(_permissionOf(step)) ||
      Perm.neverSilent.contains(_permissionOf(step));

  static String _permissionOf(AgentStepRecord step) =>
      step.permission.isNotEmpty ? step.permission : _legacyGuess(step);

  static String _legacyGuess(AgentStepRecord step) => switch (step.call.name) {
    'delete_path' => Perm.filesystemDelete,
    'run_command' => Perm.terminalExecute,
    _ => '',
  };

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = _irreversible
        ? (isDark ? DarkColors.danger : LightColors.danger)
        : JColor.primary(isDark);

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Dialog(
        backgroundColor: WinSurface.card(isDark),
        surfaceTintColor: Colors.transparent,
        elevation: 12,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(WinRadius.layer),
          side: BorderSide(color: WinSurface.hairline(isDark)),
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 580, maxHeight: 660),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _header(isDark, accent),
              const WinSeam(),
              Flexible(child: _body(isDark, accent)),
              const WinSeam(),
              _actions(context, isDark, accent),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header(bool isDark, Color accent) => Padding(
    padding: const EdgeInsets.all(WinSpace.xl),
    child: Row(
      children: [
        Container(
          height: 34,
          width: 34,
          decoration: BoxDecoration(
            color: accent.withValues(alpha: isDark ? .18 : .12),
            borderRadius: BorderRadius.circular(WinRadius.card),
          ),
          child: Icon(
            _irreversible
                ? Icons.warning_amber_rounded
                : agentToolIcon(step.call.name),
            size: 18,
            color: accent,
          ),
        ),
        const SizedBox(width: WinSpace.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'جمیران می‌خواهد این کار را انجام دهد',
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: JSurface.muted(isDark),
                ),
              ),
              const SizedBox(height: 3),
              Text(
                preview.title,
                style: TextStyle(
                  fontSize: WinText.title,
                  fontWeight: FontWeight.w800,
                  color: JSurface.text(isDark),
                ),
              ),
              if (origin != null && origin!.isNotEmpty) ...[
                const SizedBox(height: 5),
                Row(
                  children: [
                    Icon(
                      Icons.folder_open_outlined,
                      size: 13,
                      color: JSurface.muted(isDark),
                    ),
                    const SizedBox(width: 5),
                    Expanded(
                      child: Text(
                        origin!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: JSurface.muted(isDark),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ],
    ),
  );

  Widget _body(bool isDark, Color accent) => WinScrollbar(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(WinSpace.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (preview.subtitle != null) ...[
            _label('هدف', isDark),
            const SizedBox(height: 6),
            _mono(preview.subtitle!, isDark),
            const SizedBox(height: WinSpace.lg),
          ],
          if (preview.body != null && preview.body!.trim().isNotEmpty) ...[
            _label(
              preview.bodyLanguage == 'diff' ? 'تغییرات' : 'محتوا',
              isDark,
            ),
            const SizedBox(height: 6),
            Container(
              constraints: const BoxConstraints(maxHeight: 260),
              padding: const EdgeInsets.all(WinSpace.md),
              decoration: BoxDecoration(
                color: WinSurface.window(isDark),
                borderRadius: BorderRadius.circular(WinRadius.card),
                border: Border.all(color: WinSurface.hairline(isDark)),
              ),
              child: WinScrollbar(
                child: SingleChildScrollView(
                  child: SelectableText(
                    preview.body!,
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
            const SizedBox(height: WinSpace.lg),
          ],
          for (final warning in preview.warnings) ...[
            _warning(warning, isDark),
            const SizedBox(height: WinSpace.sm),
          ],
        ],
      ),
    ),
  );

  Widget _label(String text, bool isDark) => Text(
    text,
    style: TextStyle(
      fontSize: WinText.sectionLabel,
      fontWeight: FontWeight.w800,
      letterSpacing: .3,
      color: JSurface.muted(isDark),
    ),
  );

  Widget _mono(String text, bool isDark) => Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(
      horizontal: WinSpace.md,
      vertical: WinSpace.sm,
    ),
    decoration: BoxDecoration(
      color: WinSurface.window(isDark),
      borderRadius: BorderRadius.circular(WinRadius.card),
      border: Border.all(color: WinSurface.hairline(isDark)),
    ),
    child: SelectableText(
      text,
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.left,
      style: TextStyle(
        fontSize: 12,
        fontFamily: WinMono.family,
        fontFamilyFallback: WinMono.fallback,
        color: JSurface.text(isDark),
      ),
    ),
  );

  Widget _warning(String text, bool isDark) {
    final color = isDark ? DarkColors.warning : LightColors.warning;
    return Container(
      padding: const EdgeInsets.all(WinSpace.md),
      decoration: BoxDecoration(
        color: color.withValues(alpha: isDark ? .14 : .10),
        borderRadius: BorderRadius.circular(WinRadius.card),
        border: Border.all(color: color.withValues(alpha: .35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.warning_amber_rounded, size: 15, color: color),
          const SizedBox(width: WinSpace.sm),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 12,
                height: 1.6,
                fontWeight: FontWeight.w600,
                color: JSurface.text(isDark),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _actions(BuildContext context, bool isDark, Color accent) {
    void close(PermissionDecision d) => Navigator.of(context).pop(d);

    return Padding(
      padding: const EdgeInsets.all(WinSpace.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: _button(
                  label: 'اجازه بده',
                  filled: true,
                  color: accent,
                  isDark: isDark,
                  onTap: () => close(PermissionDecision.allowOnce),
                ),
              ),
              const SizedBox(width: WinSpace.sm),
              Expanded(
                child: _button(
                  label: 'نه',
                  filled: false,
                  color: JSurface.muted(isDark),
                  isDark: isDark,
                  onTap: () => close(PermissionDecision.deny),
                ),
              ),
            ],
          ),
          if (!_irreversible) ...[
            const SizedBox(height: WinSpace.sm),
            Row(
              children: [
                Expanded(
                  child: _button(
                    label: 'تا پایان این کار',
                    filled: false,
                    color: JSurface.secondary(isDark),
                    isDark: isDark,
                    onTap: () => close(PermissionDecision.allowTask),
                  ),
                ),
                const SizedBox(width: WinSpace.sm),
                Expanded(
                  child: _button(
                    label: 'تا بستن برنامه',
                    filled: false,
                    color: JSurface.secondary(isDark),
                    isDark: isDark,
                    onTap: () => close(PermissionDecision.allowSession),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _button({
    required String label,
    required bool filled,
    required Color color,
    required bool isDark,
    required VoidCallback onTap,
  }) => DecoratedBox(
    decoration: BoxDecoration(
      color: filled ? color : Colors.transparent,
      borderRadius: BorderRadius.circular(WinRadius.control),
      border: filled ? null : Border.all(color: WinSurface.hairline(isDark)),
    ),
    child: WinHoverable(
      onTap: onTap,
      radius: WinRadius.control,
      padding: const EdgeInsets.symmetric(vertical: 11),
      child: Center(
        child: Text(
          label,
          style: TextStyle(
            fontSize: WinText.bodySm,
            fontWeight: FontWeight.w700,
            color: filled ? Colors.white : color,
          ),
        ),
      ),
    ),
  );
}
