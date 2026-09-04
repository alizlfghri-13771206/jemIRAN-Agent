import 'dart:async';
import 'package:jemiran/themes/colors.dart';
import 'package:jemiran/themes/jemiran_design.dart';
import 'package:jemiran/ui/screens/chat_room/widgets/model_config.dart';
import 'package:flutter/material.dart';

class LoadingBubble extends StatefulWidget {
  final String? source;
  const LoadingBubble({super.key, required this.source});

  @override
  State<LoadingBubble> createState() => _LoadingBubbleState();
}

class _LoadingBubbleState extends State<LoadingBubble> {
  static const List<String> _phases = [
    'در حال تفکر...',
    'در حال پردازش...',
    'در حال نوشتن...',
  ];

  static const List<int> _durations = [1800, 1600, 99999];

  int _phaseIndex = 0;
  double _textOpacity = 1.0;
  Timer? _phaseTimer;

  @override
  void initState() {
    super.initState();
    _scheduleNextPhase();
  }

  void _scheduleNextPhase() {
    if (_phaseIndex >= _phases.length - 1) return;

    _phaseTimer = Timer(Duration(milliseconds: _durations[_phaseIndex]), () {
      if (!mounted) return;
      setState(() => _textOpacity = 0.0);

      Future.delayed(const Duration(milliseconds: 250), () {
        if (!mounted) return;
        setState(() {
          _phaseIndex++;
          _textOpacity = 1.0;
        });
        _scheduleNextPhase();
      });
    });
  }

  @override
  void dispose() {
    _phaseTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final source = widget.source;
    final color = source != null
        ? ModelConfig.mutedColor(source, isDark: isDark)
        : JSurface.muted(isDark);
    final label = source != null ? ModelConfig.label(source) : '';

    return RepaintBoundary(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.sm,
          AppSpacing.md,
          AppSpacing.xl,
          AppSpacing.md,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (source != null) ...[
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: JSurface.card(isDark),
                  border: Border.all(
                    color: color.withValues(alpha: .4),
                    width: 1.4,
                  ),
                  image: DecorationImage(
                    image: ModelConfig.avatarImage(source),
                    fit: BoxFit.cover,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
            ],
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.xs,
                      vertical: AppSpacing.sm,
                    ),
                    child: JTypingDots(color: color),
                  ),
                  AnimatedOpacity(
                    opacity: _textOpacity,
                    duration: const Duration(milliseconds: 250),
                    curve: Curves.easeInOut,
                    child: RichText(
                      textDirection: TextDirection.rtl,
                      text: TextSpan(
                        style: TextStyle(
                          color: JSurface.muted(isDark),
                          fontSize: 12,
                        ),
                        children: [
                          if (label.isNotEmpty) ...[
                            TextSpan(
                              text: label,
                              style: TextStyle(
                                color: color,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const TextSpan(text: '  '),
                          ],
                          TextSpan(text: _phases[_phaseIndex]),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
