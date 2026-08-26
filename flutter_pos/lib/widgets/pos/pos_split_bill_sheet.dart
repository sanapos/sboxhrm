import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/pos_sale_order.dart';
import '../pos/pos_theme.dart';
import 'package:sbox_pos/l10n/app_tr.dart';

class PosSplitBillPick {
  const PosSplitBillPick({required this.lineId, required this.qty});
  final String lineId;
  final double qty;
}

String posSplitBillErrorMessage(String? raw) {
  final msg = (raw ?? '').trim();
  final lower = msg.toLowerCase();
  if (lower.contains('không có quyền') || lower.contains('quyen')) {
    return 'Tài khoản không được tách bill. Cần quyền bán hàng (tạo hoặc sửa đơn).';
  }
  return msg.isEmpty ? 'Tách bill thất bại' : msg;
}

/// Chọn món + SL để tách bill (phần còn lại giữ bàn).
Future<List<PosSplitBillPick>?> showPosSplitBillSheet({
  required BuildContext context,
  required List<PosSaleOrderLine> lines,
}) {
  return showModalBottomSheet<List<PosSplitBillPick>>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (ctx) => _SplitBillSheet(lines: lines),
  );
}

class _SplitBillSheet extends StatefulWidget {
  const _SplitBillSheet({required this.lines});
  final List<PosSaleOrderLine> lines;

  @override
  State<_SplitBillSheet> createState() => _SplitBillSheetState();
}

class _SplitBillSheetState extends State<_SplitBillSheet> {
  final _qtyFmt = NumberFormat('#,##0.##', 'vi_VN');
  final _money = NumberFormat('#,##0', 'vi_VN');
  late final Map<String, double> _qty;

  @override
  void initState() {
    super.initState();
    _qty = {
      for (var i = 0; i < widget.lines.length; i++)
        if (_lineKey(widget.lines[i], i).isNotEmpty)
          _lineKey(widget.lines[i], i): 0,
    };
  }

  String _lineKey(PosSaleOrderLine l, int index) {
    final id = (l.id ?? '').trim();
    if (id.isNotEmpty && id != 'null') return id;
    return '';
  }

  double get _sourceQty =>
      widget.lines.fold<double>(0, (s, l) => s + l.qty);
  double get _takeQty => _qty.values.fold<double>(0, (s, v) => s + v);
  bool get _canConfirm => _takeQty > 0 && _takeQty < _sourceQty;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 12,
          bottom: 16 + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              tr('Tách hóa đơn'),
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 4),
            Text(
              tr('Chọn món khách trả trước. Phần còn lại giữ nguyên bàn.'),
              style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
            ),
            const SizedBox(height: 12),
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.5,
              ),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: widget.lines.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (ctx, i) {
                  final l = widget.lines[i];
                  final id = _lineKey(l, i);
                  final unsaved = id.isEmpty;
                  final take = unsaved ? 0.0 : (_qty[id] ?? 0);
                  final on = take > 0;
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Row(
                      children: [
                        Checkbox(
                          value: on,
                          activeColor: PosTheme.kiotBlue,
                          onChanged: unsaved
                              ? null
                              : (v) => setState(() {
                                    _qty[id] = v == true ? l.qty : 0;
                                  }),
                        ),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                tr(l.productName.isEmpty ? 'Món' : l.productName),
                                style: const TextStyle(
                                    fontWeight: FontWeight.w700, fontSize: 14),
                              ),
                              Text(
                                tr(unsaved
                                    ? 'Chưa lưu dòng — đóng sheet, đợi 1 giây rồi tách lại'
                                    : 'SL ${_qtyFmt.format(l.qty)} · ${_money.format(l.lineTotal)}'),
                                style: TextStyle(
                                    fontSize: 12, color: Colors.grey.shade600),
                              ),
                            ],
                          ),
                        ),
                        if (l.qty > 1 && on)
                          Row(
                            children: [
                              IconButton(
                                visualDensity: VisualDensity.compact,
                                onPressed: take <= 1
                                    ? null
                                    : () => setState(() => _qty[id] = take - 1),
                                icon: const Icon(Icons.remove_circle_outline),
                              ),
                              Text(
                                _qtyFmt.format(take),
                                style: const TextStyle(
                                    fontWeight: FontWeight.w800),
                              ),
                              IconButton(
                                visualDensity: VisualDensity.compact,
                                onPressed: take >= l.qty
                                    ? null
                                    : () => setState(() => _qty[id] = take + 1),
                                icon: const Icon(Icons.add_circle_outline),
                              ),
                            ],
                          ),
                      ],
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _canConfirm
                  ? () {
                      final picks = <PosSplitBillPick>[];
                      for (final e in _qty.entries) {
                        if (e.value <= 0) continue;
                        picks.add(PosSplitBillPick(lineId: e.key, qty: e.value));
                      }
                      Navigator.pop(context, picks);
                    }
                  : null,
              style: FilledButton.styleFrom(
                backgroundColor: PosTheme.kiotBlue,
                minimumSize: const Size(0, 48),
              ),
              child: Text(tr(
                _canConfirm
                    ? 'Tách ${_qtyFmt.format(_takeQty)} phần để thanh toán'
                    : 'Chọn món — không tách hết bàn',
              )),
            ),
          ],
        ),
      ),
    );
  }
}
