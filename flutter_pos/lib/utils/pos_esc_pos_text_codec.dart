import 'dart:convert';

/// Bảng mã ESC/POS cho tiếng Việt (TCVN-3 / code page 30).
/// Dùng khi máy hỗ trợ `ESC t 30` (Zywell/Xprinter một số model).
class PosEscPosTextCodec {
  /// UTF-8 → byte TCVN-3 (single-byte).
  static final Map<int, int> _utf8ToTcvn3 = _buildTcvn3Map();

  static List<int> encodeTcvn3(String text) {
    final out = <int>[];
    for (final rune in text.runes) {
      out.add(_utf8ToTcvn3[rune] ?? (rune < 128 ? rune : 0x3F));
    }
    return out;
  }

  static List<int> initTcvn3() => [0x1B, 0x40, 0x1B, 0x74, 0x1E];

  /// CP1258 — code page 27 (Xprinter/Zywell một số model).
  /// [page] có thể đổi nếu firmware map khác (thường 27).
  static List<int> initCp1258({int page = 27}) =>
      [0x1B, 0x40, 0x1B, 0x74, page.clamp(0, 255)];

  static final Map<int, int> _utf8ToCp1258 = _buildCp1258Map();

  static List<int> encodeCp1258(String text) {
    final out = <int>[];
    for (final rune in text.runes) {
      if (rune < 128) {
        out.add(rune);
        continue;
      }
      final b = _utf8ToCp1258[rune];
      if (b != null) {
        out.add(b);
      } else {
        final plain = stripDiacritics(String.fromCharCode(rune));
        out.add(plain.isNotEmpty ? plain.codeUnitAt(0) : 0x3F);
      }
    }
    return out;
  }

  /// Khởi tạo UTF-8 tốt hơn trên máy Epson/clone hiện đại:
  /// ESC t 255 (một số firmware) + hủy Kanji FS .
  /// Vẫn không đảm bảo trên mọi máy Trung Quốc — ưu tiên image mode.
  static List<int> initUtf8() => [
        0x1B, 0x40,
        0x1B, 0x74, 0xFF,
        0x1C, 0x2E,
      ];

  static List<int> encodeUtf8(String text) => utf8.encode(text);

  static String stripDiacritics(String input) {
    const map = {
      'à': 'a', 'á': 'a', 'ả': 'a', 'ã': 'a', 'ạ': 'a',
      'ă': 'a', 'ằ': 'a', 'ắ': 'a', 'ẳ': 'a', 'ẵ': 'a', 'ặ': 'a',
      'â': 'a', 'ầ': 'a', 'ấ': 'a', 'ẩ': 'a', 'ẫ': 'a', 'ậ': 'a',
      'è': 'e', 'é': 'e', 'ẻ': 'e', 'ẽ': 'e', 'ẹ': 'e',
      'ê': 'e', 'ề': 'e', 'ế': 'e', 'ể': 'e', 'ễ': 'e', 'ệ': 'e',
      'ì': 'i', 'í': 'i', 'ỉ': 'i', 'ĩ': 'i', 'ị': 'i',
      'ò': 'o', 'ó': 'o', 'ỏ': 'o', 'õ': 'o', 'ọ': 'o',
      'ô': 'o', 'ồ': 'o', 'ố': 'o', 'ổ': 'o', 'ỗ': 'o', 'ộ': 'o',
      'ơ': 'o', 'ờ': 'o', 'ớ': 'o', 'ở': 'o', 'ỡ': 'o', 'ợ': 'o',
      'ù': 'u', 'ú': 'u', 'ủ': 'u', 'ũ': 'u', 'ụ': 'u',
      'ư': 'u', 'ừ': 'u', 'ứ': 'u', 'ử': 'u', 'ữ': 'u', 'ự': 'u',
      'ỳ': 'y', 'ý': 'y', 'ỷ': 'y', 'ỹ': 'y', 'ỵ': 'y',
      'đ': 'd',
      'À': 'A', 'Á': 'A', 'Ả': 'A', 'Ã': 'A', 'Ạ': 'A',
      'Ă': 'A', 'Ằ': 'A', 'Ắ': 'A', 'Ẳ': 'A', 'Ẵ': 'A', 'Ặ': 'A',
      'Â': 'A', 'Ầ': 'A', 'Ấ': 'A', 'Ẩ': 'A', 'Ẫ': 'A', 'Ậ': 'A',
      'È': 'E', 'É': 'E', 'Ẻ': 'E', 'Ẽ': 'E', 'Ẹ': 'E',
      'Ê': 'E', 'Ề': 'E', 'Ế': 'E', 'Ể': 'E', 'Ễ': 'E', 'Ệ': 'E',
      'Ì': 'I', 'Í': 'I', 'Ỉ': 'I', 'Ĩ': 'I', 'Ị': 'I',
      'Ò': 'O', 'Ó': 'O', 'Ỏ': 'O', 'Õ': 'O', 'Ọ': 'O',
      'Ô': 'O', 'Ồ': 'O', 'Ố': 'O', 'Ổ': 'O', 'Ỗ': 'O', 'Ộ': 'O',
      'Ơ': 'O', 'Ờ': 'O', 'Ớ': 'O', 'Ở': 'O', 'Ỡ': 'O', 'Ợ': 'O',
      'Ù': 'U', 'Ú': 'U', 'Ủ': 'U', 'Ũ': 'U', 'Ụ': 'U',
      'Ư': 'U', 'Ừ': 'U', 'Ứ': 'U', 'Ử': 'U', 'Ữ': 'U', 'Ự': 'U',
      'Ỳ': 'Y', 'Ý': 'Y', 'Ỷ': 'Y', 'Ỹ': 'Y', 'Ỵ': 'Y',
      'Đ': 'D',
    };
    final sb = StringBuffer();
    for (final ch in input.runes) {
      final s = String.fromCharCode(ch);
      sb.write(map[s] ?? s);
    }
    return sb.toString();
  }

