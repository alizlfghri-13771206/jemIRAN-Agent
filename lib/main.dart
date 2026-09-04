import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jemiran/desktop/app_home.dart';
import 'package:jemiran/desktop/app_release.dart';
import 'package:jemiran/desktop/desktop_entry.dart';
import 'package:jemiran/desktop/shell/tray_entry.dart';
import 'package:jemiran/riverpod/theme.dart';
import 'package:jemiran/riverpod/theme_notifier.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppRelease.initialize();

  await initDesktopTray();

  final prefs = await SharedPreferences.getInstance();
  final initialTheme = ThemeNotifier.readFrom(prefs);

  runApp(
    ProviderScope(
      overrides: [
        themeProvider.overrideWith((ref) => ThemeNotifier(initialTheme)),
      ],
      child: const JemiranAgentApp(),
    ),
  );
}

class JemiranAgentApp extends ConsumerWidget {
  const JemiranAgentApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(themeProvider);
    return MaterialApp(
      title: 'Jemiran Agent',
      debugShowCheckedModeBanner: false,
      themeMode: mode,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      builder: (context, child) => wrapDesktopChrome(child),
      home: appChatHome(),
    );
  }
}
