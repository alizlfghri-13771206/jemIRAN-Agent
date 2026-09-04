import 'package:flutter/material.dart';
import 'package:jemiran/desktop/agent/agent_workspace.dart';
import 'package:jemiran/desktop/agent/core/agent_task.dart';
import 'package:jemiran/desktop/theme/desktop_tokens.dart';
import 'package:jemiran/desktop/theme/win_controls.dart';
import 'package:jemiran/themes/colors.dart';
import 'package:jemiran/themes/jemiran_design.dart';

Future<bool> showTaskRollbackDialog(
  BuildContext context,
  AgentTask task,
) async {
  final confirmed = await showDialog<bool>(
    context: context,
    barrierDismissible: true,
    builder: (_) => _RollbackDialog(task: task),
  );
  return confirmed == true;
}

class _RollbackDialog extends StatelessWidget {
  const _RollbackDialog({required this.task});

  final AgentTask task;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final danger = isDark ? DarkColors.warning : LightColors.warning;
    final paths = task.changedPaths.toList();

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
          constraints: const BoxConstraints(maxWidth: 540, maxHeight: 560),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.all(WinSpace.xl),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      height: 32,
                      width: 32,
                      decoration: BoxDecoration(
                        color: danger.withValues(alpha: isDark ? .18 : .12),
                        borderRadius: BorderRadius.circular(WinRadius.card),
                      ),
                      child: Icon(
                        Icons.settings_backup_restore_rounded,
                        size: 17,
                        color: danger,
                      ),
                    ),
                    const SizedBox(width: WinSpace.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'بازگرداندن تغییرات این کار',
                            style: TextStyle(
                              fontSize: WinText.body,
                              fontWeight: FontWeight.w700,
                              color: JSurface.text(isDark),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'این ${paths.length} مسیر به وضعیتی که پیش از شروع '
                            'این کار داشتند برمی‌گردند. هر تغییری که بعد از آن '
                            'روی همین مسیرها انجام شده — چه توسط شما و چه توسط '
                            'کار دیگری — از بین می‌رود.',
                            style: TextStyle(
                              fontSize: 12,
                              height: 1.8,
                              color: JSurface.muted(isDark),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              if (task.hasUntrackedChanges)
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    WinSpace.xl,
                    0,
                    WinSpace.xl,
                    WinSpace.md,
                  ),
                  child: Container(
                    padding: const EdgeInsets.all(WinSpace.md),
                    decoration: BoxDecoration(
                      color: danger.withValues(alpha: isDark ? .16 : .1),
                      borderRadius: BorderRadius.circular(WinRadius.card),
                      border: Border.all(color: danger.withValues(alpha: .4)),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.warning_amber_rounded,
                          size: 16,
                          color: danger,
                        ),
                        const SizedBox(width: WinSpace.sm),
                        Expanded(
                          child: Text(
                            'این بازگردانی کامل نیست: در این کار '
                            '${task.untrackedChanges} عملیات انجام شده که '
                            'قابل بازگرداندن نیست — اجرای فرمان، نصب بسته یا '
                            'تغییر Git. فقط فایل‌های فهرست پایین برمی‌گردند.',
                            style: TextStyle(
                              fontSize: 11.5,
                              height: 1.8,
                              color: JSurface.text(isDark),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              const WinSeam(),
              Flexible(
                child: WinScrollbar(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(WinSpace.xl),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (final path in paths)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: Text(
                              AgentWorkspace.display(path),
                              textDirection: TextDirection.ltr,
                              style: TextStyle(
                                fontSize: 11.5,
                                fontFamily: 'monospace',
                                color: JSurface.text(isDark),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              const WinSeam(),
              Padding(
                padding: const EdgeInsets.all(WinSpace.lg),
                child: Row(
                  children: [
                    Expanded(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: danger,
                          borderRadius: BorderRadius.circular(
                            WinRadius.control,
                          ),
                        ),
                        child: WinHoverable(
                          onTap: () => Navigator.of(context).pop(true),
                          radius: WinRadius.control,
                          padding: const EdgeInsets.symmetric(vertical: 11),
                          child: const Center(
                            child: Text(
                              'بله، برگردان',
                              style: TextStyle(
                                fontSize: WinText.bodySm,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: WinSpace.sm),
                    DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(WinRadius.control),
                        border: Border.all(color: WinSurface.hairline(isDark)),
                      ),
                      child: WinHoverable(
                        onTap: () => Navigator.of(context).pop(false),
                        radius: WinRadius.control,
                        padding: const EdgeInsets.symmetric(
                          vertical: 11,
                          horizontal: WinSpace.xl,
                        ),
                        child: Text(
                          'انصراف',
                          style: TextStyle(
                            fontSize: WinText.bodySm,
                            fontWeight: FontWeight.w700,
                            color: JSurface.muted(isDark),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
