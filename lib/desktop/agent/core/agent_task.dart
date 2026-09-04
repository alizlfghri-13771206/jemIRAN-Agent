import '../tools/agent_tool.dart';
import 'agent_storage.dart';

enum AgentPhase {
  idle,

  thinking,

  planning,

  awaitingAnswer,

  awaitingPermission,

  executing,

  observing,

  verifying,

  interrupted,

  incomplete,

  done,
  failed,
  cancelled;

  String get label => switch (this) {
    idle => 'آماده',
    thinking => 'در حال فکر کردن',
    planning => 'در حال برنامه‌ریزی',
    awaitingAnswer => 'منتظر پاسخ شما',
    awaitingPermission => 'منتظر اجازهٔ شما',
    executing => 'در حال اجرای ابزارها',
    observing => 'در حال بررسی نتیجه',
    verifying => 'در حال راستی‌آزمایی',
    interrupted => 'متوقف‌شده',
    incomplete => 'ناتمام ماند',
    done => 'انجام شد',
    failed => 'ناموفق',
    cancelled => 'لغو شد',
  };

  bool get isTerminal =>
      this == done ||
      this == failed ||
      this == cancelled ||
      this == interrupted ||
      this == incomplete;

  bool get isResumable =>
      this == failed ||
      this == cancelled ||
      this == interrupted ||
      this == incomplete;
}

enum StepStatus {
  awaitingPermission,
  running,
  done,
  failed,

  denied,

  blocked,

  cancelled;

  bool get isTerminal => this != awaitingPermission && this != running;
}

class AgentStepRecord {
  AgentStepRecord({
    required this.call,
    required this.toolLabel,
    required this.risk,
    this.permission = '',
    this.status = StepStatus.awaitingPermission,
  }) : startedAt = DateTime.now();

  final ToolCall call;
  final String toolLabel;
  final ToolRisk risk;

  final String permission;

  StepStatus status;
  ToolResult? result;

  String? refusal;

  final List<String> progress = [];

  final DateTime startedAt;
  Duration? duration;

  int index = 0;
  int total = 0;

  String get id => call.id;

  String get headline {
    final target =
        call.str('path') ??
        call.str('command') ??
        call.str('query') ??
        call.str('pattern') ??
        call.str('question') ??
        call.str('url') ??
        call.str('action') ??
        call.str('from') ??
        call.str('target');
    if (target == null) return toolLabel;
    return target.startsWith('$toolLabel · ') ? target : '$toolLabel · $target';
  }
}

class PlanStep {
  PlanStep(this.text, {required this.id, this.done = false});

  final int id;
  final String text;
  bool done;
}

class QaPair {
  QaPair({required this.question, this.answer});

  final AgentQuestion question;
  String? answer;
}

class AgentTask {
  AgentTask({
    required this.goal,
    this.projectPath,
    String? id,
    DateTime? startedAt,
  }) : id = id ?? _newTaskId(),
       startedAt = startedAt ?? DateTime.now(),
       updatedAt = DateTime.now();

  static int _idSequence = 0;

  static String _newTaskId() =>
      'task_${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}_'
      '${(_idSequence++).toRadixString(36)}';

  final String id;

  final String goal;

  final String? projectPath;

  final DateTime startedAt;
  DateTime updatedAt;

  int? sessionId;
  String? modelKey;

  AgentPhase phase = AgentPhase.idle;

  String? currentAction;

  final List<PlanStep> plan = [];
  final List<QaPair> conversation = [];
  final List<AgentStepRecord> steps = [];

  final Set<String> grantedPermissions = {};

  final Set<String> changedPaths = {};

  final List<String> errors = [];

  int round = 0;

  int retryCount = 0;

  String? finalAnswer;

  bool cancelled = false;
  bool rolledBack = false;

  int untrackedChanges = 0;

  bool tainted = false;

  bool get hasUntrackedChanges => untrackedChanges > 0;

  int get completedSteps =>
      steps.where((s) => s.status == StepStatus.done).length;

  int get failedSteps =>
      steps.where((s) => s.status == StepStatus.failed).length;

  bool get hasChanges => changedPaths.isNotEmpty;

  void note(String error) {
    errors.add(error);
    if (errors.length > 50) errors.removeRange(0, errors.length - 50);
  }

  void touch() => updatedAt = DateTime.now();

  Map<String, dynamic> toJson() => {
    'version': 2,
    'id': id,
    'goal': SecretScrubber.scrub(goal),
    if (projectPath != null) 'project_path': projectPath,
    'started_at': startedAt.toIso8601String(),
    'updated_at': updatedAt.toIso8601String(),
    'phase': phase.name,
    if (currentAction != null)
      'current_action': SecretScrubber.scrub(currentAction!),
    if (sessionId != null) 'session_id': sessionId,
    if (modelKey != null) 'model': modelKey,
    'plan': [
      for (final item in plan)
        {
          'id': item.id,
          'text': SecretScrubber.scrub(item.text),
          'done': item.done,
        },
    ],
    'steps': [for (final step in steps) _stepToJson(step)],
    'permissions': grantedPermissions.toList(),
    'changed_paths': changedPaths.map(SecretScrubber.scrub).toList(),
    'errors': errors.map(SecretScrubber.scrub).toList(),
    'round': round,
    'retry_count': retryCount,
    if (finalAnswer != null) 'final_answer': SecretScrubber.scrub(finalAnswer!),
    'cancelled': cancelled,
    'rolled_back': rolledBack,
    'untracked_changes': untrackedChanges,
    'tainted': tainted,
  };

