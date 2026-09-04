import 'package:flutter_test/flutter_test.dart';
import 'package:jemiran/desktop/agent/acquisition/capability_catalog.dart';
import 'package:jemiran/desktop/agent/acquisition/pdf_builder.dart';

void main() {
  group('سیاست نصب', () {
    test('winget در دامنهٔ کاربر نصب می‌کند نه سیستم', () {
      final args = PackageManager.winget.installArgs('Some.Package');
      expect(args, containsAllInOrder(['--scope', 'user']));
      expect(args, contains('--exact'));
    });

    test('pip هم در دامنهٔ کاربر نصب می‌کند', () {
      expect(PackageManager.pip.installArgs('requests'), contains('--user'));
    });

    test('نام بسته دقیقاً همان چیزی است که داده شده', () {
      expect(
        PackageManager.winget.installArgs('JohnMacFarlane.Pandoc'),
        contains('JohnMacFarlane.Pandoc'),
      );
    });

    test('npm به‌عنوان روشی که ممکن است مدیر بخواهد علامت خورده', () {
      expect(PackageManager.npm.mayNeedAdmin, isTrue);
      expect(PackageManager.winget.mayNeedAdmin, isFalse);
    });
  });

  group('فهرست قابلیت‌ها', () {
    test('PDF داخلی است و هیچ راه نصبی ندارد', () {
      final pdf = CapabilityCatalog.find('pdf');
      expect(pdf, isNotNull);
      expect(pdf!.isBuiltin, isTrue);
      expect(pdf.providers, isEmpty);
    });

    test('ساخت Word داخلی است و نصب Python یا Office نمی‌خواهد', () {
      final docx = CapabilityCatalog.find('docx');
      expect(docx, isNotNull);
      expect(docx!.isBuiltin, isTrue);
      expect(docx.providers, isEmpty);
    });

    test('هر راه نصب یک فرمان بررسی سلامت دارد', () {
      for (final capability in CapabilityCatalog.all) {
        for (final provider in capability.providers) {
          expect(
            provider.verifyCommand,
            isNotEmpty,
            reason: '${capability.key} راه نصبی بدون بررسی سلامت دارد',
          );
        }
      }
    });

    test('هر قابلیت غیرداخلی راهی برای تشخیص دارد', () {
      for (final capability in CapabilityCatalog.all) {
        if (capability.isBuiltin) continue;
        expect(
          capability.existingCommands,
          isNotEmpty,
          reason:
              '${capability.key} راهی برای فهمیدن «از قبل نصب است» ندارد، '
              'پس ممکن است دوباره نصب شود',
        );
      }
    });

    test('کلیدها یکتا هستند', () {
      final keys = CapabilityCatalog.keys;
      expect(keys.toSet().length, keys.length);
    });

    test('قابلیت ناشناخته null می‌دهد', () {
      expect(CapabilityCatalog.find('چیزی-که-نیست'), isNull);
    });
  });

  group('سند PDF', () {
    test('سند راست‌به‌چپ ساخته می‌شود', () {
      final html = PdfBuilder.wrapDocument(body: '<p>سلام</p>', title: 'تست');
      expect(html, contains('dir="rtl"'));
      expect(html, contains('lang="fa"'));
    });

    test('بلوک کد چپ‌به‌راست می‌ماند', () {
      final html = PdfBuilder.wrapDocument(body: '', title: null);
      expect(html, contains('direction: ltr'));
      expect(html, contains('unicode-bidi: isolate'));
    });

    test('عنوان از تزریق HTML امن است', () {
      final html = PdfBuilder.wrapDocument(
        body: '',
        title: '<script>alert(1)</script>',
      );
      expect(html, isNot(contains('<script>alert(1)</script>')));
      expect(html, contains('&lt;script&gt;'));
    });

    test('فونت فارسی سیستمی مشخص شده', () {
      final html = PdfBuilder.wrapDocument(body: '', title: null);
      expect(html, contains('Tahoma'));
    });
  });
}
