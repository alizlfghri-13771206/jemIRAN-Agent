import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:jemiran/desktop/agent/agent_workspace.dart';
import 'package:jemiran/desktop/theme/desktop_tokens.dart';
import 'package:jemiran/desktop/theme/win_controls.dart';
import 'package:jemiran/themes/colors.dart';
import 'package:jemiran/themes/jemiran_design.dart';

class DesktopComposer extends StatefulWidget {
  const DesktopComposer({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.isLoading,
    required this.canSend,
    required this.attachmentBusy,
    required this.onSend,
    required this.onCancel,
    required this.onAttach,
    required this.onManageResources,
    required this.onSelectProject,
    required this.onRemoveResource,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool isLoading;
  final bool canSend;
  final bool attachmentBusy;
  final VoidCallback onSend;
  final VoidCallback onCancel;
  final VoidCallback onAttach;

  final VoidCallback? onManageResources;
  final ValueChanged<String>? onSelectProject;
  final ValueChanged<String>? onRemoveResource;

  @override
  State<DesktopComposer> createState() => _DesktopComposerState();
}

class _DesktopComposerState extends State<DesktopComposer> {
  bool _focused = false;
  bool _expanded = false;

  @override
  void initState() {
    super.initState();
    widget.focusNode.addListener(_onFocusChanged);
  }

  @override
  void dispose() {
    widget.focusNode.removeListener(_onFocusChanged);
    super.dispose();
  }

  void _onFocusChanged() {
    if (!mounted) return;
    final has = widget.focusNode.hasFocus;
    if (has != _focused) setState(() => _focused = has);
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey != LogicalKeyboardKey.enter &&
        event.logicalKey != LogicalKeyboardKey.numpadEnter) {
      return KeyEventResult.ignored;
    }

    final keyboard = HardwareKeyboard.instance;
    if (keyboard.isShiftPressed || keyboard.isControlPressed) {
      return KeyEventResult.ignored;
    }
    if (widget.isLoading || !widget.canSend) return KeyEventResult.handled;
    widget.onSend();
    return KeyEventResult.handled;
  }

  Widget _resourceStrip(bool isDark) {
    final resources = AgentWorkspace.resources;
    if (resources.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: WinSpace.sm),
      child: Align(
        alignment: Alignment.centerLeft,
        child: SizedBox(
          height: 26,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            shrinkWrap: true,
            itemCount: resources.length,
            separatorBuilder: (_, _) => const SizedBox(width: WinSpace.xs),
            itemBuilder: (context, i) => _resourceChip(resources[i], isDark),
          ),
        ),
      ),
    );
  }

  Widget _resourceChip(AgentResource resource, bool isDark) {
    final accent = JColor.primary(isDark);
    final active =
        resource.isDirectory && resource.path == AgentWorkspace.primaryRoot;
    return WinHoverable(
      onTap: resource.isDirectory
          ? (widget.onSelectProject == null
                ? null
                : () => widget.onSelectProject!(resource.path))
          : widget.onManageResources,
      radius: WinRadius.control,
      tooltip:
          '${resource.path}\n${resource.permissionLabel}'
          '${active ? '\nپروژهٔ فعال' : ''}',
      padding: const EdgeInsets.symmetric(horizontal: WinSpace.sm, vertical: 3),
      baseColor: accent.withValues(
        alpha: active ? (isDark ? .24 : .17) : (isDark ? .10 : .07),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            resource.isDirectory
                ? Icons.folder_outlined
                : Icons.description_outlined,
            size: 13,
            color: accent,
          ),
          if (active) ...[
            const SizedBox(width: 4),
            Icon(Icons.check_circle_rounded, size: 11, color: accent),
          ],
          const SizedBox(width: 5),
          Text(
            resource.name,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: JSurface.text(isDark),
            ),
          ),
          const SizedBox(width: 4),
          Semantics(
            button: true,
            label: 'قطع دسترسی ${resource.name}',
            child: InkWell(
              onTap: widget.onRemoveResource == null
                  ? null
                  : () => widget.onRemoveResource!(resource.path),
              borderRadius: BorderRadius.circular(10),
              child: Padding(
                padding: const EdgeInsets.all(2),
                child: Icon(
                  Icons.close_rounded,
                  size: 12,
                  color: accent.withValues(alpha: .9),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final borderColor = _focused
        ? JColor.primary(isDark).withValues(alpha: .75)
        : WinSurface.hairline(isDark);

    final expandedEditorHeight = (MediaQuery.sizeOf(context).height * .42)
        .clamp(220.0, 460.0);

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            curve: Curves.easeOut,
            padding: WinSpace.composer,
            decoration: BoxDecoration(
              color: WinSurface.card(isDark),
              borderRadius: BorderRadius.circular(WinRadius.layer),
              border: Border.all(color: borderColor, width: _focused ? 1.4 : 1),
              boxShadow: _focused
                  ? AppShadows.glow(JColor.primary(isDark), alpha: .10)
                  : AppShadows.subtle(isDark),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    WinIconButton(
                      key: const ValueKey('desktop_composer_expand'),
                      icon: _expanded
                          ? Icons.close_fullscreen_rounded
                          : Icons.open_in_full_rounded,
                      tooltip: _expanded
                          ? 'کوچک‌کردن فضای نوشتن'
                          : 'گسترش فضای نوشتن',
                      size: 30,
                      iconSize: 16,
                      selected: _expanded,
                      onTap: () => setState(() => _expanded = !_expanded),
                    ),
                    const SizedBox(width: WinSpace.sm),
                    Expanded(child: _resourceStrip(isDark)),
                  ],
                ),
                AnimatedContainer(
                  duration: JMotion.fast,
                  curve: JMotion.curve,
                  height: _expanded ? expandedEditorHeight : null,
                  constraints: BoxConstraints(
                    maxHeight: _expanded
                        ? expandedEditorHeight
                        : WinMetrics.composerMaxHeight,
                  ),
                  child: WinScrollbar(
                    child: Focus(
                      canRequestFocus: false,
                      skipTraversal: true,
                      onKeyEvent: _onKey,
                      child: TextField(
                        controller: widget.controller,
                        focusNode: widget.focusNode,
                        autofocus: true,
                        maxLines: null,
                        minLines: _expanded ? null : 1,
                        expands: _expanded,
                        textDirection: TextDirection.rtl,
                        keyboardType: TextInputType.multiline,
                        cursorColor: JColor.secondary(isDark),
                        cursorWidth: 1.6,
                        style: TextStyle(
                          fontSize: WinText.body,
                          height: 1.75,
                          fontWeight: FontWeight.w500,
                          color: JSurface.text(isDark),
                        ),
                        decoration: InputDecoration(
                          filled: false,
                          isDense: true,
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          hintText: 'شروع کن...',
                          hintTextDirection: TextDirection.rtl,
                          hintStyle: TextStyle(
                            fontSize: WinText.bodySm,
                            fontWeight: FontWeight.w500,
                            color: JSurface.muted(isDark),
                          ),
                          contentPadding: WinSpace.composerField,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: WinSpace.sm),
                Row(
                  children: [
                    WinIconButton(
                      icon: Icons.attach_file_rounded,
                      tooltip: 'پیوست فایل',
                      onTap: widget.isLoading ? null : widget.onAttach,
                    ),
                    const SizedBox(width: WinSpace.xs),
                    WinIconButton(
                      icon: Icons.hub_outlined,
                      tooltip: 'پوشه‌ها و فایل‌های در دسترس ایجنت',
                      onTap: widget.onManageResources,
                    ),
                    const Spacer(),
                    Text(
                      widget.isLoading ? 'Esc برای توقف' : 'Enter برای ارسال',
                      style: TextStyle(
                        fontSize: 10.5,
                        color: JSurface.muted(isDark),
                      ),
                    ),
                    const SizedBox(width: WinSpace.md),
                    _sendButton(isDark),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Center(
            child: Text(
              'Shift+Enter خط جدید · Ctrl+N گفت‌وگوی جدید · Ctrl+B نوار کنار',
              style: TextStyle(fontSize: 10, color: JSurface.muted(isDark)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sendButton(bool isDark) {
    final enabled = widget.isLoading || widget.canSend;
    return WinHoverable(
      onTap: widget.isLoading
          ? widget.onCancel
          : (widget.canSend ? widget.onSend : null),
      radius: WinRadius.control,
      tooltip: widget.isLoading ? 'توقف' : 'ارسال',
      child: AnimatedOpacity(
        duration: JMotion.fast,
        opacity: enabled ? 1 : .4,
        child: Container(
          height: 34,
          width: 46,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            gradient: JGradient.brand(isDark),
            borderRadius: BorderRadius.circular(WinRadius.control),
          ),
          child: widget.attachmentBusy && !widget.isLoading
              ? const SizedBox(
                  height: 15,
                  width: 15,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.8,
                    valueColor: AlwaysStoppedAnimation(Colors.white),
                  ),
                )
              : Icon(
                  widget.isLoading
                      ? Icons.stop_rounded
                      : Icons.arrow_upward_rounded,
                  color: Colors.white,
                  size: 17,
                ),
        ),
      ),
    );
  }
}
