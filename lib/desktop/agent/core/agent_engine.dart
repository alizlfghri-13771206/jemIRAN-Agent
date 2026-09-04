import 'dart:async';
import 'dart:convert';

import '../browser/browser_session.dart';
import '../network/provider_exception.dart';
import '../policy/agent_policy.dart';
import '../tools/agent_tool.dart';
import '../tools/tool_registry.dart';
import 'agent_event.dart';
import 'agent_protocol.dart';
import 'context_budget.dart';
import 'agent_task.dart';
import 'model_adapter.dart';
import 'mutation_verifier.dart';
import 'tool_output_budget.dart';

class _BatchOutcome {
  _BatchOutcome(this.followUp, {this.toolResults, required this.contextTokens});

  final String followUp;

  final List<Map<String, dynamic>>? toolResults;

  final int contextTokens;
}

const _structuredResultsFollowUp =
    '[نتیجهٔ ابزارها از کانال ساختاری ارسال شد؛ پیام‌های نقش tool را تحلیل کن.]';

class AgentEngine {
  AgentEngine({
    required this.model,
    required this.registry,
    required this.readPolicy,
    required this.onGrant,
    required this.requestPermission,
    required this.askQuestion,
    this.skillsSection,
    this.memorySection,
    this.projectPath,
    this.onTaskChanged,
    this.sessionScope = 'default',
    this.taintedInitially,
    this.onTainted,
    this.readContextBudget,
  });

  final ContextBudget Function()? readContextBudget;

  final bool Function()? taintedInitially;

  final void Function()? onTainted;

  final ModelAdapter model;
  final ToolRegistry registry;

  final AgentPolicyState Function() readPolicy;

  final void Function(String permission, PermissionDecision decision) onGrant;

  final Future<PermissionDecision> Function(
    AgentStepRecord step,
    ToolPreview preview,
  )
  requestPermission;

  final Future<String?> Function(AgentQuestion question) askQuestion;

  final String? skillsSection;
  final String? memorySection;
  final String? projectPath;
  final void Function(AgentTask task)? onTaskChanged;

  final String sessionScope;

  int _compactionThresholdFor(List<Map<String, dynamic>>? tools) =>
      (readContextBudget?.call() ?? ContextBudget.fallback).thresholdForTools(
        tools,
      );

  final _events = StreamController<AgentEvent>.broadcast();

  Stream<AgentEvent> get events => _events.stream;

  AgentTask? _task;
  AgentTask? get task => _task;

  bool _cancelled = false;

  AgentPhase _activePhase = AgentPhase.executing;

  bool get isRunning => _task != null && !(_task!.phase.isTerminal);

  bool _allReadOnly(List<ToolCall> calls) => calls.every((call) {
    final tool = registry.find(call.name);
    return tool != null && tool.riskOf(call) == ToolRisk.read;
  });

  bool get isTainted => _task?.tainted ?? false;

  Future<void>? _cancelFuture;

  Future<void> cancel() {
    _cancelled = true;
    _task?.cancelled = true;
    return _cancelFuture ??= model.cancel();
  }

  Future<void> dispose() async {
    await cancel();
    await model.dispose();
    await _events.close();
  }

  void _emit(AgentEvent event) {
    if (!_events.isClosed) _events.add(event);
    final task = _task;
    if (task != null) onTaskChanged?.call(task);
  }

  void _phase(AgentPhase phase, {String? action}) {
    final task = _task;
    if (task != null) {
      task.phase = phase;
      task.currentAction = action;
    }
    _emit(PhaseChanged(phase, action: action));
  }

  Future<AgentTask> run(
    String goal, {
    List<String>? uploadedRefs,
    String? replyContext,
    bool agentMode = true,
    AgentTask? resumeTask,
  }) => BrowserSession.runScoped(
    sessionScope,
    () => _run(
      goal,
      uploadedRefs: uploadedRefs,
      replyContext: replyContext,
      agentMode: agentMode,
      resumeTask: resumeTask,
    ),
  );

