import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jemiran/desktop/agent/agent_workspace.dart';
import 'package:jemiran/desktop/agent/audit/audit_recorder.dart';
import 'package:jemiran/desktop/agent/browser/browser_session.dart';
import 'package:jemiran/desktop/agent/byok/byok_adapter.dart';
import 'package:jemiran/desktop/agent/byok/byok_provider.dart';
import 'package:jemiran/desktop/agent/byok/local_attachments.dart';
import 'package:jemiran/desktop/agent/core/agent_engine.dart';
import 'package:jemiran/desktop/agent/core/agent_storage.dart';
import 'package:jemiran/desktop/agent/core/agent_event.dart';
import 'package:jemiran/desktop/agent/core/agent_task.dart';
import 'package:jemiran/desktop/agent/core/checkpoint_store.dart';
import 'package:jemiran/desktop/agent/core/context_budget.dart';
import 'package:jemiran/desktop/agent/core/model_failover.dart';
import 'package:jemiran/desktop/agent/core/task_store.dart';
import 'package:jemiran/desktop/agent/core/work_session_store.dart';
import 'package:jemiran/desktop/agent/memory/agent_memory.dart';
import 'package:jemiran/desktop/agent/policy/agent_policy.dart';
import 'package:jemiran/desktop/agent/skills/agent_skill.dart';
import 'package:jemiran/desktop/agent/tools/tool_registry.dart';
import 'package:jemiran/desktop/agent/widgets/agent_panel.dart';
import 'package:jemiran/desktop/agent/widgets/permission_dialog.dart';
import 'package:jemiran/desktop/agent/widgets/question_dialog.dart';
import 'package:jemiran/desktop/agent/widgets/rollback_dialog.dart';
import 'package:jemiran/desktop/agent/widgets/tool_call_card.dart';
import 'package:jemiran/desktop/chat/desktop_composer.dart';
import 'package:jemiran/desktop/chat/desktop_ai_message.dart';
import 'package:jemiran/desktop/chat/desktop_user_message.dart';
import 'package:jemiran/desktop/chat/session_title_coordinator.dart';
import 'package:jemiran/desktop/models/desktop_models_notifier.dart';
import 'package:jemiran/desktop/routing/desktop_model_route.dart';
import 'package:jemiran/desktop/routing/desktop_model_route_dialog.dart';
import 'package:jemiran/desktop/shell/agent_notifier.dart';
import 'package:jemiran/desktop/shell/desktop_state.dart';
import 'package:jemiran/desktop/shell/desktop_runtime_control.dart';
import 'package:jemiran/desktop/theme/desktop_tokens.dart';
import 'package:jemiran/desktop/theme/win_controls.dart';
import 'package:jemiran/model/chat_session_model.dart';
import 'package:jemiran/model/message.dart';
import 'package:jemiran/model/pending_attachment.dart';
import 'package:jemiran/desktop/agent/network/provider_exception.dart';
import 'package:jemiran/themes/colors.dart';
import 'package:jemiran/themes/jemiran_design.dart';
import 'package:jemiran/ui/screens/chat_room/widgets/attachment_preview.dart';
import 'package:jemiran/ui/screens/chat_room/widgets/model_config.dart';
import 'package:jemiran/ui/screens/chat_room/widgets/reply_widgets.dart';
import 'package:jemiran/utils/image_compressor.dart';
import 'package:jemiran/desktop/agent/widgets/agent_home.dart';

sealed class DesktopChatItem {
  const DesktopChatItem();

  String get key;
}

class DesktopMessageItem extends DesktopChatItem {
  const DesktopMessageItem(this.message);
  final Message message;

  @override
  String get key => 'm_${message.id}';
}

class DesktopAgentItem extends DesktopChatItem {
  const DesktopAgentItem(this.step, {required this.taskId});
  final AgentStepRecord step;
  final String taskId;

  @override
  String get key => 'a_${step.id}';
}

class _ConversationRuntime {
  _ConversationRuntime({this.work});

  final WorkSession? work;
  final ByokConversationState byokConversation = ByokConversationState();
  final List<DesktopChatItem> items = [];
  String? typingMessageId;

  String? streamingMessageId;
  bool isLoading = false;
  bool isSending = false;
  int requestGeneration = 0;
  int? sessionId;
  AgentEngine? engine;
  StreamSubscription<AgentEvent>? engineSub;
  AgentPhase phase = AgentPhase.idle;
  String? phaseAction;
  AgentTask? task;

  String? runningModelKey;

  DateTime? turnStartedAt;

  FailoverReconnectState? reconnect;

  FailoverModelAdapter? failover;

  bool get isWork => work != null;

  String get sessionScope => '${AgentStorage.accountKey}:${work?.id ?? 'chat'}';
}

class DesktopChatView extends ConsumerStatefulWidget {
  const DesktopChatView({super.key, this.initialModel});

  final String? initialModel;

  @override
  ConsumerState<DesktopChatView> createState() => DesktopChatViewState();
}

class DesktopChatViewState extends ConsumerState<DesktopChatView> {
  final _scrollController = ScrollController();
  final _textController = TextEditingController();
  final _focusNode = FocusNode();

  late _ConversationRuntime _current = _ConversationRuntime();
  final Map<String, _ConversationRuntime> _workRuntimes = {};
  PendingAttachment? _attachment;
  Message? _replyToMessage;

  Timer? _progressRedrawTimer;
  Timer? _streamRedrawTimer;
  Future<void> _interactionQueue = Future<void>.value();

  List<DesktopChatItem> get _items => _current.items;
  String? get _typingMessageId => _current.typingMessageId;
  set _typingMessageId(String? value) => _current.typingMessageId = value;
  bool get _isLoading => _current.isLoading;
  set _isLoading(bool value) => _current.isLoading = value;
  bool get _isSending => _current.isSending;
  AgentPhase get _phase => _current.phase;
  set _phase(AgentPhase value) => _current.phase = value;
  String? get _phaseAction => _current.phaseAction;
  set _phaseAction(String? value) => _current.phaseAction = value;

  final _registry = ToolRegistry.windows();
  final _titleCoordinator = SessionTitleCoordinator();

  FailoverReconnectState? get _reconnect => _current.reconnect;

  String get _activeModel {
    final models = ref.read(desktopModelsProvider);
    final primary = ref.read(desktopModelRouteProvider).primary;
    if (primary != null &&
        models.models.any(
          (item) => item['key'] == primary && modelRunnable(item),
        )) {
      return primary;
    }
    return models.firstUsableModelKey ?? '';
  }

  String? _resolveModelKey([String? preferred]) {
    bool exists(String? key) =>
        key != null && key.isNotEmpty && ByokStore.byModelKey(key) != null;
    if (exists(preferred)) return preferred;
    final active = _activeModel;
    if (exists(active)) return active;
    final usable = ByokStore.usable;
    return usable.isEmpty ? null : usable.first.modelKey;
  }

