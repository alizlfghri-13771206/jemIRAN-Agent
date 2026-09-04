import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:jemiran/desktop/agent/core/agent_task.dart';
import 'package:jemiran/desktop/agent/widgets/agent_activity_label.dart';
import 'package:jemiran/desktop/theme/desktop_tokens.dart';
import 'package:jemiran/desktop/theme/win_controls.dart';
import 'package:jemiran/model/message.dart';
import 'package:jemiran/themes/jemiran_design.dart';
import 'package:jemiran/ui/screens/chat_room/widgets/model_config.dart';
import 'package:jemiran/ui/screens/chat_room/widgets/reply_widgets.dart';
import 'package:jemiran/ui/screens/chat_room/widgets/typewriter_text.dart';
import 'package:jemiran/widgets/cached_image.dart';

class DesktopAiMessage extends StatefulWidget {
  const DesktopAiMessage({
    super.key,
    required this.message,
    required this.typingMessageId,
    required this.isLoading,
    required this.isSelecting,
    required this.onReply,
    this.onTypingDone,
  });

  final Message message;
  final String? typingMessageId;
  final bool isLoading;
  final bool isSelecting;
  final void Function(Message) onReply;
  final VoidCallback? onTypingDone;

  @override
  State<DesktopAiMessage> createState() => _DesktopAiMessageState();
}

class _DesktopAiMessageState extends State<DesktopAiMessage> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final message = widget.message;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final source = message.aiSource ?? 'deepseek';
    final accent = ModelConfig.mutedColor(source, isDark: isDark);
    final isTyping = message.id == widget.typingMessageId;
    final showActions =
        _hovered && !widget.isLoading && !widget.isSelecting && !isTyping;

    return RepaintBoundary(
      child: Semantics(
        container: true,
        label: 'پاسخ هوش مصنوعی',
        child: MouseRegion(
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: WinSpace.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                InlineReply(message: message),
                if (message.hasImage) ...[
                  InteractiveViewer(
                    child: JNetworkImage(
                      url: message.imageUrl!,
                      accent: accent,
                      cachePx: 1440,
                      borderRadius: BorderRadius.circular(WinRadius.card),
                    ),
                  ),
                  if (message.text.isNotEmpty)
                    const SizedBox(height: WinSpace.md),
                ],
                if (message.text.isNotEmpty)
                  MediaQuery(
                    data: MediaQuery.of(
                      context,
                    ).copyWith(textScaler: const TextScaler.linear(.9)),
                    child: isTyping && !message.hasImage
                        ? FadeInText(
                            text: message.text,
                            onDone: widget.onTypingDone,
                          )
                        : AiMessageMarkdown(text: message.text),
                  ),
                AnimatedSize(
                  duration: const Duration(milliseconds: 140),
                  curve: Curves.easeOutCubic,
                  alignment: AlignmentDirectional.centerStart,
                  child: showActions
                      ? Padding(
                          padding: const EdgeInsets.only(top: WinSpace.xs),
                          child: Align(
                            alignment: AlignmentDirectional.centerStart,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                WinIconButton(
                                  icon: Icons.copy_rounded,
                                  tooltip: 'کپی پاسخ',
                                  size: 28,
                                  iconSize: 15,
                                  color: JSurface.muted(isDark),
                                  onTap: () => Clipboard.setData(
                                    ClipboardData(text: message.text),
                                  ),
                                ),
                                const SizedBox(width: WinSpace.xs),
                                WinIconButton(
                                  icon: Icons.reply_rounded,
                                  tooltip: 'پاسخ به این پیام',
                                  size: 28,
                                  iconSize: 15,
                                  color: JSurface.muted(isDark),
                                  onTap: () => widget.onReply(message),
                                ),
                              ],
                            ),
                          ),
                        )
                      : const SizedBox.shrink(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class DesktopAiLoading extends StatefulWidget {
  const DesktopAiLoading({
    super.key,
    required this.phase,
    required this.model,
    this.action,
    this.startedAt,
    this.clock,
  });

  final AgentPhase phase;
  final String model;
  final String? action;

  final DateTime? startedAt;

  final DateTime Function()? clock;

  @override
  State<DesktopAiLoading> createState() => _DesktopAiLoadingState();
}

class _DesktopAiLoadingState extends State<DesktopAiLoading> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    if (widget.startedAt != null) {
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  String _elapsed() {
    final now = widget.clock ?? DateTime.now;
    final seconds = now().difference(widget.startedAt!).inSeconds;
    if (seconds < 60) return '${seconds}s';
    return '${seconds ~/ 60}m ${seconds % 60}s';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = JColor.primary(isDark);
    final label = agentActivityLabel(widget.phase, action: widget.action);
    final modelLabel = ModelConfig.label(widget.model);
    return Semantics(
      liveRegion: true,
      label: label,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: WinSpace.lg),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              JTypingDots(color: accent, dotSize: 6),
              const SizedBox(width: WinSpace.sm),
              Text(
                modelLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: WinFont.family,
                  fontSize: WinText.bodySm,
                  fontWeight: FontWeight.w800,
                  color: JSurface.secondary(isDark),
                ),
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Directionality(
                  textDirection: TextDirection.rtl,
                  child: Text(
                    '· $label',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: WinFont.family,
                      fontSize: WinText.bodySm,
                      fontWeight: FontWeight.w500,
                      color: JSurface.muted(isDark),
                    ),
                  ),
                ),
              ),
              if (widget.startedAt != null) ...[
                const SizedBox(width: 8),
                Text(
                  _elapsed(),
                  style: TextStyle(
                    fontFamily: WinMono.family,
                    fontSize: WinText.caption,
                    fontWeight: FontWeight.w600,
                    color: JSurface.muted(isDark),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