  Future<AgentTask> _run(
    String goal, {
    List<String>? uploadedRefs,
    String? replyContext,
    bool agentMode = true,
    AgentTask? resumeTask,
  }) async {
    _cancelled = false;
    final task = resumeTask ?? AgentTask(goal: goal, projectPath: projectPath);
    if (taintedInitially?.call() ?? false) task.tainted = true;
    if (resumeTask != null) {
      task
        ..cancelled = false
        ..currentAction = null
        ..phase = AgentPhase.idle
        ..touch();
      task.retryCount += 1;
    }
    task.modelKey = model.modelKey;
    _task = task;
    _emit(TaskStarted(task));

    final policy = readPolicy();
    final limit = AgentProtocol.maxRounds(policy.mode);

    final resumeSection = resumeTask == null
        ? ''
        : _resumeCheckpointSection(task);
    final quoted = resumeSection.isEmpty
        ? AgentProtocol.replyQuote(replyContext)
        : '';
    List<Map<String, dynamic>>? pendingToolResults;
    String? pendingContextCheckpoint;
    var outgoing = agentMode
        ? '${AgentProtocol.preamble(registry: registry, mode: policy.mode, skillsSection: skillsSection, memorySection: memorySection)}\n'
              '${resumeSection.isEmpty ? '$quoted[پیام کاربر]\n$goal' : resumeSection}'
        : '$quoted$goal';

    var refsForThisTurn = uploadedRefs;
    var malformedCallRetries = 0;
    var emptyReplyRetries = 0;
    var unfinishedNudges = 0;
    var contextRecoveryUsed = false;
    final mutations = MutationVerifier();
    final outputBudget = ToolOutputBudget(
      readContextBudget?.call() ?? ContextBudget.fallback,
    );

    var sessionTokens = AgentProtocol.estimatedTokens(outgoing);

    try {
      for (var round = 0; round < limit; round++) {
        if (_cancelled) return _finish(task, AgentPhase.cancelled);

        final toolDefinitions = agentMode
            ? [for (final t in registry.available) t.toolSchema]
            : null;
        final compactionThreshold = _compactionThresholdFor(toolDefinitions);

        if (agentMode && sessionTokens > compactionThreshold) {
          _emit(
            RecoverableError('گفت‌وگو طولانی شد؛ در حال فشرده‌سازی زمینه…'),
          );
          _emit(ContextCompacted(round: round + 1, reason: 'threshold'));
          final checkpoint =
              '${AgentProtocol.preamble(registry: registry, mode: policy.mode, skillsSection: skillsSection, memorySection: memorySection)}\n'
              '${AgentProtocol.compactionSummary(task)}';
          await model.startFreshSession();
          task.sessionId = null;
          task.note('زمینهٔ گفت‌وگو فشرده شد (دور ${round + 1}).');
          if (pendingToolResults == null) {
            outgoing = checkpoint;
            sessionTokens = AgentProtocol.estimatedTokens(outgoing);
          } else {
            pendingContextCheckpoint = checkpoint;
            sessionTokens =
                AgentProtocol.estimatedTokens(checkpoint) +
                AgentProtocol.estimatedTokens(jsonEncode(pendingToolResults));
          }
        }

        _phase(AgentPhase.thinking);
        final streamed = StringBuffer();
        final ModelTurn turn;
        try {
          turn = await model.send(
            ModelRequest(
              text: outgoing,
              uploadedRefs: refsForThisTurn,
              tools: toolDefinitions,
              toolResults: pendingToolResults,
              contextCheckpoint: pendingContextCheckpoint,
              cacheSessionId: task.id,
              onAttemptStart: () {
                streamed.clear();
                _emit(AssistantDelta('', model: model.modelKey));
              },
              onDelta: (piece) {
                if (_cancelled) return;
                streamed.write(piece);
                final visible = AgentProtocol.stripLiveControlBlocks(
                  streamed.toString(),
                );
                if (visible.isEmpty) return;
                _emit(AssistantDelta(visible, model: model.modelKey));
              },
            ),
          );
        } on ApiException catch (error) {
          final overflow =
              error.code == 'context_limit' ||
              (error.isTooLarge && error.code == null);
          if (!overflow || contextRecoveryUsed) rethrow;
          contextRecoveryUsed = true;
          _emit(
            RecoverableError('زمینه از سقف رد شد؛ فشرده‌سازی و تلاش دوباره…'),
          );
          _emit(ContextCompacted(round: round + 1, reason: 'overflow'));
          final checkpoint =
              '${AgentProtocol.preamble(registry: registry, mode: policy.mode, skillsSection: skillsSection, memorySection: memorySection)}\n'
              '${AgentProtocol.compactionSummary(task)}';
          await model.startFreshSession();
          task.sessionId = null;
          task.note('زمینه از سقف سرور رد شد؛ فشرده شد (دور ${round + 1}).');
          if (pendingToolResults == null) {
            outgoing = checkpoint;
            sessionTokens = AgentProtocol.estimatedTokens(outgoing);
          } else {
            pendingContextCheckpoint = checkpoint;
            sessionTokens =
                AgentProtocol.estimatedTokens(checkpoint) +
                AgentProtocol.estimatedTokens(jsonEncode(pendingToolResults));
          }
          _phase(AgentPhase.thinking);
          continue;
        }
        pendingToolResults = null;
        pendingContextCheckpoint = null;
        task.sessionId = turn.sessionId ?? task.sessionId;
        task.modelKey = model.modelKey;
        task.round = round + 1;
        refsForThisTurn = null;

        if (_cancelled) return _finish(task, AgentPhase.cancelled);

        final structured = agentMode ? turn.toolCalls : null;
        final usedStructuredChannel =
            structured != null && structured.isNotEmpty;
        final calls = usedStructuredChannel
            ? structured
            : (agentMode
                  ? AgentProtocol.parseCalls(turn.text, registry)
                  : const <ToolCall>[]);
        final hasToolBlocks =
            !usedStructuredChannel &&
            agentMode &&
            AgentProtocol.hasCalls(turn.text);
        final oversizedBatch = calls.length > AgentProtocol.maxToolCallsPerTurn;
        final malformedCall =
            oversizedBatch ||
            (hasToolBlocks &&
                (calls.isEmpty ||
                    AgentProtocol.hasInvalidCalls(turn.text, registry)));

        final plan = AgentProtocol.parsePlan(turn.text);
        if (plan.isNotEmpty) {
          task.plan
            ..clear()
            ..addAll(plan);
          _phase(AgentPhase.planning);
          _emit(PlanUpdated(task.plan));
        }

        final truncated = turn.finishReason == 'length';
        final visible = truncated
            ? AgentProtocol.stripLiveControlBlocks(turn.text)
            : AgentProtocol.stripControlBlocks(turn.text, registry: registry);
        if (!malformedCall && (visible.isNotEmpty || turn.imageUrl != null)) {
          final footer = calls.isEmpty ? mutations.footer() : null;
          _emit(
            AssistantSaid(
              footer == null ? visible : '$visible\n\n$footer',
              model: model.modelKey,
              imageUrl: turn.imageUrl,
              isFinal: calls.isEmpty,
            ),
          );
        }

        if (malformedCall) {
          malformedCallRetries++;
          task.note(
            oversizedBatch
                ? 'مدل بیش از ${AgentProtocol.maxToolCallsPerTurn} فراخوان '
                      'ابزار را در یک نوبت فرستاد '
                : 'پاسخ مدل شامل فراخوان ابزار خراب یا ناشناخته بود '
                      '(تلاش $malformedCallRetries).',
          );
          if (malformedCallRetries <= 2) {
            _emit(
              RecoverableError(
                'قالب فراخوان ابزار درست نبود؛ در حال اصلاح خودکار…',
              ),
            );
            outgoing = AgentProtocol.malformedCallFeedback(registry);
            sessionTokens +=
                AgentProtocol.estimatedTokens(turn.text) +
                AgentProtocol.estimatedTokens(outgoing);
            _phase(AgentPhase.observing);
            continue;
          }
          _emit(
            RecoverableError(
              'مدل بعد از دو تلاش نتوانست فراخوان ابزار معتبری بسازد؛ '
              'هیچ عملیاتی اجرا نشد.',
            ),
          );
          return _finish(task, AgentPhase.failed);
        }

        malformedCallRetries = 0;

        if (calls.isEmpty) {
          if (agentMode && visible.isEmpty && turn.imageUrl == null) {
            emptyReplyRetries++;
            task.note('مدل پاسخ خالی برگرداند (تلاش $emptyReplyRetries).');
            if (emptyReplyRetries <= 2) {
              _emit(
                RecoverableError('پاسخ مدل خالی بود؛ در حال درخواست دوباره…'),
              );
              outgoing = AgentProtocol.emptyReplyFeedback();
              sessionTokens +=
                  AgentProtocol.estimatedTokens(turn.text) +
                  AgentProtocol.estimatedTokens(outgoing);
              _phase(AgentPhase.observing);
              continue;
            }
            _emit(
              RecoverableError(
                'مدل بعد از دو تلاش پاسخ متنی برنگرداند؛ '
                'با «ادامه با مدل بعدی» مدل دیگری را امتحان کنید.',
              ),
            );
            return _finish(task, AgentPhase.failed);
          }
          final unfinished = task.plan.any((step) => !step.done);
          if (agentMode &&
              unfinished &&
              unfinishedNudges == 0 &&
              task.plan.isNotEmpty) {
            unfinishedNudges++;
            task.note('جواب نهایی زودهنگام بود؛ بندهای ناتمام یادآوری شد.');
            _emit(RecoverableError('هنوز بندهایی از نقشه باز است؛ ادامه…'));
            outgoing = AgentProtocol.unfinishedPlanNudge(task);
            sessionTokens +=
                AgentProtocol.estimatedTokens(turn.text) +
                AgentProtocol.estimatedTokens(outgoing);
            _phase(AgentPhase.observing);
            continue;
          }

          task.finalAnswer = visible;
          if (agentMode && truncated) {
            task.note('پاسخ مدل به سقف طول خروجی خورد و ناتمام ماند.');
            _emit(
              RecoverableError(
                'پاسخ به سقف طول خروجی خورد؛ ادامه‌اش نوشته نشد.',
              ),
            );
            return _finish(task, AgentPhase.incomplete);
          }
          final stillOpen = task.plan.where((step) => !step.done).length;
          if (agentMode && stillOpen > 0) {
            task.note(
              'مدل جواب نهایی داد ولی $stillOpen بند نقشه تیک نخورده بود.',
            );
            return _finish(task, AgentPhase.incomplete);
          }
          return _finish(task, AgentPhase.done);
        }

        emptyReplyRetries = 0;

        _activePhase = task.changedPaths.isNotEmpty && _allReadOnly(calls)
            ? AgentPhase.verifying
            : AgentPhase.executing;
        _phase(_activePhase);
        final outcome = await _runBatch(
          verifier: mutations,
          budget: outputBudget,
          task,
          calls,
          usedStructuredChannel: usedStructuredChannel,
        );
        if (_cancelled) return _finish(task, AgentPhase.cancelled);

        if (outcome.followUp.isEmpty) {
          return _finish(task, AgentPhase.done);
        }

        outgoing = outcome.followUp;
        pendingToolResults = outcome.toolResults;
        sessionTokens +=
            AgentProtocol.estimatedTokens(turn.text) + outcome.contextTokens;
        _phase(AgentPhase.observing);
      }

      task.note('به سقف $limit دور رسید و بدون جواب نهایی متوقف شد.');
      _emit(
        AssistantSaid(
          AgentProtocol.roundLimitNotice(limit),
          model: model.modelKey,
          isFinal: true,
        ),
      );
      return _finish(task, AgentPhase.incomplete);
    } catch (e) {
      task.note('$e');
      task.phase = AgentPhase.failed;
      task.currentAction = null;
      _emit(PhaseChanged(AgentPhase.failed));
      _emit(TaskFinished(task, error: '$e'));
      return task;
    }
  }

