import 'package:flutter/services.dart';

String localMobileDigits(String raw) {
  var s = raw.replaceAll(RegExp(r'\D'), '');

  if (s.length == 14 && s.startsWith('0098')) {
    s = s.substring(4);
  } else if (s.length == 12 && s.startsWith('98')) {
    s = s.substring(2);
  }

  s = s.replaceFirst(RegExp(r'^0+'), '');

  return s.length > 10 ? s.substring(0, 10) : s;
}

String fullMobileOrEmpty(String raw) {
  final d = localMobileDigits(raw);
  return d.length == 10 && d.startsWith('9') ? '0$d' : '';
}

class IranMobileInputFormatter extends TextInputFormatter {
  const IranMobileInputFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digits = localMobileDigits(newValue.text);
    return TextEditingValue(
      text: digits,
      selection: TextSelection.collapsed(offset: digits.length),
    );
  }
}
