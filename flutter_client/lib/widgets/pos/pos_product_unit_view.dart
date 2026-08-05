import 'dart:convert';

import '../../models/pos_product.dart';

/// Một «góc nhìn» ĐVT/biến thể trên danh sách (kiểu chip KiotViet).
class PosProductUnitView {
  /// Khóa duy nhất: `base`, `v:<variantId>`, `u:<unitId>`.
  final String viewKey;
  final String label;
  final String? variantId;
  final String? unitId;
  final String displayCode;
  final double basePrice;
  final double costPrice;
  final double onHandQty;

  const PosProductUnitView({
    required this.viewKey,
    required this.label,
    this.variantId,
    this.unitId,
    required this.displayCode,
    required this.basePrice,
    required this.costPrice,
    required this.onHandQty,
  });

  bool get isBase => variantId == null && unitId == null;
}

String? parseVariantUnitName(String? attributeJson) {
  if (attributeJson == null || attributeJson.isEmpty) return null;
  try {
    final map = jsonDecode(attributeJson) as Map<String, dynamic>;
    return map['_unit']?.toString();
  } catch (_) {
    return null;
  }
}

double parseVariantConversionRate(String? attributeJson) {
  if (attributeJson == null || attributeJson.isEmpty) return 1;
  try {
    final map = jsonDecode(attributeJson) as Map<String, dynamic>;
    final raw = map['_conversion'];
    if (raw == null) return 1;
    final n = raw is num ? raw.toDouble() : double.tryParse('$raw');
    if (n == null || n <= 0) return 1;
    return n;
  } catch (_) {
    return 1;
  }
}

bool variantHasRealAttributes(PosProductVariant v) {
  if (!variantIsBaseUnitOnly(v)) return true;
  return false;
}

bool variantIsBaseUnitOnly(PosProductVariant v) {
  final unit = parseVariantUnitName(v.attributeJson);
  if (unit == null || unit.isEmpty) return false;
  final raw = v.attributeJson;
  if (raw == null || raw.isEmpty) return true;
  try {
    final map = jsonDecode(raw) as Map<String, dynamic>;
    for (final e in map.entries) {
      if (!e.key.startsWith('_') && '${e.value}'.trim().isNotEmpty) {
        return false;
      }
    }
    return true;
  } catch (_) {
    return false;
  }
}

/// Giá bán theo ĐVT — KiotViet: ĐVT quy đổi mà giá = giá cơ bản thì nhân tỷ lệ.
double resolveSellUnitPrice({
  required double productBasePrice,
  required double configuredPrice,
  required double conversionRate,
}) {
  final rate = conversionRate > 0 ? conversionRate : 1;
  if (rate > 1 &&
      productBasePrice > 0 &&
      (configuredPrice <= 0 ||
          (configuredPrice - productBasePrice).abs() < 0.01)) {
    return productBasePrice * rate;
  }
  if (configuredPrice > 0) return configuredPrice;
  return productBasePrice * rate;
}

double _unitPriceForExtra(PosProduct product, PosProductUnit unit) {
  return resolveSellUnitPrice(
    productBasePrice: product.basePrice,
    configuredPrice: unit.basePrice,
    conversionRate: unit.conversionRate,
  );
}

double _variantSellPrice(PosProduct product, PosProductVariant variant) {
  final rate = parseVariantConversionRate(variant.attributeJson);
  return resolveSellUnitPrice(
    productBasePrice: product.basePrice,
    configuredPrice: variant.basePrice,
    conversionRate: rate,
  );
}

double _stockForExtra(PosProduct product, PosProductUnit unit) {
  final rate = unit.conversionRate > 0 ? unit.conversionRate : 1;
  return product.onHandQty / rate;
}

