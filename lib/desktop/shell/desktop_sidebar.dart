import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jemiran/desktop/shell/desktop_state.dart';
import 'package:jemiran/desktop/agent/core/work_session_store.dart';
import 'package:jemiran/desktop/agent/browser/browser_session.dart';
import 'package:jemiran/desktop/agent/core/agent_storage.dart';
import 'package:jemiran/desktop/agent/core/task_store.dart';
import 'package:jemiran/desktop/agent/byok/byok_provider.dart';
import 'package:jemiran/desktop/settings/desktop_settings_screen.dart';
import 'package:jemiran/desktop/theme/desktop_tokens.dart';
import 'package:jemiran/desktop/theme/win_controls.dart';
import 'package:jemiran/model/chat_session_model.dart';
import 'package:jemiran/themes/colors.dart';
import 'package:jemiran/themes/jemiran_design.dart';
import 'package:jemiran/ui/screens/chat_room/widgets/model_config.dart';
import 'package:jemiran/utils/persian_numbers.dart';
import 'package:jemiran/utils/shamsi_date.dart';

class DesktopSidebar extends ConsumerStatefulWidget {
  const DesktopSidebar({
    super.key,
    required this.onNewChat,
    required this.onLoadSession,
    required this.onNewWork,
    required this.onLoadWork,
  });

  final VoidCallback onNewChat;
  final void Function(ChatSessionModel session) onLoadSession;
  final VoidCallback onNewWork;
  final ValueChanged<WorkSession> onLoadWork;

  @override
  ConsumerState<DesktopSidebar> createState() => _DesktopSidebarState();
}

class _DesktopSidebarState extends ConsumerState<DesktopSidebar> {
  static const _imageModels = {'gemini_image', 'gpt_image', 'gpt_image2'};

  List<ChatSessionModel>? _sessions;
  bool _loading = true;
  String _query = '';
  final _searchController = TextEditingController();
  final _listController = ScrollController();
  final Map<int, String> _shamsiCache = {};
  int _loadGeneration = 0;

  @override
  void initState() {
    super.initState();
    WorkSessionStore.instance.addListener(_onWorksChanged);
    _loadSessions();
  }

