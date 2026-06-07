import 'dart:convert';

/// Sửa chuỗi tiếng Việt bị lỗi encoding (UTF-8 đọc nhầm Latin-1).
String fixVietnameseMojibake(String input) {
  if (!(input.contains('Ã') ||
      input.contains('Â') ||
      input.contains('áº') ||
      input.contains('Æ°'))) {
    return input;
  }
  try {
    const cp1252Extra = {
      '\u20ac': 0x80,
      '\u201a': 0x82,
      '\u0192': 0x83,
      '\u201e': 0x84,
      '\u2026': 0x85,
      '\u2018': 0x91,
      '\u2019': 0x92,
      '\u201c': 0x93,
      '\u201d': 0x94,
      '\u2013': 0x96,
      '\u2014': 0x97,
    };
    final bytes = <int>[];
    for (final ch in input.runes) {
      final c = String.fromCharCode(ch);
      if (cp1252Extra.containsKey(c)) {
        bytes.add(cp1252Extra[c]!);
      } else if (ch <= 0xFF) {
        bytes.add(ch);
      } else {
        return input;
      }
    }
    return utf8.decode(bytes);
  } catch (_) {
    return input;
  }
}