/// Xây danh sách chip ĐVT cho một SP (variant + bảng PosProductUnit).
List<PosProductUnitView> buildPosProductUnitViews(
  PosProduct product,
  List<PosProductVariant> variants, {
  List<PosProductUnit>? extraUnits,
}) {
  final views = <PosProductUnitView>[];
  final usedLabels = <String>{};
  final extras = extraUnits ?? const <PosProductUnit>[];
  PosProductUnit? baseUnitRecord;
  for (final u in extras) {
    if (u.isBaseUnit && u.isDirectSale) {
      baseUnitRecord = u;
      break;
    }
  }

  if (variants.isEmpty) {
    final baseName = baseUnitRecord?.unitName.isNotEmpty == true
        ? baseUnitRecord!.unitName
        : (product.baseUnitName.isEmpty ? 'Cái' : product.baseUnitName);
    final basePrice = baseUnitRecord != null
        ? _unitPriceForExtra(product, baseUnitRecord)
        : product.basePrice;
    views.add(PosProductUnitView(
      viewKey: baseUnitRecord != null ? 'u:${baseUnitRecord.id}' : 'base',
      label: baseName,
      unitId: baseUnitRecord?.id,
      displayCode: product.productCode,
      basePrice: basePrice,
      costPrice: product.costPrice,
      onHandQty: product.onHandQty,
    ));
    usedLabels.add(baseName);
  } else {
    final usedVariantIds = <String>{};
    final baseName =
        product.baseUnitName.isEmpty ? 'Cái' : product.baseUnitName;
    PosProductVariant? baseVariant;
    for (final v in variants) {
      if (variantIsBaseUnitOnly(v) &&
          (parseVariantUnitName(v.attributeJson) ?? '') == baseName) {
        baseVariant = v;
        break;
      }
    }
    if (baseVariant != null) {
      usedVariantIds.add(baseVariant.id);
      views.add(PosProductUnitView(
        viewKey: 'v:${baseVariant.id}',
        label: baseName,
        variantId: baseVariant.id,
        displayCode: baseVariant.skuCode,
        basePrice: _variantSellPrice(product, baseVariant),
        costPrice: baseVariant.costPrice,
        onHandQty: product.onHandQty,
      ));
      usedLabels.add(baseName);
    } else if (baseUnitRecord != null) {
      views.add(PosProductUnitView(
        viewKey: 'u:${baseUnitRecord.id}',
        label: baseName,
        unitId: baseUnitRecord.id,
        displayCode: product.productCode,
        basePrice: _unitPriceForExtra(product, baseUnitRecord),
        costPrice: product.costPrice,
        onHandQty: product.onHandQty,
      ));
      usedLabels.add(baseName);
    } else {
      views.add(PosProductUnitView(
        viewKey: 'base',
        label: baseName,
        displayCode: product.productCode,
        basePrice: product.basePrice,
        costPrice: product.costPrice,
        onHandQty: product.onHandQty,
      ));
      usedLabels.add(baseName);
    }

    for (final v in variants) {
      if (usedVariantIds.contains(v.id)) continue;
      final unit = parseVariantUnitName(v.attributeJson);
      final label = unit?.isNotEmpty == true ? unit! : v.name;
      if (usedLabels.contains(label)) continue;
      final rate = parseVariantConversionRate(v.attributeJson);
      final displayStock = variantIsBaseUnitOnly(v)
          ? (rate > 0 ? product.onHandQty / rate : product.onHandQty)
          : v.onHandQty;
      views.add(PosProductUnitView(
        viewKey: 'v:${v.id}',
        label: label,
        variantId: v.id,
        displayCode: v.skuCode,
        basePrice: _variantSellPrice(product, v),
        costPrice: v.costPrice,
        onHandQty: displayStock,
      ));
      usedLabels.add(label);
    }
  }

  for (final u in extras) {
    if (!u.isDirectSale || u.isBaseUnit) continue;
    final label = u.unitName.trim();
    if (label.isEmpty || usedLabels.contains(label)) continue;
    views.add(PosProductUnitView(
      viewKey: 'u:${u.id}',
      label: label,
      unitId: u.id,
      displayCode: product.productCode,
      basePrice: _unitPriceForExtra(product, u),
      costPrice: _unitPriceForExtra(product, u),
      onHandQty: _stockForExtra(product, u),
    ));
    usedLabels.add(label);
  }

  return views;
}

