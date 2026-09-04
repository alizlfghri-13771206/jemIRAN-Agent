import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jemiran/desktop/models/desktop_models_notifier.dart';
import 'package:jemiran/desktop/routing/desktop_model_route.dart';
import 'package:jemiran/desktop/theme/desktop_tokens.dart';
import 'package:jemiran/desktop/theme/win_controls.dart';
import 'package:jemiran/themes/colors.dart';
import 'package:jemiran/themes/jemiran_design.dart';

import 'byok_adapter.dart';
import 'byok_provider.dart';
import 'secret_vault.dart';

class ByokSettingsCard extends ConsumerStatefulWidget {
  const ByokSettingsCard({super.key, required this.isDark});

  final bool isDark;

  @override
  ConsumerState<ByokSettingsCard> createState() => _ByokSettingsCardState();
}

class _ByokSettingsCardState extends ConsumerState<ByokSettingsCard> {
  Future<void> _syncPicker() async {
    final models = ref.read(desktopModelsProvider.notifier);
    models.refreshByokModels();
    final route = ref.read(desktopModelRouteProvider.notifier);
    await route.ready;
    await route.reconcile(models.usableModelKeys, allowEmpty: true);
  }

  @override
  void initState() {
    super.initState();
    ByokStore.load();
  }

  Future<void> _edit([ByokProvider? existing]) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _ByokProviderDialog(existing: existing),
    );
    if (saved == true && mounted) {
      await _syncPicker();
      if (!mounted) return;
      setState(() {});
    }
  }

  Future<void> _delete(ByokProvider provider) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('حذف ارائه‌دهنده'),
          content: Text(
            '«${provider.label}» و کلیدش کاملاً پاک می‌شوند. این کار برگشت‌پذیر نیست.',
            style: const TextStyle(height: 1.9),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('انصراف'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('حذف'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true) return;
    ByokStore.remove(provider.id);
    if (!mounted) return;
    await _syncPicker();
    if (!mounted) return;
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;
    final providers = ByokStore.providers;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(WinSpace.xl),
      decoration: BoxDecoration(
        color: WinSurface.card(isDark),
        borderRadius: BorderRadius.circular(WinRadius.layer),
        border: Border.all(color: WinSurface.hairline(isDark)),
        boxShadow: AppShadows.subtle(isDark),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'ارائه‌دهنده‌های من',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
                ),
              ),
              if (SecretVault.isSupported)
                WinHoverable(
                  onTap: _edit,
                  radius: WinRadius.control,
                  padding: const EdgeInsets.symmetric(
                    horizontal: WinSpace.md,
                    vertical: WinSpace.sm,
                  ),
                  baseColor: WinSurface.window(isDark),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.add_rounded,
                        size: 18,
                        color: JColor.primary(isDark),
                      ),
                      const SizedBox(width: WinSpace.xs),
                      const Text(
                        'افزودن',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: WinSpace.sm),
          Text(
            'درخواست‌ها مستقیم از همین دستگاه به ارائه‌دهنده‌ای می‌روند که '
            'خودت انتخاب کرده‌ای. صورتحساب هم مستقیماً بین تو و همان '
            'ارائه‌دهنده است، و کلید رمزگذاری‌شده روی همین دستگاه می‌ماند.',
            style: TextStyle(
              height: 1.9,
              fontSize: 12.5,
              color: JSurface.muted(isDark),
            ),
          ),
          if (!SecretVault.isSupported) ...[
            const SizedBox(height: WinSpace.md),
            _Notice(
              isDark: isDark,
              icon: Icons.lock_outline_rounded,
              text: 'ذخیرهٔ امن کلید فقط روی ویندوز در دسترس است.',
            ),
          ] else if (providers.isEmpty) ...[
            const SizedBox(height: WinSpace.md),
            _Notice(
              isDark: isDark,
              icon: Icons.key_off_rounded,
              text: 'هنوز ارائه‌دهنده‌ای اضافه نکرده‌ای.',
            ),
          ] else
            for (final provider in providers) ...[
              const SizedBox(height: WinSpace.sm),
              _ProviderRow(
                isDark: isDark,
                provider: provider,
                onEdit: () => _edit(provider),
                onDelete: () => _delete(provider),
                onToggle: (value) async {
                  ByokStore.save(provider.copyWith(enabled: value));
                  await _syncPicker();
                  if (!mounted) return;
                  setState(() {});
                },
              ),
            ],
        ],
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.isDark, required this.icon, required this.text});

  final bool isDark;
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Icon(icon, size: 18, color: JSurface.muted(isDark)),
      const SizedBox(width: WinSpace.sm),
      Expanded(
        child: Text(
          text,
          style: TextStyle(fontSize: 12.5, color: JSurface.muted(isDark)),
        ),
      ),
    ],
  );
}

