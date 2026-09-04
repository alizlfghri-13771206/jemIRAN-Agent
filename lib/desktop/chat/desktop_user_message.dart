import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:jemiran/desktop/theme/desktop_tokens.dart';
import 'package:jemiran/model/message.dart';
import 'package:jemiran/themes/jemiran_design.dart';
import 'package:jemiran/ui/screens/chat_room/widgets/guess_direction.dart';
import 'package:jemiran/ui/screens/chat_room/widgets/reply_widgets.dart';

const double desktopUserMessageFontSize = 14;

class DesktopUserMessage extends StatelessWidget {
  const DesktopUserMessage({super.key, required this.message, this.onResend});

  final Message message;
  final VoidCallback? onResend;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = JColor.primary(isDark);
    final time = jFormatTime(jMessageTime(message.id));

    return RepaintBoundary(
      child: Semantics(
        container: true,
        label: 'پیام شما',
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: WinSpace.md),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final maxBubbleWidth = constraints.maxWidth * .76;
              return Align(
                alignment: Alignment.centerRight,
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: maxBubbleWidth),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      GestureDetector(
                        onLongPress: () => _copyMessage(context),
                        child: DecoratedBox(
                          key: const ValueKey('desktop_user_bubble_surface'),
                          decoration: BoxDecoration(
                            color: Color.alphaBlend(
                              accent.withValues(alpha: isDark ? .075 : .045),
                              WinSurface.card(isDark),
                            ),
                            borderRadius: BorderRadius.circular(
                              WinRadius.layer,
                            ),
                            border: Border.all(
                              color: accent.withValues(
                                alpha: isDark ? .20 : .14,
                              ),
                              width: .8,
                            ),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(
                              WinSpace.lg,
                              WinSpace.md,
                              WinSpace.lg,
                              10,
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                InlineReply(message: message),
                                if (message.hasAttachment ||
                                    message.hasAttachedImages) ...[
                                  _DesktopAttachment(
                                    message: message,
                                    isDark: isDark,
                                  ),
                                  const SizedBox(height: WinSpace.sm),
                                ],
                                if (message.text.isNotEmpty)
                                  ...message.text.split('\n').map((line) {
                                    final direction = detectDirection(line);
                                    return Text(
                                      line,
                                      textDirection: direction,
                                      textAlign: direction == TextDirection.rtl
                                          ? TextAlign.right
                                          : TextAlign.left,
                                      style: TextStyle(
                                        fontFamily: WinFont.family,
                                        fontSize: desktopUserMessageFontSize,
                                        height: 1.65,
                                        letterSpacing: -.15,
                                        color: JSurface.text(isDark),
                                      ),
                                    );
                                  }),
                                JMessageMeta(
                                  isDark: isDark,
                                  time: time,
                                  showTick: true,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 5),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _MessageAction(
                            icon: Icons.copy_rounded,
                            label: 'کپی',
                            onTap: () => _copyMessage(context),
                          ),
                          const SizedBox(width: 4),
                          _MessageAction(
                            icon: Icons.refresh_rounded,
                            label: 'ارسال دوباره',
                            onTap: onResend,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  void _copyMessage(BuildContext context) {
    Clipboard.setData(ClipboardData(text: message.text));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        duration: Duration(milliseconds: 650),
        content: Text(
          'پیام شما کپی شد',
          textAlign: TextAlign.right,
          textDirection: TextDirection.rtl,
        ),
      ),
    );
  }
}

class _MessageAction extends StatelessWidget {
  const _MessageAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Tooltip(
      message: label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
          child: Icon(
            icon,
            size: 13,
            color: onTap == null
                ? JSurface.muted(isDark).withValues(alpha: .45)
                : JSurface.muted(isDark),
          ),
        ),
      ),
    );
  }
}

class _DesktopAttachment extends StatelessWidget {
  const _DesktopAttachment({required this.message, required this.isDark});

