import 'dart:io';

import 'package:jemiran/desktop/agent/acquisition/capability_catalog.dart';
import 'package:jemiran/desktop/agent/acquisition/capability_service.dart';
import 'package:jemiran/desktop/agent/acquisition/pdf_builder.dart';
import 'package:jemiran/desktop/agent/acquisition/tool_probe.dart';

int _passed = 0;
int _failed = 0;

void check(String name, bool ok, [String? detail]) {
  if (ok) {
    _passed++;
    stdout.writeln('  ✓ $name${detail == null ? '' : '  ($detail)'}');
  } else {
    _failed++;
    stdout.writeln('  ✗ $name${detail == null ? '' : '  →  $detail'}');
  }
}

const _markdown = '''
# گزارش آزمایشی

این یک سند **فارسی** است که باید درست چاپ شود.

## فهرست

- مورد اول
- مورد دوم با یک کلمهٔ English وسطش
- مورد سوم با عدد ۱۲۳ و 456

## کد

```dart
void main() {
  print('سلام');
}
```

## جدول

| ستون | مقدار |
|------|-------|
| الف  | ۱۰    |
| ب    | ۲۰    |

> نقل قول برای آزمایش.
''';

Future<void> main() async {
  stdout.writeln('— بررسی ابزارهای سیستم —');

  final git = await ToolProbe.probe('git');
  check('git تشخیص داده شد', git.installed, git.version);

  final nonsense = await ToolProbe.probe('ابزار-که-وجود-ندارد');
  check('ابزار ناموجود درست تشخیص داده شد', !nonsense.installed);

  stdout.writeln('\n— گزارش قابلیت‌ها (Tool Registry) —');
  final survey = await CapabilityService.survey();
  check(
    'همهٔ قابلیت‌ها بررسی شدند',
    survey.length == CapabilityCatalog.keys.length,
    '${survey.length} قابلیت',
  );
  for (final s in survey) {
    final mark = switch (s.state) {
      CapabilityState.builtin => '◆ داخلی',
      CapabilityState.available => '✓ نصب',
      CapabilityState.installable => '↓ قابل نصب',
      CapabilityState.unavailable => '✗ ناموجود',
    };
    stdout.writeln(
      '     $mark  ${s.capability.label}'
      '${s.provider == null ? '' : '  ← ${s.provider!.packageId}'}',
    );
  }

  stdout.writeln('\n— منطق «اول بررسی کن، بعد نصب» (بند ۱۵) —');
  final pdf = await CapabilityService.resolve('pdf');
  check(
    'PDF داخلی است و نصب لازم ندارد',
    pdf.state == CapabilityState.builtin,
    pdf.capability.builtinBy,
  );

  final gitCap = await CapabilityService.resolve('git');
  check(
    'گیت که نصب است، «نصب نیست» گزارش نمی‌شود',
    gitCap.state == CapabilityState.available,
  );

  final install = await CapabilityService.install(gitCap);
  check(
    'نصب دوبارهٔ چیزی که هست انجام نمی‌شود',
    install.ok && install.message.contains('از قبل نصب'),
    install.message,
  );

  final pdfInstall = await CapabilityService.install(pdf);
  check(
    'نصب قابلیت داخلی هم بی‌اثر است',
    pdfInstall.ok && pdfInstall.message.contains('نصبی لازم نیست'),
    pdfInstall.message,
  );

  stdout.writeln('\n— قابلیت نصب‌نشده —');
  final ocr = await CapabilityService.resolve('document_convert');
  check(
    'pandoc نصب نیست و «قابل نصب» شناخته شد',
    ocr.state == CapabilityState.installable,
    ocr.provider?.packageId,
  );
  check(
    'منبع نصب، مدیر بستهٔ رسمی است',
    ocr.provider?.manager.command == 'winget',
  );
  check(
    'نصب در دامنهٔ کاربر است نه سیستم',
    ocr.provider?.manager.installArgs('X').contains('user') ?? false,
  );

  final unknown = await CapabilityService.resolve('چیز-عجیب');
  check(
    'قابلیت ناشناخته با راهنمایی رد می‌شود',
    unknown.state == CapabilityState.unavailable &&
        (unknown.reason?.contains('pdf') ?? false),
  );

  stdout.writeln('\n— ساخت PDF واقعی —');
  final dir = await Directory.systemTemp.createTemp('jemiran_pdf_');
  final out = '${dir.path}${Platform.pathSeparator}گزارش.pdf';

  try {
    final bytes = await PdfBuilder.fromMarkdown(
      markdown: _markdown,
      outputPath: out,
      title: 'گزارش آزمایشی',
    );

    final file = File(out);
    check('فایل ساخته شد', file.existsSync());
    check('حجم منطقی دارد', bytes > 3000, '$bytes بایت');

    final header = await file.openRead(0, 5).first;
    check(
      'واقعاً PDF است',
      String.fromCharCodes(header).startsWith('%PDF-'),
      String.fromCharCodes(header),
    );
    stdout.writeln('     $out');
  } catch (e) {
    _failed++;
    stdout.writeln('  ✗ ساخت PDF: $e');
  }

  stdout.writeln('\n═══════════════════════');
  stdout.writeln('موفق: $_passed   ناموفق: $_failed');
  exit(_failed == 0 ? 0 : 1);
}