  static String _resumeCheckpointSection(AgentTask task) {
    final completed = task.steps
        .where((step) => step.status == StepStatus.done)
        .map((step) => '✓ ${step.headline}')
        .take(20)
        .join('\n');
    final changed = task.changedPaths.take(20).join('\n');
    final lastErrors = task.errors.reversed
        .take(5)
        .toList()
        .reversed
        .join('\n');
    return '''
[ادامهٔ Task از checkpoint محلی]
این ادامهٔ همان Task است، نه درخواست تازه. عملیات موفق زیر را دوباره اجرا نکن.
هدف اصلی:
${task.goal}

عملیات موفق ثبت‌شده:
${completed.isEmpty ? 'موردی ثبت نشده است.' : completed}

مسیرهای تغییرکرده:
${changed.isEmpty ? 'موردی ثبت نشده است.' : changed}

آخرین خطاها:
${lastErrors.isEmpty ? 'خطایی ثبت نشده است.' : lastErrors}

ابتدا وضعیت فعلی را فقط با عملیات خواندنی راستی‌آزمایی کن؛ سپس صرفاً بخش باقی‌مانده را کامل کن. عملیات حساس موفق را هرگز تکرار نکن.
''';
  }

  AgentTask _finish(AgentTask task, AgentPhase phase) {
    task.phase = phase;
    task.currentAction = null;
    _emit(PhaseChanged(phase));
    _emit(TaskFinished(task));
    return task;
  }

