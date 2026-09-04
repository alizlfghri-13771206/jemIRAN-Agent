import 'dart:ui';

TextDirection detectDirection(String text) {
  final withoutCode = text
      .replaceAll(RegExp(r'```[\s\S]*?```'), '')
      .replaceAll(RegExp(r'`[^`]+`'), '')
      .replaceAll(RegExp(r'\$\$[\s\S]*?\$\$'), '')
      .replaceAll(RegExp(r'(?<!\$)\$[^\$\n]{1,300}\$'), '');

  if (withoutCode.trim().isEmpty) return TextDirection.ltr;

  final persianChars = RegExp(
    r'[\u0600-\u06FF]',
  ).allMatches(withoutCode).length;
  final latinLetters = RegExp(r'[a-zA-Z]').allMatches(withoutCode).length;
  final totalLetters = persianChars + latinLetters;

  if (totalLetters == 0) return TextDirection.ltr;

  final persianRatio = persianChars / totalLetters;
  return persianRatio >= 0.3 ? TextDirection.rtl : TextDirection.ltr;
}

TextDirection detectParagraphDirection(String paragraph) {
  final firstMeaningfulChar = RegExp(
    r'[^\s\d\W]',
  ).firstMatch(paragraph)?.group(0);
  if (firstMeaningfulChar == null) return TextDirection.ltr;

  if (RegExp(r'[\u0600-\u06FF]').hasMatch(firstMeaningfulChar)) {
    return TextDirection.rtl;
  }

  return TextDirection.ltr;
}
