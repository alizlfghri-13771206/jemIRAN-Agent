import 'dart:convert';

enum ToolRisk { read, write, network, execute, destructive }

class ToolResult {
  const ToolResult({
    required this.ok,
    required this.summary,
    this.data = const {},
    this.detail,
    this.error,
    this.changedPaths = const [],
    this.untrusted = false,
  });

  final bool untrusted;

  final bool ok;

  final String summary;

  final Map<String, dynamic> data;

  final String? detail;

  final String? error;

  final List<String> changedPaths;

  factory ToolResult.failure(String message, {Map<String, dynamic>? data}) =>
      ToolResult(
        ok: false,
        summary: message,
        error: message,
        data: {'ok': false, 'error': message, ...?data},
      );

  factory ToolResult.success({
    required String summary,
    Map<String, dynamic> data = const {},
    String? detail,
    List<String> changedPaths = const [],
    bool untrusted = false,
  }) => ToolResult(
    ok: true,
    summary: summary,
    data: {'ok': true, ...data},
    detail: detail,
    changedPaths: changedPaths,
    untrusted: untrusted,
  );

  String encode() =>
      jsonEncode(data.containsKey('ok') ? data : {'ok': ok, ...data});
}

class ToolCall {
  ToolCall({required this.name, required this.args, String? id, this.stepId})
    : id = id ?? _newId();

  static int _sequence = 0;

  static String _newId() =>
      'tc_${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}'
      '_${(_sequence++).toRadixString(36)}';

  final String id;
  final String name;
  final Map<String, dynamic> args;

  final int? stepId;

  String? str(String key) {
    final v = args[key];
    if (v == null) return null;
    final s = v.toString();
    return s.isEmpty ? null : s;
  }

  int? integer(String key) {
    final v = args[key];
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse((v ?? '').toString());
  }

  bool flag(String key, {bool fallback = false}) {
    final v = args[key];
    if (v is bool) return v;
    if (v == null) return fallback;
    return v.toString().toLowerCase() == 'true';
  }

  List<String> strings(String key) {
    final v = args[key];
    if (v is List) return v.map((e) => e.toString()).toList();
    if (v is String && v.isNotEmpty) return [v];
    return const [];
  }
}

class ToolPreview {
  const ToolPreview({
    required this.title,
    this.subtitle,
    this.body,
    this.bodyLanguage,
    this.warnings = const [],
  });

  final String title;

  final String? subtitle;

  final String? body;

  final String? bodyLanguage;

  final List<String> warnings;
}

abstract class AgentTool {
  const AgentTool();

  String get name;

  String get label;

  ToolRisk get risk;

  bool get yieldsUntrustedContent => false;

  String get permission;

  String permissionOf(ToolCall call) => permission;

  String get signature;

  String get purpose {
    final dash = signature.indexOf('—');
    if (dash < 0) return signature;
    final prose = signature.substring(dash + 1).trim();
    return prose.isEmpty ? signature : prose;
  }

  Map<String, dynamic> get parameterSchema => const <String, dynamic>{};

  List<String> get requiredParameters => const <String>[];

  static const planStepProperty = <String, dynamic>{
    'type': 'integer',
    'minimum': 1,
  };

  Map<String, dynamic> get toolSchema => {
    'type': 'function',
    'function': {
      'name': name,
      'description': '$label — $purpose',
      'parameters': {
        'type': 'object',
        'properties': <String, dynamic>{
          ...parameterSchema,
          'step': planStepProperty,
        },
        if (requiredParameters.isNotEmpty) 'required': requiredParameters,
        'additionalProperties': true,
      },
    },
  };

  bool get available => true;

  ToolRisk riskOf(ToolCall call) => risk;

  bool get checkpointsChanges => true;

  String? hardDeny(ToolCall call) => null;

  ToolPreview preview(ToolCall call);

  Future<ToolResult> run(ToolCall call, ToolContext context);
}

class ToolContext {
  const ToolContext({
    required this.taskId,
    required this.isCancelled,
    required this.report,
    required this.ask,
    this.sessionScope = 'default',
  });

  final String taskId;

  final String sessionScope;

  final bool Function() isCancelled;

  final void Function(String line) report;

  final Future<String?> Function(AgentQuestion question) ask;
}

class AgentQuestion {
  AgentQuestion({
    required this.text,
    this.options = const [],
    this.freeText = false,
    this.placeholder,
    String? id,
  }) : id = id ?? _newId();

  static int _sequence = 0;

  static String _newId() =>
      'q_${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}'
      '_${(_sequence++).toRadixString(36)}';

  final String id;
  final String text;

  final List<String> options;

  final bool freeText;

  final String? placeholder;
}
