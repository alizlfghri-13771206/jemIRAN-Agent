import 'package:jemiran/themes/colors.dart';
import 'package:jemiran/themes/jemiran_design.dart';
import 'package:jemiran/ui/screens/chat_room/widgets/model_config.dart';
import 'package:flutter/material.dart';

class SelectToolbar extends StatelessWidget {
  final int selectedCount;
  final String activeModel;
  final List<String> availableModels;
  final ValueChanged<String> onSendToModel;

  const SelectToolbar({
    super.key,
    required this.selectedCount,
    required this.activeModel,
    required this.availableModels,
    required this.onSendToModel,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final others = availableModels.where((m) => m != activeModel).toList();

    return JGlass(
      isDark: isDark,
      radius: AppRadius.xl,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      child: Row(
        children: [
          Flexible(
            flex: 3,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              child: Row(
                children: [
                  ...others.map(
                    (model) => Padding(
                      padding: const EdgeInsets.only(left: AppSpacing.sm),
                      child: _ModelButton(
                        model: model,
                        isDark: isDark,
                        onTap: () => onSendToModel(model),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Flexible(
            flex: 1,
            child: Row(
              children: [
                const SizedBox(width: AppSpacing.sm),
                Flexible(
                  child: Text(
                    '$selectedCount انتخاب شد',
                    textDirection: TextDirection.rtl,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: JSurface.text(isDark),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ModelButton extends StatelessWidget {
  final String model;
  final bool isDark;
  final VoidCallback onTap;

  const _ModelButton({
    required this.model,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = ModelConfig.mutedColor(model, isDark: isDark);

    return JPressable(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.pill),
      splashColor: color.withValues(alpha: .12),
      semanticLabel: 'ارسال به ${ModelConfig.label(model)}',
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        decoration: BoxDecoration(
          color: color.withValues(alpha: .10),
          borderRadius: BorderRadius.circular(AppRadius.pill),
          border: Border.all(color: color.withValues(alpha: .30)),
        ),
        child: Text(
          ModelConfig.label(model),
          style: TextStyle(
            fontSize: 11,
            color: color,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}
