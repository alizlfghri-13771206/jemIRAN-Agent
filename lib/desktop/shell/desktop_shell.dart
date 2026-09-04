import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jemiran/desktop/agent/memory/agent_memory.dart';
import 'package:jemiran/desktop/agent/core/agent_storage.dart';
import 'package:jemiran/desktop/agent/core/task_store.dart';
import 'package:jemiran/desktop/agent/core/work_session_store.dart';
import 'package:jemiran/desktop/agent/policy/agent_policy.dart';
import 'package:jemiran/desktop/agent/skills/agent_skill.dart';
import 'package:jemiran/desktop/agent/agent_workspace.dart';
import 'package:jemiran/desktop/chat/desktop_chat_view.dart';
import 'package:jemiran/desktop/routing/desktop_model_route.dart';
import 'package:jemiran/desktop/shell/desktop_sidebar.dart';
import 'package:jemiran/desktop/shell/desktop_state.dart';
import 'package:jemiran/themes/jemiran_design.dart';
import 'package:jemiran/desktop/shell/sidebar_resize_handle.dart';
import 'package:jemiran/desktop/shell/window_title_bar.dart';
import 'package:jemiran/desktop/theme/desktop_tokens.dart';
import 'package:jemiran/model/chat_session_model.dart';

class DesktopShell extends ConsumerStatefulWidget {
  const DesktopShell({super.key, this.initialModel});

  final String? initialModel;

  @override
  ConsumerState<DesktopShell> createState() => _DesktopShellState();
}

class _DesktopShellState extends ConsumerState<DesktopShell> {
  final _chatKey = GlobalKey<DesktopChatViewState>();
  bool _bootstrapped = false;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    AgentStorage.setAccountScope('windows-local');
    ref.read(activeSkillsProvider.notifier).clear();
    if (!mounted) return;
    await ref.read(desktopModelRouteProvider.notifier).resetForAccount();
    if (!mounted) return;

    await AgentWorkspace.load();
    if (!mounted) return;
    ref.read(agentWorkspaceProvider.notifier).bump();
    await ref.read(agentPolicyProvider.notifier).load();

    await ref.read(skillsProvider.notifier).reload();
    if (!mounted) return;
    await ref.read(memoryProvider.notifier).reload();
    if (!mounted) return;
    await AgentTaskStore.instance.load();
    if (!mounted) return;
    await WorkSessionStore.instance.load();
    if (!mounted) return;
    setState(() => _bootstrapped = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final works = WorkSessionStore.instance.works;
      if (works.isEmpty) {
        unawaited(_chatKey.currentState?.startNewWork());
      } else {
        unawaited(_chatKey.currentState?.loadWork(works.first));
      }
    });
  }

  void _newChat() => _chatKey.currentState?.startNewChat();

  void _newWork() => unawaited(_chatKey.currentState?.startNewWork());

  void _newConversation() {
    if (ref.read(desktopConversationKindProvider) ==
        DesktopConversationKind.work) {
      _newWork();
    } else {
      _newChat();
    }
  }

  void _loadSession(ChatSessionModel session) {
    _chatKey.currentState?.loadSession(session);
    _closeSidebarIfFloating();
  }

  void _loadWork(WorkSession work) {
    unawaited(_chatKey.currentState?.loadWork(work));
    _closeSidebarIfFloating();
  }

  bool get _sidebarFloats =>
      MediaQuery.sizeOf(context).width < WinMetrics.sidebarBreakpoint;

  void _closeSidebarIfFloating() {
    if (_sidebarFloats) ref.read(sidebarOpenProvider.notifier).set(false);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final open = ref.watch(sidebarOpenProvider);
    final floats = _sidebarFloats;

    if (!_bootstrapped) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final sidebar = DesktopSidebar(
      onNewChat: () {
        _newChat();
        _closeSidebarIfFloating();
      },
      onLoadSession: _loadSession,
      onNewWork: () {
        _newWork();
        _closeSidebarIfFloating();
      },
      onLoadWork: _loadWork,
    );

    final chat = DesktopChatView(
      key: _chatKey,
      initialModel: widget.initialModel,
    );

    return Scaffold(
      backgroundColor: WinSurface.window(isDark),
      body: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.keyN, control: true):
              _newConversation,
          const SingleActivator(LogicalKeyboardKey.keyB, control: true): () =>
              ref.read(sidebarOpenProvider.notifier).toggle(),
          const SingleActivator(LogicalKeyboardKey.keyL, control: true): () =>
              _chatKey.currentState?.focusComposer(),
          const SingleActivator(LogicalKeyboardKey.escape): () =>
              _chatKey.currentState?.cancelActiveRequest(),
        },
        child: Focus(
          autofocus: true,
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: Column(
              children: [
                WindowTitleBar(
                  isDark: isDark,
                  title: Padding(
                    padding: const EdgeInsets.only(left: WinSpace.md),
                    child: Text(
                      'جمیران ایجنت',
                      style: TextStyle(
                        fontFamily: 'vazir',
                        fontSize: WinText.caption,
                        fontWeight: FontWeight.w600,
                        color: JSurface.muted(isDark),
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: _shellBody(isDark, chat, sidebar, floats, open),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _shellBody(
    bool isDark,
    Widget chat,
    Widget sidebar,
    bool floats,
    bool open,
  ) => floats
      ? Stack(
          children: [
            Positioned.fill(child: _content(isDark, chat)),
            if (open) ...[
              Positioned.fill(
                child: GestureDetector(
                  onTap: () =>
                      ref.read(sidebarOpenProvider.notifier).set(false),
                  child: ColoredBox(color: Colors.black.withValues(alpha: .35)),
                ),
              ),
              Positioned(
                top: 0,
                bottom: 0,
                left: 0,
                child: Material(
                  elevation: 12,
                  color: WinSurface.sidebar(isDark),
                  child: sidebar,
                ),
              ),
            ],
          ],
        )
      : Row(
          children: [
            if (open) ...[sidebar, SidebarResizeHandle(isDark: isDark)],
            Expanded(child: _content(isDark, chat)),
          ],
        );

  Widget _content(bool isDark, Widget chat) =>
      ColoredBox(color: WinSurface.layer(isDark), child: chat);
}
