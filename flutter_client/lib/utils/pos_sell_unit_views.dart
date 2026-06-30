import '../models/pos_product.dart';
import '../services/api_service.dart';
import '../widgets/pos/pos_product_unit_view.dart';

/// Tải đầy đủ ĐVT/biến thể cho màn bán hàng (variant + PosProductUnit).
Future<List<PosProductUnitView>> loadPosSellUnitViews(
  ApiService api,
  PosProduct product,
) async {
  final fullRes = await api.getPosProduct(product.id);
  var p = product;
  if (fullRes['isSuccess'] == true && fullRes['data'] is Map) {
    p = PosProduct.fromJson(fullRes['data'] as Map<String, dynamic>);
  }

  final variants = <PosProductVariant>[];
  final vRes = await api.getPosProductVariants(p.id);
  if (vRes['isSuccess'] == true && vRes['data'] is List) {
    variants.addAll(
      (vRes['data'] as List)
          .map((e) => PosProductVariant.fromJson(e as Map<String, dynamic>))
          .where((v) => v.isActive),
    );
  }

  final units = <PosProductUnit>[];
  final uRes = await api.getPosProductUnits(p.id);
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
