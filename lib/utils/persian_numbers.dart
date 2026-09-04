extension FarsiNumbers on String {
  String get farsiNumber {
    const english = ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"];
    const farsi = ["۱", "۲", "۳", "۴", "۵", "۶", "۷", "۸", "۹", "۰"];
    String text = this;
    for (int i = 0; i < 10; i++) {
      text = text.replaceAll(english[i], farsi[i]);
    }
    return text;
  }
}

class FaNumber {
  static String group(int value) {
    final s = value.toString().replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
      (m) => '${m[1]}٬',
    );
    return s.farsiNumber;
  }

  static String toman(int value) => '${group(value)} تومان';
  static String tomanCompact(int value) {
    if (value >= 1000000) {
      final m = value / 1000000;
      final s = m == m.roundToDouble()
          ? m.round().toString()
          : m.toStringAsFixed(1).replaceAll('.', '٫');
      return '${s.farsiNumber} میلیون تومان';
    }
    if (value >= 1000) {
      return '${(value / 1000).round().toString().farsiNumber} هزار تومان';
    }
    return toman(value);
  }

  static String perMessage(int value) => '~${group(value)} ت / پیام';
}
