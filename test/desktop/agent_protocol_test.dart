import 'package:flutter_test/flutter_test.dart';
import 'package:jemiran/desktop/agent/core/agent_protocol.dart';
import 'package:jemiran/desktop/agent/policy/agent_policy.dart';
import 'package:jemiran/desktop/agent/tools/tool_registry.dart';

void main() {
  final registry = ToolRegistry.windows();

  group('parseCalls', () {
    test('یک بلوک استاندارد را می‌خواند', () {
      const reply = '''
باشه، اول فایل را می‌خوانم.

```jemiran_tool
{"tool": "read_file", "args": {"path": "lib/main.dart", "limit": 40}}
```
''';
      final calls = AgentProtocol.parseCalls(reply, registry);
      expect(calls, hasLength(1));
      expect(calls.single.name, 'read_file');
      expect(calls.single.str('path'), 'lib/main.dart');
      expect(calls.single.integer('limit'), 40);
    });

    test('شکل تخت (بدون args) هم پذیرفته می‌شود', () {
      const reply = '```jemiran_tool\n{"tool": "list_dir", "path": "lib"}\n```';
      final calls = AgentProtocol.parseCalls(reply, registry);
      expect(calls.single.str('path'), 'lib');
    });

    test('JSON هم‌خط با fence و نام بزرگ هم پذیرفته می‌شود', () {
      const reply =
          '```JEMIRAN_TOOL {"tool":"list_dir","args":{"path":"."}}```';
      final calls = AgentProtocol.parseCalls(reply, registry);
      expect(calls, hasLength(1));
      expect(calls.single.name, 'list_dir');
    });

    test('آرایه‌ای از چند فراخوان در یک بلوک', () {
      const reply = '''
```jemiran_tool
[{"tool": "list_dir", "path": "."}, {"tool": "file_info", "path": "a.txt"}]
```
''';
      expect(AgentProtocol.parseCalls(reply, registry), hasLength(2));
    });

    test('JSON خراب بی‌صدا رد می‌شود و بقیه را خراب نمی‌کند', () {
      const reply = '''
```jemiran_tool
{این JSON نیست}
```
```jemiran_tool
{"tool": "list_dir", "path": "."}
```
''';
      final calls = AgentProtocol.parseCalls(reply, registry);
      expect(calls, hasLength(1));
      expect(calls.single.name, 'list_dir');
    });

    test('ابزار ناشناخته اجرا نمی‌شود', () {
      const reply =
          '```jemiran_tool\n{"tool": "format_c_drive", "path": "C:/"}\n```';
      expect(AgentProtocol.parseCalls(reply, registry), isEmpty);
    });

    test('batch نیمه‌معتبر برای اجرای ناقص پذیرفته نمی‌شود', () {
      const reply = '''
```jemiran_tool
{"tool":"list_dir","path":"."}
```
```jemiran_tool
{"tool":"unknown_tool","args":{}}
```
''';
      expect(AgentProtocol.parseCalls(reply, registry), hasLength(1));
      expect(AgentProtocol.hasInvalidCalls(reply, registry), isTrue);
    });

    test('متن بدون بلوک هیچ فراخوانی ندارد', () {
      expect(
        AgentProtocol.parseCalls('فقط یک جواب معمولی است.', registry),
        isEmpty,
      );
    });
  });

  group('stripControlBlocks', () {
    test('بلوک‌های کنترلی از متن قابل نمایش حذف می‌شوند', () {
      const reply = '''
اول نگاه می‌کنم.

```jemiran_tool
{"tool": "list_dir", "path": "."}
```

بعد گزارش می‌دهم.''';
      final visible = AgentProtocol.stripControlBlocks(reply);
      expect(visible, contains('اول نگاه می‌کنم.'));
      expect(visible, contains('بعد گزارش می‌دهم.'));
      expect(visible, isNot(contains('jemiran_tool')));
      expect(visible, isNot(contains('list_dir')));
    });

    test('بلوک کد معمولی دست نمی‌خورد', () {
      const reply = '```dart\nvoid main() {}\n```';
      expect(AgentProtocol.stripControlBlocks(reply), contains('void main()'));
    });

    test('بلوک خراب یا ابزار ناشناخته بی‌صدا حذف نمی‌شود', () {
      const malformed = '```jemiran_tool\n{خراب}\n```';
      const unknown = '```jemiran_tool\n{"tool":"unknown_tool","args":{}}\n```';
      expect(
        AgentProtocol.stripControlBlocks(malformed, registry: registry),
        contains('{خراب}'),
      );
      expect(
        AgentProtocol.stripControlBlocks(unknown, registry: registry),
        contains('unknown_tool'),
      );
    });
  });

  group('parsePlan', () {
    test('نقشه را به گام تبدیل می‌کند', () {
      const reply = '```jemiran_plan\n["خواندن", "تحلیل", "اصلاح"]\n```';
      final plan = AgentProtocol.parsePlan(reply);
      expect(plan.map((s) => s.text), ['خواندن', 'تحلیل', 'اصلاح']);
      expect(plan.every((s) => !s.done), isTrue);
    });

    test('نقشهٔ خراب یعنی نقشه نداریم، نه خطا', () {
      expect(AgentProtocol.parsePlan('```jemiran_plan\nنه JSON\n```'), isEmpty);
    });
  });

  test('پرامپت ساخت Word را به ابزار داخلی هدایت می‌کند', () {
    final prompt = AgentProtocol.preamble(
      registry: registry,
      mode: AgentMode.manual,
    );
    expect(prompt, contains('make_docx'));
    expect(prompt, contains('Python'));
    expect(prompt, contains('JSON باید کاملاً معتبر باشد'));
  });
}