class _ProviderRow extends StatelessWidget {
  const _ProviderRow({
    required this.isDark,
    required this.provider,
    required this.onEdit,
    required this.onDelete,
    required this.onToggle,
  });

  final bool isDark;
  final ByokProvider provider;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final ValueChanged<bool> onToggle;

  @override
  Widget build(BuildContext context) {
    final missingSecret = !provider.hasSecret;

    return Container(
      padding: const EdgeInsets.all(WinSpace.md),
      decoration: BoxDecoration(
        color: WinSurface.window(isDark),
        borderRadius: BorderRadius.circular(WinRadius.card),
        border: Border.all(color: WinSurface.hairline(isDark)),
      ),
      child: Row(
        children: [
          Icon(
            missingSecret ? Icons.key_off_rounded : Icons.vpn_key_rounded,
            size: 20,
            color: missingSecret
                ? JSurface.muted(isDark)
                : JColor.primary(isDark),
          ),
          const SizedBox(width: WinSpace.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        provider.label.isEmpty
                            ? provider.kind.label
                            : provider.label,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                    const SizedBox(width: WinSpace.sm),
                    _DirectBadge(isDark: isDark),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  missingSecret
                      ? '${provider.kind.label} · ${provider.modelId} · کلید ندارد'
                      : '${provider.kind.label} · ${provider.modelId}',
                  style: TextStyle(
                    fontSize: 12,
                    color: missingSecret
                        ? _danger(isDark)
                        : JSurface.muted(isDark),
                  ),
                ),
              ],
            ),
          ),
          Switch(value: provider.enabled, onChanged: onToggle),
          IconButton(
            tooltip: 'ویرایش',
            onPressed: onEdit,
            icon: const Icon(Icons.edit_outlined, size: 18),
          ),
          IconButton(
            tooltip: 'حذف',
            onPressed: onDelete,
            icon: const Icon(Icons.delete_outline_rounded, size: 18),
          ),
        ],
      ),
    );
  }
}

class _DirectBadge extends StatelessWidget {
  const _DirectBadge({required this.isDark});

  final bool isDark;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
    decoration: BoxDecoration(
      color: JColor.primary(isDark).withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(999),
    ),
    child: Text(
      'مستقیم',
      style: TextStyle(
        fontSize: 10.5,
        fontWeight: FontWeight.w900,
        color: JColor.primary(isDark),
      ),
    ),
  );
}

class _ByokProviderDialog extends StatefulWidget {
  const _ByokProviderDialog({this.existing});

  final ByokProvider? existing;

  @override
  State<_ByokProviderDialog> createState() => _ByokProviderDialogState();
}

class _ByokProviderDialogState extends State<_ByokProviderDialog> {
  late ByokProviderKind _kind =
      widget.existing?.kind ?? ByokProviderKind.anthropic;
  late final _label = TextEditingController(text: widget.existing?.label ?? '');
  late final _modelId = TextEditingController(
    text: widget.existing?.modelId ?? '',
  );
  late final _baseUrl = TextEditingController(
    text: widget.existing?.baseUrl ?? '',
  );
  final _secret = TextEditingController();

  String? _error;
  String? _testMessage;
  bool _testOk = false;
  bool _busy = false;

  @override
  void dispose() {
    _label.dispose();
    _modelId.dispose();
    _baseUrl.dispose();
    _secret.dispose();
    super.dispose();
  }

  late final String _newId = 'byok_${DateTime.now().microsecondsSinceEpoch}';

  ByokProvider _draft() => ByokProvider(
    id: widget.existing?.id ?? _newId,
    kind: _kind,
    label: _label.text.trim().isEmpty ? _kind.label : _label.text.trim(),
    modelId: _modelId.text.trim(),
    baseUrl: _kind == ByokProviderKind.custom && _baseUrl.text.trim().isNotEmpty
        ? _baseUrl.text.trim()
        : null,
    headers: widget.existing?.headers ?? const {},
    enabled: widget.existing?.enabled ?? true,
    contextTokens:
        widget.existing?.contextTokens ?? ByokProvider.defaultContextTokens,
    maxOutputTokens:
        widget.existing?.maxOutputTokens ?? ByokProvider.defaultOutputTokens,
  );

  String? _effectiveSecret() {
    final typed = _secret.text.trim();
    if (typed.isNotEmpty) return typed;
    final existing = widget.existing;
    return existing == null ? null : SecretVault.read(existing.secretRef);
  }