  static Map<String, dynamic> _stepToJson(AgentStepRecord step) => {
    'id': step.call.id,
    'tool': step.call.name,
    'target': SecretScrubber.scrub(step.headline),
    'label': SecretScrubber.scrub(step.toolLabel),
    'risk': step.risk.name,
    'status': step.status.name,
    'started_at': step.startedAt.toIso8601String(),
    if (step.duration != null) 'duration_ms': step.duration!.inMilliseconds,
    if (step.refusal != null) 'refusal': SecretScrubber.scrub(step.refusal!),
    if (step.result != null) ...{
      'result_ok': step.result!.ok,
      'result_summary': SecretScrubber.scrub(step.result!.summary),
      if (step.result!.error != null)
        'result_error': SecretScrubber.scrub(step.result!.error!),
      'result_changed_paths': step.result!.changedPaths
          .map(SecretScrubber.scrub)
          .toList(),
    },
    'index': step.index,
    'total': step.total,
  };

  factory AgentTask.fromJson(Map<String, dynamic> json) {
    final task = AgentTask(
      id: json['id']?.toString(),
      goal: json['goal']?.toString() ?? '',
      projectPath: json['project_path']?.toString(),
      startedAt: DateTime.tryParse(json['started_at']?.toString() ?? ''),
    );
    task.updatedAt =
        DateTime.tryParse(json['updated_at']?.toString() ?? '') ??
        task.startedAt;
    task.phase = AgentPhase.values.firstWhere(
      (value) => value.name == json['phase'],
      orElse: () => AgentPhase.interrupted,
    );
    task.currentAction = json['current_action']?.toString();
    task.sessionId = json['session_id'] is num
        ? (json['session_id'] as num).toInt()
        : int.tryParse(json['session_id']?.toString() ?? '');
    task.modelKey = json['model']?.toString();
    task.round = (json['round'] as num?)?.toInt() ?? 0;
    task.retryCount = (json['retry_count'] as num?)?.toInt() ?? 0;
    task.finalAnswer = json['final_answer']?.toString();
    task.cancelled = json['cancelled'] == true;
    task.rolledBack = json['rolled_back'] == true;
    task.untrackedChanges = (json['untracked_changes'] as num?)?.toInt() ?? 0;
    task.tainted = json['tainted'] == true;

    for (final raw in json['plan'] as List? ?? const []) {
      if (raw is! Map) continue;
      final id = (raw['id'] as num?)?.toInt() ?? (task.plan.length + 1);
      task.plan.add(
        PlanStep(
          raw['text']?.toString() ?? '',
          id: id,
          done: raw['done'] == true,
        ),
      );
    }
    for (final raw in json['steps'] as List? ?? const []) {
      if (raw is! Map) continue;
      final map = Map<String, dynamic>.from(raw);
      final call = ToolCall(
        id: map['id']?.toString(),
        name: map['tool']?.toString() ?? 'unknown',
        args: {'target': map['target']?.toString()},
      );
      final step =
          AgentStepRecord(
              call: call,
              toolLabel: map['label']?.toString() ?? call.name,
              risk: ToolRisk.values.firstWhere(
                (value) => value.name == map['risk'],
                orElse: () => ToolRisk.read,
              ),
              status: StepStatus.values.firstWhere(
                (value) => value.name == map['status'],
                orElse: () => StepStatus.failed,
              ),
            )
            ..index = (map['index'] as num?)?.toInt() ?? 0
            ..total = (map['total'] as num?)?.toInt() ?? 0
            ..refusal = map['refusal']?.toString();
      final durationMs = (map['duration_ms'] as num?)?.toInt();
      if (durationMs != null) {
        step.duration = Duration(milliseconds: durationMs);
      }
      if (map.containsKey('result_ok')) {
        step.result = ToolResult(
          ok: map['result_ok'] == true,
          summary: map['result_summary']?.toString() ?? '',
          error: map['result_error']?.toString(),
          changedPaths: (map['result_changed_paths'] as List? ?? const [])
              .map((value) => value.toString())
              .toList(),
        );
      }
      task.steps.add(step);
    }
    task.grantedPermissions.addAll(
      (json['permissions'] as List? ?? const []).map((e) => e.toString()),
    );
    task.changedPaths.addAll(
      (json['changed_paths'] as List? ?? const []).map((e) => e.toString()),
    );
    task.errors.addAll(
      (json['errors'] as List? ?? const []).map((e) => e.toString()),
    );
    return task;
  }
}
