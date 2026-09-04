import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jemiran/desktop/theme/desktop_tokens.dart';
import 'package:jemiran/riverpod/user_notifier.dart';
import 'package:jemiran/themes/jemiran_design.dart';

class AgentHome extends ConsumerWidget {
  const AgentHome({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final username = ref.watch(userProvider).username.trim();
    final hasServerName = username.isNotEmpty && username != 'کاربر';

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(
            horizontal: WinSpace.gutter,
            vertical: WinSpace.xxl,
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 880),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(
                  hasServerName
                      ? 'سلام $username، به جمیران ایجنت خوش اومدی'
                      : 'سلام، به جمیران ایجنت خوش اومدی',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    height: 1.6,
                    color: JSurface.text(isDark),
                  ),
                ),
                const SizedBox(height: WinSpace.sm),
                Text(
                  'تمامی اطلاعات شما از جمله پروژه‌ها، تاریخچه فعالیت‌ها '
                  'همچنین کدها و فایل‌های وابسته به هر پروژه به‌صورت کاملاً '
                  'لوکال در دستگاه شما ذخیره می‌شوند.\n'
                  'پس نگران نشت پروژه‌های خود نباشید.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: WinText.body,
                    height: 1.9,
                    color: JSurface.muted(isDark),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
