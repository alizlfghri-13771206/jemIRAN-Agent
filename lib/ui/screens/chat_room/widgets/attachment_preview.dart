import 'package:flutter/material.dart';
import 'package:jemiran/model/pending_attachment.dart';
import 'package:jemiran/themes/colors.dart';
import 'package:jemiran/themes/jemiran_design.dart';

class AttachmentPreview extends StatelessWidget {
  final PendingAttachment attachment;
  final VoidCallback onClear;
  final VoidCallback? onRetry;

  const AttachmentPreview({
    super.key,
    required this.attachment,
    required this.onClear,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primary = JColor.primary(isDark);
    final danger = isDark ? DarkColors.danger : LightColors.danger;
    final success = isDark ? DarkColors.success : LightColors.success;

    final tone = attachment.isFailed ? danger : primary;

    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: isDark ? .12 : .08),
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(
          color: tone.withValues(alpha: attachment.isFailed ? .5 : .3),
        ),
      ),
      child: Row(
        children: [
          _buildThumbnail(context, primary),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  attachment.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                _StatusLine(
                  attachment: attachment,
                  primary: primary,
                  success: success,
                  danger: danger,
                ),
              ],
            ),
          ),
          if (attachment.isFailed && onRetry != null) ...[
            JPressable(
              onTap: onRetry,
              borderRadius: BorderRadius.circular(AppRadius.pill),
              semanticLabel: 'تلاش دوباره',
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.xs,
                ),
                decoration: BoxDecoration(
                  color: danger.withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.refresh_rounded, size: 14, color: danger),
                    const SizedBox(width: 3),
                    Text(
                      'تلاش دوباره',
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        color: danger,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
          ],
          JPressable(
            onTap: onClear,
            borderRadius: BorderRadius.circular(AppRadius.pill),
            semanticLabel: 'حذف پیوست',
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.sm),
              child: Icon(
                Icons.close_rounded,
                size: 16,
                color: primary.withValues(alpha: 0.6),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildThumbnail(BuildContext context, Color primary) {
    Widget base;
    if (attachment.isImage) {
      base = ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.xs),
        child: Image.memory(
          attachment.bytes,
          height: 40,
          width: 40,
          fit: BoxFit.cover,
          cacheWidth: 120,
        ),
      );
    } else {
      base = Container(
        height: 40,
        width: 40,
        decoration: BoxDecoration(
          color: primary.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(AppRadius.xs),
        ),
        child: Icon(Icons.insert_drive_file_outlined, color: primary, size: 22),
      );
    }

    if (attachment.isUploading) {
      base = Stack(
        alignment: Alignment.center,
        children: [
          base,
          Container(
            height: 40,
            width: 40,
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: .35),
              borderRadius: BorderRadius.circular(AppRadius.xs),
            ),
          ),
          const SizedBox(
            height: 18,
            width: 18,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation(Colors.white),
            ),
          ),
        ],
      );
    }
    return base;
  }
}

class _StatusLine extends StatelessWidget {
  final PendingAttachment attachment;
  final Color primary;
  final Color success;
  final Color danger;

  const _StatusLine({
    required this.attachment,
    required this.primary,
    required this.success,
    required this.danger,
  });

  @override
  Widget build(BuildContext context) {
    final (icon, text, color) = switch (attachment.status) {
      AttachmentUploadStatus.uploading => (
        null,
        'در حال آپلود…',
        primary.withValues(alpha: .8),
      ),
      AttachmentUploadStatus.done => (
        Icons.check_circle_rounded,
        'آماده',
        success,
      ),
      AttachmentUploadStatus.failed => (
        Icons.error_rounded,
        'آپلود ناموفق',
        danger,
      ),
    };

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 3),
        ] else ...[
          SizedBox(
            height: 10,
            width: 10,
            child: CircularProgressIndicator(
              strokeWidth: 1.6,
              valueColor: AlwaysStoppedAnimation(color),
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
        ],
        Text(
          text,
          style: TextStyle(
            fontSize: 10.5,
            fontWeight: FontWeight.w600,
            color: color,
          ),
        ),
      ],
    );
  }
}
