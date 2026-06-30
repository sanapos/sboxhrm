import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/pos_product.dart';
import '../services/api_service.dart';
import '../widgets/pos/pos_theme.dart';

/// Kết quả tìm hàng cho phiếu nhập/trả NCC.
class PosPurchaseLookupPick {
  const PosPurchaseLookupPick({
    required this.product,
    this.variantId,
    this.unitId,
    this.unitLabel,
  });

  final PosProduct product;
  final String? variantId;
  final String? unitId;
  final String? unitLabel;
}

/// Quét mã / SKU chính xác hoặc tìm theo tên — hiện danh sách chọn nếu nhiều kết quả.
Future<PosPurchaseLookupPick?> lookupOrPickPosProduct(
  BuildContext context,
  ApiService api,
  String query,
) async {
  final q = query.trim();
  if (q.isEmpty) return null;

  final fromExact = await _tryExactLookup(api, q);
  if (fromExact != null) return fromExact;

  final searchRes = await api.getPosProducts(search: q, pageSize: 30);
  if (searchRes['isSuccess'] != true || searchRes['data'] is! Map) return null;

  final rawItems = (searchRes['data'] as Map)['items'] as List? ?? [];
  final items = rawItems
      .map((e) => PosProduct.fromJson(e as Map<String, dynamic>))
      .toList();

  if (items.isEmpty) return null;
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

Future<PosPurchaseLookupPick?> _tryExactLookup(ApiService api, String q) async {
  final lookup = await api.lookupPosSellItem(q);
  if (lookup['isSuccess'] != true || lookup['data'] is! Map) return null;

  final data = lookup['data'] as Map<String, dynamic>;
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
    return PosPurchaseLookupPick(product: enriched?.product ?? stub, variantId: variant.id);
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
                  child: Text('Chọn hàng hóa · "$query"',
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                ),
                IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
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
                  title: Text(p.name),
                  subtitle: Text('${p.productCode}${p.barcode != null ? ' · ${p.barcode}' : ''}'),
                  trailing: Text('GV: ${money.format(p.costPrice)}',
                      style: const TextStyle(fontSize: 12, color: PosTheme.textSecondary)),
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
