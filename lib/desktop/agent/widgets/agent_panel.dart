import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jemiran/desktop/agent/agent_workspace.dart';
import 'package:jemiran/desktop/agent/memory/agent_memory.dart';
import 'package:jemiran/desktop/agent/policy/agent_policy.dart';
import 'package:jemiran/desktop/agent/skills/agent_skill.dart';
import 'package:jemiran/desktop/agent/tools/agent_tool.dart';
import 'package:jemiran/desktop/agent/tools/tool_registry.dart';
import 'package:jemiran/desktop/agent/widgets/tool_call_card.dart';
import 'package:jemiran/desktop/theme/desktop_tokens.dart';
import 'package:jemiran/desktop/theme/win_controls.dart';
import 'package:jemiran/themes/colors.dart';
import 'package:jemiran/themes/jemiran_design.dart';

Future<void> showAgentPanel(BuildContext context) =>
    showDialog(context: context, builder: (_) => const _AgentPanel());

class _AgentPanel extends ConsumerStatefulWidget {
  const _AgentPanel();

  @override
  ConsumerState<_AgentPanel> createState() => _AgentPanelState();
}

class _AgentPanelState extends ConsumerState<_AgentPanel> {
  bool _picking = false;
  final _registry = ToolRegistry.windows();

  Future<void> _pick({required bool directory}) async {
    if (_picking) return;
    setState(() => _picking = true);
    try {
      if (directory) {
        final dir = await FilePicker.platform.getDirectoryPath(
          dialogTitle: 'پوشه‌ای که دستیار اجازهٔ دسترسی دارد',
        );
        if (dir == null || !mounted) return;
        await ref.read(agentWorkspaceProvider.notifier).pick(dir);
      } else {
        final result = await FilePicker.platform.pickFiles(
          dialogTitle: 'فایلی که دستیار اجازهٔ دسترسی دارد',
        );
        final path = result?.files.single.path;
        if (path == null || !mounted) return;
        await ref.read(agentWorkspaceProvider.notifier).pickFile(path);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('انتخاب ممکن نشد: $e')));
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final policy = ref.watch(agentPolicyProvider);
    ref.watch(agentWorkspaceProvider);
    ref.watch(skillsProvider);
    ref.watch(memoryProvider);
    final activeSkills = ref.watch(activeSkillsProvider);
    final resources = AgentWorkspace.resources;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Dialog(
        backgroundColor: WinSurface.card(isDark),
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(WinRadius.layer),
          side: BorderSide(color: WinSurface.hairline(isDark)),
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680, maxHeight: 700),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              _header(isDark),
              const WinSeam(),
              Flexible(
                child: WinScrollbar(
                  child: ListView(
                    padding: const EdgeInsets.all(WinSpace.xl),
                    children: [
                      const SizedBox(height: WinSpace.xl),
                      _modeSection(isDark, policy),
                      const SizedBox(height: WinSpace.xl),
                      _skillsSection(isDark, activeSkills),
                      const SizedBox(height: WinSpace.xl),
                      _memorySection(isDark),
                      const SizedBox(height: WinSpace.xl),
                      _resourcesSection(isDark, resources),
                      const SizedBox(height: WinSpace.xl),
                      _grantsSection(isDark, policy),
                      const SizedBox(height: WinSpace.xl),
                      _toolsSection(isDark),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header(bool isDark) => Padding(
    padding: const EdgeInsets.fromLTRB(
      WinSpace.xl,
      WinSpace.lg,
      WinSpace.md,
      WinSpace.lg,
    ),
    child: Row(
      children: [
        Icon(Icons.hub_outlined, size: 19, color: JColor.primary(isDark)),
        const SizedBox(width: WinSpace.md),
        Expanded(
          child: Text(
            'مرکز کنترل جمیران ایجنت',
            style: TextStyle(
              fontSize: WinText.title,
              fontWeight: FontWeight.w800,
              color: JSurface.text(isDark),
            ),
          ),
        ),
        WinIconButton(
          icon: Icons.close_rounded,
          tooltip: 'بستن',
          onTap: () => Navigator.of(context).pop(),
        ),
      ],
    ),
  );

  Widget _sectionLabel(String text, bool isDark) => Padding(
    padding: const EdgeInsets.only(bottom: WinSpace.sm),
    child: Text(
      text,
      style: TextStyle(
        fontSize: WinText.sectionLabel,
        fontWeight: FontWeight.w800,
        letterSpacing: .3,
        color: JSurface.muted(isDark),
      ),
    ),
  );

  Widget _modeSection(bool isDark, AgentPolicyState policy) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _sectionLabel('حالت و اختیار ایجنت', isDark),
      Row(
        children: [
          Expanded(
            child: _modeCard(
              isDark: isDark,
              selected: policy.mode == AgentMode.manual,
              icon: Icons.pan_tool_outlined,
              title: 'دستی',
              body: 'قبل از هر تغییر اجازه می‌گیرد.',
              onTap: () => ref
                  .read(agentPolicyProvider.notifier)
                  .setMode(AgentMode.manual),
            ),
          ),
          const SizedBox(width: WinSpace.sm),
          Expanded(
            child: _modeCard(
              isDark: isDark,
              selected: policy.mode == AgentMode.autonomous,
              icon: Icons.auto_mode_rounded,
              title: 'نیمه‌خودکار',
              body:
                  'خودش تا پایان کار پیش می‌رود. حذف، ارسال فرم و نصب '
                  'ابزار و اجرای Terminal همچنان تأیید می‌خواهد.',
              onTap: () => ref
                  .read(agentPolicyProvider.notifier)
                  .setMode(AgentMode.autonomous),
            ),
          ),
        ],
      ),
      const SizedBox(height: WinSpace.sm),
      _modeCard(
        isDark: isDark,
        selected: policy.mode == AgentMode.unattended,
        icon: Icons.rocket_launch_outlined,
        title: 'تمام‌خودکار',
        body:
            'همهٔ عملیات — نصب، حذف، افزودن و اجرای فرمان — بدون پرسش '
            'انجام می‌شوند. مرز پوشه‌های مجاز همچنان برقرار است.',
        onTap: () => ref
            .read(agentPolicyProvider.notifier)
            .setMode(AgentMode.unattended),
      ),
      const SizedBox(height: WinSpace.sm),
      Row(
        children: [
          Expanded(
            child: Text(
              'خواندن بدون پرسیدن انجام شود',
              style: TextStyle(fontSize: 12, color: JSurface.secondary(isDark)),
            ),
          ),
          Switch(
            value: policy.autoApproveReads,
            onChanged: (v) =>
                ref.read(agentPolicyProvider.notifier).setAutoApproveReads(v),
          ),
        ],
      ),
    ],
  );

  Widget _modeCard({
    required bool isDark,
    required bool selected,
    required IconData icon,
    required String title,
    required String body,
    required VoidCallback onTap,
  }) {
    final accent = JColor.primary(isDark);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: selected
            ? accent.withValues(alpha: isDark ? .16 : .09)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(WinRadius.card),
        border: Border.all(
          color: selected ? accent : WinSurface.hairline(isDark),
        ),
      ),
      child: WinHoverable(
        onTap: onTap,
        radius: WinRadius.card,
        padding: const EdgeInsets.all(WinSpace.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  icon,
                  size: 15,
                  color: selected ? accent : JSurface.muted(isDark),
                ),
                const SizedBox(width: WinSpace.sm),
                Text(
                  title,
                  style: TextStyle(
                    fontSize: WinText.bodySm,
                    fontWeight: FontWeight.w800,
                    color: selected ? accent : JSurface.text(isDark),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 5),
            Text(
              body,
              style: TextStyle(
                fontSize: 11,
                height: 1.6,
                color: JSurface.muted(isDark),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _skillsSection(bool isDark, Set<String> active) {
    final skills = SkillStore.instance.all;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionLabel('مهارت‌ها', isDark),
        if (skills.isEmpty)
          Text(
            'ایجنت هنوز مهارت ماندگاری ثبت نکرده است.',
            style: TextStyle(fontSize: 12, color: JSurface.muted(isDark)),
          )
        else
          for (final skill in skills)
            Container(
              margin: const EdgeInsets.only(bottom: WinSpace.sm),
              padding: const EdgeInsets.all(WinSpace.md),
              decoration: BoxDecoration(
                color: WinSurface.window(isDark),
                borderRadius: BorderRadius.circular(WinRadius.card),
                border: Border.all(color: WinSurface.hairline(isDark)),
              ),
              child: Row(
                children: [
                  Checkbox(
                    value: active.contains(skill.id),
                    onChanged: (_) => ref
                        .read(activeSkillsProvider.notifier)
                        .toggle(skill.id),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          skill.name,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: JSurface.text(isDark),
                          ),
                        ),
                        if (skill.purpose.isNotEmpty)
                          Text(
                            skill.purpose,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 10.5,
                              color: JSurface.muted(isDark),
                            ),
                          ),
                      ],
                    ),
                  ),
                  WinIconButton(
                    icon: Icons.delete_outline_rounded,
                    tooltip: 'حذف مهارت',
                    onTap: () async {
                      await ref.read(skillsProvider.notifier).delete(skill.id);
                      ref
                          .read(activeSkillsProvider.notifier)
                          .set({...active}..remove(skill.id));
                    },
                  ),
                ],
              ),
            ),
      ],
    );
  }

