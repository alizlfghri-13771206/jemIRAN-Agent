import '../tools/agent_tool.dart';
import 'agent_task.dart';

sealed class AgentEvent {
  AgentEvent() : at = DateTime.now();

  final DateTime at;
}

class TaskStarted extends AgentEvent {
  TaskStarted(this.task);
  final AgentTask task;
}

class PhaseChanged extends AgentEvent {
  PhaseChanged(this.phase, {this.action});
  final AgentPhase phase;

  final String? action;
}

class PlanUpdated extends AgentEvent {
  PlanUpdated(this.steps);
  final List<PlanStep> steps;
}

class AssistantDelta extends AgentEvent {
  AssistantDelta(this.text, {this.model});

  final String text;
  final String? model;
}

class AssistantSaid extends AgentEvent {
  AssistantSaid(this.text, {this.model, this.imageUrl, this.isFinal = false});
  final String text;
  final String? model;
  final String? imageUrl;

  final bool isFinal;
}

class StepStarted extends AgentEvent {
  StepStarted(this.step);
  final AgentStepRecord step;
}

class StepProgress extends AgentEvent {
  StepProgress(this.stepId, this.line);
  final String stepId;
  final String line;
}

class StepUpdated extends AgentEvent {
  StepUpdated(this.step);
  final AgentStepRecord step;
}

class StepFinished extends AgentEvent {
  StepFinished(this.step);
  final AgentStepRecord step;
}

class PermissionRequested extends AgentEvent {
  PermissionRequested(this.step, this.preview);
  final AgentStepRecord step;
  final ToolPreview preview;
}

class QuestionAsked extends AgentEvent {
  QuestionAsked(this.question);
  final AgentQuestion question;
}

class QuestionAnswered extends AgentEvent {
  QuestionAnswered(this.questionId, this.answer);
  final String questionId;
  final String? answer;
}

class RecoverableError extends AgentEvent {
  RecoverableError(this.message);
  final String message;
}

class ContextCompacted extends AgentEvent {
  ContextCompacted({required this.round, required this.reason});

  final int round;

  final String reason;
}

class ModelSwitched extends AgentEvent {
  ModelSwitched({required this.from, required this.to, required this.reason});

  final String from;
  final String to;

  final String reason;
}

class TaskFinished extends AgentEvent {
  TaskFinished(this.task, {this.error});
  final AgentTask task;

  final String? error;
}
