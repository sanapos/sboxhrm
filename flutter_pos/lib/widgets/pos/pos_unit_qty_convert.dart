import 'package:flutter/material.dart';
import 'package:sbox_pos/l10n/app_tr.dart';

import '../../models/pos_product.dart';
import '../../services/api_service.dart';

/// ĐVT quy đổi của hàng (bảng đơn vị: Thùng = 24 Lon…) — cache theo phiên để các dòng phiếu không gọi lặp.
final Map<String, Future<List<PosProductUnit>>> _unitCache = {};

Future<List<PosProductUnit>> loadPosConversionUnits(ApiService api, String productId) {
  return _unitCache.putIfAbsent(productId, () async {
    final res = await api.getPosProductUnits(productId);
    if (res['isSuccess'] != true || res['data'] is! List) {
      _unitCache.remove(productId);
      return const <PosProductUnit>[];
    }
    return [
      for (final e in res['data'] as List)
        if (e is Map) PosProductUnit.fromJson(Map<String, dynamic>.from(e)),
    ].where((u) => !u.isBaseUnit && u.conversionRate > 0 && u.conversionRate != 1).toList()
      ..sort((a, b) => b.conversionRate.compareTo(a.conversionRate));
  });
}

/// Bỏ cache khi vừa sửa ĐVT của hàng.
void invalidatePosConversionUnits([String? productId]) =>
    productId == null ? _unitCache.clear() : _unitCache.remove(productId);

String _fmt(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();

/// Hộp thoại «2 Thùng + 5 Lon = 53 Lon» → trả về SL theo đơn vị cơ bản.
Future<double?> showPosUnitQtyConvertDialog(
  BuildContext context, {
  required String productName,
  required String baseUnit,
  required List<PosProductUnit> units,
  String title = 'Quy đổi số lượng',
}) {
  final ctrls = {for (final u in units) u.id: TextEditingController()};
  final baseCtrl = TextEditingController();
  double parse(TextEditingController c) => double.tryParse(c.text.trim().replaceAll(',', '.')) ?? 0;
  double total() =>
      units.fold<double>(0, (s, u) => s + parse(ctrls[u.id]!) * u.conversionRate) + parse(baseCtrl);
  return showDialog<double>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setDlg) {
        Widget row(String label, TextEditingController c) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: TextField(
                controller: c,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: label,
                  isDense: true,
                  border: const OutlineInputBorder(),
                ),
                onChanged: (_) => setDlg(() {}),
              ),
            );
        final t = total();
        return AlertDialog(
          title: Text(tr(title)),
          content: SizedBox(
            width: 340,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(tr(productName), style: const TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 12),
                for (final u in units)
                  row('${u.unitName} (= ${_fmt(u.conversionRate)} $baseUnit)', ctrls[u.id]!),
                row('$baseUnit lẻ', baseCtrl),
                Text(tr('= ${_fmt(t)} $baseUnit'),
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Theme.of(ctx).colorScheme.primary)),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr('Hủy'))),
            FilledButton(
              onPressed: t > 0 ? () => Navigator.pop(ctx, t) : null,
              child: Text(tr('Áp dụng')),
            ),
          ],
        );
      },
    ),
  );
}

/// Nút nhỏ «Quy đổi» cạnh ô số lượng — chỉ hiện khi hàng có ĐVT quy đổi (thùng, hộp, lốc…).
class PosUnitConvertButton extends StatelessWidget {
  const PosUnitConvertButton({
    super.key,
    required this.api,
    required this.productId,
    required this.productName,
    required this.baseUnit,
    required this.onQty,
    this.compact = false,
  });

  final ApiService api;
  final String productId;
  final String productName;
  final String baseUnit;
  final ValueChanged<double> onQty;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<PosProductUnit>>(
      future: loadPosConversionUnits(api, productId),
      builder: (context, snap) {
        final units = snap.data ?? const <PosProductUnit>[];
        if (units.isEmpty) return const SizedBox.shrink();
        Future<void> open() async {
          final v = await showPosUnitQtyConvertDialog(
            context,
            productName: productName,
            baseUnit: baseUnit.isEmpty ? 'đơn vị' : baseUnit,
            units: units,
          );
          if (v != null) onQty(v);
        }

        final hint = units.map((u) => '${u.unitName} ${_fmt(u.conversionRate)}').join(' · ');
        if (compact) {
          return IconButton(
            tooltip: tr('Quy đổi ($hint)'),
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.swap_horiz_rounded, size: 20),
            onPressed: open,
          );
        }
        return TextButton.icon(
          onPressed: open,
          style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
          icon: const Icon(Icons.swap_horiz_rounded, size: 18),
          label: Text(tr('Quy đổi ($hint)'), style: const TextStyle(fontSize: 12)),
        );
      },
    );
  }
}