  final Message message;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final bytes = message.attachmentBytesList;
    if (bytes != null && bytes.isNotEmpty) {
      return _DesktopImageGrid(
        count: bytes.length,
        imageBuilder: (index) => Image.memory(
          bytes[index],
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => _brokenImage(isDark),
        ),
        onTap: (index) => _openBytes(context, bytes[index]),
      );
    }

    final urls = message.attachmentImageUrls;
    if (urls != null && urls.isNotEmpty) {
      return _DesktopImageGrid(
        count: urls.length,
        imageBuilder: (index) => Image.network(
          urls[index],
          fit: BoxFit.cover,
          loadingBuilder: (context, child, progress) => progress == null
              ? child
              : Center(
                  child: SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: JColor.primary(isDark),
                    ),
                  ),
                ),
          errorBuilder: (_, _, _) => _brokenImage(isDark),
        ),
        onTap: (index) => _openNetwork(context, urls[index]),
      );
    }

    final accent = JColor.primary(isDark);
    return Container(
      constraints: const BoxConstraints(maxWidth: 320),
      padding: const EdgeInsets.symmetric(
        horizontal: WinSpace.md,
        vertical: WinSpace.sm,
      ),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: .09),
        borderRadius: BorderRadius.circular(WinRadius.control),
        border: Border.all(color: accent.withValues(alpha: .20), width: .8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            message.isImageAttachment
                ? Icons.image_outlined
                : Icons.attach_file_rounded,
            size: 15,
            color: accent,
          ),
          const SizedBox(width: WinSpace.sm),
          Flexible(
            child: Text(
              message.attachmentName ?? '',
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: WinFont.family,
                fontSize: WinText.caption,
                fontWeight: FontWeight.w600,
                color: accent,
              ),
            ),
          ),
        ],
      ),
    );
  }

  static Widget _brokenImage(bool isDark) => ColoredBox(
    color: WinSurface.window(isDark),
    child: Center(
      child: Icon(
        Icons.broken_image_outlined,
        size: 26,
        color: JSurface.muted(isDark),
      ),
    ),
  );

  static void _openBytes(BuildContext context, Uint8List bytes) {
    _openImage(context, Image.memory(bytes, fit: BoxFit.contain));
  }

  static void _openNetwork(BuildContext context, String url) {
    _openImage(context, Image.network(url, fit: BoxFit.contain));
  }

  static void _openImage(BuildContext context, Widget image) {
    Navigator.of(context).push(
      PageRouteBuilder<void>(
        opaque: false,
        barrierColor: Colors.black87,
        pageBuilder: (context, _, _) => Scaffold(
          backgroundColor: Colors.black87,
          body: Stack(
            children: [
              Center(
                child: InteractiveViewer(
                  minScale: .5,
                  maxScale: 4,
                  child: image,
                ),
              ),
              Positioned(
                top: 18,
                left: 18,
                child: IconButton.filledTonal(
                  tooltip: 'بستن',
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close_rounded),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DesktopImageGrid extends StatelessWidget {
  const _DesktopImageGrid({
    required this.count,
    required this.imageBuilder,
    required this.onTap,
  });

  final int count;
  final Widget Function(int index) imageBuilder;
  final void Function(int index) onTap;

  @override
  Widget build(BuildContext context) {
    if (count == 1) {
      return InkWell(
        borderRadius: BorderRadius.circular(WinRadius.card),
        onTap: () => onTap(0),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(WinRadius.card),
          child: SizedBox(width: 360, height: 210, child: imageBuilder(0)),
        ),
      );
    }

    return SizedBox(
      width: 360,
      child: Wrap(
        spacing: WinSpace.sm,
        runSpacing: WinSpace.sm,
        children: List.generate(count, (index) {
          return InkWell(
            borderRadius: BorderRadius.circular(WinRadius.control),
            onTap: () => onTap(index),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(WinRadius.control),
              child: SizedBox.square(
                dimension: 176,
                child: imageBuilder(index),
              ),
            ),
          );
        }),
      ),
    );
  }
}
