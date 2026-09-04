import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jemiran/desktop/theme/desktop_tokens.dart';
import 'package:jemiran/desktop/theme/win_controls.dart';
import 'package:jemiran/desktop/models/desktop_models_notifier.dart';
import 'package:jemiran/themes/colors.dart';
import 'package:jemiran/themes/jemiran_design.dart';
import 'package:jemiran/ui/screens/chat_room/widgets/model_config.dart';

import 'desktop_model_route.dart';

Future<void> showDesktopModelRouteDialog(BuildContext context) =>
    showDialog<void>(
      context: context,
      builder: (_) => const _DesktopModelRouteDialog(),
    );

class _DesktopModelRouteDialog extends ConsumerStatefulWidget {
  const _DesktopModelRouteDialog();

  @override
  ConsumerState<_DesktopModelRouteDialog> createState() =>
      _DesktopModelRouteDialogState();
}

class _DesktopModelRouteDialogState
    extends ConsumerState<_DesktopModelRouteDialog> {
  Timer? _refreshTimer;

  final Set<String> _expanded = {};
  bool _seededExpansion = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
    _refreshTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => _refresh(),
    );
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    await ref.read(desktopModelsProvider.notifier).refresh();
    if (!mounted) return;
    final available = ref
        .read(desktopModelsProvider)
        .models
        .where(modelRunnable)
        .map((model) => model['key'] as String?)
        .whereType<String>()
        .toList(growable: false);
    await ref.read(desktopModelRouteProvider.notifier).reconcile(available);
  }

  Widget _row(
    Map<String, dynamic> model,
    DesktopModelRouteState route,
    bool isDark,
  ) {
    final key = model['key'] as String;
    final isSelected = route.contains(key);
    final priority = route.priority.indexOf(key);
    final available = modelRunnable(model);
    return _RouteRow(
      model: model,
      selected: isSelected,
      priority: priority,
      available: available,
      isDark: isDark,
      onToggle: available
          ? () => ref.read(desktopModelRouteProvider.notifier).toggle(key)
          : null,
      onPrimary: isSelected && priority > 0
          ? () => ref.read(desktopModelRouteProvider.notifier).setPrimary(key)
          : null,
      onUp: isSelected && priority > 0
          ? () => ref.read(desktopModelRouteProvider.notifier).move(key, -1)
          : null,
      onDown:
          isSelected && priority >= 0 && priority < route.priority.length - 1
          ? () => ref.read(desktopModelRouteProvider.notifier).move(key, 1)
          : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final route = ref.watch(desktopModelRouteProvider);
    final state = ref.watch(desktopModelsProvider);
    final byKey = {
      for (final model in state.models)
        if (model['key'] is String) model['key'] as String: model,
    };
    final selected = route.priority
        .where(byKey.containsKey)
        .map((key) => byKey[key]!)
        .toList(growable: false);
    final groups = state.agentModelsByCompany;

    if (!_seededExpansion && groups.isNotEmpty) {
      _seededExpansion = true;
      for (final group in groups) {
        if (group.models.any(
          (model) => route.contains(model['key'] as String? ?? ''),
        )) {
          _expanded.add(group.company);
        }
      }
      if (_expanded.isEmpty) _expanded.add(groups.first.company);
    }

    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        width: 700,
        constraints: const BoxConstraints(maxHeight: 720),
        padding: const EdgeInsets.all(WinSpace.xl),
        decoration: BoxDecoration(
          color: WinSurface.layer(isDark),
          borderRadius: BorderRadius.circular(WinRadius.layer),
          border: Border.all(color: WinSurface.hairline(isDark)),
          boxShadow: AppShadows.soft(isDark),
        ),
        child: Directionality(
          textDirection: TextDirection.rtl,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'انتخاب مدل و اولویت‌بندی',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                            color: JSurface.text(isDark),
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          'مدل‌های موردنظر خود را انتخاب کنید.',
                          style: TextStyle(
                            fontSize: 12,
                            height: 1.7,
                            color: JSurface.muted(isDark),
                          ),
                        ),
                      ],
                    ),
                  ),
                  WinIconButton(
                    icon: Icons.close_rounded,
                    tooltip: 'بستن',
                    onTap: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: WinSpace.lg),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    if (selected.isNotEmpty) ...[
                      _SectionLabel(
                        text: 'مدل‌ها به ترتیب اولویت',
                        isDark: isDark,
                      ),
                      for (final model in selected) ...[
                        _row(model, route, isDark),
                        const SizedBox(height: 7),
                      ],
                      const SizedBox(height: WinSpace.md),
                    ],
                    _SectionLabel(
                      text: 'همه مدل‌های جمیران ایجنت',
                      isDark: isDark,
                    ),
                    for (final group in groups)
                      _CompanyGroup(
                        company: group.company,
                        isDark: isDark,
                        expanded: _expanded.contains(group.company),
                        onToggle: () => setState(() {
                          if (!_expanded.remove(group.company)) {
                            _expanded.add(group.company);
                          }
                        }),
                        children: [
                          for (final model in group.models) ...[
                            _row(model, route, isDark),
                            const SizedBox(height: 7),
                          ],
                        ],
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

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.text, required this.isDark});

  final String text;
  final bool isDark;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: WinSpace.sm, top: 2),
    child: Text(
      text,
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w800,
        letterSpacing: .2,
        color: JSurface.muted(isDark),
      ),
    ),
  );
}

