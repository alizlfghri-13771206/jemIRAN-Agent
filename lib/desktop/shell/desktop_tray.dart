import 'dart:io';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/painting.dart' show Size;
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

import '../agent/core/task_store.dart';
import '../agent/core/work_session_store.dart';
import 'desktop_runtime_control.dart';

class DesktopTray with TrayListener, WindowListener {
  DesktopTray._();

  static final DesktopTray instance = DesktopTray._();

  static const _iconPath = 'assets/tray/tray_icon.ico';

  bool _ready = false;

  Future<void> init() async {
    if (_ready || !Platform.isWindows) return;

    try {
      await windowManager.ensureInitialized();

      await windowManager.setPreventClose(true);
      windowManager.addListener(this);

      try {
        await windowManager.setTitleBarStyle(
          TitleBarStyle.hidden,
          windowButtonVisibility: false,
        );
        await windowManager.setMinimumSize(const Size(720, 520));
      } catch (e) {
        debugPrint('نوار عنوان سفارشی فعال نشد: $e');
      }

      await trayManager.setIcon(_iconPath);
      await trayManager.setToolTip('jemIRAN');
      await trayManager.setContextMenu(
        Menu(
          items: [
            MenuItem(key: 'show', label: 'نمایش جمیران ایجنت'),
            MenuItem.separator(),
            MenuItem(key: 'exit', label: 'خروج'),
          ],
        ),
      );
      trayManager.addListener(this);

      _ready = true;
    } catch (e) {
      debugPrint('[tray] راه‌اندازی سینی ممکن نشد: $e');
    }
  }

  Future<void> showWindow() async {
    try {
      await windowManager.show();
      await windowManager.focus();
    } catch (_) {}
  }

  @override
  void onWindowClose() {
    windowManager.hide();
  }

  @override
  void onTrayIconMouseDown() => showWindow();

  @override
  void onTrayIconRightMouseDown() => trayManager.popUpContextMenu();

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    switch (menuItem.key) {
      case 'show':
        showWindow();
      case 'exit':
        _quit();
    }
  }

  Future<void> _quit() async {
    await DesktopRuntimeControl.shutdownAll();
    await AgentTaskStore.instance.flush();
    await WorkSessionStore.instance.flush();
    try {
      await trayManager.destroy();
    } catch (_) {}
    await windowManager.setPreventClose(false);
    await windowManager.destroy();
  }

  void dispose() {
    if (!_ready) return;
    windowManager.removeListener(this);
    trayManager.removeListener(this);
    _ready = false;
  }
}