  static const _noProviderNotice =
      'هیچ ارائه‌دهندهٔ آماده‌ای نیست. از تنظیمات ← «ارائه‌دهنده‌های من» '
      'یک ارائه‌دهنده با کلید خودت اضافه کن.';

  @override
  void initState() {
    super.initState();
    _textController.addListener(_onComposerChanged);
    DesktopRuntimeControl.attach(_shutdownAllRuntimes);
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncModels());
  }

  bool _lastCanSend = false;

  void _onComposerChanged() {
    final now = _canSend;
    if (now == _lastCanSend || !mounted) return;
    setState(() => _lastCanSend = now);
  }

  @override
  void dispose() {
    DesktopRuntimeControl.detach();
    final runtimes = <_ConversationRuntime>{_current, ..._workRuntimes.values};
    for (final runtime in runtimes) {
      unawaited(runtime.engine?.cancel() ?? Future<void>.value());
      unawaited(runtime.engineSub?.cancel() ?? Future<void>.value());
      if (runtime.engine != null) unawaited(runtime.engine!.dispose());
    }
    _progressRedrawTimer?.cancel();
    _streamRedrawTimer?.cancel();
    unawaited(AgentTaskStore.instance.flush());
    unawaited(WorkSessionStore.instance.flush());
    _scrollController.dispose();
    _textController.removeListener(_onComposerChanged);
    _textController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _syncModels() async {
    final notifier = ref.read(desktopModelsProvider.notifier);
    await notifier.loadIfNeeded();
    if (!mounted) return;

    final available = ref
        .read(desktopModelsProvider)
        .models
        .where(modelRunnable)
        .map((m) => m['key'] as String?)
        .whereType<String>()
        .toList();
    if (available.isEmpty) return;

    final route = ref.read(desktopModelRouteProvider.notifier);
    await route.ready;
    await route.reconcile(available);
    if (widget.initialModel != null &&
        available.contains(widget.initialModel)) {
      route.setPrimary(widget.initialModel!);
    }
  }

  void _clearReconnect(_ConversationRuntime runtime, int generation) {
    if (generation != runtime.requestGeneration) return;
    runtime.failover = null;
    final hadRunning = runtime.runningModelKey != null;
    runtime.runningModelKey = null;
    runtime.turnStartedAt = null;
    if (runtime.reconnect == null && !hadRunning) return;
    runtime.reconnect = null;
    if (mounted && identical(_current, runtime)) setState(() {});
  }

  void _skipToNextModel() {
    final runtime = _current;
    final adapter = runtime.failover;
    if (adapter == null || !adapter.canSkipToNextModel) return;
    adapter.skipToNextModel();
    setState(() => runtime.reconnect = null);
  }

  void startNewChat() {
    _saveCurrentWork();
    if (!_current.isWork) _stopRuntime(_current);
    _current = _ConversationRuntime();
    unawaited(
      AgentWorkspace.replace(const []).then((_) {
        if (mounted) ref.read(agentWorkspaceProvider.notifier).bump();
      }),
    );
    setState(() {
      _attachment = null;
      _replyToMessage = null;
    });
    ref
        .read(desktopConversationKindProvider.notifier)
        .set(DesktopConversationKind.chat);
    ref.read(activeWorkProvider.notifier).set(null);
    ref.read(activeSessionProvider.notifier).set(null);
    _focusNode.requestFocus();
  }

  Future<void> _shutdownAllRuntimes() async {
    final runtimes = <_ConversationRuntime>{_current, ..._workRuntimes.values};
    for (final runtime in runtimes) {
      await runtime.engine?.cancel();
      await runtime.engineSub?.cancel();
      if (runtime.engine != null) await runtime.engine!.dispose();
      runtime
        ..engine = null
        ..engineSub = null
        ..isLoading = false
        ..isSending = false;
      if (runtime.task != null && !runtime.task!.phase.isTerminal) {
        runtime.task!
          ..phase = AgentPhase.interrupted
          ..currentAction = null
          ..touch();
        AgentTaskStore.instance.scheduleSave(runtime.task!);
      }
      _persistRuntime(runtime, immediate: true);
    }
    await AgentTaskStore.instance.flush();
    await WorkSessionStore.instance.flush();
    await BrowserSession.disposeAll();
  }

  Future<T> _serializeInteraction<T>(Future<T> Function() action) {
    final completer = Completer<T>();
    _interactionQueue = _interactionQueue.then((_) async {
      try {
        completer.complete(await action());
      } catch (error, stack) {
        completer.completeError(error, stack);
      }
    });
    return completer.future;
  }

  Future<void> startNewWork() async {
    _saveCurrentWork();
    final work = await WorkSessionStore.instance.create(resources: const []);
    if (!mounted) return;
    await loadWork(work);
  }

  Future<void> loadWork(WorkSession work) async {
    _saveCurrentWork();
    var runtime = _workRuntimes[work.id];
    if (runtime == null) {
      runtime = _ConversationRuntime(work: work)
        ..sessionId = work.transportSessionId
        ..phase = AgentPhase.idle;
      for (final entry in work.timeline) {
        final kind = entry['kind'];
        if (kind == 'message' && entry['message'] is Map) {
          try {
            final message = Message.fromJson(
              Map<String, dynamic>.from(entry['message'] as Map),
            );
            runtime.items.add(DesktopMessageItem(message));
            if (!message.isLoading && message.text.trim().isNotEmpty) {
              runtime.byokConversation.seedTextMessage(
                isUser: message.isUser,
                text: message.text,
              );
            }
          } catch (_) {}
        } else if (kind == 'step') {
          final taskId = entry['task_id']?.toString();
          final stepId = entry['step_id']?.toString();
          if (taskId == null || stepId == null) continue;
          final step = AgentTaskStore.instance.stepById(taskId, stepId);
          if (step != null) {
            runtime.items.add(DesktopAgentItem(step, taskId: taskId));
          }
        }
      }
      runtime.task = AgentTaskStore.instance.byId(work.activeTaskId);
      if (runtime.task != null) {
        runtime.phase = runtime.task!.phase;
        runtime.phaseAction = runtime.task!.currentAction;
      }
      _workRuntimes[work.id] = runtime;
    }

    await AgentWorkspace.replace(
      work.resources,
      activeProjectPath: work.projectPath,
    );
    if (!mounted) return;
    _current = runtime;
    ref
        .read(desktopConversationKindProvider.notifier)
        .set(DesktopConversationKind.work);
    ref.read(activeWorkProvider.notifier).set(work.id);
    ref.read(activeSessionProvider.notifier).set(null);
    ref.read(agentWorkspaceProvider.notifier).bump();
    final model = work.modelKey;
    if (model != null &&
        ref
            .read(desktopModelsProvider)
            .models
            .any((item) => item['key'] == model && modelRunnable(item))) {
      ref.read(desktopModelRouteProvider.notifier).setPrimary(model);
    }
    setState(() {
      _attachment = null;
      _replyToMessage = null;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
  }

  Future<void> loadSession(ChatSessionModel session) async {
    _saveCurrentWork();
    if (!_current.isWork) _stopRuntime(_current);
    _current = _ConversationRuntime();
    await AgentWorkspace.replace(const []);
    if (mounted) ref.read(agentWorkspaceProvider.notifier).bump();
    final sessionId = session.id;
    if (sessionId == null) {
      _snack('این گفت‌وگو شناسهٔ معتبری ندارد و قابل بازکردن نیست.');
      return;
    }
    final sessionProject = AgentTaskStore.instance.projectPathForSession(
      sessionId,
    );
    if (sessionProject != null) {
      await ref
          .read(agentWorkspaceProvider.notifier)
          .selectProject(sessionProject);
    }
    if (session.title.trim().isNotEmpty) {
      _titleCoordinator.markKnown(sessionId);
    }
    setState(() {
      _items.clear();
      _current.sessionId = sessionId;
      _attachment = null;
      _replyToMessage = null;
      _typingMessageId = null;
      _isLoading = false;
      _phase = AgentPhase.idle;
      _phaseAction = null;
    });
    ref.read(activeSessionProvider.notifier).set(sessionId);
    ref.read(activeWorkProvider.notifier).set(null);
    ref
        .read(desktopConversationKindProvider.notifier)
        .set(DesktopConversationKind.chat);
    final sessionModel = session.modelDefault;
    if (sessionModel != null &&
        ref
            .read(desktopModelsProvider)
            .models
            .any(
              (model) => model['key'] == sessionModel && modelRunnable(model),
            )) {
      ref.read(desktopModelRouteProvider.notifier).setPrimary(sessionModel);
    }
  }

  void focusComposer() => _focusNode.requestFocus();

  void resumeTask(AgentTask task) {
    if (_isLoading) return;
    if (task.projectPath != null) {
      unawaited(
        ref
            .read(agentWorkspaceProvider.notifier)
            .selectProject(task.projectPath!),
      );
    }
    if (task.sessionId != null) {
      _current.sessionId = task.sessionId;
      ref.read(activeSessionProvider.notifier).set(task.sessionId);
    }
    final completed = task.steps
        .where((step) => step.status == StepStatus.done)
        .map((step) => '✓ ${step.headline}')
        .take(12)
        .join('\n');
    final changed = task.changedPaths.take(12).join('\n');
    _textController.text =
        '''
این کار قبلاً متوقف شده است. با بررسی وضعیت فعلی و بدون تکرار کورکورانهٔ عملیات ادامه بده.

هدف اصلی:
${task.goal}

گام‌های ثبت‌شده:
${completed.isEmpty ? 'گام موفقی ثبت نشده است.' : completed}

مسیرهای تغییرکرده:
${changed.isEmpty ? 'مسیری ثبت نشده است.' : changed}

ابتدا وضعیت موجود را راستی‌آزمایی کن، سپس فقط کارهای باقی‌مانده را انجام بده.
'''
            .trim();
    _textController.selection = TextSelection.collapsed(
      offset: _textController.text.length,
    );
    _focusNode.requestFocus();
    if (mounted) setState(() {});
    _snack('خلاصهٔ امن ادامه آماده شد؛ برای شروع، ارسال را بزنید.');
  }

  void cancelActiveRequest() {
    if (_isLoading) _cancelRequest();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      final target = _scrollController.position.maxScrollExtent;
      final distance = (target - _scrollController.offset).abs();
      if (distance < 8) return;
      _scrollController.animateTo(
        target,
        duration: Duration(
          milliseconds: (distance * 0.5).clamp(160.0, 460.0).round(),
        ),
        curve: Curves.easeOutCubic,
      );
    });
  }

  static String _truncatePreview(String text) =>
      text.length > 60 ? '${text.substring(0, 60)}...' : text;

  void _addMessage(Message message) => _items.add(DesktopMessageItem(message));

  void _removeTrailingLoader() {
    _removeTrailingLoaderFor(_current);
  }

  void _removeTrailingLoaderFor(_ConversationRuntime runtime) {
    for (var i = runtime.items.length - 1; i >= 0; i--) {
      final item = runtime.items[i];
      if (item is DesktopMessageItem && item.message.isLoading) {
        runtime.items.removeAt(i);
        return;
      }
    }
  }

  void _syncActivityLoaderFor(_ConversationRuntime runtime, String model) {
    _removeTrailingLoaderFor(runtime);
    if (runtime.phase.isTerminal || runtime.phase == AgentPhase.idle) return;
    runtime.items.add(
      DesktopMessageItem(
        Message(text: '', isUser: false, isLoading: true, aiSource: model),
      ),
    );
  }

  bool get _attachmentUploading => _attachment?.isUploading == true;

  bool get _canSend {
    if (_isSending || _isLoading || _attachmentUploading) return false;
    return _textController.text.trim().isNotEmpty ||
        _attachment?.isDone == true;
  }

  void _cancelRequest() {
    _stopActiveEngine();
    if (!mounted) return;
    setState(() {
      _removeTrailingLoader();
      _isLoading = false;
      _phase = AgentPhase.cancelled;
      _phaseAction = null;
    });
  }

  void _stopActiveEngine() {
    _stopRuntime(_current);
  }

  void _stopRuntime(_ConversationRuntime runtime) {
    runtime.requestGeneration++;
    runtime.isSending = false;
    final engine = runtime.engine;
    final subscription = runtime.engineSub;
    runtime.engine = null;
    runtime.engineSub = null;
    unawaited(engine?.cancel() ?? Future<void>.value());
    if (subscription != null) unawaited(subscription.cancel());
    if (engine != null) unawaited(engine.dispose());
    _persistRuntime(runtime, immediate: true);
  }

  void _saveCurrentWork() {
    final work = _current.work;
    if (work == null) return;
    work
      ..resources = List<AgentResource>.from(AgentWorkspace.resources)
      ..projectPath = AgentWorkspace.primaryRoot;
    _persistRuntime(_current, immediate: true);
  }

  void _persistRuntime(_ConversationRuntime runtime, {bool immediate = false}) {
    final work = runtime.work;
    if (work == null) return;
    final timeline = <Map<String, dynamic>>[];
    for (final item in runtime.items) {
      switch (item) {
        case DesktopMessageItem(:final message):
          if (message.isLoading) continue;
          timeline.add({'kind': 'message', 'message': message.toJson()});
        case DesktopAgentItem(:final step, :final taskId):
          timeline.add({'kind': 'step', 'task_id': taskId, 'step_id': step.id});
      }
    }
    work
      ..timeline = timeline
      ..transportSessionId = runtime.sessionId
      ..modelKey = runtime.task?.modelKey ?? work.modelKey
      ..activeTaskId = runtime.isLoading ? runtime.task?.id : null;
    unawaited(WorkSessionStore.instance.save(work, immediate: immediate));
  }

  static String _errorText(Object e) {
    if (e is! ApiException) return 'مشکلی پیش آمده. لطفاً دوباره امتحان کنید.';
    if (e.isPaymentRequired) return e.message;
    if (e.isForbidden) return 'ارائه‌دهنده اجازهٔ استفاده از این مدل را نداد.';
    if (e.isProviderBusy) {
      return e.message.trim().isNotEmpty
          ? e.message
          : 'ارائه‌دهنده شلوغ است. چند لحظه دیگر دوباره امتحان کنید.';
    }
    if (e.isTooLarge) return 'حجم درخواست بیش از حد مجاز ارائه‌دهنده است.';
    if (e.isTimeout) return 'پاسخ ارائه‌دهنده دریافت نشد. دوباره امتحان کنید.';
    if (e.isNoInternet) return 'اتصال اینترنت برقرار نیست.';
    return e.message;
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const [
        'jpg',
        'jpeg',
        'png',
        'gif',
        'webp',
        'pdf',
        'txt',
      ],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;

    final f = result.files.first;
    if (f.bytes == null) return;

    final mime = _mimeOf(f.extension);
    final prepared = mime.startsWith('image/')
        ? await ImageCompressor.compressIfNeeded(f.bytes!, mime)
        : (bytes: f.bytes!, mime: mime);

    final attachment = PendingAttachment(
      name: f.name,
      mime: prepared.mime,
      bytes: prepared.bytes,
    );
    if (!mounted) return;
    setState(() => _attachment = attachment);
    _uploadAttachment(attachment);
  }

  Future<void> _uploadAttachment(PendingAttachment attachment) async {
    try {
      final ref = LocalAttachmentStore.put(
        bytes: attachment.bytes,
        name: attachment.name,
        mime: attachment.mime,
      );
      if (!mounted || !identical(_attachment, attachment)) return;
      setState(() {
        attachment.ref = ref;
        attachment.status = AttachmentUploadStatus.done;
      });
    } catch (e) {
      debugPrint('آماده‌سازی پیوست ناموفق: $e');
      if (!mounted || !identical(_attachment, attachment)) return;
      setState(() => attachment.status = AttachmentUploadStatus.failed);
    }
  }

  static String _mimeOf(String? ext) => switch ((ext ?? '').toLowerCase()) {
    'jpg' || 'jpeg' => 'image/jpeg',
    'png' => 'image/png',
    'gif' => 'image/gif',
    'webp' => 'image/webp',
    'pdf' => 'application/pdf',
    'txt' => 'text/plain',
    _ => 'application/octet-stream',
  };

  Future<void> _send() async {
    if (_isSending || _isLoading) return;
    final prompt = _textController.text.trim();
    final attachment = _attachment;
    if (prompt.isEmpty && attachment == null) return;

    if (attachment?.isFailed == true) {
      _snack('آپلود فایل ناموفق بود. «تلاش دوباره» را بزنید یا حذفش کنید.');
      return;
    }
    if (_attachmentUploading) {
      _snack('صبر کنید تا آپلود فایل تمام شود…');
      return;
    }

    final model = _resolveModelKey();
    if (model == null) {
      _snack(_noProviderNotice);
      return;
    }

    final runtime = _current;
    runtime.isSending = true;
    final generation = ++runtime.requestGeneration;
    final replyTo = _replyToMessage;
    final uploadedRefs = attachment?.isDone == true ? [attachment!.ref!] : null;
    final isImage = attachment?.isImage ?? false;
    final requestPrompt = prompt.isEmpty && attachment != null
        ? 'فایل پیوست‌شده را بررسی کن.'
        : prompt;

    _textController.clear();

    final agentActive = runtime.isWork;
    final workspaceSnapshot = AgentWorkspace.snapshot();

    setState(() {
      _replyToMessage = null;
      _attachment = null;
      _addMessage(
        Message(
          text: prompt,
          isUser: true,
          attachmentName: attachment?.name,
          attachmentMimeType: attachment?.mime,
          attachmentBytesList: (isImage && attachment != null)
              ? [Uint8List.fromList(attachment.bytes)]
              : null,
          replyToId: replyTo?.id,
          replyToPreview: replyTo != null
              ? _truncatePreview(replyTo.text)
              : null,
          replyToSource: replyTo?.isUser == true ? 'user' : replyTo?.aiSource,
        ),
      );
      _addMessage(
        Message(text: '', isUser: false, isLoading: true, aiSource: model),
      );
      _isLoading = true;
      _phase = AgentPhase.thinking;
      _phaseAction = null;
    });
    _scrollToBottom();
    _persistRuntime(runtime);

    final engine = _buildEngine(runtime, model, requestPrompt, generation);

    try {
      await AgentWorkspace.runWithSnapshot(
        workspaceSnapshot,
        () => engine.run(
          requestPrompt,
          uploadedRefs: uploadedRefs,
          replyContext: replyTo?.text,
          agentMode: agentActive,
        ),
      );
    } catch (e) {
      if (generation != runtime.requestGeneration || !mounted) return;
      void update() {
        _removeTrailingLoaderFor(runtime);
        runtime.items.add(
          DesktopMessageItem(
            Message(text: _errorText(e), isUser: false, aiSource: model),
          ),
        );
        runtime.isLoading = false;
        runtime.phase = AgentPhase.failed;
        runtime.phaseAction = null;
      }

      if (identical(_current, runtime)) {
        setState(update);
        _scrollToBottom();
      } else {
        update();
      }
      _persistRuntime(runtime, immediate: true);
    } finally {
      if (generation == runtime.requestGeneration) runtime.isSending = false;
      MemoryStore.instance.clearEphemeral(taskId: runtime.task?.id);
      _clearReconnect(runtime, generation);
    }
  }

  AgentEngine _buildEngine(
    _ConversationRuntime runtime,
    String model,
    String prompt,
    int generation,
  ) {
    final projectPath = AgentWorkspace.primaryRoot;
    final route = ref.read(desktopModelRouteProvider);
    final chain = [
      for (final key in buildFailoverChain(
        speaker: model,
        members: route.priority,
      ))
        if (ByokStore.byModelKey(key) != null) key,
    ];
    final localTaskGrants = <String>{};
    final recorder = AuditRecorder(modelKey: model);
    final adapter = FailoverModelAdapter(
      chain: chain.isEmpty ? [model] : chain,
      initialSessionId: runtime.sessionId,
      create: (modelKey, sessionId) {
        final byok = ByokStore.byModelKey(modelKey);
        if (byok == null) {
          throw ApiException(
            'ارائه‌دهندهٔ این مدل دیگر تنظیم نیست؛ در تنظیمات دوباره اضافه‌اش کن.',
            403,
            code: 'model_missing',
          );
        }
        return ByokModelAdapter(
          provider: byok,
          maxOutputTokens: byok.maxOutputTokens,
          conversation: runtime.byokConversation,
        );
      },
      onNotice: (message) {
        if (!mounted || generation != runtime.requestGeneration) return;
        _onAgentEvent(
          runtime,
          RecoverableError(message),
          model,
          prompt,
          generation,
        );
      },
      onSwitched: (from, to) {
        recorder.onEvent(ModelSwitched(from: from, to: to, reason: 'no_reply'));
        _onAgentEvent(
          runtime,
          RecoverableError(
            'ادامه با «${ModelConfig.label(to)}» — از کلید همان '
            'ارائه‌دهنده خرج می‌شود.',
          ),
          model,
          prompt,
          generation,
        );
        if (!mounted || generation != runtime.requestGeneration) return;
        setState(() => runtime.runningModelKey = to);
      },
      onReconnect: (reconnect) {
        if (!mounted || generation != runtime.requestGeneration) return;
        runtime.reconnect = reconnect;
        if (identical(_current, runtime)) setState(() {});
      },
    );
    runtime.failover = adapter;
    runtime.runningModelKey = adapter.modelKey;
    runtime.turnStartedAt = DateTime.now();

    final explicitMemory = MemoryStore.promptSection(
      MemoryStore.instance.relevantFor(projectPath, taskId: runtime.task?.id),
    );
    final projectContext = AgentTaskStore.instance.promptSectionForProject(
      projectPath,
    );
    final engine = AgentEngine(
      model: adapter,
      registry: _registry,
      readContextBudget: () {
        final key = runtime.runningModelKey ?? adapter.modelKey;
        final provider = ByokStore.byModelKey(key);
        if (provider == null) return ContextBudget.fallback;
        return ContextBudget(
          maxContextTokens: provider.contextTokens,
          reservedOutputTokens: provider.maxOutputTokens.clamp(
            512,
            provider.contextTokens ~/ 2,
          ),
        );
      },
      taintedInitially: () => runtime.work?.tainted ?? false,
      onTainted: () {
        final work = runtime.work;
        if (work == null || work.tainted) return;
        work.tainted = true;
        unawaited(WorkSessionStore.instance.save(work, immediate: true));
      },
      readPolicy: () => ref
          .read(agentPolicyProvider)
          .copyWith(taskGrants: Set<String>.unmodifiable(localTaskGrants)),
      onGrant: (permission, decision) {
        final notifier = ref.read(agentPolicyProvider.notifier);
        if (decision == PermissionDecision.allowSession) {
          notifier.grantForSession(permission);
        } else if (decision == PermissionDecision.allowTask) {
          localTaskGrants.add(permission);
        }
      },
      requestPermission: (step, preview) async {
        if (!mounted) return PermissionDecision.deny;
        unawaited(
          AgentNotifier.instance.permissionNeeded(
            title: preview.title,
            subtitle: preview.subtitle,
            origin: _originLabel(runtime),
          ),
        );
        final decision = await _serializeInteraction(
          () => showAgentPermissionDialog(
            context,
            step,
            preview,
            origin: _originLabel(runtime),
          ),
        );
        unawaited(AgentNotifier.instance.clearAll());
        return decision;
      },
      askQuestion: (question) async {
        if (!mounted) return null;
        unawaited(
          AgentNotifier.instance.questionAsked(
            question.text,
            origin: _originLabel(runtime),
          ),
        );
        final answer = await _serializeInteraction(
          () => showAgentQuestionDialog(context, question),
        );
        unawaited(AgentNotifier.instance.clearAll());
        return answer;
      },
      skillsSection: _skillsSection(prompt),
      memorySection: [
        explicitMemory,
        projectContext,
      ].where((part) => part.isNotEmpty).join('\n\n'),
      projectPath: projectPath,
      sessionScope: runtime.sessionScope,
      onTaskChanged: (task) {
        runtime.task = task;
        task.sessionId ??= runtime.sessionId;
        runtime.work?.activeTaskId = task.phase.isTerminal ? null : task.id;
        AgentTaskStore.instance.scheduleSave(task);
        _persistRuntime(runtime);
      },
    );

    final previousEngine = runtime.engine;
    final previousSubscription = runtime.engineSub;
    unawaited(previousEngine?.cancel() ?? Future<void>.value());
    if (previousSubscription != null) {
      unawaited(previousSubscription.cancel());
    }
    if (previousEngine != null) unawaited(previousEngine.dispose());
    runtime.engine = engine;
    runtime.engineSub = engine.events.listen((event) {
      recorder.modelKey = runtime.runningModelKey ?? model;
      recorder.onEvent(event);
      _onAgentEvent(runtime, event, model, prompt, generation);
    });
    return engine;
  }

  void _onAgentEvent(
    _ConversationRuntime runtime,
    AgentEvent event,
    String model,
    String prompt,
    int generation,
  ) {
    if (!mounted || generation != runtime.requestGeneration) return;

    void redraw(VoidCallback mutation) {
      if (identical(_current, runtime)) {
        setState(mutation);
      } else {
        mutation();
      }
      _persistRuntime(runtime);
    }

    switch (event) {
      case PhaseChanged(:final phase, :final action):
        redraw(() {
          runtime.phase = phase;
          runtime.phaseAction = action;
          if (phase.isTerminal) {
            _removeTrailingLoaderFor(runtime);
            runtime.isLoading = false;
          } else {
            _syncActivityLoaderFor(runtime, model);
          }
        });

      case PlanUpdated():
        break;

      case AssistantDelta(:final text, model: final actualModel):
        if (text.trim().isEmpty) {
          _scheduleStreamRedraw(runtime, () => _dropStreamingMessage(runtime));
          break;
        }
        _scheduleStreamRedraw(runtime, () {
          _removeTrailingLoaderFor(runtime);
          final existing = runtime.streamingMessageId;
          final index = existing == null
              ? -1
              : runtime.items.lastIndexWhere(
                  (item) =>
                      item is DesktopMessageItem && item.message.id == existing,
                );
          final msg = Message(
            id: existing,
            text: text,
            isUser: false,
            aiSource: actualModel ?? model,
          );
          if (index >= 0) {
            runtime.items[index] = DesktopMessageItem(msg);
          } else {
            runtime.streamingMessageId = msg.id;
            runtime.items.add(DesktopMessageItem(msg));
          }
        });

      case AssistantSaid(
        :final text,
        model: final actualModel,
        :final imageUrl,
        :final isFinal,
      ):
        redraw(() {
          _removeTrailingLoaderFor(runtime);
          _dropStreamingMessage(runtime);
          if (text.trim().isEmpty && imageUrl == null) return;
          final msg = Message(
            text: text,
            isUser: false,
            aiSource: actualModel ?? model,
            imageUrl: imageUrl,
          );
          runtime.items.add(DesktopMessageItem(msg));
          runtime.typingMessageId = (imageUrl == null && isFinal)
              ? msg.id
              : null;
        });
        if (isFinal) _maybeTitleSession(runtime, prompt, text);
        if (identical(_current, runtime)) _scrollToBottom();

      case StepStarted(:final step):
        redraw(() {
          _removeTrailingLoaderFor(runtime);
          final taskId = runtime.task?.id ?? 'task_unknown';
          runtime.items.add(DesktopAgentItem(step, taskId: taskId));
        });
        if (identical(_current, runtime)) _scrollToBottom();

      case StepProgress():
        _scheduleProgressRedraw(runtime);

      case StepUpdated():
        redraw(() {});

      case StepFinished():
        redraw(() {});
        if (identical(_current, runtime)) _scrollToBottom();

      case QuestionAsked() || QuestionAnswered() || PermissionRequested():
        redraw(() {});

      case ContextCompacted():
      case ModelSwitched():
        break;

      case RecoverableError(:final message):
        redraw(() {
          runtime.items.add(
            DesktopMessageItem(
              Message(text: message, isUser: false, aiSource: '_system'),
            ),
          );
          if (runtime.isLoading) _syncActivityLoaderFor(runtime, model);
        });
        if (identical(_current, runtime)) _scrollToBottom();

      case TaskStarted():
        runtime.task = event.task;
        _persistRuntime(runtime, immediate: true);
        break;

      case TaskFinished(:final task, :final error):
        runtime.task = task;
        redraw(() {
          _removeTrailingLoaderFor(runtime);
          runtime.isLoading = false;
          runtime.phaseAction = null;
          if (error != null || task.finalAnswer == null) {
            _dropStreamingMessage(runtime);
          }
          if (error != null) {
            runtime.items.add(
              DesktopMessageItem(
                Message(
                  text: error.trim().isEmpty
                      ? 'کار ناموفق بود. لطفاً دوباره امتحان کنید.'
                      : 'کار ناموفق بود: $error',
                  isUser: false,
                  aiSource: model,
                ),
              ),
            );
          }
        });
        unawaited(
          AgentNotifier.instance.taskFinished(
            ok: error == null && task.phase == AgentPhase.done,
            summary: task.finalAnswer?.trim().isNotEmpty == true
                ? task.finalAnswer!
                : task.goal,
          ),
        );
        _persistRuntime(runtime, immediate: true);
        if (identical(_current, runtime)) _scrollToBottom();
    }
  }

  void _dropStreamingMessage(_ConversationRuntime runtime) {
    final id = runtime.streamingMessageId;
    if (id == null) return;
    runtime.items.removeWhere(
      (item) => item is DesktopMessageItem && item.message.id == id,
    );
    runtime.streamingMessageId = null;
  }

  void _scheduleStreamRedraw(
    _ConversationRuntime runtime,
    void Function() mutate,
  ) {
    mutate();
    if (_streamRedrawTimer?.isActive == true) return;
    _streamRedrawTimer = Timer(const Duration(milliseconds: 60), () {
      if (!mounted || !identical(_current, runtime)) return;
      setState(_scrollToBottomIfPinned);
    });
  }

  void _scrollToBottomIfPinned() {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    if (position.maxScrollExtent - position.pixels > 120) return;
    _scrollController.jumpTo(position.maxScrollExtent);
  }

  void _scheduleProgressRedraw(_ConversationRuntime runtime) {
    if (_progressRedrawTimer?.isActive == true) return;
    _progressRedrawTimer = Timer(const Duration(milliseconds: 120), () {
      if (!mounted || !identical(_current, runtime)) return;
      setState(() {});
    });
  }

  void _maybeTitleSession(
    _ConversationRuntime runtime,
    String prompt,
    String reply,
  ) {
    final work = runtime.work;
    if (work != null) {
      if (work.title == 'Work جدید') {
        final clean = prompt.trim().replaceAll(RegExp(r'\s+'), ' ');
        work.title = clean.length <= 54 ? clean : '${clean.substring(0, 54)}…';
      }
      _persistRuntime(runtime, immediate: true);
      return;
    }
    final sessionId = runtime.sessionId;
    if (sessionId == null || _titleCoordinator.isKnown(sessionId)) return;
    if (reply.trim().isEmpty) return;
    _titleCoordinator.markKnown(sessionId);
  }

  String _skillsSection(String prompt) {
    final store = SkillStore.instance;
    final chosen = ref.read(activeSkillsProvider);
    final skills = chosen.isEmpty
        ? store.suggestFor(prompt)
        : store.all.where((s) => chosen.contains(s.id)).toList();
    return SkillStore.promptSection(skills);
  }

  String? _originLabel(_ConversationRuntime runtime) {
    final work = runtime.work;
    if (work == null) return null;
    final root = work.projectPath;
    final folder = root == null ? null : p.basename(root);
    final title = work.title.trim();
    return [
      if (title.isNotEmpty) title,
      if (folder != null && folder.isNotEmpty) folder,
    ].join('  ·  ');
  }

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text, textDirection: TextDirection.rtl)),
    );
  }

  void _handleReplyAction(Message message) {
    if (!message.isUser && message.aiSource != null) {
      ref
          .read(desktopModelRouteProvider.notifier)
          .setPrimary(message.aiSource!);
    }
    setState(() => _replyToMessage = message);
    _focusNode.requestFocus();
  }

  Future<void> _resendUserMessage(Message message) async {
    if (_isLoading || _isSending) {
      _snack(
        'این Work هنوز در حال اجراست؛ پس از پایان یا توقف دوباره بفرستید.',
      );
      return;
    }
    if (message.hasAttachment || message.hasAttachedImages) {
      _textController.text = message.text;
      _textController.selection = TextSelection.collapsed(
        offset: _textController.text.length,
      );
      _focusNode.requestFocus();
      _snack(
        'برای جلوگیری از ارسال ناقص، فایل را دوباره پیوست کنید؛ متن آماده شد.',
      );
      return;
    }
    _textController.text = message.text;
    _textController.selection = TextSelection.collapsed(
      offset: _textController.text.length,
    );
    await _send();
  }

  Future<void> _retryFailedTask() async {
    final runtime = _current;
    final task = runtime.task;
    if (!runtime.isWork ||
        task == null ||
        runtime.isLoading ||
        runtime.isSending ||
        !task.phase.isResumable) {
      return;
    }
    final model = _resolveModelKey(task.modelKey);
    if (model == null) {
      _snack(_noProviderNotice);
      return;
    }
    runtime.isSending = true;
    final generation = ++runtime.requestGeneration;
    final snapshot = AgentWorkspace.snapshot();
    if (mounted) {
      setState(() {
        runtime.phase = AgentPhase.thinking;
        runtime.phaseAction = 'ادامه از checkpoint';
        runtime.isLoading = true;
        _syncActivityLoaderFor(runtime, model);
      });
    }
    _persistRuntime(runtime, immediate: true);
    final engine = _buildEngine(runtime, model, task.goal, generation);
    try {
      await AgentWorkspace.runWithSnapshot(
        snapshot,
        () => engine.run(task.goal, agentMode: true, resumeTask: task),
      );
    } catch (error) {
      if (!mounted || generation != runtime.requestGeneration) return;
      setState(() {
        _removeTrailingLoaderFor(runtime);
        runtime.isLoading = false;
        runtime.phase = AgentPhase.failed;
        runtime.items.add(
          DesktopMessageItem(
            Message(
              text: 'ادامه از checkpoint ناموفق بود: ${_errorText(error)}',
              isUser: false,
              aiSource: model,
            ),
          ),
        );
      });
      _persistRuntime(runtime, immediate: true);
    } finally {
      if (generation == runtime.requestGeneration) runtime.isSending = false;
      _clearReconnect(runtime, generation);
    }
  }

  Future<void> _rollbackTask() async {
    final runtime = _current;
    final task = runtime.task;
    if (task == null ||
        runtime.isLoading ||
        runtime.isSending ||
        !task.hasChanges ||
        task.rolledBack) {
      return;
    }

    final workspace = AgentWorkspace.snapshot();
    if (!await showTaskRollbackDialog(context, task)) return;
    if (!mounted || !identical(_current, runtime)) return;

    int restored;
    try {
      restored = await AgentWorkspace.runWithSnapshot(
        workspace,
        () => AgentCheckpointStore.rollback(task.id),
      );
    } catch (e) {
      _snack('بازگرداندن ناموفق بود: $e');
      return;
    }
    if (!mounted) return;

    if (restored > 0) {
      task
        ..rolledBack = true
        ..note('تغییرات این کار به وضعیت پیش از شروع برگردانده شد.')
        ..touch();
      AgentTaskStore.instance.scheduleSave(task);
    }
    setState(() {
      runtime.items.add(
        DesktopMessageItem(
          Message(
            text: restored > 0
                ? '$restored مسیر به وضعیت پیش از این کار برگشت.'
                : 'چیزی برای بازگرداندن پیدا نشد؛ snapshot این کار دیگر '
                      'روی دیسک نیست.',
            isUser: false,
            aiSource: '_system',
          ),
        ),
      );
    });
    _persistRuntime(runtime, immediate: true);
    _scrollToBottom();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Column(
      children: [
        _topBar(isDark),
        const WinSeam(),
        Expanded(
          child: Stack(
            children: [
              Positioned.fill(
                child: IgnorePointer(
                  child: AnimatedOpacity(
                    opacity: _items.isEmpty ? 1 : 0,
                    duration: JMotion.heroFade,
                    curve: JMotion.curve,
                    child: JPageGlow(isDark: isDark),
                  ),
                ),
              ),
              _items.isEmpty ? _emptyState() : _messageList(isDark),
            ],
          ),
        ),
        if (_reconnect case final reconnect?)
          _ReconnectBar(
            state: reconnect,
            isDark: isDark,
            onSkip: reconnect.canSkip ? _skipToNextModel : null,
          ),
        _composerArea(),
      ],
    );
  }

  Widget _topBar(bool isDark) {
    final sidebarOpen = ref.watch(sidebarOpenProvider);
    final route = ref.watch(desktopModelRouteProvider);
    final primaryModel =
        _current.runningModelKey ??
        route.primary ??
        ref.watch(desktopModelsProvider).firstUsableModelKey ??
        '';
    ref.watch(agentWorkspaceProvider);

    return Container(
      height: WinMetrics.topBarHeight,
      color: WinSurface.layer(isDark),
      padding: const EdgeInsets.symmetric(horizontal: WinSpace.sm),
      child: Row(
        children: [
          if (!sidebarOpen)
            WinIconButton(
              icon: Icons.view_sidebar_outlined,
              tooltip: 'باز کردن نوار کنار  (Ctrl+B)',
              onTap: () => ref.read(sidebarOpenProvider.notifier).toggle(),
            ),
          Expanded(
            child: Directionality(
              textDirection: TextDirection.rtl,
              child: Row(
                children: [
                  const SizedBox(width: WinSpace.xs),
                  WinHoverable(
                    onTap: () => showDesktopModelRouteDialog(context),
                    radius: WinRadius.control,
                    tooltip: 'انتخاب مدل‌ها و اولویت‌بندی',
                    padding: const EdgeInsets.symmetric(
                      horizontal: WinSpace.md,
                      vertical: 6,
                    ),
                    child: Row(
                      children: [
                        Container(
                          height: 8,
                          width: 8,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: ModelConfig.mutedColor(
                              primaryModel,
                              isDark: isDark,
                            ),
                          ),
                        ),
                        const SizedBox(width: WinSpace.sm),
                        Text(
                          ModelConfig.label(primaryModel),
                          style: TextStyle(
                            fontSize: WinText.bodySm,
                            fontWeight: FontWeight.w700,
                            color: JSurface.text(isDark),
                          ),
                        ),
                        if (route.priority.length > 1) ...[
                          const SizedBox(width: WinSpace.sm),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: JColor.primary(
                                isDark,
                              ).withValues(alpha: .14),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              'مسیر ${route.priority.length} مدل',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: JColor.primary(isDark),
                              ),
                            ),
                          ),
                        ],
                        const SizedBox(width: WinSpace.xs),
                        Icon(
                          Icons.expand_more_rounded,
                          size: 16,
                          color: JSurface.muted(isDark),
                        ),
                      ],
                    ),
                  ),
                  const Spacer(),
                  _agentBadge(isDark),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _agentBadge(bool isDark) {
    final rootCount = AgentWorkspace.roots.length;
    final warn = rootCount == 0;
    final color = warn
        ? (isDark ? DarkColors.warning : LightColors.warning)
        : JColor.primary(isDark);

    return Padding(
      padding: const EdgeInsets.only(left: WinSpace.sm),
      child: WinHoverable(
        onTap: _isLoading ? null : () => showAgentPanel(context),
        radius: WinRadius.control,
        tooltip: warn
            ? 'حالت ایجنت روشن است اما پوشه‌ای انتخاب نشده'
            : 'دسترسی فایل فعال',
        padding: const EdgeInsets.symmetric(
          horizontal: WinSpace.md,
          vertical: 5,
        ),
        child: Row(
          children: [
            Icon(
              warn ? Icons.warning_amber_rounded : Icons.hub_outlined,
              size: 14,
              color: color,
            ),
            const SizedBox(width: 6),
            Text(
              warn
                  ? 'برای شروع پروژه، یک فولدر برای ذخیره‌سازی انتخاب کنید.'
                  : 'ایجنت',
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

  Widget _emptyState() => const AgentHome(key: ValueKey('agent_home'));

  bool get _showTrailingActivity {
    if (!_isLoading) return false;
    if (_items.isEmpty) return true;
    final last = _items.last;
    return !(last is DesktopMessageItem && last.message.isLoading);
  }

  Widget _messageList(bool isDark) => WinScrollbar(
    controller: _scrollController,
    child: ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(vertical: WinSpace.xl),
      itemCount: _items.length + (_showTrailingActivity ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == _items.length) {
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: WinMetrics.contentMaxWidth,
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: WinSpace.gutter,
                ),
                child: DesktopAiLoading(
                  key: const ValueKey('trailing_activity'),
                  phase: _phase,
                  action: _phaseAction,
                  startedAt: _current.turnStartedAt,
                  model: _current.runningModelKey ?? _activeModel,
                ),
              ),
            ),
          );
        }
        final item = _items[index];
        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: WinMetrics.contentMaxWidth,
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: WinSpace.gutter),
              child: _buildItem(item, index),
            ),
          ),
        );
      },
    ),
  );

  Widget _buildItem(DesktopChatItem item, int index) {
    switch (item) {
      case DesktopAgentItem(:final step):
        return ToolCallCard(key: ValueKey(item.key), step: step);
      case DesktopMessageItem(:final message):
        if (message.aiSource == '_system') {
          return _SystemNote(key: ValueKey(item.key), text: message.text);
        }
        if (message.isLoading) {
          return DesktopAiLoading(
            key: ValueKey('loading_${message.id}'),
            phase: _phase,
            action: _phaseAction,
            startedAt: _current.turnStartedAt,
            model: _current.runningModelKey ?? message.aiSource ?? _activeModel,
          );
        }
        if (message.isUser) {
          return DesktopUserMessage(
            key: ValueKey(item.key),
            message: message,
            onResend: () => _resendUserMessage(message),
          );
        }
        final ai = DesktopAiMessage(
          message: message,
          typingMessageId: _typingMessageId,
          isLoading: _isLoading,
          isSelecting: false,
          onReply: _handleReplyAction,
          onTypingDone: () {
            if (mounted) setState(() => _typingMessageId = null);
          },
        );
        final task = _current.task;
        final isLast =
            index == _items.length - 1 &&
            _current.isWork &&
            !_isLoading &&
            task != null;
        final retryable = isLast && task.phase.isResumable;
        final undoable = isLast && task.hasChanges && !task.rolledBack;
        if (!retryable && !undoable) {
          return KeyedSubtree(key: ValueKey(item.key), child: ai);
        }
        return Column(
          key: ValueKey(item.key),
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ai,
            _TaskActionBar(
              onRetry: retryable ? _retryFailedTask : null,
              onRollback: undoable ? _rollbackTask : null,
            ),
          ],
        );
    }
  }

  Widget _composerArea() => Padding(
    padding: const EdgeInsets.fromLTRB(
      WinSpace.lg,
      0,
      WinSpace.lg,
      WinSpace.lg,
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_attachment != null)
          AttachmentPreview(
            attachment: _attachment!,
            onClear: () => setState(() => _attachment = null),
            onRetry: () {
              final a = _attachment;
              if (a == null) return;
              setState(() => a.status = AttachmentUploadStatus.uploading);
              _uploadAttachment(a);
            },
          ),
        if (_replyToMessage != null)
          ReplyPreview(
            message: _replyToMessage!,
            onClear: () => setState(() => _replyToMessage = null),
            truncate: _truncatePreview,
          ),
        DesktopComposer(
          controller: _textController,
          focusNode: _focusNode,
          isLoading: _isLoading,
          canSend: _canSend,
          attachmentBusy: _attachmentUploading,
          onSend: _send,
          onCancel: _cancelRequest,
          onAttach: _pickFile,
          onManageResources: _isLoading ? null : () => showAgentPanel(context),
          onSelectProject: _isLoading
              ? null
              : (path) => ref
                    .read(agentWorkspaceProvider.notifier)
                    .selectProject(path),
          onRemoveResource: _isLoading
              ? null
              : (path) async {
                  await ref.read(agentWorkspaceProvider.notifier).remove(path);
                  _saveCurrentWork();
                  if (mounted) setState(() {});
                },
        ),
      ],
    ),
  );
}

