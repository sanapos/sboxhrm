import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../providers/permission_provider.dart';
import '../../services/api_service.dart';
import '../../widgets/notification_overlay.dart';
import '../../widgets/pos/pos_theme.dart';
import 'package:sbox_pos/l10n/app_tr.dart';

/// Hàng cần nhập thêm: tồn ≤ tồn tối thiểu, số lượng gợi ý = tồn tối đa − tồn.
/// Chọn dòng → tạo phiếu nhập NHÁP theo từng nhà cung cấp (vào Nhập hàng để kiểm và hoàn thành).
class PosReorderSuggestionsScreen extends StatefulWidget {
  const PosReorderSuggestionsScreen({super.key});

  @override
  State<PosReorderSuggestionsScreen> createState() => _PosReorderSuggestionsScreenState();
}

class _Row {
  _Row(this.raw) : qty = (raw['suggestQty'] as num?)?.toDouble() ?? 1;
  final Map<String, dynamic> raw;
  double qty;
  bool selected = true;
  String get id => '${raw['productId']}';
  String get supplierKey => '${raw['supplierId'] ?? ''}';
  String get supplierName => (raw['supplierName'] as String?)?.trim().isNotEmpty == true
      ? raw['supplierName'] as String
      : 'Chưa gán nhà cung cấp';
  double get cost => (raw['costPrice'] as num?)?.toDouble() ?? 0;
}

class _PosReorderSuggestionsScreenState extends State<PosReorderSuggestionsScreen> {
  final _api = ApiService();
  final _money = NumberFormat('#,###', 'vi_VN');
  final _qtyFmt = NumberFormat('#,##0.##', 'vi_VN');
  List<_Row> _rows = [];
  bool _loading = true;
  bool _creating = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final res = await _api.getPosReorderSuggestions();
    if (!mounted) return;
    if (res['isSuccess'] == true && res['data'] is Map) {
      final items = ((res['data'] as Map)['items'] as List? ?? const [])
          .map((e) => _Row(Map<String, dynamic>.from(e as Map)))
          .toList();
      setState(() {
        _rows = items;
        _loading = false;
      });
    } else {
      setState(() {
        _loading = false;
        _error = res['message']?.toString() ?? 'Không tải được danh sách';
      });
    }
  }

  Map<String, List<_Row>> get _groups {
    final m = <String, List<_Row>>{};
    for (final r in _rows) {
      m.putIfAbsent(r.supplierKey, () => []).add(r);
    }
    return m;
  }

  Future<void> _createDrafts() async {
    final picked = _rows.where((r) => r.selected && r.qty > 0).toList();
    if (picked.isEmpty) return;
    setState(() => _creating = true);
    var ok = 0;
    final errors = <String>[];
    final bySupplier = <String, List<_Row>>{};
    for (final r in picked) {
      bySupplier.putIfAbsent(r.supplierKey, () => []).add(r);
    }
    for (final entry in bySupplier.entries) {
      final res = await _api.createPosPurchaseReceipt({
        'supplierId': entry.key.isEmpty ? null : entry.key,
        'note': 'Phiếu nháp từ «Hàng cần nhập thêm»',
        'discountAmount': 0,
        'discountIsPercent': false,
        'discountInput': 0,
        'paidAmount': 0,
        'complete': false,
        'lines': [
          for (final r in entry.value)
            {
              'productId': r.id,
              'variantId': null,
              'qty': r.qty,
              'costPrice': r.cost,
              'discountAmount': 0,
              'vatRate': 0,
              'vatIncluded': false,
              'vatExempt': false,
              'unitName': r.raw['unitName'],
              'lineNote': null,
            },
        ],
      });
      if (res['isSuccess'] == true) {
        ok++;
      } else {
        errors.add('${entry.value.first.supplierName}: ${res['message'] ?? 'lỗi'}');
      }
    }
    if (!mounted) return;
    setState(() => _creating = false);
    if (ok > 0) {
      NotificationOverlayManager().showSuccess(
        title: 'Đã tạo phiếu nhập nháp',
        message: tr('$ok phiếu — vào Kho → Nhập hàng để kiểm tra và hoàn thành'),
      );
    }
    if (errors.isNotEmpty) {
      NotificationOverlayManager().showError(title: 'Một số phiếu lỗi', message: errors.join('\n'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final canCreateReceipt =
        Provider.of<PermissionProvider>(context).canCreate('PosPurchaseReceipts');
    final selected = _rows.where((r) => r.selected).toList();
    final total = selected.fold<double>(0, (s, r) => s + r.qty * r.cost);
    return Scaffold(
      appBar: AppBar(
        title: Text(tr('Hàng cần nhập thêm')),
        actions: [IconButton(onPressed: _load, icon: const Icon(Icons.refresh))],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(tr(_error!)))
              : _rows.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          tr('Không có hàng dưới tồn tối thiểu.\nĐặt «Tồn tối thiểu» trong thông tin hàng hóa để hệ thống nhắc nhập.'),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    )
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 96),
                      children: [
                        for (final g in _groups.values) ...[
                          Padding(
                            padding: const EdgeInsets.fromLTRB(4, 12, 4, 6),
                            child: Text(tr(g.first.supplierName),
                                style: const TextStyle(fontWeight: FontWeight.w700, color: PosTheme.kiotBlue)),
                          ),
                          for (final r in g) _rowTile(r),
                        ],
                      ],
                    ),
      bottomNavigationBar: _rows.isEmpty
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        tr('${selected.length} mặt hàng · ~${_money.format(total)}đ'),
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                    FilledButton.icon(
                      style: PosTheme.filledButtonStyle,
                      onPressed: !canCreateReceipt || selected.isEmpty || _creating ? null : _createDrafts,
                      icon: _creating
                          ? const SizedBox(
                              width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.post_add, size: 18),
                      label: Text(tr('Tạo phiếu nhập nháp')),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _rowTile(_Row r) {
    final onHand = (r.raw['onHand'] as num?)?.toDouble() ?? 0;
    final min = (r.raw['minStock'] as num?)?.toDouble() ?? 0;
    final out = onHand <= 0;
    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 6, 10, 6),
        child: Row(
          children: [
            Checkbox(value: r.selected, onChanged: (v) => setState(() => r.selected = v ?? false)),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${r.raw['name']}',
                      maxLines: 2, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  Text(
                    tr('Tồn ${_qtyFmt.format(onHand)} / tối thiểu ${_qtyFmt.format(min)} ${r.raw['unitName'] ?? ''}'),
                    style: TextStyle(fontSize: 12, color: out ? Colors.red.shade700 : PosTheme.textSecondary),
                  ),
                ],
              ),
            ),
            SizedBox(
              width: 84,
              child: TextFormField(
                initialValue: _qtyFmt.format(r.qty),
                textAlign: TextAlign.right,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
                decoration: PosTheme.inputDecoration(label: 'Nhập'),
                onChanged: (v) => setState(() =>
                    r.qty = double.tryParse(v.replaceAll('.', '').replaceAll(',', '.')) ?? 0),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
