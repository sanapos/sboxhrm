import 'package:flutter/material.dart';
import 'package:sbox_pos/l10n/app_tr.dart';

import '../../models/pos_product.dart';
import '../../services/api_service.dart';
import '../../utils/number_formatter.dart';
import '../notification_overlay.dart';
import 'pos_theme.dart';

class PosBarcodeHint {
  const PosBarcodeHint({
    required this.barcode,
    this.name,
    this.unitName,
    this.brandName,
    this.categoryName,
    this.imageUrl,
    this.fromCatalog = false,
  });

  final String barcode;
  final String? name;
  final String? unitName;
  final String? brandName;
  final String? categoryName;
  final String? imageUrl;
  final bool fromCatalog;

  factory PosBarcodeHint.fromLookup(Map<String, dynamic> data) {
    final catalog = data['catalog'];
    final barcode = (data['barcode'] ?? '').toString().trim();
    if (catalog is Map) {
      return PosBarcodeHint(
        barcode: (catalog['barcode'] ?? barcode).toString().trim(),
        name: catalog['name']?.toString(),
        unitName: catalog['unitName']?.toString(),
        brandName: catalog['brandName']?.toString(),
        categoryName: catalog['categoryName']?.toString(),
        imageUrl: catalog['imageUrl']?.toString(),
        fromCatalog: true,
      );
    }
    return PosBarcodeHint(barcode: barcode);
  }
}

/// Form gọn: tên (gợi ý từ điển) + giá bán / giá vốn / ĐVT.
Future<PosProduct?> showPosQuickAddByBarcode(
  BuildContext context,
  ApiService api,
  PosBarcodeHint hint,
) {
  return showModalBottomSheet<PosProduct>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => _QuickAddBarcodeSheet(api: api, hint: hint),
  );
}

class _QuickAddBarcodeSheet extends StatefulWidget {
  const _QuickAddBarcodeSheet({required this.api, required this.hint});
  final ApiService api;
  final PosBarcodeHint hint;

  @override
  State<_QuickAddBarcodeSheet> createState() => _QuickAddBarcodeSheetState();
}

class _QuickAddBarcodeSheetState extends State<_QuickAddBarcodeSheet> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _priceCtrl;
  late final TextEditingController _costCtrl;
  late final TextEditingController _unitCtrl;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.hint.name ?? '');
    _priceCtrl = TextEditingController();
    _costCtrl = TextEditingController();
    _unitCtrl = TextEditingController(
        text: (widget.hint.unitName ?? '').trim().isEmpty
            ? 'Cái'
            : widget.hint.unitName!.trim());
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _priceCtrl.dispose();
    _costCtrl.dispose();
    _unitCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    final price = parseFormattedNumber(_priceCtrl.text)?.toDouble() ?? -1;
    if (name.isEmpty) {
      NotificationOverlayManager().showError(
        title: 'Thiếu tên',
        message: tr('Nhập tên hàng hóa'),
      );
      return;
    }
    if (price < 0) {
      NotificationOverlayManager().showError(
        title: 'Thiếu giá bán',
        message: tr('Nhập giá bán để thêm vào hóa đơn'),
      );
      return;
    }
    setState(() => _saving = true);
    final res = await widget.api.createPosProductQuick({
      'barcode': widget.hint.barcode,
      'name': name,
      'basePrice': price,
      'costPrice': parseFormattedNumber(_costCtrl.text)?.toDouble() ?? 0,
      'baseUnitName': _unitCtrl.text.trim().isEmpty ? 'Cái' : _unitCtrl.text.trim(),
      if ((widget.hint.brandName ?? '').trim().isNotEmpty)
        'brandName': widget.hint.brandName!.trim(),
      if ((widget.hint.categoryName ?? '').trim().isNotEmpty)
        'categoryName': widget.hint.categoryName!.trim(),
      if ((widget.hint.imageUrl ?? '').trim().isNotEmpty)
        'imageUrl': widget.hint.imageUrl!.trim(),
    });
    if (!mounted) return;
    setState(() => _saving = false);
    if (res['isSuccess'] == true && res['data'] is Map) {
      final p = PosProduct.fromJson(res['data'] as Map<String, dynamic>);
      Navigator.pop(context, p);
      return;
    }
    NotificationOverlayManager().showError(
      title: 'Không thêm được',
      message: tr((res['message'] ?? res['errors'] ?? 'Lỗi lưu hàng hóa').toString()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final inset = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: inset),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: PosTheme.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Text(
              tr(widget.hint.fromCatalog
                  ? 'Thêm hàng từ từ điển mã vạch'
                  : 'Mã vạch chưa có trong cửa hàng'),
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text(
              tr('Mã ${widget.hint.barcode} — chỉ cần nhập giá bán, giá vốn, đơn vị'),
              style: const TextStyle(fontSize: 12, color: PosTheme.textSecondary),
            ),
            const SizedBox(height: 12),
            if ((widget.hint.imageUrl ?? '').trim().isNotEmpty) ...[
              Center(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.network(
                    widget.hint.imageUrl!.trim(),
                    height: 88,
                    width: 88,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const SizedBox(
                      height: 88,
                      width: 88,
                      child: Icon(Icons.image_not_supported_outlined),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],
            TextField(
              controller: _nameCtrl,
              textInputAction: TextInputAction.next,
              decoration: PosTheme.inputDecoration(label: 'Tên hàng'),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _priceCtrl,
                    autofocus: true,
                    keyboardType: TextInputType.number,
                    inputFormatters: [ThousandSeparatorFormatter()],
                    decoration: PosTheme.inputDecoration(label: 'Giá bán *'),
                    onSubmitted: (_) => _save(),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _costCtrl,
                    keyboardType: TextInputType.number,
                    inputFormatters: [ThousandSeparatorFormatter()],
                    decoration: PosTheme.inputDecoration(label: 'Giá vốn'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _unitCtrl,
              decoration: PosTheme.inputDecoration(
                label: 'Đơn vị tính',
                hint: 'Cái, Lon, Chai…',
              ),
            ),
            const SizedBox(height: 14),
            FilledButton(
              onPressed: _saving ? null : _save,
              style: PosTheme.filledButtonStyle,
              child: Text(tr(_saving ? 'Đang lưu…' : 'Lưu và bán')),
            ),
          ],
        ),
      ),
    );
  }
}
