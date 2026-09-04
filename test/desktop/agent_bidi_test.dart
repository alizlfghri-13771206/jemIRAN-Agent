import 'package:flutter_test/flutter_test.dart';
import 'package:jemiran/desktop/agent/widgets/agent_bidi.dart';

const lri = '\u2066';
const pdi = '\u2069';

String plain(String s) => s.replaceAll(lri, '').replaceAll(pdi, '');

List<String> islands(String s) =>
    RegExp('$lri([^$pdi]*)$pdi').allMatches(s).map((m) => m[1]!).toList();

void main() {
  group('AgentBidi.ltr', () {
    test('رشته را در یک جزیره می‌پیچد', () {
      expect(AgentBidi.ltr('C:\\Projects'), '${lri}C:\\Projects$pdi');
    });

    test('رشتهٔ خالی دست نمی‌خورد', () {
      expect(AgentBidi.ltr(''), '');
    });
  });

  group('AgentBidi.sentence — باگ اصلی', () {
    test('فرمان چندکلمه‌ای یک جزیرهٔ واحد می‌شود', () {
      const input = 'flutter create --project-name=timer_app .';
      final out = AgentBidi.sentence(input);

      expect(islands(out), [
        input,
      ], reason: 'کل فرمان باید یک واحد باشد، نه چند جزیرهٔ جدا');
    });

    test('فرمان لاتین + دنبالهٔ فارسی درست جدا می‌شوند', () {
      final out = AgentBidi.sentence(
        'flutter create --project-name=timer_app . — کد خروج 1',
      );

      expect(
        islands(out).first,
        'flutter create --project-name=timer_app .',
        reason: 'خط تیره به جملهٔ فارسی تعلق دارد، نه به فرمان',
      );
      expect(plain(out), contains('— کد خروج'));
    });

    test('متن بدون کاراکترهای جهت تغییر نمی‌کند', () {
      const input = 'git commit -m x انجام شد';
      expect(plain(AgentBidi.sentence(input)), input);
    });

    test('جملهٔ کاملاً فارسی دست نمی‌خورد', () {
      const input = 'فایل با موفقیت ساخته شد';
      expect(AgentBidi.sentence(input), input);
    });

    test('عدد و واحد یک واحد می‌مانند', () {
      final out = AgentBidi.sentence('اجرا در 42 ms تمام شد');
      expect(islands(out), ['42 ms']);
    });

    test('نام فایل مختلط جزیرهٔ خودش را می‌گیرد', () {
      final out = AgentBidi.sentence('سلام.txt ساخته شد');
      expect(islands(out), ['سلام.txt']);
      expect(plain(out), 'سلام.txt ساخته شد');
    });

    test('چند بخش لاتین جدا، جزیره‌های جدا می‌گیرند', () {
      final out = AgentBidi.sentence('فایل main.dart و بعد test.dart بررسی شد');
      expect(islands(out), ['main.dart', 'test.dart']);
    });

    test('مسیر ویندوزی با فاصله سالم می‌ماند', () {
      final out = AgentBidi.sentence(r'C:\New folder\a.txt ساخته شد');
      expect(islands(out), [r'C:\New folder\a.txt']);
    });

    test('ارقام فارسی جزیره نمی‌گیرند', () {
      final out = AgentBidi.sentence('۳ فایل بررسی شد');
      expect(islands(out), isEmpty);
    });

    test('رشتهٔ خالی', () {
      expect(AgentBidi.sentence(''), '');
    });
  });
}
