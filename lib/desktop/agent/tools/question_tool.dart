import '../policy/agent_policy.dart';
import 'agent_tool.dart';

class AskUserTool extends AgentTool {
  const AskUserTool();

  @override
  String get name => 'ask_user';
  @override
  String get label => 'پرسش از کاربر';

  @override
  ToolRisk get risk => ToolRisk.read;

  @override
  String get permission => Perm.agentAsk;

  @override
  String get signature =>
      'ask_user {"question": "کدام پروژه؟", "options": ["الف", "ب"], "free_text": false, "placeholder": "..."} '
      '— وقتی اطلاعات لازم را نداری بپرس؛ حدس نزن.';

  @override
  Map<String, dynamic> get parameterSchema => const {
    'question': {'type': 'string'},
    'options': {
      'type': 'array',
      'items': {'type': 'string'},
      'description': 'گزینه‌های آماده',
    },
    'free_text': {'type': 'boolean', 'description': 'پاسخ دلخواه هم مجاز'},
    'placeholder': {'type': 'string'},
  };

  @override
  List<String> get requiredParameters => const ['question'];

  @override
  ToolPreview preview(ToolCall call) =>
      ToolPreview(title: 'پرسش از کاربر', subtitle: call.str('question'));

  @override
  Future<ToolResult> run(ToolCall call, ToolContext context) async {
    final question = call.str('question');
    if (question == null) {
      return ToolResult.failure('پارامتر question لازم است.');
    }

    final options = call.strings('options');
    final answer = await context.ask(
      AgentQuestion(
        text: question,
        options: options,
        freeText: options.isEmpty || call.flag('free_text'),
        placeholder: call.str('placeholder'),
      ),
    );

    if (answer == null) {
      return ToolResult(
        ok: false,
        summary: 'کاربر پاسخ نداد',
        error: 'unanswered',
        data: {
          'ok': false,
          'question': question,
          'answered': false,
          'note':
              'کاربر پاسخ نداد یا پنجره را بست. بدون این اطلاعات ادامه نده '
              'مگر اینکه راه دیگری داشته باشی.',
        },
      );
    }

    return ToolResult.success(
      summary: 'پاسخ: $answer',
      data: {'question': question, 'answered': true, 'answer': answer},
      detail: '$question\n← $answer',
    );
  }
}
