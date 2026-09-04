import 'package:jemiran/themes/colors.dart';
import 'package:jemiran/themes/jemiran_design.dart';
import 'package:jemiran/ui/screens/chat_room/widgets/model_config.dart';
import 'package:flutter/material.dart';
import 'package:jemiran/model/message.dart';

class ReplyPreview extends StatelessWidget {
  final Message message;
  final VoidCallback onClear;
  final String Function(String) truncate;

  const ReplyPreview({
    super.key,
    required this.message,
    required this.onClear,
    required this.truncate,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final source = message.isUser
        ? 'شما'
        : ModelConfig.label(message.aiSource ?? '');
    final color = message.isUser
        ? JColor.primary(isDark)
        : ModelConfig.mutedColor(message.aiSource ?? 'gemini', isDark: isDark);

    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: isDark ? .12 : .08),
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border(left: BorderSide(color: color, width: 3)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'ریپلای به $source',
                  textDirection: TextDirection.rtl,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  truncate(message.text),
                  maxLines: 2,
                  textDirection: TextDirection.rtl,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.6,
                    color: JSurface.secondary(isDark),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          JPressable(
            onTap: onClear,
            borderRadius: BorderRadius.circular(AppRadius.pill),
            semanticLabel: 'حذف ریپلای',
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.sm),
              child: Icon(
                Icons.close_rounded,
                size: 16,
                color: color.withValues(alpha: .7),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class InlineReply extends StatelessWidget {
  final Message message;

  const InlineReply({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    if (!message.hasReply) return const SizedBox.shrink();

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final source = message.replyToSource == 'user'
        ? 'شما'
        : ModelConfig.label(message.replyToSource ?? '');
    final color = message.replyToSource == 'user'
        ? JColor.primary(isDark)
        : ModelConfig.mutedColor(
            message.replyToSource ?? 'gemini',
            isDark: isDark,
          );

    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: isDark ? .14 : .10),
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border(left: BorderSide(color: color, width: 2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            source,
            textDirection: TextDirection.rtl,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            message.replyToPreview ?? '',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11.5,
              height: 1.6,
              color: JSurface.secondary(isDark),
            ),
          ),
        ],
      ),
    );
  }
}