  Future<void> _test() async {
    final secret = _effectiveSecret();
    if (secret == null || secret.isEmpty) {
      setState(() {
        _testOk = false;
        _testMessage = 'اول کلید را وارد کن.';
      });
      return;
    }
    if (_modelId.text.trim().isEmpty) {
      setState(() {
        _testOk = false;
        _testMessage = 'شناسهٔ مدل لازم است.';
      });
      return;
    }
    setState(() {
      _busy = true;
      _testMessage = null;
    });
    final result = await testByokProvider(_draft(), secret: secret);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _testOk = result.ok;
      _testMessage = result.message;
    });
  }

  void _save() {
    final draft = _draft();
    if (draft.modelId.isEmpty) {
      setState(() => _error = 'شناسهٔ مدل لازم است.');
      return;
    }
    if (_kind == ByokProviderKind.custom &&
        (_baseUrl.text.trim().isEmpty ||
            !ByokProvider.isAllowedBaseUrl(_baseUrl.text.trim()))) {
      setState(
        () => _error =
            'آدرس باید HTTPS معتبر باشد؛ HTTP فقط برای localhost مجاز است.',
      );
      return;
    }
    final typed = _secret.text.trim();
    if (typed.isEmpty && !(widget.existing?.hasSecret ?? false)) {
      setState(() => _error = 'کلید لازم است.');
      return;
    }
    try {
      ByokStore.save(draft, secret: typed.isEmpty ? null : typed);
    } catch (error) {
      setState(() => _error = error.toString());
      return;
    }
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: AlertDialog(
        title: Text(
          widget.existing == null ? 'افزودن ارائه‌دهنده' : 'ویرایش ارائه‌دهنده',
        ),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                DropdownButtonFormField<ByokProviderKind>(
                  initialValue: _kind,
                  decoration: const InputDecoration(labelText: 'ارائه‌دهنده'),
                  items: [
                    for (final kind in ByokProviderKind.values)
                      DropdownMenuItem(value: kind, child: Text(kind.label)),
                  ],
                  onChanged: widget.existing != null
                      ? null
                      : (value) => setState(() {
                          _kind = value ?? _kind;
                          if (_kind != ByokProviderKind.custom) {
                            _baseUrl.clear();
                          }
                          _testMessage = null;
                        }),
                ),
                const SizedBox(height: WinSpace.md),
                TextField(
                  controller: _label,
                  decoration: const InputDecoration(
                    labelText: 'نام دلخواه (اختیاری)',
                  ),
                ),
                const SizedBox(height: WinSpace.md),
                TextField(
                  controller: _modelId,
                  decoration: const InputDecoration(
                    labelText: 'شناسهٔ مدل',
                    hintText: 'claude-sonnet-5',
                  ),
                ),
                if (_kind == ByokProviderKind.custom) ...[
                  const SizedBox(height: WinSpace.md),
                  TextField(
                    controller: _baseUrl,
                    decoration: const InputDecoration(
                      labelText: 'آدرس پایه',
                      hintText: 'http://127.0.0.1:11434/v1',
                    ),
                  ),
                ],
                const SizedBox(height: WinSpace.md),
                TextField(
                  controller: _secret,
                  obscureText: true,
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration: InputDecoration(
                    labelText: 'کلید API',
                    hintText: (widget.existing?.hasSecret ?? false)
                        ? 'برای نگه‌داشتن کلید فعلی، خالی بگذار'
                        : null,
                  ),
                ),
                const SizedBox(height: WinSpace.sm),
                Text(
                  'کلید با رمزگذاری خود ویندوز روی همین دستگاه ذخیره '
                  'می‌شود و جایی جز خودِ ارائه‌دهنده نمی‌رود.',
                  style: TextStyle(
                    fontSize: 11.5,
                    height: 1.8,
                    color: JSurface.muted(isDark),
                  ),
                ),
                if (_testMessage != null) ...[
                  const SizedBox(height: WinSpace.md),
                  Row(
                    children: [
                      Icon(
                        _testOk
                            ? Icons.check_circle_outline_rounded
                            : Icons.error_outline_rounded,
                        size: 18,
                        color: _testOk ? _success(isDark) : _danger(isDark),
                      ),
                      const SizedBox(width: WinSpace.sm),
                      Expanded(
                        child: Text(
                          _testMessage!,
                          style: TextStyle(
                            fontSize: 12.5,
                            color: _testOk ? _success(isDark) : _danger(isDark),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
                if (_error != null) ...[
                  const SizedBox(height: WinSpace.sm),
                  Text(
                    _error!,
                    style: TextStyle(fontSize: 12.5, color: _danger(isDark)),
                  ),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('انصراف'),
          ),
          TextButton(
            onPressed: _busy ? null : _test,
            child: Text(_busy ? 'در حال بررسی…' : 'امتحان کلید'),
          ),
          FilledButton(
            onPressed: _busy ? null : _save,
            child: const Text('ذخیره'),
          ),
        ],
      ),
    );
  }
}

Color _danger(bool isDark) => isDark ? DarkColors.danger : LightColors.danger;
Color _success(bool isDark) =>
    isDark ? DarkColors.success : LightColors.success;
