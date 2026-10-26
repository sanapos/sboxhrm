import '../models/pos_product.dart';

import '../services/api_service.dart';

import '../widgets/pos/pos_product_unit_view.dart';



/// ĐVT/biến thể nhúng trong catalog — không gọi API.

List<PosProductUnitView> buildPosSellUnitViewsFromProduct(PosProduct product) {

  final variants =

      product.variants?.where((v) => v.isActive).toList() ?? const [];

  final units =

      product.units?.where((u) => u.isDirectSale).toList() ?? const [];

  return buildPosProductUnitViews(product, variants, extraUnits: units);

}



bool posProductHasEmbeddedSellViews(PosProduct product) {
  final saleUnits = product.units?.where((u) => u.isDirectSale).length ?? 0;
  if (saleUnits > 1) return true;
  final variants = product.variants?.where((v) => v.isActive).length ?? 0;
  return variants > 1;
}



class _UnitViewsCacheEntry {
  _UnitViewsCacheEntry(this.key, this.views) : at = DateTime.now();
  final String key;
  final List<PosProductUnitView> views;
  final DateTime at;
}

final _unitViewsCache = <String, _UnitViewsCacheEntry>{};
final _unitViewsInflight = <String, Future<List<PosProductUnitView>>>{};
const _unitViewsTtl = Duration(minutes: 5);

/// Tải đầy đủ ĐVT/biến thể — ưu tiên dữ liệu nhúng, fallback API.
/// Dùng chung bộ nhớ đệm (5 phút, theo updatedAt SP): lưới món tải sẵn → bấm món không chờ mạng.
/// [useCache] = false khi cần số liệu mới (kiểm tồn trước thanh toán).
/// [trustEmbedded]: SP lấy từ danh mục bán (/api/pos/sales/products) — đã nhúng ĐỦ ĐVT + biến thể (kể cả
/// danh sách rỗng) → không gọi API. Trước đây lưới bán gọi 3 API cho MỖI món đơn giản khi mở màn bán
/// (cửa hàng 20.000 món ≈ 60.000 request).
Future<List<PosProductUnitView>> loadPosSellUnitViews(
  ApiService api,
  PosProduct product, {
  bool useCache = true,
  bool trustEmbedded = false,
}) {
  if (posProductHasEmbeddedSellViews(product) ||
      (trustEmbedded && product.units != null && product.variants != null)) {
    return Future.value(buildPosSellUnitViewsFromProduct(product));
  }
  final key = '${product.updatedAt?.millisecondsSinceEpoch ?? 0}';
  if (useCache) {
    final hit = _unitViewsCache[product.id];
    if (hit != null &&
        hit.key == key &&
        DateTime.now().difference(hit.at) < _unitViewsTtl) {
      return Future.value(hit.views);
    }
    final running = _unitViewsInflight[product.id];
    if (running != null) return running;
  }
  final f = _loadPosSellUnitViewsFromApi(api, product).then((views) {
    if (views.isNotEmpty) {
      _unitViewsCache[product.id] = _UnitViewsCacheEntry(key, views);
    }
    return views;
  }).whenComplete(() {
    _unitViewsInflight.remove(product.id);
  });
  _unitViewsInflight[product.id] = f;
  return f;
}

/// 3 API chạy song song (trước đây nối tiếp ~280ms trên T1).
Future<List<PosProductUnitView>> _loadPosSellUnitViewsFromApi(
  ApiService api,
  PosProduct product,
) async {
  final res = await Future.wait([
    api.getPosProduct(product.id),
    api.getPosProductVariants(product.id),
    api.getPosProductUnits(product.id),
  ]);
  final fullRes = res[0];
  var p = product;
  if (fullRes['isSuccess'] == true && fullRes['data'] is Map) {
    p = PosProduct.fromJson(fullRes['data'] as Map<String, dynamic>);
  }
  if (posProductHasEmbeddedSellViews(p)) {
    return buildPosSellUnitViewsFromProduct(p);
  }
  final variants = <PosProductVariant>[];
  final vRes = res[1];
  if (vRes['isSuccess'] == true && vRes['data'] is List) {
    variants.addAll(
      (vRes['data'] as List)
          .map((e) => PosProductVariant.fromJson(e as Map<String, dynamic>))
          .where((v) => v.isActive),
    );
  }
  final units = <PosProductUnit>[];
  final uRes = res[2];
  if (uRes['isSuccess'] == true && uRes['data'] is List) {
    units.addAll(
      (uRes['data'] as List)
          .map((e) => PosProductUnit.fromJson(e as Map<String, dynamic>))
          .where((u) => u.isDirectSale),
    );
  } else if (p.units != null) {
    units.addAll(p.units!.where((u) => u.isDirectSale));
  }
  return buildPosProductUnitViews(p, variants, extraUnits: units);
}

PosProductUnitView? pickUnitView(

  List<PosProductUnitView> views, {

  String? variantId,

  String? unitId,

  String? unitLabel,

}) {

  if (views.isEmpty) return null;

  if (unitId != null) {

    final byUnit = views.where((v) => v.unitId == unitId).firstOrNull;

    if (byUnit != null) return byUnit;

  }

  if (variantId != null) {

    final byVar = views.where((v) => v.variantId == variantId).firstOrNull;

    if (byVar != null) return byVar;

  }

  if (unitLabel != null && unitLabel.isNotEmpty) {

    final byLabel = views.where((v) => v.label == unitLabel).firstOrNull;

    if (byLabel != null) return byLabel;

  }

  return views.first;

}

