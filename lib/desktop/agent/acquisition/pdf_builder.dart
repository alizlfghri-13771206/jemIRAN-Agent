import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:markdown/markdown.dart' as md;

import '../browser/cdp_client.dart';

abstract final class PdfBuilder {
  static Future<int> fromMarkdown({
    required String markdown,
    required String outputPath,
    String? title,
  }) async {
    final body = md.markdownToHtml(
      markdown,
      extensionSet: md.ExtensionSet.gitHubWeb,
    );
    return fromHtml(
      html: wrapDocument(body: body, title: title),
      outputPath: outputPath,
    );
  }

  static Future<int> fromHtml({
    required String html,
    required String outputPath,
  }) async {
    final client = await CdpClient.launch(headless: true);
    StreamSubscription<CdpEvent>? requestGuard;
    try {
      await client.send('Emulation.setScriptExecutionDisabled', {
        'value': true,
      });
      await client.send('Fetch.enable', {
        'patterns': [
          {'urlPattern': '*', 'requestStage': 'Request'},
        ],
      });
      requestGuard = client.events
          .where((event) => event.method == 'Fetch.requestPaused')
          .listen((event) {
            final id = event.params['requestId']?.toString();
            if (id == null) return;
            unawaited(
              client
                  .send('Fetch.failRequest', {
                    'requestId': id,
                    'errorReason': 'BlockedByClient',
                  })
                  .catchError((_) => <String, dynamic>{}),
            );
          });

      final tree = await client.send('Page.getFrameTree');
      final frameId =
          ((tree['frameTree'] as Map?)?['frame'] as Map?)?['id'] as String?;
      if (frameId == null) {
        throw const CdpException('فریم صفحه پیدا نشد.');
      }

      await client.send('Page.setDocumentContent', {
        'frameId': frameId,
        'html': html,
      });

      await Future<void>.delayed(const Duration(milliseconds: 350));

      final result = await client.send('Page.printToPDF', {
        'printBackground': true,
        'preferCSSPageSize': true,
        'marginTop': 0.6,
        'marginBottom': 0.6,
        'marginLeft': 0.6,
        'marginRight': 0.6,
      });

      final data = result['data'];
      if (data is! String) {
        throw const CdpException('موتور چاپ خروجی نداد.');
      }

      final bytes = base64Decode(data);
      final file = File(outputPath);
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes);
      return bytes.length;
    } finally {
      await requestGuard?.cancel();
      await client.dispose();
    }
  }

  static String wrapDocument({required String body, String? title}) {
    final safeTitle = const HtmlEscape().convert(title ?? 'سند');
    return '''
<!doctype html>
<html lang="fa" dir="rtl">
<head>
<meta charset="utf-8">
<title>$safeTitle</title>
<style>
  @page { size: A4; }
  body {
    font-family: Tahoma, "Segoe UI", "Iranian Sans", sans-serif;
    font-size: 11.5pt;
    line-height: 1.9;
    color: #1a1a1a;
  }
  h1, h2, h3 { line-height: 1.5; margin-top: 1.2em; }
  h1 { font-size: 19pt; }
  h2 { font-size: 15pt; }
  h3 { font-size: 13pt; }
  code, pre {
    font-family: Consolas, "Courier New", monospace;
    direction: ltr;
    text-align: left;
    unicode-bidi: isolate;
  }
  pre {
    background: #f5f5f5;
    padding: 10px 12px;
    border-radius: 6px;
    border: 1px solid #e2e2e2;
    overflow-wrap: break-word;
    white-space: pre-wrap;
  }
  code { background: #f2f2f2; padding: 1px 4px; border-radius: 3px; }
  pre code { background: none; padding: 0; }
  table { border-collapse: collapse; width: 100%; }
  th, td { border: 1px solid #d8d8d8; padding: 6px 9px; }
  th { background: #f5f5f5; }
  blockquote {
    border-right: 3px solid #ccc;
    margin: 1em 0;
    padding: 0 1em 0 0;
    color: #555;
  }
  img { max-width: 100%; }
  a { color: #0b5cad; }
</style>
</head>
<body>
$body
</body>
</html>
''';
  }
}
