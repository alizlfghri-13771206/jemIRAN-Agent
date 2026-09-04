import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:jemiran/themes/colors.dart';

abstract final class JColor {
  static Color primary(bool isDark) =>
      isDark ? DarkColors.primary : LightColors.primary;

  static Color secondary(bool isDark) =>
      isDark ? DarkColors.accent : LightColors.accent;

  static const _tealLight = Color(0xFF14B8A6);
  static const _tealDark = Color(0xFF4FD1C5);

  static const _pinkLight = Color(0xFFEC4899);
  static const _pinkDark = Color(0xFFF78CC4);

  static const _greenLight = Color(0xFF10B981);
  static const _greenDark = Color(0xFF4ADE9B);

  static Color teal(bool isDark) => isDark ? _tealDark : _tealLight;

  static Color pink(bool isDark) => isDark ? _pinkDark : _pinkLight;

  static Color green(bool isDark) => isDark ? _greenDark : _greenLight;

  static Color studioImage(bool isDark) => secondary(isDark);
  static Color studioFilm(bool isDark) => pink(isDark);
  static Color studioVoice(bool isDark) => green(isDark);
  static Color studioDocs(bool isDark) => primary(isDark);
}

abstract final class JSurface {
  static Color page(bool isDark) =>
      isDark ? DarkColors.background : LightColors.background;

  static Color card(bool isDark) =>
      isDark ? DarkColors.surfaceElevated : LightColors.surface;

  static Color glass(bool isDark) => isDark
      ? DarkColors.surfaceElevated.withValues(alpha: .72)
      : LightColors.surface.withValues(alpha: .72);

  static Color hairline(bool isDark) =>
      isDark ? DarkColors.border : LightColors.border;

  static Color text(bool isDark) => isDark ? DarkColors.text : LightColors.text;

  static Color secondary(bool isDark) =>
      isDark ? DarkColors.secondaryText : LightColors.secondaryText;

  static Color muted(bool isDark) =>
      isDark ? DarkColors.tertiaryText : LightColors.tertiaryText;
}

abstract final class JGradient {
  static LinearGradient brand(bool isDark) => LinearGradient(
    colors: [JColor.primary(isDark), JColor.secondary(isDark)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static LinearGradient hero(bool isDark) => LinearGradient(
    colors: [
      JColor.primary(isDark),
      JColor.secondary(isDark),
      JColor.pink(isDark),
    ],
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
  );

  static LinearGradient heroBorder(bool isDark) => LinearGradient(
    begin: Alignment.topRight,
    end: Alignment.bottomLeft,
    colors: [
      JColor.pink(isDark).withValues(alpha: isDark ? .42 : .32),
      JColor.secondary(isDark).withValues(alpha: isDark ? .34 : .24),
      JColor.teal(isDark).withValues(alpha: isDark ? .38 : .28),
    ],
  );

  static LinearGradient accentBorder(Color accent, bool isDark) =>
      LinearGradient(
        begin: Alignment.topRight,
        end: Alignment.bottomLeft,
        colors: [
          accent.withValues(alpha: isDark ? .45 : .32),
          accent.withValues(alpha: isDark ? .12 : .07),
        ],
      );

  static LinearGradient accentSurface(Color accent, bool isDark) =>
      LinearGradient(
        begin: Alignment.topRight,
        end: Alignment.bottomLeft,
        colors: [
          accent.withValues(alpha: isDark ? .14 : .10),
          accent.withValues(alpha: isDark ? .04 : .025),
        ],
      );

  static LinearGradient accentIcon(Color accent, bool isDark) => LinearGradient(
    begin: Alignment.topRight,
    end: Alignment.bottomLeft,
    colors: [
      accent.withValues(alpha: isDark ? .32 : .22),
      accent.withValues(alpha: isDark ? .14 : .10),
    ],
  );
}

abstract final class JShadow {
  static List<BoxShadow> tint(
    Color accent,
    bool isDark, {
    double alpha = .16,
    double blur = 26,
    double y = 12,
  }) => [
    BoxShadow(
      color: accent.withValues(alpha: isDark ? alpha * .75 : alpha),
      blurRadius: blur,
      spreadRadius: -10,
      offset: Offset(0, y),
    ),
  ];
}

ImageProvider jAvatarImage(String assetPath, {int cachePx = 128}) =>
    jSizedImage(AssetImage(assetPath), cachePx: cachePx);
ImageProvider jSizedImage(ImageProvider base, {int cachePx = 128}) =>
    ResizeImage(base, width: cachePx, allowUpscaling: false);

const double jSheetRadius = 32;

abstract final class JMotion {
  static const fast = Duration(milliseconds: 200);
  static const base = Duration(milliseconds: 260);
  static const slow = Duration(milliseconds: 320);

  static const heroFade = Duration(milliseconds: 420);

  static const press = Duration(milliseconds: 130);

  static const curve = Curves.easeOutCubic;
}

class JPressable extends StatefulWidget {
  const JPressable({
    super.key,
    required this.child,
    this.onTap,
    this.borderRadius,
    this.pressedScale = .972,
    this.splashColor,
    this.semanticLabel,
  });

  final Widget child;
  final VoidCallback? onTap;
  final BorderRadius? borderRadius;
  final double pressedScale;
  final Color? splashColor;
  final String? semanticLabel;

  @override
  State<JPressable> createState() => _JPressableState();
}

class _JPressableState extends State<JPressable> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (_pressed == value || !mounted) return;
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final radius = widget.borderRadius ?? BorderRadius.circular(AppRadius.lg);

    return Semantics(
      button: widget.onTap != null,
      label: widget.semanticLabel,
      child: AnimatedScale(
        scale: (_pressed && widget.onTap != null) ? widget.pressedScale : 1,
        duration: JMotion.press,
        curve: JMotion.curve,
        child: Material(
          type: MaterialType.transparency,
          borderRadius: radius,
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: widget.onTap,
            onHighlightChanged: _setPressed,
            borderRadius: radius,
            highlightColor: Colors.transparent,
            splashColor:
                widget.splashColor ??
                JColor.secondary(isDark).withValues(alpha: .10),
            child: widget.child,
          ),
        ),
      ),
    );
  }
}

