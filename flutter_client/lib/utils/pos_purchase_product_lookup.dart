import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/pos_product.dart';
import '../services/api_service.dart';
import '../widgets/pos/pos_quick_add_barcode_sheet.dart';
import '../widgets/pos/pos_theme.dart';
import 'package:zkteco_flutter_client/l10n/app_tr.dart';

/// Kết quả tìm hàng cho phiếu nhập/trả NCC.
class PosPurchaseLookupPick {
  const PosPurchaseLookupPick({
    required this.product,
    this.variantId,
    this.unitId,
    this.unitLabel,
    this.qty,
  });

  final PosProduct product;
  final String? variantId;
  final String? unitId;
  final String? unitLabel;
  /// SL chọn khi multi-pick (null = 1).
  final double? qty;
}

/// Quét mã / SKU chính xác hoặc tìm theo tên — hiện danh sách chọn nếu nhiều kết quả.
/// [offerQuickCreate]: mã chưa có thì gợi ý thêm hàng (giá bán / vốn / ĐVT).
Future<PosPurchaseLookupPick?> lookupOrPickPosProduct(
  BuildContext context,
  ApiService api,
  String query, {
  bool offerQuickCreate = true,
}) async {
  final q = query.trim();
  if (q.isEmpty) return null;

  final lookup = await api.lookupPosSellItem(q);
  if (lookup['isSuccess'] == true && lookup['data'] is Map) {
    final data = Map<String, dynamic>.from(lookup['data'] as Map);
    final match = data['matchType']?.toString();
    if (match == 'variant' || match == 'product') {
      final fromExact = await _pickFromExact(api, data);
      if (fromExact != null) return fromExact;
    }
    if (offerQuickCreate &&
        (match == 'catalog' || (match == 'none' && _looksLikeBarcode(q))) &&
        context.mounted) {
      var hint = PosBarcodeHint.fromLookup(data);
      if (hint.barcode.isEmpty) hint = PosBarcodeHint(barcode: q);
      final created = await showPosQuickAddByBarcode(context, api, hint);
      if (created != null) return PosPurchaseLookupPick(product: created);
      return null;
    }
  }

  final searchRes = await api.getPosProducts(search: q, pageSize: 30);
  if (searchRes['isSuccess'] != true || searchRes['data'] is! Map) {
    return _maybeQuickAdd(context, api, q, offerQuickCreate);
  }

  final rawItems = (searchRes['data'] as Map)['items'] as List? ?? [];
  final items = rawItems
      .map((e) => PosProduct.fromJson(e as Map<String, dynamic>))
      .toList();

  if (items.isEmpty) {
    return _maybeQuickAdd(context, api, q, offerQuickCreate);
  }
  if (items.length == 1) {
    return _enrichProduct(api, items.first);
  }

  if (!context.mounted) return null;
  final picked = await showModalBottomSheet<PosProduct>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => _ProductPickSheet(query: q, items: items),
  );
  if (picked == null) return null;
  return _enrichProduct(api, picked);
}

bool _looksLikeBarcode(String q) {
  final t = q.trim();
  if (t.length < 6) return false;
  final digits = t.replaceAll(RegExp(r'[\s-]'), '');
  return RegExp(r'^\d{6,18}$').hasMatch(digits);
}

Future<PosPurchaseLookupPick?> _maybeQuickAdd(
  BuildContext context,
  ApiService api,
  String q,
  bool offerQuickCreate,
) async {
  if (!offerQuickCreate || !_looksLikeBarcode(q) || !context.mounted) {
    return null;
  }
  final created = await showPosQuickAddByBarcode(
    context,
    api,
    PosBarcodeHint(barcode: q),
  );
  if (created == null) return null;
  return PosPurchaseLookupPick(product: created);
}

Future<PosPurchaseLookupPick?> _pickFromExact(
    ApiService api, Map<String, dynamic> data) async {
  final matchType = data['matchType']?.toString();

  if (matchType == 'variant' && data['variant'] is Map) {
    final variantMap = data['variant'] as Map<String, dynamic>;
    final productId = data['productId']?.toString() ?? '';
    final variant = PosProductVariant.fromJson(variantMap);
    final stub = PosProduct(
      id: productId,
      productCode: variantMap['productCode']?.toString() ?? variant.skuCode,
      name: variantMap['productName']?.toString() ?? variant.name,
      costPrice: variant.costPrice,
      basePrice: variant.basePrice,
      onHandQty: variant.onHandQty,
      variantCount: 1,
    );
    final enriched = await _enrichProduct(api, stub);
    return PosPurchaseLookupPick(
        product: enriched?.product ?? stub, variantId: variant.id);
  }

  if (matchType == 'product' && data['product'] is Map) {
    final p = PosProduct.fromJson(data['product'] as Map<String, dynamic>);
    return _enrichProduct(api, p);
  }

  return null;
}

Future<PosPurchaseLookupPick?> _enrichProduct(ApiService api, PosProduct p) async {
  final res = await api.getPosProduct(p.id);
  if (res['isSuccess'] == true && res['data'] is Map) {
    final full = PosProduct.fromJson(res['data'] as Map<String, dynamic>);
    return PosPurchaseLookupPick(product: full);
  }
  return PosPurchaseLookupPick(product: p);
}

class _ProductPickSheet extends StatelessWidget {
  const _ProductPickSheet({required this.query, required this.items});

  final String query;
  final List<PosProduct> items;

  @override
  Widget build(BuildContext context) {
    final money = NumberFormat('#,##0', 'vi_VN');
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.55,
      minChildSize: 0.35,
      maxChildSize: 0.9,
      builder: (_, scroll) => Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(tr('Chọn hàng hóa · "$query"'),
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.bold)),
                ),
                IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close)),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              controller: scroll,
              itemCount: items.length,
              itemBuilder: (_, i) {
                final p = items[i];
                return ListTile(
                  title: Text(tr(p.name)),
                  subtitle: Text(tr(
                      '${p.productCode}${p.barcode != null ? ' · ${p.barcode}' : ''}')),
                  trailing: Text(tr('GV: ${money.format(p.costPrice)}'),
                      style: const TextStyle(
                          fontSize: 12, color: PosTheme.textSecondary)),
                  onTap: () => Navigator.pop(context, p),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