PosProductUnitView resolveUnitView(
  PosProduct product,
  List<PosProductVariant> variants,
  String? selectedVariantId, {
  List<PosProductUnit>? extraUnits,
}) {
  final views = buildPosProductUnitViews(product, variants, extraUnits: extraUnits);
  if (selectedVariantId == null) return views.first;
  return views.firstWhere(
    (v) => v.variantId == selectedVariantId,
    orElse: () => views.first,
  );
}

/// Tồn khả dụng bán (ĐVT của [view]): (OnHand − Reserved) quy về ĐVT hiển thị.
double resolvePosSellAvailableQty(PosProduct product, PosProductUnitView view) {
  if (product.productType == PosProductType.service) {
    return double.infinity;
  }
  if (product.productType == PosProductType.combo) {
    return product.sellableQty ?? product.onHandQty;
  }
  final reserved = product.reservedQty;
  if (reserved <= 0) return view.onHandQty;
  final onHand = product.onHandQty;
  if (onHand <= 0) return 0;
  // view.onHandQty đã theo ĐVT chip — scale reserved theo cùng tỷ lệ.
  final scale = view.onHandQty / onHand;
  final availBase = (onHand - reserved).clamp(0.0, double.infinity);
  return availBase * scale;
}

/// Tồn hiển thị trên lưới bán — khớp kho hàng (SP gốc + biến thể + ĐVT + combo).
double resolvePosSellListStockQty(
  PosProduct product,
  List<PosProductUnitView> views,
) {
  if (product.productType == PosProductType.service) {
    return double.infinity;
  }
  if (product.productType == PosProductType.combo) {
    final sellable = product.sellableQty ??
        (product.comboLines != null && product.comboLines!.isNotEmpty
            ? product.onHandQty
            : 0);
    return sellable;
  }

  if (views.isEmpty) return product.onHandQty;

  final variants = product.variants ?? const <PosProductVariant>[];
  final hasAttributeVariants = variants.any(variantHasRealAttributes);

  if (hasAttributeVariants) {
    final variantQty = views
        .where((v) => v.variantId != null)
        .fold(0.0, (sum, v) => sum + v.onHandQty);
    if (variantQty > 0) return variantQty;
  }

  final maxViewQty =
      views.fold(0.0, (max, v) => v.onHandQty > max ? v.onHandQty : max);
  if (maxViewQty > 0) return maxViewQty;
  if (product.onHandQty > 0) return product.onHandQty;
  return views.first.onHandQty;
}

/// Hết hàng trên lưới bán khi mọi ĐVT/biến thể đều 0 (trừ dịch vụ).
/// Dùng tồn khả dụng (trừ reserved) khi có thể.
bool isPosSellOutOfStock(PosProduct product, List<PosProductUnitView> views) {
  if (product.productType == PosProductType.service) {
    return false;
  }
  if (product.productType == PosProductType.combo) {
    final lines = product.comboLines;
    if (lines == null || lines.isEmpty) return true;
    return resolvePosSellListStockQty(product, views) <= 0;
  }
  if (views.isEmpty) {
    return (product.onHandQty - product.reservedQty) <= 0;
  }
  final maxAvail = views.fold<double>(
    0,
    (m, v) {
      final a = resolvePosSellAvailableQty(product, v);
      return a > m ? a : m;
    },
  );
  return maxAvail <= 0;
}

/// Chip ĐVT/biến thể có tồn > 0 — ưu tiên khi thêm vào giỏ từ lưới.
PosProductUnitView? pickDefaultSellUnitView(
  PosProduct product,
  List<PosProductUnitView> views,
) {
  if (views.isEmpty) return null;
  for (final v in views) {
    if (v.onHandQty > 0) return v;
  }
  return views.first;
}
