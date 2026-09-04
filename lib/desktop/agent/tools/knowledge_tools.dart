import '../agent_workspace.dart';
import '../core/agent_storage.dart';
import '../memory/agent_memory.dart';
import '../policy/agent_policy.dart';
import '../skills/agent_skill.dart';
import 'agent_tool.dart';

class SaveSkillTool extends AgentTool {
  const SaveSkillTool();

  @override
  String get name => 'save_skill';
  @override
  String get label => 'ثبت مهارت';

  @override
  ToolRisk get risk => ToolRisk.write;

  @override
  String get permission => Perm.skillWrite;

  @override
  bool get available => AgentStorage.root != null;

  @override
  String get signature =>
      'save_skill {"name": "دیباگ Flutter", "purpose": "...", "patterns": [...], '
      '"diagnostic_steps": [...], "known_errors": [...], "solutions": [...], '
      '"warnings": [...], "tools": [...], "tags": [...]} '
      '— دانشی که در این کار به دست آمد را برای پروژه‌های بعدی ذخیره کن. '
      'هیچ رمز، توکن، کلید یا مسیر شخصی داخلش نگذار.';

  @override
  Map<String, dynamic> get parameterSchema => const {
    'name': {'type': 'string'},
    'purpose': {'type': 'string', 'description': 'کِی به درد می‌خورد'},
    'patterns': {
      'type': 'array',
      'items': {'type': 'string'},
      'description': 'نشانه‌های تشخیص',
    },
    'diagnostic_steps': {
      'type': 'array',
      'items': {'type': 'string'},
      'description': 'به ترتیب',
    },
    'known_errors': {
      'type': 'array',
      'items': {'type': 'string'},
    },
    'solutions': {
      'type': 'array',
      'items': {'type': 'string'},
    },
    'warnings': {
      'type': 'array',
      'items': {'type': 'string'},
    },
    'tools': {
      'type': 'array',
      'items': {'type': 'string'},
    },
    'tags': {
      'type': 'array',
      'items': {'type': 'string'},
    },
  };

  @override
  List<String> get requiredParameters => const ['name', 'purpose'];

  @override
  ToolPreview preview(ToolCall call) {
    final skill = _build(call);
    return ToolPreview(
      title: 'ثبت مهارت',
      subtitle: call.str('name'),
      body: skill?.promptDigest(),
      warnings: const [
        'مهارت‌ها در پروژه‌های بعدی هم استفاده می‌شوند؛ محتوایش را ببینید.',
      ],
    );
  }

  static AgentSkill? _build(ToolCall call) {
    final name = call.str('name');
    if (name == null) return null;

    List<String> clean(String key, [String? alt]) => [
      for (final item in [
        ...call.strings(key),
        if (alt != null) ...call.strings(alt),
      ])
        SecretScrubber.scrub(item),
    ];

    return AgentSkill(
      id: AgentSkill.slugify(name),
      name: SecretScrubber.scrub(name),
      purpose: SecretScrubber.scrub(call.str('purpose') ?? ''),
      patterns: clean('patterns'),
      diagnosticSteps: clean('diagnostic_steps', 'steps'),
      knownErrors: clean('known_errors', 'errors'),
      solutions: clean('solutions'),
      warnings: clean('warnings'),
      tools: clean('tools'),
      tags: clean('tags'),
    );
  }

  @override
  Future<ToolResult> run(ToolCall call, ToolContext context) async {
    final skill = _build(call);
    if (skill == null) {
      return ToolResult.failure('پارامتر name لازم است.');
    }
    if (skill.purpose.isEmpty && skill.solutions.isEmpty) {
      return ToolResult.failure(
        'مهارت بدون purpose و solutions بی‌فایده است. محتوای واقعی بده.',
      );
    }

    await SkillStore.instance.load();
    final existing = SkillStore.instance.find(skill.id) != null;
    final ok = await SkillStore.instance.save(skill);
    if (!ok) return ToolResult.failure('ذخیرهٔ مهارت روی دیسک ممکن نشد.');

    return ToolResult.success(
      summary: existing
          ? 'مهارت «${skill.name}» به‌روز شد'
          : 'مهارت «${skill.name}» ثبت شد',
      data: {'id': skill.id, 'name': skill.name, 'updated': existing},
      detail: skill.promptDigest(),
    );
  }
}

class ListSkillsTool extends AgentTool {
  const ListSkillsTool();

  @override
  String get name => 'list_skills';
  @override
  String get label => 'فهرست مهارت‌ها';
  @override
  ToolRisk get risk => ToolRisk.read;
  @override
  String get permission => Perm.skillRead;
  @override
  bool get available => AgentStorage.root != null;

  @override
  String get signature =>
      'list_skills {} — مهارت‌های ذخیره‌شده را ببین تا تکراری نسازی';

  @override
  ToolPreview preview(ToolCall call) =>
      const ToolPreview(title: 'فهرست مهارت‌ها');

  @override
  Future<ToolResult> run(ToolCall call, ToolContext context) async {
    await SkillStore.instance.load();
    final skills = SkillStore.instance.all;
    return ToolResult.success(
      summary: '${skills.length} مهارت',
      data: {
        'skills': [
          for (final s in skills)
            {'id': s.id, 'name': s.name, 'purpose': s.purpose, 'tags': s.tags},
        ],
      },
      detail: skills.isEmpty
          ? '(هنوز مهارتی ثبت نشده)'
          : skills.map((s) => '• ${s.name} — ${s.purpose}').join('\n'),
    );
  }
}

class RememberTool extends AgentTool {
  const RememberTool();

  @override
  String get name => 'remember';
  @override
  String get label => 'به‌یادسپاری';
  @override
  ToolRisk get risk => ToolRisk.write;
  @override
  String get permission => Perm.memoryWrite;
  @override
  bool get available => AgentStorage.root != null;

  @override
  String get signature =>
      'remember {"scope": "user|project|task", "text": "..."} '
      '— زمینه‌ای که در گفت‌وگوهای بعدی لازم است. راز و رمز ذخیره نکن.';

  @override
  Map<String, dynamic> get parameterSchema => const {
    'scope': {
      'type': 'string',
      'enum': ['user', 'project', 'task'],
    },
    'text': {'type': 'string', 'description': 'راز و توکن ننویس'},
  };

  @override
  List<String> get requiredParameters => const ['scope', 'text'];

  @override
  ToolPreview preview(ToolCall call) => ToolPreview(
    title: 'به‌یادسپاری',
    subtitle: MemoryScope.parse(call.str('scope')).label,
    body: call.str('text'),
  );

  @override
  Future<ToolResult> run(ToolCall call, ToolContext context) async {
    final text = call.str('text');
    if (text == null) return ToolResult.failure('پارامتر text لازم است.');

    final scope = MemoryScope.parse(call.str('scope'));
    await MemoryStore.instance.load();
    final note = await MemoryStore.instance.remember(
      scope: scope,
      text: text,
      projectPath: scope == MemoryScope.project
          ? AgentWorkspace.primaryRoot
          : null,
      taskId: scope == MemoryScope.task ? context.taskId : null,
    );

    return ToolResult.success(
      summary: 'به یاد سپرده شد (${scope.label})',
      data: {'id': note.id, 'scope': scope.name, 'text': note.text},
      detail: note.text,
    );
  }
}

const knowledgeTools = <AgentTool>[
  SaveSkillTool(),
  ListSkillsTool(),
  RememberTool(),
];
