import 'dart:io';

import '../acquisition/pdf_builder.dart';
import '../agent_workspace.dart';
import '../core/checkpoint_store.dart';
import '../browser/chrome_locator.dart';
import '../policy/agent_policy.dart';
import 'agent_tool.dart';

class MakePdfTool extends AgentTool {
  const MakePdfTool();

  @override
  String get name => 'make_pdf';
  @override
  String get label => 'ساخت PDF';

  @override
  ToolRisk get risk => ToolRisk.write;

  @override
  String get permission => Perm.filesystemCreate;

  @override
  bool get available => AgentWorkspace.hasRoot && ChromeLocator.isAvailable;

  @override
  String get signature =>
      'make_pdf {"output": "گزارش.pdf", "source_path": "notes.md"} '
      'یا {"output": "...", "markdown": "متن مستقیم", "title": "..."} '
      '— Markdown یا HTML را به PDF تبدیل می‌کند. نیازی به نصب چیزی نیست.';

  @override
  Map<String, dynamic> get parameterSchema => const {
    'output': {'type': 'string', 'description': 'پسوند .pdf'},
    'source_path': {'type': 'string', 'description': 'فایل md یا html'},
    'markdown': {'type': 'string', 'description': 'متن مستقیم'},
    'html': {'type': 'string', 'description': 'متن مستقیم'},
    'title': {'type': 'string'},
  };

  @override
  List<String> get requiredParameters => const ['output'];

  @override
  String? hardDeny(ToolCall call) {
    final output = call.str('output');
    if (output == null) return null;

    final absolute = AgentWorkspace.toAbsolute(output);
    if (absolute == null) return null;

    final owner = AgentWorkspace.owner(absolute);
    if (owner == null) return 'مسیر خروجی «$output» بیرون از منابع مجاز است.';
    if (!owner.canWrite) {
      return 'روی «${owner.name}» اجازهٔ نوشتن داده نشده '
          '(اجازه‌های فعلی: ${owner.permissionLabel}).';
    }

    final source = call.str('source_path');
    if (source != null) {
      final sourceAbs = AgentWorkspace.toAbsolute(source);
      if (sourceAbs != null) {
        final sourceOwner = AgentWorkspace.owner(sourceAbs);
        if (sourceOwner == null) {
          return 'فایل ورودی «$source» بیرون از منابع مجاز است.';
        }
        if (!sourceOwner.canRead) {
          return 'روی «${sourceOwner.name}» اجازهٔ خواندن داده نشده.';
        }
      }
    }
    return null;
  }

  @override
  ToolPreview preview(ToolCall call) => ToolPreview(
    title: 'ساخت فایل PDF',
    subtitle: call.str('output'),
    body: call.str('source_path') == null
        ? _clip(call.str('markdown') ?? call.str('html') ?? '')
        : 'از فایل: ${call.str('source_path')}',
  );

  static String _clip(String text) =>
      text.length <= 600 ? text : '${text.substring(0, 600)}\n…';

  @override
  Future<ToolResult> run(ToolCall call, ToolContext context) async {
    final output = call.str('output');
    if (output == null) {
      return ToolResult.failure('پارامتر output لازم است.');
    }

    final outputPath = AgentWorkspace.toAbsolute(output);
    if (outputPath == null) {
      return ToolResult.failure(
        'مسیر «$output» نسبی است و پوشهٔ کاری انتخاب نشده.',
      );
    }
    final owner = AgentWorkspace.owner(outputPath);
    if (owner == null || !owner.canWrite) {
      return ToolResult.failure('اجازهٔ نوشتن در «$output» وجود ندارد.');
    }

    String? markdown = call.str('markdown');
    String? html = call.str('html');
    final sourcePath = call.str('source_path');

    if (sourcePath != null) {
      final absolute = AgentWorkspace.toAbsolute(sourcePath);
      if (absolute == null) {
        return ToolResult.failure('مسیر ورودی «$sourcePath» قابل حل نیست.');
      }
      final file = File(absolute);
      if (!file.existsSync()) {
        return ToolResult.failure('فایل ورودی پیدا نشد: $sourcePath');
      }
      final content = await file.readAsString();
      if (absolute.toLowerCase().endsWith('.html') ||
          absolute.toLowerCase().endsWith('.htm')) {
        html = content;
      } else {
        markdown = content;
      }
    }

    if ((markdown == null || markdown.trim().isEmpty) &&
        (html == null || html.trim().isEmpty)) {
      return ToolResult.failure(
        'یکی از source_path، markdown یا html لازم است.',
      );
    }

    if (!await AgentCheckpointStore.capture(context.taskId, outputPath)) {
      return ToolResult.failure(
        'برای مسیر خروجی checkpoint امن ساخته نشد؛ فایلی نوشته نشد.',
      );
    }

    try {
      context.report('ساخت PDF…');
      final bytes = html != null
          ? await PdfBuilder.fromHtml(
              html: html.contains('<html')
                  ? html
                  : PdfBuilder.wrapDocument(
                      body: html,
                      title: call.str('title'),
                    ),
              outputPath: outputPath,
            )
          : await PdfBuilder.fromMarkdown(
              markdown: markdown!,
              outputPath: outputPath,
              title: call.str('title'),
            );

      final shown = AgentWorkspace.display(outputPath);
      return ToolResult.success(
        summary: '$shown ساخته شد (${_size(bytes)})',
        data: {'path': outputPath, 'bytes': bytes, 'engine': 'chromium-print'},
        detail: '$outputPath\n${_size(bytes)}',
        changedPaths: [outputPath],
      );
    } catch (e) {
      return ToolResult.failure('ساخت PDF ناموفق بود: $e');
    }
  }

  static String _size(int bytes) => bytes < 1024
      ? '$bytes بایت'
      : bytes < 1024 * 1024
      ? '${(bytes / 1024).toStringAsFixed(1)} کیلوبایت'
      : '${(bytes / (1024 * 1024)).toStringAsFixed(1)} مگابایت';
}
