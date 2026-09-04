import 'package:flutter/material.dart';
import 'package:jemiran/desktop/theme/desktop_tokens.dart';
import 'package:jemiran/themes/jemiran_design.dart';

class WinHoverable extends StatefulWidget {
  const WinHoverable({
    super.key,
    required this.child,
    this.onTap,
    this.onSecondaryTap,
    this.radius = WinRadius.card,
    this.padding = EdgeInsets.zero,
    this.selected = false,
    this.baseColor,
    this.tooltip,
    this.enabled = true,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onSecondaryTap;
  final double radius;
  final EdgeInsets padding;
  final bool selected;
  final Color? baseColor;
  final String? tooltip;
  final bool enabled;

  @override
  State<WinHoverable> createState() => _WinHoverableState();
}

class _WinHoverableState extends State<WinHoverable> {
  bool _hover = false;
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final interactive = widget.enabled && widget.onTap != null;

    Color? fill = widget.baseColor;
    if (widget.selected) {
      fill = WinSurface.selected(isDark);
    } else if (interactive && _down) {
      fill = WinSurface.pressed(isDark);
    } else if (interactive && _hover) {
      fill = WinSurface.hover(isDark);
    }

    Widget content = AnimatedContainer(
      duration: const Duration(milliseconds: 110),
      curve: Curves.easeOut,
      padding: widget.padding,
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(widget.radius),
      ),
      child: widget.child,
    );

    if (widget.tooltip != null) {
      content = Tooltip(
        message: widget.tooltip!,
        waitDuration: const Duration(milliseconds: 450),
        child: content,
      );
    }

    return MouseRegion(
      cursor: interactive ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() {
        _hover = false;
        _down = false;
      }),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: interactive ? widget.onTap : null,
        onSecondaryTap: widget.onSecondaryTap,
        onTapDown: interactive ? (_) => setState(() => _down = true) : null,
        onTapUp: interactive ? (_) => setState(() => _down = false) : null,
        onTapCancel: interactive ? () => setState(() => _down = false) : null,
        child: content,
      ),
    );
  }
}

class WinIconButton extends StatelessWidget {
  const WinIconButton({
    super.key,
    required this.icon,
    required this.onTap,
    this.tooltip,
    this.size = 34,
    this.iconSize = 18,
    this.color,
    this.selected = false,
    this.enabled = true,
  });

  final IconData icon;
  final VoidCallback? onTap;
  final String? tooltip;
  final double size;
  final double iconSize;
  final Color? color;
  final bool selected;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final tint =
        color ??
        (selected ? JColor.primary(isDark) : JSurface.secondary(isDark));
    return WinHoverable(
      onTap: onTap,
      enabled: enabled,
      tooltip: tooltip,
      selected: selected,
      radius: WinRadius.control,
      child: SizedBox(
        height: size,
        width: size,
        child: Center(
          child: Icon(
            icon,
            size: iconSize,
            color: enabled ? tint : tint.withValues(alpha: .4),
          ),
        ),
      ),
    );
  }
}

class WinSectionLabel extends StatelessWidget {
  const WinSectionLabel(this.text, {super.key, this.trailing});

  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        WinSpace.md,
        WinSpace.lg,
        WinSpace.md,
        WinSpace.sm,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: WinText.sectionLabel,
                fontWeight: FontWeight.w800,
                letterSpacing: .2,
                color: JSurface.muted(isDark),
              ),
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

class WinScrollbar extends StatefulWidget {
  const WinScrollbar({super.key, required this.child, this.controller});

  final Widget child;

  final ScrollController? controller;

  @override
  State<WinScrollbar> createState() => _WinScrollbarState();
}

class _WinScrollbarState extends State<WinScrollbar> {
  ScrollController? _fallback;

  ScrollController get _controller => widget.controller ?? _ensureFallback();

  ScrollController _ensureFallback() => _fallback ??= ScrollController();

  @override
  void dispose() {
    _fallback?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    var child = widget.child;

    if (widget.controller == null) {
      child = PrimaryScrollController(
        controller: controller,
        automaticallyInheritForPlatforms: TargetPlatform.values.toSet(),
        child: child,
      );
    }

    return Scrollbar(
      controller: controller,
      thickness: 8,
      radius: const Radius.circular(4),
      interactive: true,
      child: child,
    );
  }
}

class WinSeam extends StatelessWidget {
  const WinSeam({super.key, this.vertical = false});

  final bool vertical;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final color = WinSurface.seam(isDark);
    return vertical
        ? Container(width: 1, color: color)
        : Container(height: 1, color: color);
  }
}
