import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:jemiran/themes/colors.dart';

class JNetworkImage extends StatelessWidget {
  const JNetworkImage({
    super.key,
    required this.url,
    this.fit = BoxFit.cover,
    this.width,
    this.height,
    this.accent,
    this.cachePx,
    this.borderRadius,
  });

  final String url;
  final BoxFit fit;
  final double? width;
  final double? height;

  final Color? accent;

  final int? cachePx;

  final BorderRadius? borderRadius;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final tint = accent ?? (isDark ? DarkColors.primary : LightColors.primary);
    final placeholderBg = isDark
        ? DarkColors.surfaceElevated
        : LightColors.surfaceHigh;

    final image = CachedNetworkImage(
      imageUrl: url,
      fit: fit,
      width: width,
      height: height,
      memCacheWidth: cachePx,
      fadeInDuration: const Duration(milliseconds: 200),
      progressIndicatorBuilder: (context, _, progress) => _Frame(
        background: placeholderBg,
        borderRadius: borderRadius,
        child: CircularProgressIndicator(
          value: progress.progress,
          strokeWidth: 2,
          color: tint,
        ),
      ),
      errorWidget: (context, _, _) => _Frame(
        background: placeholderBg,
        borderRadius: borderRadius,
        child: Icon(
          Icons.broken_image_outlined,
          size: 26,
          color: isDark ? DarkColors.tertiaryText : LightColors.tertiaryText,
        ),
      ),
    );

    if (borderRadius == null) return image;
    return ClipRRect(borderRadius: borderRadius!, child: image);
  }
}

class _Frame extends StatelessWidget {
  const _Frame({
    required this.background,
    required this.child,
    this.borderRadius,
  });

  final Color background;
  final Widget child;
  final BorderRadius? borderRadius;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 1,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: background,
          borderRadius: borderRadius ?? BorderRadius.circular(AppRadius.md),
        ),
        child: Center(child: child),
      ),
    );
  }
}
