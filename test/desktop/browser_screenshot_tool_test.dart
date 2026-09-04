import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:jemiran/desktop/agent/core/agent_storage.dart';
import 'package:jemiran/desktop/agent/policy/agent_policy.dart';
import 'package:jemiran/desktop/agent/tools/agent_tool.dart';
import 'package:jemiran/desktop/agent/tools/browser_tools.dart';
import 'package:jemiran/desktop/agent/tools/tool_registry.dart';

void main() {
  late Directory temp;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('jemiran-shot-');
    AgentStorage.setBaseRootForTesting(temp);
    AgentStorage.setAccountScope('shot@example.com');
  });

  tearDown(() {
    AgentStorage.setBaseRootForTesting(null);
    try {
      temp.deleteSync(recursive: true);
    } catch (_) {}
  });

  test('ابزار عکس صفحه واقعاً در رجیستری اعلام می‌شود', () {
    expect(browserTools.map((t) => t.name), contains('browser_screenshot'));
    expect(ToolRegistry.windows().find('browser_screenshot'), isNotNull);
  });

  test('مجوز و ریسکش با بقیهٔ ابزارهای خواندن مرورگر یکی است', () {
    final tool = browserTools.firstWhere((t) => t.name == 'browser_screenshot');
    expect(tool.permission, Perm.browserRead);
    expect(tool.risk, ToolRisk.read);
    expect(tool.yieldsUntrustedContent, isTrue);
  });

  test('عکس‌ها در فضای حساب می‌نشینند، نه پروژهٔ کاربر', () {
    final dir = BrowserScreenshotTool.directory();
    expect(dir, isNotNull);
    expect(dir!.path, startsWith(AgentStorage.root!.path));
    expect(dir.existsSync(), isTrue);
  });

  test('هرس، پوشه را بی‌مرز رشد نمی‌دهد', () {
    final dir = BrowserScreenshotTool.directory()!;
    for (var i = 0; i < BrowserScreenshotTool.maxKept + 8; i++) {
      File('${dir.path}/page_$i.png').writeAsBytesSync([i]);
    }
    BrowserScreenshotTool.prune(dir);
    expect(
      dir.listSync().whereType<File>().length,
      BrowserScreenshotTool.maxKept,
    );
  });
}
