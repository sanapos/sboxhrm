import '../models/pos_product.dart';
import '../widgets/pos/pos_product_unit_view.dart';

/// Một dòng điều chỉnh tồn — khớp logic server (SP / biến thể / ĐVT quy đổi).
class PosSellStockLineDelta {
  final String productId;
  final String? variantId;
  final double qty;
  final bool addBack;

  const PosSellStockLineDelta({
    required this.productId,
    this.variantId,
    required this.qty,
    this.addBack = false,
  });
}

double _stockDeltaInBase(PosProductVariant? variant, double qtyInUnit) {
  if (variant != null && variantIsBaseUnitOnly(variant)) {
    final rate = parseVariantConversionRate(variant.attributeJson);
    return qtyInUnit * (rate > 0 ? rate : 1);
  }
  return qtyInUnit;
}

PosProductVariant _variantWithQty(PosProductVariant v, double qty) {
  return PosProductVariant(
    id: v.id,
    skuCode: v.skuCode,
    barcode: v.barcode,
    name: v.name,
    attributeJson: v.attributeJson,
    costPrice: v.costPrice,
    basePrice: v.basePrice,
    onHandQty: qty,
    isActive: v.isActive,
  );
}

/// Áp dụng một dòng tồn lên bản sao [product] (bán = trừ, trả/nhập = cộng).
PosProduct applyPosSellStockLine(PosProduct product, PosSellStockLineDelta line) {
  if (line.qty <= 0 || line.productId != product.id) return product;

  final sign = line.addBack ? 1.0 : -1.0;
  PosProductVariant? variant;
  if (line.variantId != null && line.variantId!.isNotEmpty) {
    variant = product.variants?.where((v) => v.id == line.variantId).firstOrNull;
  }

  if (variant != null && variantIsBaseUnitOnly(variant)) {
    final baseDelta = _stockDeltaInBase(variant, line.qty);
    final next = (product.onHandQty + sign * baseDelta).clamp(0.0, double.infinity);
    return product.copyWith(onHandQty: next);
  }

  if (variant != null && product.variants != null) {
    final variants = product.variants!.map((v) {
      if (v.id != variant!.id) return v;
      final next = (v.onHandQty + sign * line.qty).clamp(0.0, double.infinity);
      return _variantWithQty(v, next);
    }).toList();
    return product.copyWithVariants(variants);
  }

  final next = (product.onHandQty + sign * line.qty).clamp(0.0, double.infinity);
  return product.copyWith(onHandQty: next);
}

PosProduct applyPosSellStockLines(
  PosProduct product,
  Iterable<PosSellStockLineDelta> lines,
) {
  var p = product;
  for (final line in lines) {
    if (line.productId != product.id) continue;
    p = applyPosSellStockLine(p, line);
  }
  return p;
}

List<PosSellStockLineDelta> mergeStockLineDeltas(
  Iterable<PosSellStockLineDelta> lines,
) {
  final map = <String, PosSellStockLineDelta>{};
  for (final line in lines) {
    if (line.qty <= 0) continue;
    final key = '${line.productId}|${line.variantId ?? ''}|${line.addBack}';
    final existing = map[key];
    if (existing == null) {
      map[key] = line;
    } else {
      map[key] = PosSellStockLineDelta(
        productId: line.productId,
        variantId: line.variantId,
        qty: existing.qty + line.qty,
        addBack: line.addBack,
      );
    }
  }
  return map.values.toList();
}