  void _onWorksChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    WorkSessionStore.instance.removeListener(_onWorksChanged);
    _searchController.dispose();
    _listController.dispose();
    super.dispose();
  }

  Future<void> _loadSessions() async {
    final generation = ++_loadGeneration;
    const result = <ChatSessionModel>[];
    if (!mounted || generation != _loadGeneration) return;
    setState(() {
      _sessions = result
          .where((s) => !_imageModels.contains(s.modelDefault))
          .toList();
      _loading = false;
    });
  }

  Future<void> _delete(ChatSessionModel session) async {
    final sessions = _sessions;
    if (sessions == null || session.id == null) return;
    final index = sessions.indexOf(session);
    if (index < 0) return;

    setState(() => sessions.removeAt(index));
    if (ref.read(activeSessionProvider) == session.id) {
      widget.onNewChat();
    }

    var undone = false;
    final messenger = ScaffoldMessenger.of(context);
    messenger.clearSnackBars();
    final controller = messenger.showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 3),
        content: const Text('گفت‌وگو حذف شد', textDirection: TextDirection.rtl),
        action: SnackBarAction(
          label: 'بازگردانی',
          onPressed: () {
            undone = true;
            if (!mounted) return;
            setState(() {
              final list = _sessions;
              if (list != null && !list.contains(session)) {
                list.insert(index.clamp(0, list.length), session);
              }
            });
          },
        ),
      ),
    );

    await controller.closed;
    if (undone) return;
  }

  static String _groupOf(int createdAtSec) {
    final date = DateTime.fromMillisecondsSinceEpoch(createdAtSec * 1000);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(date.year, date.month, date.day);
    final diff = today.difference(day).inDays;
    if (diff <= 0) return 'امروز';
    if (diff == 1) return 'دیروز';
    if (diff <= 7) return '۷ روز گذشته';
    return 'قدیمی‌تر';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    ref.listen<int>(sessionsRefreshProvider, (_, _) => _loadSessions());

    return Container(
      width: ref.watch(sidebarWidthProvider),
      color: WinSurface.sidebar(isDark),
      child: Directionality(
        textDirection: TextDirection.rtl,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _topRow(isDark),
            _kindSelector(isDark),
            _newChatButton(isDark),
            _searchField(isDark),
            Expanded(child: _sessionList(isDark)),
            const WinSeam(),
            _userRow(isDark),
          ],
        ),
      ),
    );
  }

  Widget _topRow(bool isDark) => Padding(
    padding: const EdgeInsets.fromLTRB(
      WinSpace.md,
      WinSpace.md,
      WinSpace.sm,
      WinSpace.xs,
    ),
    child: Row(
      children: [
        Container(
          height: 26,
          width: 26,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(WinRadius.control),
            image: const DecorationImage(
              image: AssetImage('assets/images/aiIcon.png'),
              fit: BoxFit.cover,
            ),
          ),
        ),
        const SizedBox(width: WinSpace.md),
        Expanded(
          child: Text(
            'جمیران ایجنت',
            style: TextStyle(
              fontSize: WinText.title,
              fontWeight: FontWeight.w800,
              color: JSurface.text(isDark),
            ),
          ),
        ),
        WinIconButton(
          icon: Icons.view_sidebar_outlined,
          tooltip: 'بستن نوار کنار  (Ctrl+B)',
          size: 30,
          iconSize: 17,
          onTap: () => ref.read(sidebarOpenProvider.notifier).toggle(),
        ),
      ],
    ),
  );

  Widget _newChatButton(bool isDark) => Padding(
    padding: const EdgeInsets.fromLTRB(
      WinSpace.md,
      WinSpace.sm,
      WinSpace.md,
      WinSpace.xs,
    ),
    child: WinHoverable(
      onTap:
          ref.watch(desktopConversationKindProvider) ==
              DesktopConversationKind.work
          ? widget.onNewWork
          : widget.onNewChat,
      radius: WinRadius.card,
      tooltip:
          ref.read(desktopConversationKindProvider) ==
              DesktopConversationKind.work
          ? 'Work جدید  (Ctrl+N)'
          : 'گفت‌وگوی جدید  (Ctrl+N)',
      baseColor: JColor.primary(isDark).withValues(alpha: isDark ? .16 : .10),
      padding: const EdgeInsets.symmetric(
        horizontal: WinSpace.md,
        vertical: WinSpace.md,
      ),
      child: Row(
        children: [
          Icon(Icons.add_rounded, size: 18, color: JColor.primary(isDark)),
          const SizedBox(width: WinSpace.md),
          Expanded(
            child: Text(
              ref.watch(desktopConversationKindProvider) ==
                      DesktopConversationKind.work
                  ? 'Work جدید'
                  : 'گفت‌وگوی جدید',
              style: TextStyle(
                fontSize: WinText.bodySm,
                fontWeight: FontWeight.w800,
                color: JColor.primary(isDark),
              ),
            ),
          ),
          Text(
            'Ctrl+N',
            style: TextStyle(
              fontSize: 10,
              fontFamily: WinMono.family,
              fontFamilyFallback: WinMono.fallback,
              color: JColor.primary(isDark).withValues(alpha: .7),
            ),
          ),
        ],
      ),
    ),
  );

  Widget _searchField(bool isDark) => Padding(
    padding: const EdgeInsets.fromLTRB(
      WinSpace.md,
      WinSpace.sm,
      WinSpace.md,
      WinSpace.xs,
    ),
    child: Container(
      height: 34,
      decoration: BoxDecoration(
        color: WinSurface.layer(isDark),
        borderRadius: BorderRadius.circular(WinRadius.control),
        border: Border.all(color: WinSurface.hairline(isDark)),
      ),
      child: TextField(
        controller: _searchController,
        onChanged: (v) => setState(() => _query = v.trim()),
        cursorColor: JColor.primary(isDark),
        style: TextStyle(fontSize: 12.5, color: JSurface.text(isDark)),
        decoration: InputDecoration(
          hintText:
              ref.watch(desktopConversationKindProvider) ==
                  DesktopConversationKind.work
              ? 'جست‌وجو در Workها'
              : 'جست‌وجو در گفت‌وگوها',
          hintStyle: TextStyle(fontSize: 12, color: JSurface.muted(isDark)),
          prefixIcon: Icon(
            Icons.search_rounded,
            size: 16,
            color: JSurface.muted(isDark),
          ),
          prefixIconConstraints: const BoxConstraints(minWidth: 32),
          suffixIcon: _query.isEmpty
              ? null
              : WinIconButton(
                  icon: Icons.close_rounded,
                  size: 24,
                  iconSize: 14,
                  onTap: () {
                    _searchController.clear();
                    setState(() => _query = '');
                  },
                ),
          filled: false,
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(vertical: 9),
        ),
      ),
    ),
  );

  Widget _sessionList(bool isDark) {
    if (ref.watch(desktopConversationKindProvider) ==
        DesktopConversationKind.work) {
      return _workList(isDark);
    }
    if (_loading) {
      return Padding(
        padding: const EdgeInsets.all(WinSpace.md),
        child: Column(
          children: List.generate(
            6,
            (_) => Padding(
              padding: const EdgeInsets.only(bottom: WinSpace.sm),
              child: JSkeletonLine(isDark: isDark, height: 30),
            ),
          ),
        ),
      );
    }

    var sessions = _sessions ?? const <ChatSessionModel>[];
    final workTransportIds = <int>{
      for (final work in WorkSessionStore.instance.works)
        if (work.transportSessionId != null) work.transportSessionId!,
      for (final task in AgentTaskStore.instance.tasks)
        if (task.sessionId != null &&
            (task.steps.isNotEmpty || task.projectPath != null))
          task.sessionId!,
    };
    sessions = sessions
        .where((session) => !workTransportIds.contains(session.id))
        .toList(growable: false);
    if (_query.isNotEmpty) {
      final q = _query.toLowerCase();
      sessions = sessions
          .where((s) => s.title.toLowerCase().contains(q))
          .toList();
    }

    if (sessions.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(WinSpace.xl),
          child: Text(
            _query.isNotEmpty
                ? 'گفت‌وگویی با این عنوان پیدا نشد'
                : 'هنوز گفت‌وگویی نداری',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: WinText.caption,
              height: 1.8,
              color: JSurface.muted(isDark),
            ),
          ),
        ),
      );
    }

    final headers = List<String?>.filled(sessions.length, null);
    String? currentGroup;
    for (var i = 0; i < sessions.length; i++) {
      final group = _groupOf(sessions[i].createdAt);
      if (group != currentGroup) {
        currentGroup = group;
        headers[i] = group;
      }
    }

    final activeId = ref.watch(activeSessionProvider);

    return WinScrollbar(
      controller: _listController,
      child: ListView.builder(
        controller: _listController,
        padding: const EdgeInsets.only(bottom: WinSpace.md),
        itemCount: sessions.length,
        itemBuilder: (context, i) {
          final session = sessions[i];
          final tile = _SessionRow(
            session: session,
            selected: activeId != null && activeId == session.id,
            label: _shamsiCache.putIfAbsent(
              session.createdAt,
              () => DateTime.fromMillisecondsSinceEpoch(
                session.createdAt * 1000,
              ).toShamsi().farsiNumber,
            ),
            onTap: () => widget.onLoadSession(session),
            onDelete: () => _delete(session),
          );
          final header = headers[i];
          if (header == null) return tile;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [WinSectionLabel(header), tile],
          );
        },
      ),
    );
  }

  Widget _kindSelector(bool isDark) {
    final kind = ref.watch(desktopConversationKindProvider);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        WinSpace.md,
        WinSpace.sm,
        WinSpace.md,
        WinSpace.xs,
      ),
      child: Container(
        height: 34,
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: WinSurface.layer(isDark),
          borderRadius: BorderRadius.circular(WinRadius.control),
          border: Border.all(color: WinSurface.hairline(isDark)),
        ),
        child: Row(
          children: [
            Expanded(
              child: _kindButton(
                isDark: isDark,
                selected: kind == DesktopConversationKind.work,
                icon: Icons.folder_special_outlined,
                label: 'Work',
                onTap: () => ref
                    .read(desktopConversationKindProvider.notifier)
                    .set(DesktopConversationKind.work),
              ),
            ),
            const SizedBox(width: 3),
            Expanded(
              child: _kindButton(
                isDark: isDark,
                selected: kind == DesktopConversationKind.chat,
                icon: Icons.chat_bubble_outline_rounded,
                label: 'Chat',
                onTap: () => ref
                    .read(desktopConversationKindProvider.notifier)
                    .set(DesktopConversationKind.chat),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _kindButton({
    required bool isDark,
    required bool selected,
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) => WinHoverable(
    onTap: onTap,
    selected: selected,
    radius: WinRadius.control,
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          icon,
          size: 14,
          color: selected ? JColor.primary(isDark) : JSurface.muted(isDark),
        ),
        const SizedBox(width: 5),
        Text(
          label,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
            color: selected ? JColor.primary(isDark) : JSurface.text(isDark),
          ),
        ),
      ],
    ),
  );

  Widget _workList(bool isDark) {
    var works = WorkSessionStore.instance.works;
    if (_query.isNotEmpty) {
      final q = _query.toLowerCase();
      works = works
          .where((work) => work.title.toLowerCase().contains(q))
          .toList();
    }
    if (works.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(WinSpace.xl),
          child: Text(
            _query.isEmpty
                ? 'هنوز Work محلی نداری'
                : 'Workی با این عنوان پیدا نشد',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: WinText.caption,
              height: 1.8,
              color: JSurface.muted(isDark),
            ),
          ),
        ),
      );
    }
    final activeId = ref.watch(activeWorkProvider);
    var pinHeaderShown = false;
    var historyHeaderShown = false;
    return WinScrollbar(
      controller: _listController,
      child: ListView.builder(
        controller: _listController,
        padding: const EdgeInsets.only(bottom: WinSpace.md),
        itemCount: works.length,
        itemBuilder: (context, index) {
          final work = works[index];
          String? header;
          if (work.pinned && !pinHeaderShown) {
            pinHeaderShown = true;
            header = 'سنجاق‌شده‌ها';
          } else if (!work.pinned && !historyHeaderShown) {
            historyHeaderShown = true;
            header = 'تاریخچه';
          }
          final row = _WorkRow(
            work: work,
            selected: activeId == work.id,
            onTap: () => widget.onLoadWork(work),
            onPin: () => WorkSessionStore.instance.togglePin(work.id),
            onRename: () => _renameWork(work),
            onDelete: () => _deleteWork(work),
          );
          return header == null
              ? row
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [WinSectionLabel(header), row],
                );
        },
      ),
    );
  }

  Future<void> _renameWork(WorkSession work) async {
    final controller = TextEditingController(text: work.title);
    final value = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('تغییر نام Work'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 80,
          onSubmitted: (value) => Navigator.of(dialogContext).pop(value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('انصراف'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(controller.text),
            child: const Text('ذخیره'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (value != null) await WorkSessionStore.instance.rename(work.id, value);
  }

  Future<void> _deleteWork(WorkSession work) async {
    if (work.activeTaskId != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'این Work در حال اجراست؛ ابتدا آن را باز و متوقف کنید.',
            textDirection: TextDirection.rtl,
          ),
        ),
      );
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('حذف Work؟'),
        content: const Text(
          'فقط تاریخچه و تنظیمات محلی این Work حذف می‌شود؛ فایل‌های پروژه روی دیسک دست‌نخورده می‌مانند.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('انصراف'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('حذف'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    if (ref.read(activeWorkProvider) == work.id) widget.onNewWork();
    await BrowserSession.disposeScope('${AgentStorage.accountKey}:${work.id}');
    await WorkSessionStore.instance.delete(work.id);
  }

  Widget _userRow(bool isDark) {
    final providers = ByokStore.usable;
    final active = providers.isEmpty ? null : providers.first;

    return Padding(
      padding: const EdgeInsets.all(WinSpace.sm),
      child: Row(
        children: [
          Expanded(
            child: WinHoverable(
              radius: WinRadius.card,
              tooltip: 'ارائه‌دهنده‌ها و کلیدها',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const DesktopSettingsScreen(),
                ),
              ),
              padding: const EdgeInsets.symmetric(
                horizontal: WinSpace.sm,
                vertical: WinSpace.sm,
              ),
              child: Row(
                children: [
                  Icon(
                    active == null
                        ? Icons.key_off_outlined
                        : Icons.key_outlined,
                    size: 18,
                    color: JSurface.muted(isDark),
                  ),
                  const SizedBox(width: WinSpace.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          active?.label.isNotEmpty == true
                              ? active!.label
                              : 'کلیدی اضافه نشده',
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
                          active == null
                              ? 'برای شروع یک ارائه‌دهنده اضافه کنید'
                              : active.modelId,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 10.5,
                            color: JSurface.muted(isDark),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          WinIconButton(
            icon: Icons.settings_outlined,
            tooltip: 'تنظیمات',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const DesktopSettingsScreen()),
            ),
          ),
        ],
      ),
    );
  }
}

class _SessionRow extends StatefulWidget {
  const _SessionRow({
    required this.session,
    required this.label,
    required this.selected,
    required this.onTap,
    required this.onDelete,
  });

  final ChatSessionModel session;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  State<_SessionRow> createState() => _SessionRowState();
}

class _SessionRowState extends State<_SessionRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final title = widget.session.title.isNotEmpty
        ? widget.session.title
        : 'گفت‌وگوی جدید';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: WinSpace.sm, vertical: 1),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: WinHoverable(
          onTap: widget.onTap,
          selected: widget.selected,
          radius: WinRadius.card,
          padding: const EdgeInsets.symmetric(
            horizontal: WinSpace.md,
            vertical: WinSpace.sm,
          ),
          child: Row(
            children: [
              Icon(
                Icons.chat_bubble_outline_rounded,
                size: 15,
                color: widget.selected
                    ? JColor.primary(isDark)
                    : JSurface.muted(isDark),
              ),
              const SizedBox(width: WinSpace.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: widget.selected
                            ? FontWeight.w800
                            : FontWeight.w600,
                        color: JSurface.text(isDark),
                      ),
                    ),
                    if (_hover || widget.selected) ...[
                      const SizedBox(height: 2),
                      Text(
                        widget.label,
                        style: TextStyle(
                          fontSize: 10,
                          color: JSurface.muted(isDark),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (_hover)
                WinIconButton(
                  icon: Icons.delete_outline_rounded,
                  size: 24,
                  iconSize: 15,
                  tooltip: 'حذف گفت‌وگو',
                  color: isDark ? DarkColors.danger : LightColors.danger,
                  onTap: widget.onDelete,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WorkRow extends StatefulWidget {
  const _WorkRow({
    required this.work,
    required this.selected,
    required this.onTap,
    required this.onPin,
    required this.onRename,
    required this.onDelete,
  });

  final WorkSession work;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onPin;
  final VoidCallback onRename;
  final VoidCallback onDelete;

  @override
  State<_WorkRow> createState() => _WorkRowState();
}

class _WorkRowState extends State<_WorkRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final running = widget.work.activeTaskId != null;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: WinSpace.sm, vertical: 1),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: WinHoverable(
          onTap: widget.onTap,
          selected: widget.selected,
          radius: WinRadius.card,
          padding: const EdgeInsets.symmetric(
            horizontal: WinSpace.md,
            vertical: WinSpace.sm,
          ),
          child: Row(
            children: [
              Icon(
                running ? Icons.sync_rounded : Icons.folder_special_outlined,
                size: 15,
                color: running || widget.selected
                    ? JColor.primary(isDark)
                    : JSurface.muted(isDark),
              ),
              const SizedBox(width: WinSpace.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.work.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: widget.selected
                            ? FontWeight.w800
                            : FontWeight.w600,
                        color: JSurface.text(isDark),
                      ),
                    ),
                    if (running || _hover) ...[
                      const SizedBox(height: 2),
                      Text(
                        running ? 'در حال اجرا در پس‌زمینه' : 'ذخیره‌شده محلی',
                        style: TextStyle(
                          fontSize: 10,
                          color: JSurface.muted(isDark),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (widget.work.pinned && !_hover)
                Icon(
                  Icons.push_pin_rounded,
                  size: 13,
                  color: JColor.primary(isDark),
                ),
              if (_hover) ...[
                WinIconButton(
                  icon: widget.work.pinned
                      ? Icons.push_pin_rounded
                      : Icons.push_pin_outlined,
                  size: 23,
                  iconSize: 14,
                  tooltip: widget.work.pinned ? 'برداشتن سنجاق' : 'سنجاق کردن',
                  onTap: widget.onPin,
                ),
                WinIconButton(
                  icon: Icons.edit_outlined,
                  size: 23,
                  iconSize: 14,
                  tooltip: 'تغییر نام',
                  onTap: widget.onRename,
                ),
                WinIconButton(
                  icon: Icons.delete_outline_rounded,
                  size: 23,
                  iconSize: 14,
                  tooltip: 'حذف Work',
                  color: isDark ? DarkColors.danger : LightColors.danger,
                  onTap: widget.onDelete,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

String desktopModelLabel(String key) => ModelConfig.label(key);