  Future<_BatchOutcome> _runBatch(
    AgentTask task,
    List<ToolCall> calls, {
    bool usedStructuredChannel = false,
    MutationVerifier? verifier,
    ToolOutputBudget? budget,
  }) async {
    final executed = <({ToolCall call, ToolResult result})>[];
    final toolReplies = <({ToolCall call, ToolResult result})>[];
    final refusals = <String>[];

    void refuse(ToolCall call, String reason) {
      toolReplies.add((call: call, result: ToolResult.failure(reason)));
      refusals.add(AgentProtocol.refusalEnvelope(call, reason));
    }

    void markPendingCancelled() {
      for (final step in task.steps) {
        if (step.status.isTerminal) continue;
        step
          ..status = StepStatus.cancelled
          ..refusal = 'کار پیش از اجرای این گام لغو شد.';
        _emit(StepFinished(step));
      }
    }

    for (var i = 0; i < calls.length; i++) {
      if (_cancelled) {
        markPendingCancelled();
        break;
      }

      final call = calls[i];
      final tool = registry.find(call.name);
      if (tool == null) {
        refuse(call, 'ابزار ناشناخته: ${call.name}');
        continue;
      }

      final step =
          AgentStepRecord(
              call: call,
              toolLabel: tool.label,
              risk: tool.riskOf(call),
              permission: tool.permissionOf(call),
            )
            ..index = i + 1
            ..total = calls.length;
      task.steps.add(step);
      _emit(StepStarted(step));

      final verdict = readPolicy().evaluate(
        tool: tool,
        call: call,
        hardDenyReason: tool.hardDeny(call),
        tainted: isTainted,
      );

      if (verdict.outcome == PolicyOutcome.deny) {
        final reason = verdict.reason ?? 'این عملیات طبق سیاست مجاز نیست.';
        step
          ..status = StepStatus.blocked
          ..refusal = reason;
        _emit(StepFinished(step));
        refuse(call, reason);
        continue;
      }

      if (verdict.outcome == PolicyOutcome.ask) {
        _phase(AgentPhase.awaitingPermission, action: step.headline);
        final preview = tool.preview(call);
        _emit(PermissionRequested(step, preview));

        final decision = await requestPermission(step, preview);
        if (_cancelled) {
          markPendingCancelled();
          break;
        }

        if (decision == PermissionDecision.deny) {
          step
            ..status = StepStatus.denied
            ..refusal = 'کاربر اجازه نداد.';
          _emit(StepFinished(step));
          refuse(call, 'کاربر اجازه نداد.');
          continue;
        }

        if (decision != PermissionDecision.allowOnce) {
          final granted = tool.permissionOf(call);
          onGrant(granted, decision);
          task.grantedPermissions.add(granted);
        }
      }

      _phase(_activePhase, action: step.headline);
      step.status = StepStatus.running;
      _emit(StepUpdated(step));

      final startedAt = DateTime.now();
      ToolResult result;
      try {
        result = await tool.run(
          call,
          ToolContext(
            taskId: task.id,
            isCancelled: () => _cancelled,
            report: (line) {
              if (step.progress.length < 500) step.progress.add(line);
              _emit(StepProgress(step.id, line));
            },
            ask: (question) => _ask(task, question),
            sessionScope: sessionScope,
          ),
        );
      } catch (e) {
        result = ToolResult.failure('اجرای ابزار ناموفق: $e');
      }
      verifier?.record(call, result);
      if (budget != null) {
        result = budget.apply(call, result).result;
      }

      step
        ..duration = DateTime.now().difference(startedAt)
        ..result = result
        ..status = result.ok ? StepStatus.done : StepStatus.failed;

      if (!result.ok && result.error != null) {
        task.note('${call.name}: ${result.error}');
        _emit(RecoverableError('${tool.label}: ${result.error}'));
      }
      task.changedPaths.addAll(result.changedPaths);
      if (tool.yieldsUntrustedContent || result.untrusted) {
        if (!task.tainted) {
          task.tainted = true;
          onTainted?.call();
        }
      }
      if (result.ok &&
          !tool.checkpointsChanges &&
          tool.riskOf(call) != ToolRisk.read) {
        task.untrackedChanges++;
      }

      _emit(StepFinished(step));
      executed.add((call: call, result: result));
      toolReplies.add((call: call, result: result));
    }

    var planChanged = false;
    for (final item in executed) {
      if (!item.result.ok) continue;
      final stepId = item.call.stepId;
      if (stepId == null) continue;
      for (final planStep in task.plan) {
        if (planStep.id != stepId || planStep.done) continue;
        planStep.done = true;
        planChanged = true;
      }
    }
    if (planChanged) _emit(PlanUpdated(List.of(task.plan)));

    final injected = executed.fold<int>(
      0,
      (sum, item) =>
          sum + AgentProtocol.countControlFences(item.result.encode()),
    );
    if (injected > 0) {
      task.note('در خروجی ابزار $injected بلوک شبیه فراخوان دیده و بی‌اثر شد.');
      _emit(
        RecoverableError(
          'در محتوای خوانده‌شده متنی بود که شکل دستور داشت؛ به‌عنوان داده '
          'رفتار شد و اجرا نشد.',
        ),
      );
    }

    final buffer = StringBuffer();
    if (executed.isNotEmpty) {
      buffer.write(AgentProtocol.resultEnvelope(executed));
    }
    for (final refusal in refusals) {
      if (buffer.isNotEmpty) buffer.writeln();
      buffer.writeln(refusal);
    }

    final structuredResults = usedStructuredChannel
        ? [
            for (final item in toolReplies)
              {
                'tool_call_id': item.call.id,
                'name': item.call.name,
                'arguments': item.call.args,
                'content': item.result.encode(),
              },
          ]
        : null;
    final followUp = usedStructuredChannel
        ? _structuredResultsFollowUp
        : buffer.toString().trim();
    final structuredContextTokens = structuredResults == null
        ? 0
        : AgentProtocol.estimatedTokens(jsonEncode(structuredResults));
    return _BatchOutcome(
      followUp,
      toolResults: structuredResults,
      contextTokens:
          AgentProtocol.estimatedTokens(followUp) + structuredContextTokens,
    );
  }

  Future<String?> _ask(AgentTask task, AgentQuestion question) async {
    final pair = QaPair(question: question);
    task.conversation.add(pair);

    _phase(AgentPhase.awaitingAnswer, action: question.text);
    _emit(QuestionAsked(question));

    final answer = await askQuestion(question);
    pair.answer = answer;

    _emit(QuestionAnswered(question.id, answer));
    _phase(_activePhase);
    return answer;
  }
}