class JGlass extends StatelessWidget {
  const JGlass({
    super.key,
    required this.child,
    required this.isDark,
    this.radius = AppRadius.lg,
    this.padding = EdgeInsets.zero,
    this.blur = 0,
    this.shadow = true,
  });

  final Widget child;
  final bool isDark;
  final double radius;
  final EdgeInsetsGeometry padding;
  final double blur;

  final bool shadow;

  @override
  Widget build(BuildContext context) {
    final borderRadius = BorderRadius.circular(radius);
    final frosted = blur > 0;

    final surface = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: frosted ? JSurface.glass(isDark) : JSurface.card(isDark),
        borderRadius: borderRadius,
        border: Border.all(color: JSurface.hairline(isDark)),
      ),
      child: child,
    );

    final shell = BoxDecoration(
      borderRadius: borderRadius,
      boxShadow: shadow ? AppShadows.soft(isDark) : null,
    );

    if (!frosted) return DecoratedBox(decoration: shell, child: surface);

    return DecoratedBox(
      decoration: shell,
      child: ClipRRect(
        borderRadius: borderRadius,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
          child: surface,
        ),
      ),
    );
  }
}

class JGradientText extends StatefulWidget {
  const JGradientText(
    this.text, {
    super.key,
    required this.style,
    required this.gradient,
    this.textAlign,
    this.shimmer = false,
  });

  final String text;
  final TextStyle style;
  final LinearGradient gradient;
  final TextAlign? textAlign;

  final bool shimmer;

  @override
  State<JGradientText> createState() => _JGradientTextState();
}

class _JGradientTextState extends State<JGradientText>
    with SingleTickerProviderStateMixin {
  AnimationController? _ctrl;

  @override
  void initState() {
    super.initState();
    if (widget.shimmer) {
      _ctrl = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 4200),
      )..repeat();
    }
  }

  @override
  void dispose() {
    _ctrl?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final label = Text(
      widget.text,
      textAlign: widget.textAlign,
      style: widget.style.copyWith(color: Colors.white),
    );

    final ctrl = _ctrl;
    if (ctrl == null) {
      return ShaderMask(
        blendMode: BlendMode.srcIn,
        shaderCallback: (rect) => widget.gradient.createShader(rect),
        child: label,
      );
    }
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: ctrl,
        child: label,
        builder: (context, child) {
          final sweeping = LinearGradient(
            colors: widget.gradient.colors,
            begin: widget.gradient.begin,
            end: widget.gradient.end,
            tileMode: TileMode.mirror,
            transform: _SlidingGradient(ctrl.value),
          );
          return ShaderMask(
            blendMode: BlendMode.srcIn,
            shaderCallback: (rect) => sweeping.createShader(rect),
            child: child,
          );
        },
      ),
    );
  }
}