class _SystemNote extends StatelessWidget {
  const _SystemNote({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: WinSpace.sm),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: WinSpace.md,
            vertical: 5,
          ),
          decoration: BoxDecoration(
            color: WinSurface.card(isDark),
            borderRadius: BorderRadius.circular(WinRadius.control),
            border: Border.all(color: WinSurface.hairline(isDark)),
          ),
          child: Text(
            text,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: JSurface.muted(isDark),
            ),
          ),
        ),
      ),
    );
  }
}

class _ReconnectBar extends StatelessWidget {
  const _ReconnectBar({
    required this.state,
    required this.isDark,
    required this.onSkip,
  });

  final FailoverReconnectState state;
  final bool isDark;
  final VoidCallback? onSkip;

  @override
  Widget build(BuildContext context) {
    final accent = JColor.primary(isDark);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        WinSpace.lg,
        0,
        WinSpace.lg,
        WinSpace.sm,
      ),
      child: Directionality(
        textDirection: TextDirection.rtl,
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: WinSpace.md,
            vertical: 9,
          ),
          decoration: BoxDecoration(
            color: accent.withValues(alpha: isDark ? .12 : .08),
            borderRadius: BorderRadius.circular(WinRadius.card),
            border: Border.all(color: accent.withValues(alpha: .32)),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2, color: accent),
              ),
              const SizedBox(width: WinSpace.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      state.message,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: JSurface.text(isDark),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'مدل فعلی: ${ModelConfig.label(state.modelKey)}',
                      style: TextStyle(
                        fontSize: 10.5,
                        color: JSurface.muted(isDark),
                      ),
                    ),
                  ],
                ),
              ),
              if (onSkip != null) ...[
                const SizedBox(width: WinSpace.sm),
                WinHoverable(
                  onTap: onSkip,
                  radius: WinRadius.control,
                  tooltip: state.nextModelKey == null
                      ? null
                      : 'ادامه از همین نقطه با '
                            '${ModelConfig.label(state.nextModelKey!)}',
                  padding: const EdgeInsets.symmetric(
                    horizontal: WinSpace.md,
                    vertical: 7,
                  ),
                  baseColor: accent.withValues(alpha: isDark ? .2 : .14),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.skip_next_rounded, size: 15, color: accent),
                      const SizedBox(width: 5),
                      Text(
                        'ادامه با مدل بعدی',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w800,
                          color: accent,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _TaskActionBar extends StatelessWidget {
  const _TaskActionBar({required this.onRetry, required this.onRollback});

  final VoidCallback? onRetry;
  final VoidCallback? onRollback;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = JColor.primary(isDark);
    final danger = isDark ? DarkColors.warning : LightColors.warning;

    Widget button({
      required IconData icon,
      required String label,
      required String tooltip,
      required Color color,
      required VoidCallback onTap,
    }) => WinHoverable(
      onTap: onTap,
      radius: WinRadius.control,
      tooltip: tooltip,
      padding: const EdgeInsets.symmetric(horizontal: WinSpace.md, vertical: 7),
      baseColor: color.withValues(alpha: isDark ? .12 : .07),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );

    final retry = onRetry;
    final rollback = onRollback;
    return Padding(
      padding: const EdgeInsets.only(top: WinSpace.sm, bottom: WinSpace.md),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (retry != null)
            button(
              icon: Icons.restart_alt_rounded,
              label: 'ادامه از نقطهٔ توقف',
              tooltip: 'ادامهٔ همان Task از checkpoint محلی',
              color: accent,
              onTap: retry,
            ),
          if (retry != null && rollback != null)
            const SizedBox(width: WinSpace.sm),
          if (rollback != null)
            button(
              icon: Icons.settings_backup_restore_rounded,
              label: 'بازگرداندن تغییرات',
              tooltip: 'فایل‌ها به وضعیت پیش از شروع این کار برمی‌گردند',
              color: danger,
              onTap: rollback,
            ),
        ],
      ),
    );
  }
}