class _CompanyGroup extends StatelessWidget {
  const _CompanyGroup({
    required this.company,
    required this.isDark,
    required this.expanded,
    required this.onToggle,
    required this.children,
  });

  final String company;
  final bool isDark;
  final bool expanded;
  final VoidCallback onToggle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final count = (children.length / 2).ceil();
    return Padding(
      padding: const EdgeInsets.only(bottom: WinSpace.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          WinHoverable(
            onTap: onToggle,
            radius: WinRadius.card,
            padding: const EdgeInsets.symmetric(
              horizontal: WinSpace.md,
              vertical: 9,
            ),
            child: Row(
              children: [
                Icon(
                  expanded
                      ? Icons.keyboard_arrow_down_rounded
                      : Icons.keyboard_arrow_left_rounded,
                  size: 19,
                  color: JSurface.muted(isDark),
                ),
                const SizedBox(width: WinSpace.sm),
                Expanded(
                  child: Text(
                    company,
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w800,
                      color: JSurface.text(isDark),
                    ),
                  ),
                ),
                Text(
                  '$count مدل',
                  style: TextStyle(fontSize: 11, color: JSurface.muted(isDark)),
                ),
              ],
            ),
          ),
          if (expanded)
            Padding(
              padding: const EdgeInsets.only(top: 7, right: WinSpace.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: children,
              ),
            ),
        ],
      ),
    );
  }
}

class _RouteRow extends StatelessWidget {
  const _RouteRow({
    required this.model,
    required this.selected,
    required this.priority,
    required this.available,
    required this.isDark,
    required this.onToggle,
    required this.onPrimary,
    required this.onUp,
    required this.onDown,
  });

  final Map<String, dynamic> model;
  final bool selected;
  final int priority;
  final bool available;
  final bool isDark;
  final VoidCallback? onToggle;
  final VoidCallback? onPrimary;
  final VoidCallback? onUp;
  final VoidCallback? onDown;

  @override
  Widget build(BuildContext context) {
    final key = model['key'] as String;
    final accent = JColor.primary(isDark);
    final locked = model['locked'] == true;
    final temporarilyUnavailable = model['temporarily_unavailable'] == true;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: WinSpace.md,
        vertical: WinSpace.sm,
      ),
      decoration: BoxDecoration(
        color: selected
            ? accent.withValues(alpha: .09)
            : WinSurface.card(isDark),
        borderRadius: BorderRadius.circular(WinRadius.card),
        border: Border.all(
          color: selected
              ? accent.withValues(alpha: .45)
              : WinSurface.hairline(isDark),
        ),
      ),
      child: Row(
        children: [
          Checkbox(
            value: selected,
            onChanged: onToggle == null ? null : (_) => onToggle!(),
          ),
          if (locked) ...[
            Icon(
              Icons.lock_outline_rounded,
              size: 17,
              color: JSurface.muted(isDark),
            ),
            const SizedBox(width: WinSpace.sm),
          ],
          if (selected) ...[
            Container(
              width: 25,
              height: 25,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: .14),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                '${priority + 1}',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: accent,
                ),
              ),
            ),
            const SizedBox(width: WinSpace.sm),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        ModelConfig.label(key),
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          color: available
                              ? JSurface.text(isDark)
                              : JSurface.muted(isDark),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  locked
                      ? 'برای این مدل کلیدی تنظیم نشده است'
                      : (temporarilyUnavailable
                            ? 'موقتاً غیرفعال'
                            : 'با کلید شخصی خودت اجرا می‌شود'),
                  style: TextStyle(
                    fontSize: 10.5,
                    color: JSurface.muted(isDark),
                  ),
                ),
              ],
            ),
          ),
          if (onPrimary != null)
            TextButton(onPressed: onPrimary, child: const Text('مدل اصلی')),
          if (selected) ...[
            WinIconButton(
              icon: Icons.arrow_upward_rounded,
              tooltip: 'اولویت بالاتر',
              onTap: onUp,
            ),
            WinIconButton(
              icon: Icons.arrow_downward_rounded,
              tooltip: 'اولویت پایین‌تر',
              onTap: onDown,
            ),
          ],
        ],
      ),
    );
  }
}
