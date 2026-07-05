import '../models/pos_product.dart';
import '../widgets/pos/pos_product_unit_view.dart';

/// Khóa tra cứu giá theo bảng giá (đồng bộ với backend PosPriceListResolver).
String posPriceListItemKey({
  required String productId,
  String? variantId,
  String? unitId,
}) {
  if (variantId != null &&
      variantId.isNotEmpty &&
      unitId != null &&
      unitId.isNotEmpty) {
    return '$productId|v:$variantId|u:$unitId';
  }
  if (variantId != null && variantId.isNotEmpty) {
    return '$productId|v:$variantId';
  }
  if (unitId != null && unitId.isNotEmpty) {
    return '$productId|u:$unitId';
  }
  return productId;
}

double? resolvePosPriceListPrice(
  Map<String, double> overrides, {
  required String productId,
  String? variantId,
  String? unitId,
}) {
  if (variantId != null &&
      variantId.isNotEmpty &&
      unitId != null &&
      unitId.isNotEmpty) {
    final k = posPriceListItemKey(
        productId: productId, variantId: variantId, unitId: unitId);
    if (overrides.containsKey(k)) return overrides[k];
  }
  if (variantId != null && variantId.isNotEmpty) {
    final k = posPriceListItemKey(productId: productId, variantId: variantId);
    if (overrides.containsKey(k)) return overrides[k];
  }
  if (unitId != null && unitId.isNotEmpty) {
    final k = posPriceListItemKey(productId: productId, unitId: unitId);
    if (overrides.containsKey(k)) return overrides[k];
  }
  return overrides[productId];
}

Map<String, double> buildPosPriceOverrideMap(List<dynamic> resolvedPrices) {
  final map = <String, double>{};
  for (final raw in resolvedPrices) {
    if (raw is! Map) continue;
    final item = PosResolvedPriceLite.fromJson(Map<String, dynamic>.from(raw));
    map[posPriceListItemKey(
      productId: item.productId,
      variantId: item.variantId,
      unitId: item.unitId,
    )] = item.price;
  }
  return map;
}

class PosResolvedPriceLite {
  final String productId;
  final String? variantId;
  final String? unitId;
  final double price;

  PosResolvedPriceLite({
    required this.productId,
    this.variantId,
    this.unitId,
    required this.price,
  });

  factory PosResolvedPriceLite.fromJson(Map<String, dynamic> json) =>
      PosResolvedPriceLite(
        productId: '${json['productId'] ?? json['ProductId']}',
        variantId: (json['variantId'] ?? json['VariantId'])?.toString(),
        unitId: (json['unitId'] ?? json['UnitId'])?.toString(),
        price: ((json['price'] ?? json['Price'] ?? 0) as num).toDouble(),
      );
}

List<PosProductUnitView> applyPosPriceListToViews(
  List<PosProductUnitView> views,
  PosProduct product,
  Map<String, double> overrides,
) {
  if (overrides.isEmpty) return views;
  return views
      .map((v) {
        final price = resolvePosPriceListPrice(
          overrides,
          productId: product.id,
          variantId: v.variantId,
          unitId: v.unitId,
        );
        if (price == null) return v;
        return PosProductUnitView(
          viewKey: v.viewKey,
          label: v.label,
          variantId: v.variantId,
          unitId: v.unitId,
          displayCode: v.displayCode,
          basePrice: price,
          costPrice: v.costPrice,
          onHandQty: v.onHandQty,
        );
      })
      .toList(growable: false);
}

double applyPosPriceListToProductBase(
  PosProduct product,
  Map<String, double> overrides,
) {
  final price = resolvePosPriceListPrice(overrides, productId: product.id);
  return price ?? product.basePrice;
}