class _SlidingGradient extends GradientTransform {
  const _SlidingGradient(this.t);

  final double t;

  @override
  Matrix4 transform(Rect bounds, {TextDirection? textDirection}) =>
      Matrix4.translationValues(bounds.width * 2 * t, 0, 0);
}

class JSparkle extends StatefulWidget {
  const JSparkle({
    super.key,
    required this.gradient,
    this.size = 18,
    this.twinkle = false,
  });

  final Gradient gradient;
  final double size;
  final bool twinkle;

  @override
  State<JSparkle> createState() => _JSparkleState();
}

class _JSparkleState extends State<JSparkle>
    with SingleTickerProviderStateMixin {
  AnimationController? _ctrl;

  @override
  void initState() {
    super.initState();
    if (widget.twinkle) {
      _ctrl = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 2400),
      )..repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _ctrl?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final art = ShaderMask(
      blendMode: BlendMode.srcIn,
      shaderCallback: (rect) => widget.gradient.createShader(rect),
      child: CustomPaint(
        size: Size.square(widget.size),
        painter: const _SparklePainter(),
      ),
    );

    final ctrl = _ctrl;
    if (ctrl == null) return art;

    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: ctrl,
        child: art,
        builder: (context, child) {
          final v = Curves.easeInOut.transform(ctrl.value);
          return Transform.rotate(
            angle: v * .55,
            child: Transform.scale(scale: .74 + .40 * v, child: child),
          );
        },
      ),
    );
  }
}

class _SparklePainter extends CustomPainter {
  const _SparklePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final cx = w / 2;
    final cy = h / 2;
    final pinch = w * .16;

    final path = Path()
      ..moveTo(cx, 0)
      ..quadraticBezierTo(cx + pinch, cy - pinch, w, cy)
      ..quadraticBezierTo(cx + pinch, cy + pinch, cx, h)
      ..quadraticBezierTo(cx - pinch, cy + pinch, 0, cy)
      ..quadraticBezierTo(cx - pinch, cy - pinch, cx, 0)
      ..close();

    canvas.drawPath(path, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(covariant _SparklePainter oldDelegate) => false;
}

class JDashedCircle extends StatelessWidget {
  const JDashedCircle({
    super.key,
    required this.size,
    required this.color,
    this.child,
    this.strokeWidth = 1.3,
    this.dashCount = 18,
  });

  final double size;
  final Color color;
  final Widget? child;
  final double strokeWidth;
  final int dashCount;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.square(size),
      painter: _DashedRingPainter(
        color: color,
        strokeWidth: strokeWidth,
        dashCount: dashCount,
      ),
      child: SizedBox(
        width: size,
        height: size,
        child: Center(child: child),
      ),
    );
  }
}

class _DashedRingPainter extends CustomPainter {
  const _DashedRingPainter({
    required this.color,
    required this.strokeWidth,
    required this.dashCount,
  });

  final Color color;
  final double strokeWidth;
  final int dashCount;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = strokeWidth;

    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - strokeWidth;
    const gapRatio = .42;
    final sweep = 2 * math.pi / dashCount;

    for (var i = 0; i < dashCount; i++) {
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        i * sweep,
        sweep * (1 - gapRatio),
        false,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _DashedRingPainter old) =>
      old.color != color ||
      old.strokeWidth != strokeWidth ||
      old.dashCount != dashCount;
}

class _Glow extends StatelessWidget {
  const _Glow({required this.color, required this.size});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(colors: [color, color.withValues(alpha: 0)]),
        ),
      ),
    );
  }
}

class JPageGlow extends StatelessWidget {
  const JPageGlow({super.key, required this.isDark});

  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final a = isDark ? .16 : .10;

