import 'dart:io';

import 'package:path/path.dart' as p;

import '../acquisition/docx_builder.dart';
import '../agent_workspace.dart';
import '../core/checkpoint_store.dart';
import '../policy/agent_policy.dart';
import 'agent_tool.dart';

class MakeDocxTool extends AgentTool {
  const MakeDocxTool();

  @override
  String get name => 'make_docx';
  @override
  String get label => 'ساخت فایل Word';
  @override
  ToolRisk get risk => ToolRisk.write;
  @override
  String get permission => Perm.filesystemCreate;
  @override
  String get signature =>
      'make_docx {"output":"story.docx","title":"...","content":"متن کامل","author":"...","rtl":false} '
      '— فایل واقعی Word می‌سازد؛ برای آن Python، Office یا نصب پکیج لازم نیست.';

  @override
  Map<String, dynamic> get parameterSchema => const {
    'output': {'type': 'string', 'description': 'پسوند .docx'},
    'content': {'type': 'string', 'description': 'خط خالی = پاراگراف تازه'},
    'title': {'type': 'string'},
    'author': {'type': 'string'},
    'rtl': {'type': 'boolean', 'description': 'راست‌به‌چپ'},
  };

  @override
  List<String> get requiredParameters => const ['output', 'content'];

  @override
  String? hardDeny(ToolCall call) {
    final raw = call.str('output');
    if (raw == null) return null;
    final absolute = AgentWorkspace.toAbsolute(_withExtension(raw));
    if (absolute == null) return null;
    final owner = AgentWorkspace.owner(absolute);
    if (owner == null) return 'مسیر خروجی «$raw» بیرون از منابع مجاز است.';
    if (!owner.canWrite) {
      return 'اجازهٔ نوشتن در «${owner.name}» داده نشده است.';
    }
    return null;
  }

  @override
  ToolPreview preview(ToolCall call) => ToolPreview(
    title: 'ساخت فایل Word',
    subtitle: call.str('output'),
    body: _clip(call.str('content') ?? ''),
    bodyLanguage: 'text',
  );

  @override
  Future<ToolResult> run(ToolCall call, ToolContext context) async {
    final rawOutput = call.str('output');
    final content = call.str('content');
    if (rawOutput == null) {
      return ToolResult.failure('پارامتر output لازم است.');
    }
    if (content == null || content.trim().isEmpty) {
      return ToolResult.failure('پارامتر content و متن سند لازم است.');
    }
    if (content.length > 1000000) {
      return ToolResult.failure('متن سند از سقف یک میلیون نویسه بزرگ‌تر است.');
    }

    final output = _withExtension(rawOutput);
    final path = AgentWorkspace.toAbsolute(output);
    if (path == null) {
      return ToolResult.failure(
        'مسیر خروجی قابل حل نیست؛ ابتدا یک پوشهٔ کاری انتخاب کنید.',
      );
    }
    final owner = AgentWorkspace.owner(path);
    if (owner == null || !owner.canWrite) {
      return ToolResult.failure('اجازهٔ نوشتن در «$output» وجود ندارد.');
    }
    if (!await AgentCheckpointStore.capture(context.taskId, path)) {
      return ToolResult.failure(
        'ثبت نقطهٔ بازگشت فایل ممکن نشد؛ چیزی نوشته نشد.',
      );
    }

    try {
      context.report('در حال ساخت فایل Word…');
      final bytes = DocxBuilder.build(
        content: content,
        title: call.str('title'),
        author: call.str('author'),
        rtl: call.flag('rtl'),
      );
      final target = File(path);
      await target.parent.create(recursive: true);
      final stamp = DateTime.now().microsecondsSinceEpoch;
      final temp = File('$path.$stamp.tmp');
      final backup = File('$path.$stamp.bak');
      try {
        await temp.writeAsBytes(bytes, flush: true);
        if (await target.exists()) await target.rename(backup.path);
        await temp.rename(path);
        if (await backup.exists()) await backup.delete();
      } catch (_) {
        if (!await target.exists() && await backup.exists()) {
          await backup.rename(path);
        }
        rethrow;
      } finally {
        if (await temp.exists()) await temp.delete();
      }

      final shown = AgentWorkspace.display(path);
      return ToolResult.success(
        summary: '$shown ساخته شد (${_size(bytes.length)})',
        data: {'path': path, 'bytes': bytes.length, 'engine': 'openxml'},
        detail: path,
        changedPaths: [path],
      );
    } catch (error) {
      return ToolResult.failure('ساخت فایل Word ناموفق بود: $error');
    }
  }

  static String _withExtension(String value) =>
      p.extension(value).toLowerCase() == '.docx' ? value : '$value.docx';

  static String _clip(String value) =>
      value.length <= 600 ? value : '${value.substring(0, 600)}\n…';

  static String _size(int bytes) => bytes < 1024
      ? '$bytes بایت'
      : '${(bytes / 1024).toStringAsFixed(1)} کیلوبایت';
}