  Widget _memorySection(bool isDark) {
    final notes = MemoryStore.instance.all;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionLabel('حافظه', isDark),
        if (notes.isEmpty)
          Text(
            'چیزی در حافظهٔ ماندگار نیست.',
            style: TextStyle(fontSize: 12, color: JSurface.muted(isDark)),
          )
        else
          for (final note in notes.take(20))
            Container(
              margin: const EdgeInsets.only(bottom: WinSpace.sm),
              padding: const EdgeInsets.all(WinSpace.md),
              decoration: BoxDecoration(
                color: WinSurface.window(isDark),
                borderRadius: BorderRadius.circular(WinRadius.card),
                border: Border.all(color: WinSurface.hairline(isDark)),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: JColor.primary(isDark).withValues(alpha: .12),
                      borderRadius: BorderRadius.circular(WinRadius.control),
                    ),
                    child: Text(
                      note.scope.label,
                      style: TextStyle(
                        fontSize: 9.5,
                        color: JColor.primary(isDark),
                      ),
                    ),
                  ),
                  const SizedBox(width: WinSpace.sm),
                  Expanded(
                    child: Text(
                      note.text,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        color: JSurface.text(isDark),
                      ),
                    ),
                  ),
                  WinIconButton(
                    icon: Icons.delete_outline_rounded,
                    tooltip: 'فراموش کردن',
                    onTap: () =>
                        ref.read(memoryProvider.notifier).forget(note.id),
                  ),
                ],
              ),
            ),
      ],
    );
  }

  Widget _resourcesSection(bool isDark, List<AgentResource> resources) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: _sectionLabel('منابع مجاز', isDark)),
              _smallButton(
                isDark: isDark,
                icon: Icons.create_new_folder_outlined,
                label: 'افزودن پوشه',
                onTap: _picking ? null : () => _pick(directory: true),
              ),
              const SizedBox(width: WinSpace.xs),
              _smallButton(
                isDark: isDark,
                icon: Icons.note_add_outlined,
                label: 'افزودن فایل',
                onTap: _picking ? null : () => _pick(directory: false),
              ),
            ],
          ),
          if (resources.isEmpty)
            Container(
              padding: const EdgeInsets.all(WinSpace.lg),
              decoration: BoxDecoration(
                color: WinSurface.window(isDark),
                borderRadius: BorderRadius.circular(WinRadius.card),
                border: Border.all(color: WinSurface.hairline(isDark)),
              ),
              child: Text(
                'هیچ منبعی اضافه نشده. تا وقتی چیزی اینجا نباشد، ابزارهای فایل '
                'و ترمینال کار نمی‌کنند.',
                style: TextStyle(
                  fontSize: 12,
                  height: 1.8,
                  color: JSurface.muted(isDark),
                ),
              ),
            )
          else
            for (final resource in resources) _resourceRow(isDark, resource),
        ],
      );

  Widget _resourceRow(bool isDark, AgentResource resource) => Padding(
    padding: const EdgeInsets.only(bottom: WinSpace.sm),
    child: Container(
      padding: const EdgeInsets.all(WinSpace.md),
      decoration: BoxDecoration(
        color: WinSurface.window(isDark),
        borderRadius: BorderRadius.circular(WinRadius.card),
        border: Border.all(color: WinSurface.hairline(isDark)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                resource.isDirectory
                    ? Icons.folder_outlined
                    : Icons.description_outlined,
                size: 16,
                color: JColor.primary(isDark),
              ),
              const SizedBox(width: WinSpace.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      resource.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: WinText.bodySm,
                        fontWeight: FontWeight.w700,
                        color: JSurface.text(isDark),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      resource.path,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textDirection: TextDirection.ltr,
                      textAlign: TextAlign.left,
                      style: TextStyle(
                        fontSize: 10.5,
                        fontFamily: WinMono.family,
                        fontFamilyFallback: WinMono.fallback,
                        color: JSurface.muted(isDark),
                      ),
                    ),
                  ],
                ),
              ),
              WinIconButton(
                icon: Icons.close_rounded,
                tooltip: 'حذف فایل یا پوشهٔ انتخابی',
                onTap: () => ref
                    .read(agentWorkspaceProvider.notifier)
                    .remove(resource.path),
              ),
            ],
          ),
          const SizedBox(height: WinSpace.sm),
          Row(
            children: [
              _permChip(
                isDark: isDark,
                label: 'خواندن',
                value: resource.canRead,
                onChanged: (v) => ref
                    .read(agentWorkspaceProvider.notifier)
                    .setPermissions(resource.path, canRead: v),
              ),
              const SizedBox(width: WinSpace.xs),
              _permChip(
                isDark: isDark,
                label: 'نوشتن',
                value: resource.canWrite,
                onChanged: (v) => ref
                    .read(agentWorkspaceProvider.notifier)
                    .setPermissions(resource.path, canWrite: v),
              ),
              const SizedBox(width: WinSpace.xs),
              _permChip(
                isDark: isDark,
                label: 'حذف',
                value: resource.canDelete,
                danger: true,
                onChanged: (v) => ref
                    .read(agentWorkspaceProvider.notifier)
                    .setPermissions(resource.path, canDelete: v),
              ),
            ],
          ),
        ],
      ),
    ),
  );

  Widget _permChip({
    required bool isDark,
    required String label,
    required bool value,
    required ValueChanged<bool> onChanged,
    bool danger = false,
  }) {
    final on = danger
        ? (isDark ? DarkColors.danger : LightColors.danger)
        : JColor.primary(isDark);
    final color = value ? on : JSurface.muted(isDark);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: value
            ? on.withValues(alpha: isDark ? .16 : .10)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(WinRadius.control),
        border: Border.all(
          color: value ? on.withValues(alpha: .5) : WinSurface.hairline(isDark),
        ),
      ),
      child: WinHoverable(
        onTap: () => onChanged(!value),
        radius: WinRadius.control,
        padding: const EdgeInsets.symmetric(
          horizontal: WinSpace.md,
          vertical: 6,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              value ? Icons.check_rounded : Icons.remove_rounded,
              size: 12,
              color: color,
            ),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _grantsSection(bool isDark, AgentPolicyState policy) {
    final grants = {...policy.sessionGrants, ...policy.taskGrants};
    if (grants.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: _sectionLabel('اجازه‌های فعال', isDark)),
            _smallButton(
              isDark: isDark,
              icon: Icons.lock_reset_rounded,
              label: 'باطل کردن همه',
              onTap: () => ref.read(agentPolicyProvider.notifier).revokeAll(),
            ),
          ],
        ),
        Wrap(
          spacing: WinSpace.xs,
          runSpacing: WinSpace.xs,
          children: [
            for (final grant in grants)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: WinSpace.md,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: JColor.primary(isDark).withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(WinRadius.control),
                ),
                child: Text(
                  Perm.label(grant),
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: JColor.primary(isDark),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _toolsSection(bool isDark) {
    final tools = _registry.all;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionLabel('ابزارها', isDark),
        for (final tool in tools) _toolRow(isDark, tool),
      ],
    );
  }

  Widget _toolRow(bool isDark, AgentTool tool) {
    final risky = tool.risk == ToolRisk.destructive;
    final color = !tool.available
        ? JSurface.muted(isDark)
        : risky
        ? (isDark ? DarkColors.danger : LightColors.danger)
        : JSurface.secondary(isDark);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Icon(agentToolIcon(tool.name), size: 14, color: color),
          const SizedBox(width: WinSpace.sm),
          Expanded(
            child: Text(
              tool.label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: tool.available
                    ? JSurface.text(isDark)
                    : JSurface.muted(isDark),
              ),
            ),
          ),
          Text(
            tool.available ? agentRiskLabel(tool.risk) : 'در دسترس نیست',
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _smallButton({
    required bool isDark,
    required IconData icon,
    required String label,
    required VoidCallback? onTap,
  }) => DecoratedBox(
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(WinRadius.control),
      border: Border.all(color: WinSurface.hairline(isDark)),
    ),
    child: WinHoverable(
      onTap: onTap,
      radius: WinRadius.control,
      padding: const EdgeInsets.symmetric(horizontal: WinSpace.md, vertical: 6),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: JSurface.secondary(isDark)),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: JSurface.secondary(isDark),
            ),
          ),
        ],
      ),
    ),
  );
}
