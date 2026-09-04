import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:jemiran/themes/jemiran_design.dart';

import '../theme/desktop_tokens.dart';
import 'desktop_state.dart';

class SidebarResizeHandle extends ConsumerStatefulWidget {
  const SidebarResizeHandle({super.key, required this.isDark});

  final bool isDark;

  static const hitWidth = 9.0;

  @override
  ConsumerState<SidebarResizeHandle> createState() =>
      _SidebarResizeHandleState();
}

class _SidebarResizeHandleState extends ConsumerState<SidebarResizeHandle> {
  bool _hovered = false;
  bool _dragging = false;

  @override
  Widget build(BuildContext context) {
    final accent = JColor.primary(widget.isDark);
    final active = _hovered || _dragging;

    return MouseRegion(
      cursor: SystemMouseCursors.resizeLeftRight,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragStart: (_) => setState(() => _dragging = true),
        onHorizontalDragUpdate: (details) {
          ref
              .read(sidebarWidthProvider.notifier)
              .set(details.globalPosition.dx);
        },
        onHorizontalDragEnd: (_) {
          setState(() => _dragging = false);
          ref.read(sidebarWidthProvider.notifier).persist();
        },
        onDoubleTap: () => ref.read(sidebarWidthProvider.notifier).reset(),
        child: SizedBox(
          width: SidebarResizeHandle.hitWidth,
          child: Center(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              width: active ? 2 : .6,
              color: active ? accent : WinSurface.seam(widget.isDark),
            ),
          ),
        ),
      ),
    );
  }
}