    return IgnorePointer(
      child: RepaintBoundary(
        child: Stack(
          children: [
            PositionedDirectional(
              top: -90,
              start: -70,
              child: _Glow(
                color: JColor.primary(isDark).withValues(alpha: a),
                size: 300,
              ),
            ),
            PositionedDirectional(
              top: 120,
              end: -110,
              child: _Glow(
                color: JColor.secondary(isDark).withValues(alpha: a * .9),
                size: 320,
              ),
            ),
            PositionedDirectional(
              bottom: -120,
              start: -90,
              child: _Glow(
                color: JColor.teal(isDark).withValues(alpha: a * .8),
                size: 340,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class JAurora extends StatefulWidget {
  const JAurora({super.key, required this.isDark});

  final bool isDark;

  @override
  State<JAurora> createState() => _JAuroraState();
}

class _JAuroraState extends State<JAurora> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 13),
  )..repeat();

  late Widget _first;
  late Widget _second;
  late Widget _third;

  @override
  void initState() {
    super.initState();
    _buildGlows();
  }

  @override
  void didUpdateWidget(covariant JAurora oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isDark != widget.isDark) _buildGlows();
  }

  void _buildGlows() {
    final isDark = widget.isDark;
    final a = isDark ? .42 : .34;
    _first = RepaintBoundary(
      child: _Glow(
        color: JColor.primary(isDark).withValues(alpha: a),
        size: 250,
      ),
    );
    _second = RepaintBoundary(
      child: _Glow(
        color: JColor.secondary(isDark).withValues(alpha: a * .95),
        size: 230,
      ),
    );
    _third = RepaintBoundary(
      child: _Glow(
        color: JColor.teal(isDark).withValues(alpha: a * .85),
        size: 220,
      ),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: RepaintBoundary(
        child: AnimatedBuilder(
          animation: _ctrl,
          builder: (context, _) {
            final t = _ctrl.value * 2 * math.pi;
            return Stack(
              children: [
                _blob(
                  _first,
                  top: -80,
                  start: -60,
                  dx: math.sin(t) * 54,
                  dy: math.cos(t * .8) * 40,
                  scale: 1 + .16 * math.sin(t * 1.3),
                ),
                _blob(
                  _second,
                  top: -50,
                  end: -70,
                  dx: math.cos(t * .9) * 60,
                  dy: math.sin(t * 1.15) * 44,
                  scale: 1 + .14 * math.cos(t),
                ),
                _blob(
                  _third,
                  bottom: -90,
                  start: 30,
                  dx: math.sin(t * 1.2 + 1.1) * 52,
                  dy: math.cos(t * .7) * 36,
                  scale: 1 + .18 * math.sin(t * .85 + 2),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _blob(
    Widget glow, {
    double? top,
    double? bottom,
    double? start,
    double? end,
    required double dx,
    required double dy,
    required double scale,
  }) {
    return PositionedDirectional(
      top: top,
      bottom: bottom,
      start: start,
      end: end,
      child: Transform.translate(
        offset: Offset(dx, dy),
        child: Transform.scale(scale: scale, child: glow),
      ),
    );
  }
}

String? jFormatTime(DateTime? time) {
  if (time == null) return null;
  final h = time.hour.toString().padLeft(2, '0');
  final m = time.minute.toString().padLeft(2, '0');
  return '$h:$m';
}

DateTime? jMessageTime(String id) {
  final micros = int.tryParse(id);
  if (micros == null) return null;
  final t = DateTime.fromMicrosecondsSinceEpoch(micros);
  if (t.year < 2020 || t.year > 2100) return null;
  return t;
}

bool jIsFresh(String id, {Duration within = const Duration(seconds: 2)}) {
  final t = jMessageTime(id);
  if (t == null) return false;
  final age = DateTime.now().difference(t);
  return !age.isNegative && age < within;
}

class JBubble extends StatelessWidget {
  const JBubble({
    super.key,
    required this.child,
    required this.isDark,
    this.accent,
    this.accentWidth = 3.5,
    this.padding = const EdgeInsets.symmetric(
      horizontal: AppSpacing.lg,
      vertical: AppSpacing.md,
    ),
    this.radius = AppRadius.xl,
  });

  final Widget child;
  final bool isDark;

  final Color? accent;
  final double accentWidth;
  final EdgeInsetsGeometry padding;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final borderRadius = BorderRadius.circular(radius);
    final bar = accent;
    if (bar == null) {
      return DecoratedBox(
        decoration: BoxDecoration(
          color: JSurface.card(isDark),
          borderRadius: borderRadius,
          border: Border.all(color: JSurface.hairline(isDark)),
          boxShadow: AppShadows.subtle(isDark),
        ),
        child: Padding(padding: padding, child: child),
      );
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        boxShadow: AppShadows.subtle(isDark),
      ),
      child: ClipRRect(
        borderRadius: borderRadius,
        child: Stack(
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                color: JSurface.card(isDark),
                borderRadius: borderRadius,
                border: Border.all(color: JSurface.hairline(isDark)),
              ),
              child: Padding(
                padding: padding.add(EdgeInsets.only(left: accentWidth)),
                child: child,
              ),
            ),
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              width: accentWidth,
              child: ColoredBox(color: bar),
            ),
          ],
        ),
      ),
    );
  }
}

class JMessageEntrance extends StatefulWidget {
  const JMessageEntrance({super.key, required this.child, this.animate = true});

  final Widget child;
  final bool animate;

  @override
  State<JMessageEntrance> createState() => _JMessageEntranceState();
}

class _JMessageEntranceState extends State<JMessageEntrance>
    with SingleTickerProviderStateMixin {
  AnimationController? _ctrl;
  Animation<double>? _curved;

  @override
  void initState() {
    super.initState();
    if (!widget.animate) return;
    final ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );
    _ctrl = ctrl;
    _curved = CurvedAnimation(parent: ctrl, curve: JMotion.curve);
    ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final curved = _curved;
    if (curved == null) return widget.child;

    return FadeTransition(
      opacity: curved,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, .045),
          end: Offset.zero,
        ).animate(curved),
        child: ScaleTransition(
          scale: Tween<double>(begin: .985, end: 1).animate(curved),
          child: widget.child,
        ),
      ),
    );
  }
}

class JTypingDots extends StatefulWidget {
  const JTypingDots({super.key, required this.color, this.dotSize = 7});

