import 'package:flutter_test/flutter_test.dart';
import 'package:jemiran/desktop/agent/browser/browser_session.dart';
import 'package:jemiran/desktop/agent/browser/page_snapshot.dart';
import 'package:jemiran/desktop/agent/tools/browser_tools.dart';

void main() {
  group('مرز آدرس', () {
    test('file:// رد می‌شود', () {
      expect(
        BrowserSession.rejectUrl(r'file:///C:/Users/me/.ssh/id_rsa'),
        isNotNull,
      );
      expect(BrowserSession.rejectUrl('FILE:///C:/x'), isNotNull);
    });

    test('طرح‌های داخلی مرورگر رد می‌شوند', () {
      for (final url in const [
        'chrome://settings/passwords',
        'chrome://history',
        'edge://settings',
        'devtools://devtools/bundled/inspector.html',
        'view-source:https://example.com',
      ]) {
        expect(BrowserSession.rejectUrl(url), isNotNull, reason: url);
      }
    });

    test('javascript: رد می‌شود', () {
      expect(BrowserSession.rejectUrl('javascript:fetch("/steal")'), isNotNull);
    });

    test('http و https عمومی مجازند', () {
      expect(BrowserSession.rejectUrl('https://sanjesh.org'), isNull);
    });

    test('localhost و IPهای خصوصی رد می‌شوند', () {
      for (final url in const [
        'http://127.0.0.1:8080/x',
        'http://localhost/admin',
        'http://10.0.0.1',
        'http://172.16.1.2',
        'http://192.168.1.1',
        'http://169.254.169.254/latest/meta-data',
        'http://[::1]/',
      ]) {
        expect(BrowserSession.rejectUrl(url), isNotNull, reason: url);
      }
    });

    test('آدرس بدون طرح، https می‌گیرد نه چیز دیگر', () {
      expect(BrowserSession.rejectUrl('sanjesh.org'), isNull);
      expect(BrowserSession.normalizeUrl('sanjesh.org'), 'https://sanjesh.org');
    });

    test('آدرس خالی رد می‌شود', () {
      expect(BrowserSession.rejectUrl('   '), isNotNull);
    });
  });

  group('خواندن ساختار صفحه', () {
    final snapshot = PageSnapshot.fromJson(const {
      'url': 'https://example.com/form',
      'title': 'ثبت‌نام',
      'text': 'فرم ثبت‌نام',
      'elements': [
        {
          'ref': 'ref_0',
          'tag': 'input',
          'label': 'کد ملی',
          'type': 'text',
          'name': 'nid',
          'value': '00123',
          'required': true,
        },
        {'ref': 'ref_1', 'tag': 'input', 'label': 'رمز', 'type': 'password'},
        {
          'ref': 'ref_2',
          'tag': 'select',
          'label': 'رشته',
          'name': 'major',
          'value': 'math',
          'display': 'ریاضی',
          'options': ['ریاضی', 'تجربی'],
        },
      ],
      'forms': [
        {
          'ref': 'form_0',
          'name': 'signup',
          'fields': ['ref_0', 'ref_1', 'ref_2'],
          'action': '/submit',
          'method': 'post',
        },
      ],
    });

    test('المان‌ها و فرم خوانده می‌شوند', () {
      expect(snapshot.elements.length, 3);
      expect(snapshot.forms.single.fieldRefs.length, 3);
    });

    test('ارجاع با ref پیدا می‌شود', () {
      expect(snapshot.byRef('ref_2')?.label, 'رشته');
      expect(snapshot.byRef('ref_99'), isNull);
    });

    test('فیلد رمز هیچ مقداری ندارد', () {
      expect(snapshot.byRef('ref_1')?.value, isNull);
    });

    test('مرور نهایی متن دیدنی را نشان می‌دهد نه مقدار خام', () {
      expect(snapshot.byRef('ref_2')?.value, 'math');
      expect(snapshot.byRef('ref_2')?.shownValue, 'ریاضی');
    });

    test('ورودی متنی از دکمه و چک‌باکس تفکیک می‌شود', () {
      expect(snapshot.byRef('ref_0')?.isTextInput, isTrue);
      final checkbox = PageElement.fromJson(const {
        'ref': 'ref_5',
        'tag': 'input',
        'type': 'checkbox',
        'label': 'قوانین',
      });
      expect(checkbox.isTextInput, isFalse);
    });

    test('آنچه به مدل می‌رود شامل ref هر المان است', () {
      final json = snapshot.toJson();
      final elements = json['elements'] as List;
      expect(elements.every((e) => (e as Map).containsKey('ref')), isTrue);
    });

    test('کلیک روی submit باید از مسیر تأیید فرم عبور کند', () {
      final formSnapshot = PageSnapshot.fromJson(const {
        'url': 'https://example.com/form',
        'title': 'فرم',
        'text': '',
        'elements': [
          {'ref': 'ref_0', 'tag': 'button', 'type': 'submit', 'label': 'ارسال'},
        ],
        'forms': [
          {
            'ref': 'form_0',
            'name': 'signup',
            'fields': ['ref_0'],
          },
        ],
      });

      expect(BrowserActTool.clickWouldSubmit(formSnapshot, 'ref_0'), isTrue);
    });
  });
}
