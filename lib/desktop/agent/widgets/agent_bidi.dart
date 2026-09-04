abstract final class AgentBidi {
  static const _lri = '\u2066';
  static const _pdi = '\u2069';

  static String ltr(String value) => value.isEmpty ? value : '$_lri$value$_pdi';

  static String sentence(String value) {
    if (value.isEmpty) return value;

    final segments = _split(value);
    final kinds = [for (final s in segments) _kindOf(s)];

    final buffer = StringBuffer();
    var i = 0;
    while (i < segments.length) {
      if (kinds[i] != _Kind.latin) {
        buffer.write(kinds[i] == _Kind.mixed ? ltr(segments[i]) : segments[i]);
        i++;
        continue;
      }

      var end = i;
      for (var j = i; j < segments.length; j++) {
        if (kinds[j] == _Kind.latin || kinds[j] == _Kind.asciiPunct) {
          end = j;
        } else if (kinds[j] == _Kind.persian || kinds[j] == _Kind.mixed) {
          break;
        }
      }

      buffer.write(ltr(segments.sublist(i, end + 1).join()));
      i = end + 1;
    }

    return buffer.toString();
  }

  static List<String> _split(String value) {
    final result = <String>[];
    final spaces = RegExp(r'\s+');
    var last = 0;
    for (final m in spaces.allMatches(value)) {
      if (m.start > last) result.add(value.substring(last, m.start));
      result.add(m[0]!);
      last = m.end;
    }
    if (last < value.length) result.add(value.substring(last));
    return result;
  }

  static final _latin = RegExp(r'[A-Za-z0-9]');

  static final _persian = RegExp(r'[؀-ۿݐ-ݿﭐ-﷿ﹰ-﻿]');

  static bool _isAsciiPunct(String token) =>
      token.codeUnits.every((c) => c > 32 && c < 127);

  static _Kind _kindOf(String token) {
    if (token.trim().isEmpty) return _Kind.space;
    final hasLatin = _latin.hasMatch(token);
    final hasPersian = _persian.hasMatch(token);
    if (hasLatin && hasPersian) return _Kind.mixed;
    if (hasLatin) return _Kind.latin;
    if (hasPersian) return _Kind.persian;

    return _isAsciiPunct(token) ? _Kind.asciiPunct : _Kind.neutral;
  }
}

enum _Kind { latin, persian, mixed, asciiPunct, neutral, space }
