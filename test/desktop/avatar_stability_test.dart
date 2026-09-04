import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jemiran/desktop/shell/avatar_image.dart';

void main() {
  const pixel =
      'data:image/png;base64,'
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk'
      'YPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==';

  setUp(DesktopAvatarImage.clear);

  test('همان نشانی همیشه همان provider را می‌دهد', () {
    final first = DesktopAvatarImage.of(pixel);
    final second = DesktopAvatarImage.of(pixel);

    expect(first, isNotNull);
    expect(identical(first, second), isTrue);
  });

  test('نمونهٔ ساخته‌شده در build هرگز با قبلی برابر نبود', () {
    final bytes = pixel.split(',').last;
    final a = MemoryImage(base64Decode(bytes));
    final b = MemoryImage(base64Decode(bytes));

    expect(
      a == b,
      isFalse,
      reason: 'MemoryImage بایت‌ها را با identity می‌سنجد، نه محتوا',
    );
  });

  test('نشانی شبکه هم از همان مسیر و پایدار می‌آید', () {
    final first = DesktopAvatarImage.of('https://example.com/a.png');
    final second = DesktopAvatarImage.of('https://example.com/a.png');
    expect(identical(first, second), isTrue);
  });

  test('نشانی متفاوت، provider متفاوت', () {
    final one = DesktopAvatarImage.of(pixel);
    final two = DesktopAvatarImage.of('https://example.com/b.png');
    expect(identical(one, two), isFalse);
  });

  test('نبودِ عکس یعنی هیچ provider', () {
    expect(DesktopAvatarImage.of(null), isNull);
    expect(DesktopAvatarImage.of(''), isNull);
    expect(DesktopAvatarImage.of('   '), isNull);
  });

  test('نشانهٔ data خراب باعث خطا نمی‌شود', () {
    expect(DesktopAvatarImage.of('data:image/png;base64,@@@بی‌معنی'), isNull);
  });

  test('کش سقف دارد و بی‌نهایت رشد نمی‌کند', () {
    for (var i = 0; i < 20; i++) {
      DesktopAvatarImage.of('https://example.com/$i.png');
    }
    final last = DesktopAvatarImage.of('https://example.com/19.png');
    expect(
      identical(last, DesktopAvatarImage.of('https://example.com/19.png')),
      isTrue,
    );
  });

  test('پاک‌سازی روی خروج از حساب، عکس را نگه نمی‌دارد', () {
    final before = DesktopAvatarImage.of(pixel);
    DesktopAvatarImage.clear();
    final after = DesktopAvatarImage.of(pixel);
    expect(identical(before, after), isFalse);
  });
}
