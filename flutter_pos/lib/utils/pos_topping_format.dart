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
      .map((e) => e.startsWith('+') ? e : '+ $e')
      .toList();
  return parts.join('\n');
}
