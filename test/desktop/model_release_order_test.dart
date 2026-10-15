import 'package:flutter_test/flutter_test.dart';
import 'package:jemiran/utils/model_release_order.dart';

List<String> _order(List<String> ids) {
  final models = [
    for (final id in ids) <String, dynamic>{'id': id},
  ];
  orderByModelRelease(models, (model) => model['id'] as String);
  return [for (final model in models) model['id'] as String];
}

void main() {
  test('خانوادهٔ ترجیحی اول می‌آید، بقیه به ترتیب جدیدترین انتشار', () {
    expect(
      _order([
        'deepseek/deepseek-v3.2',
        'openai/gpt-4o-mini',
        'z-ai/glm-5.3',
        'google/gemini-4-argon',
      ]),
      [
        'google/gemini-4-argon',
        'openai/gpt-4o-mini',
        'z-ai/glm-5.3',
        'deepseek/deepseek-v3.2',
      ],
    );
  });

  test('شناسهٔ Gemini بدون پیشوند هم شناخته می‌شود', () {
    expect(_order(['openai/gpt-5-mini', 'gemini-3.8-flash']), [
      'gemini-3.8-flash',
      'openai/gpt-5-mini',
    ]);
  });

  test('شناسه‌های ناشناخته ترتیب اصلی را نگه می‌دارند', () {
    expect(_order(['my-b', 'my-a', 'my-c']), ['my-b', 'my-a', 'my-c']);
  });
}
