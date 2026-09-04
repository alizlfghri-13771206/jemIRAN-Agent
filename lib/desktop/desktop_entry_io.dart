import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:jemiran/desktop/shell/desktop_shell.dart';
import 'package:jemiran/desktop/shell/keyboard_guard.dart';
import 'package:jemiran/desktop/theme/desktop_tokens.dart';

bool get isWindowsDesktop => !kIsWeb && Platform.isWindows;

Widget buildDesktopShell({String? initialModel}) =>
    DesktopShell(initialModel: initialModel);

Widget buildPlatformOnboarding({required Widget fallback}) => fallback;

const kDesktopFontFamily = WinFont.family;

Widget wrapDesktopChrome(Widget? child) {
  final content = child ?? const SizedBox.shrink();
  if (!isWindowsDesktop) return content;

  WindowsKeyboardGuard.install();

  return _DesktopFont(child: content);
}

class _DesktopFont extends StatelessWidget {
  const _DesktopFont({required this.child});

  final Widget child;

  static TextStyle? _f(TextStyle? style) =>
      style?.copyWith(fontFamily: kDesktopFontFamily);

  @override
  Widget build(BuildContext context) {
    final base = Theme.of(context);
    return Theme(
      data: base.copyWith(
        textTheme: base.textTheme.apply(fontFamily: kDesktopFontFamily),
        primaryTextTheme: base.primaryTextTheme.apply(
          fontFamily: kDesktopFontFamily,
        ),
        appBarTheme: base.appBarTheme.copyWith(
          titleTextStyle: _f(base.appBarTheme.titleTextStyle),
          toolbarTextStyle: _f(base.appBarTheme.toolbarTextStyle),
        ),
        snackBarTheme: base.snackBarTheme.copyWith(
          contentTextStyle: _f(base.snackBarTheme.contentTextStyle),
        ),
        inputDecorationTheme: base.inputDecorationTheme.copyWith(
          hintStyle: _f(base.inputDecorationTheme.hintStyle),
          labelStyle: _f(base.inputDecorationTheme.labelStyle),
          errorStyle: _f(base.inputDecorationTheme.errorStyle),
        ),
        dialogTheme: base.dialogTheme.copyWith(
          titleTextStyle: _f(base.dialogTheme.titleTextStyle),
          contentTextStyle: _f(base.dialogTheme.contentTextStyle),
        ),
        tooltipTheme: base.tooltipTheme.copyWith(
          textStyle: _f(base.tooltipTheme.textStyle),
        ),
      ),
      child: DefaultTextStyle.merge(
        style: const TextStyle(fontFamily: kDesktopFontFamily),
        child: child,
      ),
    );
  }
}