  final Color color;
  final double dotSize;

  @override
  State<JTypingDots> createState() => _JTypingDotsState();
}

class _JTypingDotsState extends State<JTypingDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (context, _) {
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: List.generate(3, (i) {
              final phase = (_ctrl.value - i * .22) % 1.0;
              final wave = phase < .5 ? phase * 2 : (1 - phase) * 2;
              final alpha = (.28 + .72 * wave).clamp(.28, 1.0);
              final scale = .82 + .28 * wave;

              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2.5),
                child: Transform.scale(
                  scale: scale,
                  child: Container(
                    width: widget.dotSize,
                    height: widget.dotSize,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: widget.color.withValues(alpha: alpha),
                    ),
                  ),
                ),
              );
            }),
          );
        },
      ),
    );
  }
}

class JMessageMeta extends StatelessWidget {
  const JMessageMeta({
    super.key,
    required this.isDark,
    required this.time,
    this.showTick = false,
  });

  final bool isDark;
  final String? time;
  final bool showTick;

  @override
  Widget build(BuildContext context) {
    if (time == null && !showTick) return const SizedBox.shrink();
    final muted = JSurface.muted(isDark);

    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.sm),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (time != null)
            Text(
              time!,
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w500,
                color: muted,
              ),
            ),
          if (showTick) ...[
            if (time != null) const SizedBox(width: AppSpacing.xs),
            Icon(Icons.done_all_rounded, size: 14, color: muted),
          ],
        ],
      ),
    );
  }
}

class JSkeletonLine extends StatelessWidget {
  const JSkeletonLine({
    super.key,
    required this.isDark,
    this.width,
    this.height = 12,
    this.radius = 6,
  });

  final bool isDark;
  final double? width;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: isDark ? DarkColors.surfaceHigh : LightColors.surfaceHigh,
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}

class JSkeletonFade extends StatefulWidget {
  const JSkeletonFade({super.key, required this.child});

  final Widget child;

  @override
  State<JSkeletonFade> createState() => _JSkeletonFadeState();
}

class _JSkeletonFadeState extends State<JSkeletonFade>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: JMotion.base,
    value: 0,
  )..forward();

  late final Animation<double> _fade = Tween<double>(
    begin: .5,
    end: 1,
  ).animate(CurvedAnimation(parent: _ctrl, curve: JMotion.curve));

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(opacity: _fade, child: widget.child);
  }
}

class JTopGlow extends StatelessWidget {
  const JTopGlow({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final a = isDark ? .14 : .08;

    return IgnorePointer(
      child: RepaintBoundary(
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: const Alignment(0.4, -1),
              radius: 1.1,
              colors: [
                JColor.secondary(isDark).withValues(alpha: a),
                JColor.primary(isDark).withValues(alpha: a * .6),
                JColor.primary(isDark).withValues(alpha: 0),
              ],
              stops: const [0, .45, 1],
            ),
          ),
        ),
      ),
    );
  }
}
