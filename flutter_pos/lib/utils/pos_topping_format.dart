import 'dart:convert';

import 'package:intl/intl.dart';

import '../models/pos_sale_order.dart';

/// Chuẩn hóa SL topping (thiếu / 0 → 1 để tương thích phiếu cũ).
int posToppingQty(int? qty) {
  if (qty == null || qty < 1) return 1;
  return qty;
}

/// `TranChau` hoặc `TranChau x2`.
String posToppingNameWithQty(String name, int qty) {
  final q = posToppingQty(qty);
  final n = name.trim();
  if (n.isEmpty) return q > 1 ? 'x$q' : '';
  return q > 1 ? '$n x$q' : n;
}

/// Dòng in: `+ TranChau x2` hoặc `+ TranChau x2 (+16.000)`.
String posToppingPrintLine(
  String name,
  int qty, {
  double? unitPrice,
  NumberFormat? money,
}) {
  final q = posToppingQty(qty);
  final head = '+ ${posToppingNameWithQty(name, q)}';
  if (unitPrice == null || money == null) return head;
  final extra = unitPrice * q;
  if (extra <= 0) return head;
  return '$head (+${money.format(extra)})';
}

/// Ghi chú in: mỗi topping 1 dòng, rồi ghi chú món.
String posToppingNoteBlock({
  required Iterable<({String name, int qty, double price})> toppings,
  String? lineNote,
  bool withPrice = false,
  NumberFormat? money,
}) {
  final lines = <String>[];
  for (final t in toppings) {
    if (t.name.trim().isEmpty && t.qty < 1) continue;
    lines.add(posToppingPrintLine(
      t.name,
      t.qty,
      unitPrice: withPrice ? t.price : null,
      money: withPrice ? money : null,
    ));
  }
  final note = (lineNote ?? '').trim();
  if (note.isNotEmpty) lines.add(note);
  return lines.join('\n');
}

/// Đầu dòng món con của combo trên phiếu bếp: `- 1 Cà phê sữa` (ASCII — «•» không có trong
/// bảng mã chế độ chữ của nhiều máy nhiệt).
const posComboPartPrefix = '- ';

final _comboQty = NumberFormat('#,##0.###', 'vi_VN');

/// Dòng phụ dưới món — topping «+…», món con combo «•…» — in thụt, không gắn «*» như ghi chú.
bool posNoteIsSubLine(String text) {
  final t = text.trimLeft();
  return t.startsWith('+') || t.startsWith('(+') || t.startsWith(posComboPartPrefix);
}

/// Ghi chú phiếu bếp: món con combo (SL đã nhân số phần) trước, rồi topping / ghi chú món.
/// Trước phiếu combo chỉ có tên combo — bếp không biết phải làm những món gì.
String? posKitchenNoteWithComboParts(
  Iterable<({String name, double qty})> parts,
  String? note,
) {
  final lines = [
    for (final p in parts)
      if (p.name.trim().isNotEmpty) '$posComboPartPrefix${_comboQty.format(p.qty)} ${p.name.trim()}',
    if ((note ?? '').trim().isNotEmpty) note!.trim(),
  ];
  return lines.isEmpty ? null : lines.join('\n');
}

String posToppingNoteFromSaleLine(
  PosSaleOrderLine line, {
  bool withPrice = false,
  NumberFormat? money,
}) =>
    posToppingNoteBlock(
      toppings: line.toppings.map((t) => (
            name: t.name,
            qty: t.qty,
            price: t.price,
          )),
      lineNote: line.lineNote,
      withPrice: withPrice,
      money: money,
    );

String posToppingLabelText(String? toppings) {
  final raw = (toppings ?? '').trim();
  if (raw.isEmpty) return '';
  final parts = raw
      .split(RegExp(r'[\n,;]+'))
      .map((e) => e.trim())
      .where((e) => e.isNotEmpty)
      .map((e) => posNoteIsSubLine(e) ? e : '+ $e')
      .toList();
  return parts.join('\n');
}

/// Đầu tên món trên phiếu bổ sung — cùng chuỗi với PosKitchenContent.AddOnPrefix phía API.
const posKitchenAddOnPrefix = 'BỔ SUNG: ';

/// Topping + ghi chú lúc báo bếp (`{t, n}`) — cùng dạng với PosKitchenContent.Serialize phía API.
String posKitchenContentEncode(String? toppingsJson, String? lineNote) =>
    jsonEncode({'t': toppingsJson ?? '', 'n': (lineNote ?? '').trim()});

/// Phần chênh lệch so với lúc báo bếp, để in phiếu bổ sung: `+ Trân châu x2`, `- Bỏ thạch`, ghi chú mới.
/// Trước đây đổi topping là báo lại cả món — bếp làm thêm một phần. Chưa có mốc / không đổi → rỗng.
List<String> posKitchenChangeLines({
  required String? sentContent,
  required Iterable<PosSaleLineTopping> toppings,
  String? lineNote,
}) {
  if (sentContent == null || sentContent.trim().isEmpty) return const [];
  final Map<String, dynamic> sent;
  try {
    final decoded = jsonDecode(sentContent);
    if (decoded is! Map) return const [];
    sent = Map<String, dynamic>.from(decoded);
  } catch (_) {
    return const [];
  }
  Map<String, ({String name, int qty})> group(Iterable<PosSaleLineTopping> list) {
    final out = <String, ({String name, int qty})>{};
    for (final t in list) {
      final key = t.id.trim().isNotEmpty ? t.id.trim().toLowerCase() : t.name.trim();
      out[key] = (name: t.name.trim(), qty: (out[key]?.qty ?? 0) + posToppingQty(t.qty));
    }
    return out;
  }

  final before = group(parsePosSaleLineToppings(sent['t']));
  final after = group(toppings);
  final lines = <String>[];
  after.forEach((key, t) {
    final diff = t.qty - (before[key]?.qty ?? 0);
    if (diff > 0) lines.add('+ ${posToppingNameWithQty(t.name, diff)}');
  });
  before.forEach((key, t) {
    final diff = t.qty - (after[key]?.qty ?? 0);
    if (diff > 0) lines.add('- Bỏ ${posToppingNameWithQty(t.name, diff)}');
  });
  final oldNote = (sent['n'] ?? '').toString().trim();
  final note = (lineNote ?? '').trim();
  if (note != oldNote) lines.add(note.isNotEmpty ? note : 'Bỏ ghi chú: $oldNote');
  return lines;
}
