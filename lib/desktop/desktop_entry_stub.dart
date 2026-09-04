import 'package:flutter/widgets.dart';

bool get isWindowsDesktop => false;

Widget buildDesktopShell({String? initialModel}) => const SizedBox.shrink();

Widget buildPlatformOnboarding({required Widget fallback}) => fallback;

const kDesktopFontFamily = 'vazir';

Widget wrapDesktopChrome(Widget? child) => child ?? const SizedBox.shrink();
