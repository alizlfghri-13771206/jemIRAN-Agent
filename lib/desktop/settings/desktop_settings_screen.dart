import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:jemiran/desktop/theme/desktop_tokens.dart';
import 'package:jemiran/desktop/theme/win_controls.dart';
import 'package:jemiran/desktop/agent/network/agent_environment.dart';
import 'package:jemiran/desktop/agent/audit/audit_dialog.dart';
import 'package:jemiran/desktop/agent/byok/byok_settings_card.dart';
import 'package:jemiran/riverpod/theme_notifier.dart';
import 'package:jemiran/themes/colors.dart';
import 'package:jemiran/themes/jemiran_design.dart';

class DesktopSettingsScreen extends ConsumerWidget {
  const DesktopSettingsScreen({super.key});

  void _showInfo(
    BuildContext context, {
    required String title,
    required IconData icon,
    required String text,
  }) {
    showDialog<void>(
      context: context,
      builder: (_) => _DesktopInfoDialog(title: title, icon: icon, text: text),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final mode = ref.watch(themeProvider);

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: WinSurface.window(isDark),
        body: Column(
          children: [
            _SettingsTopBar(
              isDark: isDark,
              onBack: () => Navigator.maybePop(context),
            ),
            const WinSeam(),
            Expanded(
              child: Stack(
                children: [
                  Positioned.fill(child: JPageGlow(isDark: isDark)),
                  SingleChildScrollView(
                    padding: const EdgeInsets.all(WinSpace.xxl),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 1120),
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            final controls = Column(
                              children: [
                                _ThemeCard(
                                  isDark: isDark,
                                  mode: mode,
                                  onChanged: (value) => ref
                                      .read(themeProvider.notifier)
                                      .setTheme(value),
                                ),
                                const SizedBox(height: WinSpace.lg),
                                _RepositoryStatusCard(isDark: isDark),
                                const SizedBox(height: WinSpace.lg),
                                ByokSettingsCard(isDark: isDark),
                                const SizedBox(height: WinSpace.lg),
                                _DesktopCard(
                                  isDark: isDark,
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      const Text(
                                        'اطلاعات برنامه',
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w900,
                                        ),
                                      ),
                                      const SizedBox(height: WinSpace.md),
                                      _SettingsRow(
                                        isDark: isDark,
                                        icon: Icons.receipt_long_rounded,
                                        title: 'تاریخچه فعالیت',
                                        onTap: () =>
                                            showAuditLogDialog(context),
                                      ),
                                      const SizedBox(height: WinSpace.sm),
                                      _SettingsRow(
                                        isDark: isDark,
                                        icon: Icons.info_outline_rounded,
                                        title:
                                            'درباره جمیران ایجنت نسخه Open Source',
                                        onTap: () => _showInfo(
                                          context,
                                          title:
                                              'درباره جمیران ایجنت نسخه Open Source',
                                          icon: Icons.info_outline_rounded,
                                          text:
                                              'جمیران ایجنت پس از ماه‌ها تلاش ساخته و ارائه شده است. این پروژه با الهام از Claude Code و Hermes تلاش می‌کند تجربه‌ای خوب از کار با یک ایجنت ایرانی برای شما فراهم کند.',
                                        ),
                                      ),
                                      const SizedBox(height: WinSpace.sm),
                                      _SettingsRow(
                                        isDark: isDark,
                                        icon: Icons.code_rounded,
                                        title: 'اطلاعات فنی نسخه Open Source',
                                        onTap: () => _showInfo(
                                          context,
                                          title: 'اطلاعات فنی نسخه Open Source',
                                          icon: Icons.code_rounded,
                                          text:
                                              'جمیران ایجنت با زبان دارت و فریم‌ورک فلاتر طراحی شده است. برای استفاده از آن، کلید API خود را اضافه کنید تا از هستهٔ ایجنت بهره ببرید. سورس پروژه در اختیار شماست تا ایجنت‌های خودتان را بسازید، کارها را سریع‌تر پیش ببرید و در پیشرفت نرم‌افزار و هوش مصنوعی ایران سهیم باشید.',
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            );
                            final intro = _SettingsIntro(isDark: isDark);
                            if (constraints.maxWidth < 840) {
                              return Column(
                                children: [
                                  intro,
                                  const SizedBox(height: WinSpace.lg),
                                  controls,
                                ],
                              );
                            }
                            return Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                SizedBox(width: 300, child: intro),
                                const SizedBox(width: WinSpace.xl),
                                Expanded(child: controls),
                              ],
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RepositoryStatusCard extends StatefulWidget {
  const _RepositoryStatusCard({required this.isDark});

  final bool isDark;

  @override
  State<_RepositoryStatusCard> createState() => _RepositoryStatusCardState();
}

class _RepositoryStatusCardState extends State<_RepositoryStatusCard> {
  Map<String, bool>? _status;
  bool _checking = false;

  Future<void> _check() async {
    if (_checking) return;
    setState(() => _checking = true);
    final status = await AgentEnvironment.repositoryHealth();
    if (!mounted) return;
    setState(() {
      _status = status;
      _checking = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final status = _status;
    final allOk = status != null && status.values.every((value) => value);
    final color = status == null
        ? JSurface.muted(widget.isDark)
        : allOk
        ? Colors.green
        : (widget.isDark ? DarkColors.warning : LightColors.warning);
    const labels = {
      'pub.dev': 'Flutter / Dart',
      'pypi.org': 'Python',
      'registry.npmjs.org': 'Node.js',
      'github.com': 'GitHub',
    };
    return _DesktopCard(
      isDark: widget.isDark,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.public_rounded, size: 19, color: color),
              const SizedBox(width: WinSpace.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'مخازن و ریپازیتوری‌ها',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                        color: JSurface.text(widget.isDark),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      status == null
                          ? 'برای مشاهدهٔ ریپوهای متصل‌شده کلیک کنید.'
                          : allOk
                          ? 'همه مخزن‌ها از مسیر مستقل جمیران در دسترس‌اند.'
                          : 'اتصال برخی مقصدها واقعاً ناموفق بود؛ جزئیات زیر را ببینید.',
                      style: TextStyle(
                        fontSize: 11,
                        color: JSurface.muted(widget.isDark),
                      ),
                    ),
                  ],
                ),
              ),
              FilledButton.icon(
                onPressed: _checking ? null : _check,
                icon: _checking
                    ? const SizedBox(
                        width: 13,
                        height: 13,
                        child: CircularProgressIndicator(strokeWidth: 1.7),
                      )
                    : const Icon(Icons.refresh_rounded, size: 15),
                label: Text(
                  _checking ? 'در حال بررسی' : 'به‌روزرسانی و مشاهده',
                ),
              ),
            ],
          ),
          if (status != null) ...[
            const SizedBox(height: WinSpace.lg),
            Wrap(
              spacing: WinSpace.sm,
              runSpacing: WinSpace.sm,
              children: [
                for (final entry in status.entries)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: WinSpace.md,
                      vertical: 7,
                    ),
                    decoration: BoxDecoration(
                      color: (entry.value ? Colors.green : color).withValues(
                        alpha: widget.isDark ? .14 : .08,
                      ),
                      borderRadius: BorderRadius.circular(WinRadius.control),
                      border: Border.all(
                        color: (entry.value ? Colors.green : color).withValues(
                          alpha: .35,
                        ),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          entry.value
                              ? Icons.check_circle_outline_rounded
                              : Icons.error_outline_rounded,
                          size: 14,
                          color: entry.value ? Colors.green : color,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          labels[entry.key] ?? entry.key,
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            color: JSurface.text(widget.isDark),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _SettingsTopBar extends StatelessWidget {
  const _SettingsTopBar({required this.isDark, required this.onBack});
  final bool isDark;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) => Container(
    height: WinMetrics.topBarHeight,
    color: WinSurface.layer(isDark),
    padding: const EdgeInsets.symmetric(horizontal: WinSpace.md),
    child: Row(
      children: [
        const Expanded(
          child: Text(
            'تنظیمات جمیران ایجنت',
            style: TextStyle(
              fontSize: WinText.title,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        WinIconButton(
          icon: Icons.arrow_forward_rounded,
          tooltip: 'بازگشت',
          onTap: onBack,
        ),
      ],
    ),
  );
}

class _SettingsIntro extends StatelessWidget {
  const _SettingsIntro({required this.isDark});
  final bool isDark;

  static const _supportEmail = 'jemIRAN.app@gmail.com';

  Future<void> _copyEmail(BuildContext context) async {
    await Clipboard.setData(const ClipboardData(text: _supportEmail));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          content: Text(
            'ایمیل پشتیبانی کپی شد.',
            textDirection: TextDirection.rtl,
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  @override
  Widget build(BuildContext context) => _DesktopCard(
    isDark: isDark,
    child: Column(
      children: [
        Container(
          width: 76,
          height: 76,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            gradient: JGradient.brand(isDark),
            borderRadius: BorderRadius.circular(22),
          ),
          child: const Icon(Icons.settings, color: Colors.white, size: 34),
        ),
        const SizedBox(height: WinSpace.lg),
        Text(
          'تنظیمات',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 19,
            fontWeight: FontWeight.w900,
            color: JSurface.text(isDark),
          ),
        ),
        const SizedBox(height: WinSpace.sm),
        Text(
          'توی جمیران ایجنت سعی کردیم از تجربه کاربری لذت کافی رو ببرید ، '
          'ولی اگر به باگی برخوردید حتما با ما در تماس باشید.',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 11.5,
            height: 1.8,
            color: JSurface.muted(isDark),
          ),
        ),
        const SizedBox(height: WinSpace.md),
        Directionality(
          textDirection: TextDirection.ltr,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsetsDirectional.only(start: WinSpace.md),
            decoration: BoxDecoration(
              color: JSurface.page(isDark),
              borderRadius: BorderRadius.circular(WinRadius.control),
              border: Border.all(color: WinSurface.hairline(isDark)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: SelectableText(
                      _supportEmail,
                      textDirection: TextDirection.ltr,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: JSurface.secondary(isDark),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: WinSpace.sm),
                IconButton(
                  tooltip: 'کپی ایمیل',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints.tightFor(
                    width: 40,
                    height: 40,
                  ),
                  onPressed: () => _copyEmail(context),
                  icon: Icon(
                    Icons.content_copy_rounded,
                    size: 17,
                    color: JColor.primary(isDark),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}

class _ThemeCard extends StatelessWidget {
  const _ThemeCard({
    required this.isDark,
    required this.mode,
    required this.onChanged,
  });
  final bool isDark;
  final ThemeMode mode;
  final ValueChanged<ThemeMode> onChanged;

  @override
  Widget build(BuildContext context) => _DesktopCard(
    isDark: isDark,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Container(
              width: 42,
              height: 42,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: JColor.primary(isDark).withValues(alpha: .12),
                borderRadius: BorderRadius.circular(WinRadius.card),
              ),
              child: Icon(
                Icons.palette_outlined,
                color: JColor.primary(isDark),
              ),
            ),
            const SizedBox(width: WinSpace.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'ظاهر برنامه',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
                  ),
                  Text(
                    'تم دلخواهتون رو انتخاب کنید',
                    style: TextStyle(
                      fontSize: 11.5,
                      color: JSurface.muted(isDark),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: WinSpace.xl),
        Row(
          children: [
            Expanded(
              child: _ThemeOption(
                isDark: isDark,
                selected: mode == ThemeMode.light,
                icon: Icons.light_mode_outlined,
                label: 'روشن',
                onTap: () => onChanged(ThemeMode.light),
              ),
            ),
            const SizedBox(width: WinSpace.md),
            Expanded(
              child: _ThemeOption(
                isDark: isDark,
                selected: mode == ThemeMode.dark,
                icon: Icons.dark_mode_outlined,
                label: 'تیره',
                onTap: () => onChanged(ThemeMode.dark),
              ),
            ),
          ],
        ),
      ],
    ),
  );
}

class _ThemeOption extends StatelessWidget {
  const _ThemeOption({
    required this.isDark,
    required this.selected,
    required this.icon,
    required this.label,
    required this.onTap,
  });
  final bool isDark;
  final bool selected;
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => WinHoverable(
    onTap: onTap,
    selected: selected,
    radius: WinRadius.card,
    padding: const EdgeInsets.symmetric(vertical: WinSpace.lg),
    baseColor: WinSurface.window(isDark),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          selected ? Icons.check_circle_rounded : icon,
          size: 19,
          color: selected ? JColor.primary(isDark) : JSurface.muted(isDark),
        ),
        const SizedBox(width: WinSpace.sm),
        Text(
          label,
          style: TextStyle(
            fontWeight: FontWeight.w800,
            color: selected ? JColor.primary(isDark) : JSurface.text(isDark),
          ),
        ),
      ],
    ),
  );
}

class _SettingsRow extends StatelessWidget {
  const _SettingsRow({
    required this.isDark,
    required this.icon,
    required this.title,
    required this.onTap,
  });
  final bool isDark;
  final IconData icon;
  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => WinHoverable(
    onTap: onTap,
    radius: WinRadius.card,
    padding: const EdgeInsets.all(WinSpace.md),
    baseColor: WinSurface.window(isDark),
    child: Row(
      children: [
        Icon(icon, size: 21, color: JColor.primary(isDark)),
        const SizedBox(width: WinSpace.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
            ],
          ),
        ),
        Icon(
          Icons.chevron_right_rounded,
          size: 18,
          color: JSurface.muted(isDark),
        ),
      ],
    ),
  );
}

class _DesktopInfoDialog extends StatelessWidget {
  const _DesktopInfoDialog({
    required this.title,
    required this.icon,
    required this.text,
  });
  final String title;
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: AlertDialog(
        icon: Icon(icon, color: JColor.primary(isDark)),
        title: Text(title),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Text(text, style: const TextStyle(height: 1.9)),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('متوجه شدم'),
          ),
        ],
      ),
    );
  }
}

class _DesktopCard extends StatelessWidget {
  const _DesktopCard({required this.isDark, required this.child});
  final bool isDark;
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(WinSpace.xl),
    decoration: BoxDecoration(
      color: WinSurface.card(isDark),
      borderRadius: BorderRadius.circular(WinRadius.layer),
      border: Border.all(color: WinSurface.hairline(isDark)),
      boxShadow: AppShadows.subtle(isDark),
    ),
    child: child,
  );
}
