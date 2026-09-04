import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import 'package:jemiran/themes/jemiran_design.dart';

import '../theme/desktop_tokens.dart';

class WindowTitleBar extends StatefulWidget {
  const WindowTitleBar({
    super.key,
    required this.isDark,
    this.leading,
    this.title,
    this.trailing,
  });

  final bool isDark;

  final Widget? leading;
  final Widget? title;
  final Widget? trailing;

  static const height = 38.0;

  @override
  State<WindowTitleBar> createState() => _WindowTitleBarState();
}

class _WindowTitleBarState extends State<WindowTitleBar> with WindowListener {
  bool _maximized = false;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    _syncMaximized();
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  Future<void> _syncMaximized() async {
    try {
      final value = await windowManager.isMaximized();
      if (mounted && value != _maximized) setState(() => _maximized = value);
    } catch (_) {}
  }

  @override
  void onWindowMaximize() => _syncMaximized();

  @override
  void onWindowUnmaximize() => _syncMaximized();

  Future<void> _toggleMaximize() async {
    if (await windowManager.isMaximized()) {
      await windowManager.unmaximize();
    } else {
      await windowManager.maximize();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;
    return SizedBox(
      height: WindowTitleBar.height,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: WinSurface.window(isDark),
          border: Border(
            bottom: BorderSide(color: WinSurface.seam(isDark), width: .6),
          ),
        ),
        child: Row(
          children: [
            if (widget.leading != null) widget.leading!,
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onPanStart: (_) => windowManager.startDragging(),
                onDoubleTap: _toggleMaximize,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: widget.title ?? const SizedBox.shrink(),
                ),
              ),
            ),
            if (widget.trailing != null) widget.trailing!,
            _WindowButton(
              isDark: isDark,
              tooltip: 'کوچک کردن',
              onTap: windowManager.minimize,
              icon: _MinimizeIcon(color: JSurface.text(isDark)),
            ),
            _WindowButton(
              isDark: isDark,
              tooltip: _maximized ? 'بازگرداندن' : 'بزرگ کردن',
              onTap: _toggleMaximize,
              icon: _maximized
                  ? _RestoreIcon(color: JSurface.text(isDark))
                  : _MaximizeIcon(color: JSurface.text(isDark)),
            ),
            _WindowButton(
              isDark: isDark,
              tooltip: 'بستن',
              onTap: windowManager.close,
              isDanger: true,
              icon: _CloseIcon(color: JSurface.text(isDark)),
            ),
          ],
        ),
      ),
    );
  }
}

class _WindowButton extends StatefulWidget {
  const _WindowButton({
    required this.isDark,
    required this.icon,
    required this.onTap,
    required this.tooltip,
    this.isDanger = false,
  });

  final bool isDark;
  final Widget icon;
  final Future<void> Function() onTap;
  final String tooltip;
  final bool isDanger;

  @override
  State<_WindowButton> createState() => _WindowButtonState();
}

class _WindowButtonState extends State<_WindowButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final hoverColor = widget.isDanger
        ? const Color(0xFFC42B1C)
        : WinSurface.hover(widget.isDark);
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.basic,
      child: Tooltip(
        message: widget.tooltip,
        waitDuration: const Duration(milliseconds: 600),
        child: GestureDetector(
          onTap: () => widget.onTap(),
          child: Container(
            width: 46,
            height: WindowTitleBar.height,
            color: _hovered ? hoverColor : Colors.transparent,
            alignment: Alignment.center,
            child: IconTheme(
              data: IconThemeData(
                color: _hovered && widget.isDanger
                    ? Colors.white
                    : JSurface.text(widget.isDark),
              ),
              child: widget.icon,
            ),
          ),
        ),
      ),
    );
  }
}

class _MinimizeIcon extends StatelessWidget {
  const _MinimizeIcon({required this.color});
  final Color color;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 10,
    height: 10,
    child: CustomPaint(painter: _Stroke(color, _Shape.minimize)),
  );
}

class _MaximizeIcon extends StatelessWidget {
  const _MaximizeIcon({required this.color});
  final Color color;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 10,
    height: 10,
    child: CustomPaint(painter: _Stroke(color, _Shape.maximize)),
  );
}

class _RestoreIcon extends StatelessWidget {
  const _RestoreIcon({required this.color});
  final Color color;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 10,
    height: 10,
    child: CustomPaint(painter: _Stroke(color, _Shape.restore)),
  );
}

class _CloseIcon extends StatelessWidget {
  const _CloseIcon({required this.color});
  final Color color;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 10,
    height: 10,
    child: CustomPaint(painter: _Stroke(color, _Shape.close)),
  );
}

enum _Shape { minimize, maximize, restore, close }

class _Stroke extends CustomPainter {
  const _Stroke(this.color, this.shape);

  final Color color;
  final _Shape shape;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
    final w = size.width;
    final h = size.height;
    switch (shape) {
      case _Shape.minimize:
        canvas.drawLine(Offset(0, h / 2), Offset(w, h / 2), paint);
      case _Shape.maximize:
        canvas.drawRect(Rect.fromLTWH(.5, .5, w - 1, h - 1), paint);
      case _Shape.restore:
        canvas.drawRect(Rect.fromLTWH(2.5, .5, w - 3, h - 3), paint);
        canvas.drawRect(Rect.fromLTWH(.5, 2.5, w - 3, h - 3), paint);
      case _Shape.close:
        canvas.drawLine(Offset.zero, Offset(w, h), paint);
        canvas.drawLine(Offset(w, 0), Offset(0, h), paint);
    }
  }

  @override
  bool shouldRepaint(_Stroke old) => old.color != color || old.shape != shape;
}
