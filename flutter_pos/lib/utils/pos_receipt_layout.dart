/// Layout cột chung cho phiếu nhiệt K58 (32 ký tự) / K80 (48 ký tự).
/// Mẫu tham chiếu: phiếu bếp (Tên hàng|SL) + hóa đơn (Tên hàng|Đ.giá|SL|TT).
class PosReceiptLayout {
  const PosReceiptLayout._({
    required this.k58,
    required this.chars,
    required this.nameW,
    required this.qtyW,
    required this.priceW,
    required this.totalW,
  });

  factory PosReceiptLayout.fromMm(int paperWidthMm) {
    if (paperWidthMm <= 58) {
      // K58: tên rộng hơn, tiền gọn (không chấm nghìn trên cột hẹp).
      return const PosReceiptLayout._(
        k58: true,
        chars: 32,
        nameW: 14,
        qtyW: 4,
        priceW: 6,
        totalW: 6,
      );
    }
    return const PosReceiptLayout._(
      k58: false,
      chars: 48,
      nameW: 22,
      qtyW: 4,
      priceW: 9,
      totalW: 10,
    );
  }

  factory PosReceiptLayout.fromSettingsChars(int maxChars) =>
      PosReceiptLayout.fromMm(maxChars <= 32 ? 58 : 80);

  final bool k58;
  final int chars;
  final int nameW;
  final int qtyW;
  final int priceW;
  final int totalW;

  String get dash => List.filled(chars, '-').join();
  /// '=' hẹp hơn chữ thường trên máy nhiệt — cần nhiều hơn chars cột để full khổ.
  String get equals => List.filled(k58 ? 46 : 60, '=').join();
  String get doubleDash => equals;

  /// Header hóa đơn: Tên hàng | Đ.giá | SL | TT
  String get saleHeader {
    final name = _fit('Ten hang', nameW);
    final price = _fitRight('D.gia', priceW);
    final qty = _fitRight('SL', qtyW);
    final total = _fitRight('TT', totalW);
    return '$name $price $qty $total';
  }

  String get saleHeaderVi {
    final name = _fit('Tên hàng', nameW);
    final price = _fitRight('Đ.giá', priceW);
    final qty = _fitRight('SL', qtyW);
    final total = _fitRight('TT', totalW);
    return '$name $price $qty $total';
  }

  /// Header phiếu bếp: Tên hàng ........................ SL
  String get kitchenHeader {
    final left = _fit('Ten hang', chars - qtyW - 1);
    return '$left ${_fitRight('SL', qtyW)}';
  }

  String get kitchenHeaderVi {
    final left = _fit('Tên hàng', chars - qtyW - 1);
    return '$left ${_fitRight('SL', qtyW)}';
  }

  /// Dòng HĐ: tên trái + Đ.giá + SL + TT. Giá gốc (nếu CK) nằm dòng dưới cột Đ.giá.
  List<String> saleItemRows({
    required String name,
    required String qty,
    required String price,
    required String total,
    String? originalPrice,
  }) {
    final chunks = wrap(name.trim().isEmpty ? 'Mon' : name.trim(), nameW);
    final rows = <String>[
      '${_fit(chunks.first, nameW)} ${_fitRight(price, priceW)} ${_fitRight(qty, qtyW)} ${_fitRight(total, totalW)}',
    ];
    for (var i = 1; i < chunks.length; i++) {
      rows.add(_fit(chunks[i], nameW));
    }
    final orig = originalPrice?.trim();
    if (orig != null && orig.isNotEmpty) {
      // Giá gốc dưới Đ.giá (ESC/POS không gạch ngang — dùng dấu ~).
      rows.add(
        '${' ' * nameW} ${_fitRight('~$orig', priceW)} ${' ' * qtyW} ${' ' * totalW}',
      );
    }
    return rows;
  }

  /// Dòng bếp: «1. Tên» trái, «SL ĐVT» phải cùng 1 dòng (không tách Cái xuống hàng).
  List<String> kitchenItemRows({
    required int index,
    required String name,
    required String qty,
    String? unit,
    String? note,
  }) {
    final rightW = k58 ? 8 : 10;
    final leftW = chars - rightW - 1;
    final labeled = '${index}. ${name.trim().isEmpty ? 'Mon' : name.trim()}';
    final u = unit?.trim();
    final right = (u != null && u.isNotEmpty) ? '$qty $u' : qty;
    final chunks = wrap(labeled, leftW);
    final rows = <String>[
      '${_fit(chunks.first, leftW)} ${_fitRight(right, rightW)}',
    ];
    for (var i = 1; i < chunks.length; i++) {
      rows.add(_fit(chunks[i], leftW));
    }
    final n = note?.trim();
    if (n != null && n.isNotEmpty) {
      rows.add(' * $n');
    }
    return rows;
  }

  String pair(String label, String value) {
    final l = label.trim();
    final r = value.trim();
    final space = chars - l.length - r.length;
    if (space < 1) {
      return '${_fit(l, (chars - r.length - 1).clamp(1, chars))} $r';
    }
    return '$l${' ' * space}$r';
  }

  String center(String text) {
    final t = text.trim();
    if (t.length >= chars) return t.substring(0, chars);
    final pad = (chars - t.length) ~/ 2;
    return '${' ' * pad}$t';
  }

  static String _fit(String s, int width) {
    if (width <= 0) return '';
    if (s.length == width) return s;
    if (s.length > width) return s.substring(0, width);
    return s.padRight(width);
  }

  static String _fitRight(String s, int width) {
    if (width <= 0) return '';
    if (s.length == width) return s;
    if (s.length > width) return s.substring(s.length - width);
    return s.padLeft(width);
  }

  static List<String> wrap(String text, int width) {
    if (width <= 0) return [text];
    if (text.isEmpty) return [''];
    final out = <String>[];
    var rest = text;
    while (rest.length > width) {
      out.add(rest.substring(0, width));
      rest = rest.substring(width);
    }
    out.add(rest);
    return out;
  }
}
