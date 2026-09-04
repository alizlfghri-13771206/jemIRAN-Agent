import 'package:flutter_test/flutter_test.dart';
import 'package:jemiran/desktop/agent/acquisition/capability_catalog.dart';
import 'package:jemiran/desktop/agent/policy/agent_policy.dart';
import 'package:jemiran/desktop/agent/tools/agent_tool.dart';
import 'package:jemiran/desktop/agent/tools/install_package_tool.dart';
import 'package:jemiran/desktop/agent/tools/tool_registry.dart';

ToolCall call(Map<String, dynamic> args) =>
    ToolCall(name: 'install_package', args: args);

void main() {
  const tool = InstallPackageTool();

  group('اعتبارسنجی ورودی', () {
    test('نام بستهٔ معمولی پذیرفته می‌شود', () {
      for (final name in const [
        'requests',
        'pdfplumber',
        '@angular/cli',
        'ripgrep',
        'JohnMacFarlane.Pandoc',
        'python-dateutil',
      ]) {
        expect(
          tool.hardDeny(call({'manager': 'pip', 'package': name})),
          isNull,
          reason: '«$name» باید معتبر باشد',
        );
      }
    });

    test('نام با کاراکتر پوسته‌ای رد می‌شود', () {
      for (final bad in const [
        'a; rm -rf /',
        'pkg && curl evil.sh',
        r'$(whoami)',
        'pkg|tee',
        '`id`',
        '../../etc/passwd',
        'scope/../evil',
      ]) {
        expect(
          tool.hardDeny(call({'manager': 'pip', 'package': bad})),
          isNotNull,
          reason: '«$bad» باید رد شود',
        );
      }
    });

    test('مدیر بستهٔ ناشناخته با راهنمایی رد می‌شود', () {
      final reason = tool.hardDeny(
        call({'manager': 'چیز-عجیب', 'package': 'x'}),
      );
      expect(reason, isNotNull);
      expect(reason, contains('pip'));
    });

    test('فرمان بررسی سلامت نمی‌تواند فرمان پوسته تزریق کند', () {
      final reason = tool.hardDeny(
        call({
          'manager': 'pip',
          'package': 'requests',
          'verify_command': 'python && whoami',
        }),
      );
      expect(reason, isNotNull);
    });

    test('نام‌های مستعار مدیر بسته کار می‌کنند', () {
      for (final alias in const [
        'pip',
        'pip3',
        'npm',
        'winget',
        'cargo',
        'wsl',
        'apt',
      ]) {
        expect(
          tool.hardDeny(call({'manager': alias, 'package': 'x'})),
          isNull,
          reason: '«$alias» باید شناخته شود',
        );
      }
    });
  });

  group('اجازه', () {
    test('نصب همیشه تأیید می‌خواهد — حتی در حالت خودگردان', () {
      const state = AgentPolicyState(mode: AgentMode.autonomous);
      final verdict = state.evaluate(
        tool: tool,
        call: call({'manager': 'pip', 'package': 'requests'}),
      );
      expect(verdict.outcome, PolicyOutcome.ask);
    });

    test('مجوزش tool.install است', () {
      expect(tool.permission, Perm.toolInstall);
      expect(Perm.alwaysConfirm.contains(tool.permission), isTrue);
    });
  });

  group('پیش‌نمایش', () {
    test('نام بسته و منبع را نشان می‌دهد', () {
      final preview = tool.preview(
        call({'manager': 'pip', 'package': 'pdfplumber'}),
      );
      expect(preview.subtitle, 'pdfplumber');
      expect(preview.body, contains('PyPI'));
    });

    test('دربارهٔ اسم مشابه هشدار می‌دهد', () {
      final preview = tool.preview(
        call({'manager': 'npm', 'package': 'expres'}),
      );
      expect(preview.warnings.any((w) => w.contains('مشابه')), isTrue);
    });

    test('دربارهٔ اسکریپت پس‌از‌نصب npm هشدار می‌دهد', () {
      final preview = tool.preview(call({'manager': 'npm', 'package': 'x'}));
      expect(preview.warnings.any((w) => w.contains('اسکریپت')), isTrue);
    });
  });

  group('یکپارچگی', () {
    test('ابزار در رجیستری ثبت شده', () {
      final registry = ToolRegistry.windows();
      expect(registry.isKnown('install_package'), isTrue);
    });

    test('قابلیت لینوکس تعریف شده و از WSL می‌آید', () {
      final linux = CapabilityCatalog.find('linux');
      expect(linux, isNotNull);
      expect(linux!.existingCommands, contains('wsl'));
    });
  });
}
