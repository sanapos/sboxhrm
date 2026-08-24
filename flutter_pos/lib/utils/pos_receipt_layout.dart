/// Layout cột chung cho phiếu nhiệt K58 (32 ký tự) / K80 (48 ký tự).
/// Một hàng: Tên hàng | SL | Đ.giá | T.tiền. Tiền dành cột từ mép phải — không cắt, không wrap.
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
      return const PosReceiptLayout._(
        k58: true,
        chars: 32,
        nameW: 8,
        qtyW: 4,
        priceW: 10,
        totalW: 10,
      );
    }
    return const PosReceiptLayout._(
      k58: false,
      chars: 48,
      nameW: 22,
      qtyW: 4,
      priceW: 11,
      totalW: 11,
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
  String get equals => List.filled(k58 ? 48 : 64, '=').join();
  String get doubleDash => equals;

  /// Tiền đầy đủ có chấm nghìn — dòng tổng cộng.
  static String moneyItem(double v) => _withDots(v.round());

  /// Cột Đ.giá / T.tiền hàng: `500k`, `1.5tr` — tên hàng rộng hơn, không cắt số.
  static String moneyItemCompact(double v) {
    final n = v.round();
    final neg = n < 0;
    final abs = n.abs();
    String body;
    if (abs < 1000) {
      body = abs.toString();
    } else if (abs < 1000000) {
      if (abs % 1000 == 0) {
        body = '${abs ~/ 1000}k';
      } else if (abs % 100 == 0) {
        final k = abs / 1000;
        body = k.truncateToDouble() == k
            ? '${k.toInt()}k'
            : '${k.toStringAsFixed(1)}k';
      } else {
        body = _withDots(abs);
      }
    } else if (abs % 1000000 == 0) {
      body = '${abs ~/ 1000000}tr';
    } else if (abs % 100000 == 0) {
      final tr = abs / 1000000;
      body = tr.truncateToDouble() == tr
          ? '${tr.toInt()}tr'
          : '${tr.toStringAsFixed(1)}tr';
    } else if (abs % 1000 == 0) {
      body = '${_withDots(abs ~/ 1000)}k';
    } else {
      body = _withDots(abs);
    }
    return neg ? '-$body' : body;
  }

  /// HD150820260015 → HD15082026 - 0015
  static String formatSaleInvoiceNo(String raw) {
    final s = raw.trim();
    if (s.isEmpty || s == '—' || s == '-') return s;
    final upper = s.toUpperCase();
    if (!upper.startsWith('HD')) return s;
    final digits = s.substring(2);
    if (!RegExp(r'^\d+$').hasMatch(digits)) return s;
    if (digits.length >= 12 && _isDdMmYyyy(digits.substring(0, 8))) {
      return 'HD${digits.substring(0, 8)} - ${digits.substring(8)}';
    }
    if (digits.length >= 10 && _isDdMmYy(digits.substring(0, 6))) {
      return 'HD${digits.substring(0, 6)} - ${digits.substring(6)}';
    }
    return s;
  }

  static bool _isDdMmYyyy(String d) {
    final dd = int.tryParse(d.substring(0, 2)) ?? 0;
    final mm = int.tryParse(d.substring(2, 4)) ?? 0;
    final yy = int.tryParse(d.substring(4, 8)) ?? 0;
    return dd >= 1 && dd <= 31 && mm >= 1 && mm <= 12 && yy >= 2000 && yy <= 2100;
  }

  static bool _isDdMmYy(String d) {
    final dd = int.tryParse(d.substring(0, 2)) ?? 0;
    final mm = int.tryParse(d.substring(2, 4)) ?? 0;
    return dd >= 1 && dd <= 31 && mm >= 1 && mm <= 12;
  }

  static String _withDots(int n) {
    final neg = n < 0;
    final s = n.abs().toString();
    final buf = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write('.');
      buf.write(s[i]);
    }
    return neg ? '-$buf' : buf.toString();
  }

  List<String> get saleHeaders => [saleHeader];

  List<String> get saleHeadersVi => [saleHeaderVi];

  String get saleHeader =>
      saleLine(name: 'Ten hang', qty: 'SL', price: 'D.gia', total: 'T.tien');

  String get saleHeaderVi =>
      saleLine(name: 'Tên hàng', qty: 'SL', price: 'Đ.giá', total: 'T.tiền');

  /// Header phiếu bếp: Tên hàng ........................ SL
  String get kitchenHeader {
    final left = _fit('Ten hang', chars - qtyW - 1);
    return '$left ${_fitRight('SL', qtyW)}';
  }

  String get kitchenHeaderVi {
    final left = _fit('Tên hàng', chars - qtyW - 1);
    return '$left ${_fitRight('SL', qtyW)}';
  }

  /// Khối SL + Đ.giá + T.tiền — in cột phải Sunmi (printRow 5+7).
  String qtyPriceTotal({
    required String qty,
    required String price,
    required String total,
  }) {
    final q = qty.trim();
    final p = price.trim();
    final t = total.trim();
    return '${_fitRight(q, qtyW)}${_fitRight(p, priceW)}${_fitRight(t, totalW)}';
  }

  /// Một hàng Tên | SL | Đ.giá | T.tiền. Tiền giữ nguyên từ mép phải.
  String saleLine({
    required String name,
    required String qty,
    required String price,
    required String total,
  }) {
    final q = qty.trim();
    final p = price.trim();
    final t = total.trim();
    final qw = q.length > qtyW ? q.length : qtyW;
    final pw = p.length > priceW ? p.length : priceW;
    final tw = t.length > totalW ? t.length : totalW;
    final right = '${_fitRight(q, qw)}${_fitRight(p, pw)}${_fitRight(t, tw)}';
    final leftW = (chars - right.length).clamp(2, chars);
    return '${_fit(name.trim(), leftW)}$right';
  }

  /// Dòng HĐ: tên + SL + đơn giá + thành tiền cùng hàng; tên dài mới xuống dòng (không kéo tiền).
  List<String> saleItemRows({
    required String name,
    required String qty,
    required String price,
    required String total,
    String? originalPrice,
  }) {
    final q = qty.trim();
    final p = price.trim();
    final t = total.trim();
    final qw = q.length > qtyW ? q.length : qtyW;
    final pw = p.length > priceW ? p.length : priceW;
    final tw = t.length > totalW ? t.length : totalW;
    final right = '${_fitRight(q, qw)}${_fitRight(p, pw)}${_fitRight(t, tw)}';
    final leftW = (chars - right.length).clamp(2, chars);
    final label = name.trim().isEmpty ? 'Mon' : name.trim();
    final chunks = wrap(label, leftW);
    final rows = <String>[
      '${_fit(chunks.first, leftW)}$right',
      for (var i = 1; i < chunks.length; i++) _fit(chunks[i], leftW),
    ];
    final orig = originalPrice?.trim();
    if (orig != null && orig.isNotEmpty) {
      rows.add(pair('  ~$orig', ''));
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

  /// Nhãn trái + giá trị phải. Không cắt [value].
  String pair(String label, String value) {
    final l = label.trim();
    final r = value.trim();
    if (r.isEmpty) return _fit(l, chars);
    final space = chars - l.length - r.length;
    if (space < 1) {
      final keep = (chars - r.length - 1).clamp(1, chars);
      return '${_fit(l, keep)} $r';
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
    if (width <= 0) return s;
    if (s.length >= width) return s;
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