  static Map<int, int> _buildTcvn3Map() {
    const pairs = <String, String>{
      'À': '\xC0', 'Á': '\xC1', 'Â': '\xC2', 'Ã': '\xC3', 'È': '\xC8',
      'É': '\xC9', 'Ê': '\xCA', 'Ì': '\xCC', 'Í': '\xCD', 'Ò': '\xD2',
      'Ó': '\xD3', 'Ô': '\xD4', 'Õ': '\xD5', 'Ù': '\xD9', 'Ú': '\xDA',
      'Ý': '\xDD', 'à': '\xE0', 'á': '\xE1', 'â': '\xE2', 'ã': '\xE3',
      'è': '\xE8', 'é': '\xE9', 'ê': '\xEA', 'ì': '\xEC', 'í': '\xED',
      'ò': '\xF2', 'ó': '\xF3', 'ô': '\xF4', 'õ': '\xF5', 'ù': '\xF9',
      'ú': '\xFA', 'ý': '\xFD', 'Ă': '\xC4', 'ă': '\xE4', 'Đ': '\xD0',
      'đ': '\xF0', 'Ơ': '\xD6', 'ơ': '\xF6', 'Ư': '\xDC', 'ư': '\xFC',
      'Ạ': '\xA1', 'ạ': '\xA1', 'Ả': '\xA2', 'ả': '\xA2', 'Ấ': '\xA3',
      'ấ': '\xA3', 'Ầ': '\xA4', 'ầ': '\xA4', 'Ẩ': '\xA5', 'ẩ': '\xA5',
      'Ẫ': '\xA6', 'ẫ': '\xA6', 'Ậ': '\xA7', 'ậ': '\xA7', 'Ắ': '\xA8',
      'ắ': '\xA8', 'Ằ': '\xA9', 'ằ': '\xA9', 'Ẳ': '\xAA', 'ẳ': '\xAA',
      'Ẵ': '\xAB', 'ẵ': '\xAB', 'Ặ': '\xAC', 'ặ': '\xAC', 'Ẹ': '\xAD',
      'ẹ': '\xAD', 'Ẻ': '\xAE', 'ẻ': '\xAE', 'Ẽ': '\xAF', 'ẽ': '\xAF',
      'Ế': '\xB0', 'ế': '\xB0', 'Ề': '\xB1', 'ề': '\xB1', 'Ể': '\xB2',
      'ể': '\xB2', 'Ễ': '\xB3', 'ễ': '\xB3', 'Ệ': '\xB4', 'ệ': '\xB4',
      'Ỉ': '\xB5', 'ỉ': '\xB5', 'Ị': '\xB6', 'ị': '\xB6', 'Ọ': '\xB7',
      'ọ': '\xB7', 'Ỏ': '\xB8', 'ỏ': '\xB8', 'Ố': '\xB9', 'ố': '\xB9',
      'Ồ': '\xBA', 'ồ': '\xBA', 'Ổ': '\xBB', 'ổ': '\xBB', 'Ỗ': '\xBC',
      'ỗ': '\xBC', 'Ộ': '\xBD', 'ộ': '\xBD', 'Ớ': '\xBE', 'ớ': '\xBE',
      'Ờ': '\xBF', 'ờ': '\xBF', 'Ở': '\xC5', 'ở': '\xC5', 'Ỡ': '\xC6',
      'ỡ': '\xC6', 'Ợ': '\xC7', 'ợ': '\xC7', 'Ụ': '\xC8', 'ụ': '\xC8',
      'Ủ': '\xC9', 'ủ': '\xC9', 'Ứ': '\xCA', 'ứ': '\xCA', 'Ừ': '\xCB',
      'ừ': '\xCB', 'Ử': '\xCC', 'ử': '\xCC', 'Ữ': '\xCD', 'ữ': '\xCD',
      'Ự': '\xCE', 'ự': '\xCE', 'Ỳ': '\xCF', 'ỳ': '\xCF', 'Ỵ': '\xD1',
      'ỵ': '\xD1', 'Ỷ': '\xD2', 'ỷ': '\xD2', 'Ỹ': '\xD3', 'ỹ': '\xD3',
    };
    final map = <int, int>{};
    pairs.forEach((utf, tcvn) {
      map[utf.codeUnitAt(0)] = tcvn.codeUnitAt(0);
    });
    return map;
  }

