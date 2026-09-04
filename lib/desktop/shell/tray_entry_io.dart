import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;

import 'agent_notifier.dart';
import 'desktop_tray.dart';

Future<void> initDesktopTray() async {
  if (kIsWeb || !Platform.isWindows) return;
  await DesktopTray.instance.init();
  await AgentNotifier.instance.init();
}
