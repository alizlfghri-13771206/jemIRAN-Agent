import '../core/agent_event.dart';
import 'audit_log.dart';

class AuditRecorder {
  AuditRecorder({required this.modelKey});

  String modelKey;

  String? _taskId;

  void onEvent(AgentEvent event) {
    switch (event) {
      case TaskStarted(:final task):
        _taskId = task.id;
        AuditLog.record(
          AuditKind.taskStarted,
          task: task.id,
          model: modelKey,
          fields: {'goal': task.goal},
        );

      case TaskFinished(:final task, :final error):
        AuditLog.record(
          AuditKind.taskFinished,
          task: task.id,
          model: modelKey,
          fields: {
            'phase': task.phase.name,
            'changed_paths': task.changedPaths.length,
            'error': ?error,
          },
        );

      case PermissionRequested(:final step, :final preview):
        AuditLog.record(
          AuditKind.permission,
          task: _taskId,
          model: modelKey,
          fields: {
            'tool': step.call.name,
            'permission': step.permission,
            'risk': step.risk.name,
            'target': preview.subtitle ?? preview.title,
          },
        );

      case StepFinished(:final step):
        AuditLog.record(
          AuditKind.tool,
          task: _taskId,
          model: modelKey,
          fields: {
            'tool': step.call.name,
            'permission': step.permission,
            'risk': step.risk.name,
            'status': step.status.name,
            'target': step.headline,
            'ok': step.result?.ok,
            if (step.result?.error != null) 'error': step.result!.error,
          },
        );

      case ContextCompacted(:final round, :final reason):
        AuditLog.record(
          AuditKind.compaction,
          task: _taskId,
          model: modelKey,
          fields: {'round': round, 'reason': reason},
        );

      case ModelSwitched(:final from, :final to, :final reason):
        AuditLog.record(
          AuditKind.modelSwitch,
          task: _taskId,
          model: modelKey,
          fields: {'from': from, 'to': to, 'reason': reason},
        );

      case RecoverableError(:final message):
        AuditLog.record(
          AuditKind.error,
          task: _taskId,
          model: modelKey,
          fields: {'message': message},
        );

      default:
        break;
    }
  }
}