  static Map<int, int> _buildCp1258Map() {
    // Chữ hoa có dấu (ẠẢẤ…) map cùng byte chữ thường — khớp firmware ESC/POS VN
    // (page 27) vốn dùng bảng mở rộng giống TCVN hơn Windows CP1258 chuẩn.
    const pairs = <String, String>{
      'À': '\xC0', 'Á': '\xC1', 'Â': '\xC2', 'Ã': '\xC3', 'È': '\xC8',
      'É': '\xC9', 'Ê': '\xCA', 'Ì': '\xCC', 'Í': '\xCD', 'Ò': '\xD2',
      'Ó': '\xD3', 'Ô': '\xD4', 'Õ': '\xD5', 'Ù': '\xD9', 'Ú': '\xDA',
      'Ý': '\xDD', 'à': '\xE0', 'á': '\xE1', 'â': '\xE2', 'ã': '\xE3',
      'è': '\xE8', 'é': '\xE9', 'ê': '\xEA', 'ì': '\xEC', 'í': '\xED',
      'ò': '\xF2', 'ó': '\xF3', 'ô': '\xF4', 'õ': '\xF5', 'ù': '\xF9',
      'ú': '\xFA', 'ý': '\xFD', 'Ă': '\xC7', 'ă': '\xE7', 'Đ': '\xD0',
      'đ': '\xF0', 'Ơ': '\xCE', 'ơ': '\xEE', 'Ư': '\xDC', 'ư': '\xFC',
      'ạ': '\xA1', 'Ả': '\xA2', 'ả': '\xA2', 'Ấ': '\xA3', 'ấ': '\xA3',
      'Ầ': '\xA4', 'ầ': '\xA4', 'Ẩ': '\xA5', 'ẩ': '\xA5', 'Ẫ': '\xA6',
      'ẫ': '\xA6', 'Ậ': '\xA7', 'ậ': '\xA7', 'Ắ': '\xA8', 'ắ': '\xA8',
      'Ằ': '\xA9', 'ằ': '\xA9', 'Ẳ': '\xAA', 'ẳ': '\xAA', 'Ẵ': '\xAB',
      'ẵ': '\xAB', 'Ặ': '\xAC', 'ặ': '\xAC', 'Ẹ': '\xAD', 'ẹ': '\xAD',
      'Ẻ': '\xAE', 'ẻ': '\xAE', 'Ẽ': '\xAF', 'ẽ': '\xAF', 'Ế': '\xB0',
      'ế': '\xB0', 'Ề': '\xB1', 'ề': '\xB1', 'Ể': '\xB2', 'ể': '\xB2',
      'Ễ': '\xB3', 'ễ': '\xB3', 'Ệ': '\xB4', 'ệ': '\xB4', 'Ỉ': '\xB5',
      'ỉ': '\xB5', 'Ị': '\xB6', 'ị': '\xB6', 'Ọ': '\xB7', 'ọ': '\xB7',
      'Ỏ': '\xB8', 'ỏ': '\xB8', 'Ố': '\xB9', 'ố': '\xB9', 'Ồ': '\xBA',
      'ồ': '\xBA', 'Ổ': '\xBB', 'ổ': '\xBB', 'Ỗ': '\xBC', 'ỗ': '\xBC',
      'Ộ': '\xBD', 'ộ': '\xBD', 'Ớ': '\xBE', 'ớ': '\xBE', 'Ờ': '\xBF',
      'ờ': '\xBF', 'Ở': '\xC5', 'ở': '\xC5', 'Ỡ': '\xC6', 'ỡ': '\xC6',
      'Ợ': '\xC7', 'ợ': '\xC7', 'Ụ': '\xC8', 'ụ': '\xC8', 'Ủ': '\xC9',
      'ủ': '\xC9', 'Ứ': '\xCA', 'ứ': '\xCA', 'Ừ': '\xCB', 'ừ': '\xCB',
      'Ử': '\xCC', 'ử': '\xCC', 'Ữ': '\xCD', 'ữ': '\xCD', 'Ự': '\xCE',
      'ự': '\xCE', 'Ỳ': '\xCF', 'ỳ': '\xCF', 'Ỵ': '\xD1', 'ỵ': '\xD1',
      'Ỷ': '\xD2', 'ỷ': '\xD2', 'Ỹ': '\xD3', 'ỹ': '\xD3', 'Ạ': '\xA1',
    };
    final map = <int, int>{};
    pairs.forEach((utf, cp) {
      map[utf.codeUnitAt(0)] = cp.codeUnitAt(0);
    });
    return map;
  }
}
