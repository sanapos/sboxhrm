/// POS Hàng hóa — models & enums (KiotViet-style).

import '../utils/api_datetime.dart';

List<String> parsePosStringList(dynamic raw) {
  if (raw is List) {
    return raw
        .map((e) => e.toString().trim())
        .where((s) => s.isNotEmpty)
        .toList();
  }
  if (raw is String && raw.trim().isNotEmpty) {
    return raw
        .split(RegExp(r'[;\n]'))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
  }
  return const [];
}

/// Ghép ghi chú dòng hàng từ chip đã chọn + ghi chú tự nhập.
String? joinPosLineNoteParts({
  required Iterable<String> selectedQuickNotes,
  String? extraNote,
}) {
  final parts = <String>[];
  for (final n in selectedQuickNotes) {
    final t = n.trim();
    if (t.isNotEmpty && !parts.contains(t)) parts.add(t);
  }
  final extra = extraNote?.trim() ?? '';
  if (extra.isNotEmpty) {
    for (final seg in extra.split(RegExp(r'[;\n]'))) {
      final t = seg.trim();
      if (t.isNotEmpty && !parts.contains(t)) parts.add(t);
    }
  }
  return parts.isEmpty ? null : parts.join('; ');
}

/// Tách ghi chú dòng thành chip đã chọn và phần ghi chú khác.
({Set<String> selected, String extra}) splitPosLineNote(
  String? lineNote,
  List<String> quickNotes,
) {
  final selected = <String>{};
  final extraParts = <String>[];
  if (lineNote == null || lineNote.trim().isEmpty) {
    return (selected: selected, extra: '');
  }
  final quickLower = {for (final q in quickNotes) q.toLowerCase(): q};
  for (final seg in lineNote.split(RegExp(r'[;\n]'))) {
    final t = seg.trim();
    if (t.isEmpty) continue;
    final hit = quickLower[t.toLowerCase()];
    if (hit != null) {
      selected.add(hit);
    } else {
      extraParts.add(t);
    }
  }
  return (selected: selected, extra: extraParts.join('; '));
}

class PosCatalogItem {
  final String id;
  final String name;
  final String? parentId;
  final int sortOrder;
  final int productCount;

  PosCatalogItem({
    required this.id,
    required this.name,
    this.parentId,
    this.sortOrder = 0,
    this.productCount = 0,
  });

  factory PosCatalogItem.fromJson(Map<String, dynamic> json) {
    return PosCatalogItem(
      id: (json['id'] ?? json['Id'] ?? '').toString(),
      name: (json['name'] ?? json['Name'] ?? '').toString(),
      parentId: (json['parentId'] ?? json['ParentId'])?.toString(),
      sortOrder: (json['sortOrder'] ?? json['SortOrder'] as num?)?.toInt() ?? 0,
      productCount:
          (json['productCount'] ?? json['ProductCount'] as num?)?.toInt() ?? 0,
    );
  }
}

enum PosProductType { goods, service, combo }

enum PosProductSortBy { name, code, price, stock, createdAt }

enum PosStockFilter { all, belowMin, outOfStock, aboveMax }

enum PosStockoutFilter { all, within7Days, within30Days }

PosProductType posProductTypeFromString(String? raw) {
  final r = raw?.toLowerCase() ?? '';
  if (r == 'service') return PosProductType.service;
  if (r == 'combo') return PosProductType.combo;
  return PosProductType.goods;
}

String posProductTypeLabel(PosProductType t) {
  switch (t) {
    case PosProductType.service:
      return 'Dịch vụ';
    case PosProductType.combo:
      return 'Combo';
    case PosProductType.goods:
      return 'Hàng hóa';
  }
}

class PosProductUnit {
  final String id;
  final String unitName;
  final double conversionRate;
  final double basePrice;
  final bool isDirectSale;
  final bool isBaseUnit;

  PosProductUnit({
    required this.id,
    required this.unitName,
    this.conversionRate = 1,
    this.basePrice = 0,
    this.isDirectSale = true,
    this.isBaseUnit = false,
  });

  factory PosProductUnit.fromJson(Map<String, dynamic> json) {
    double n(dynamic v) =>
        v is num ? v.toDouble() : double.tryParse('$v') ?? 0;
    return PosProductUnit(
      id: (json['id'] ?? json['Id'] ?? '').toString(),
      unitName: (json['unitName'] ?? json['UnitName'] ?? '').toString(),
      conversionRate: n(json['conversionRate'] ?? json['ConversionRate']),
      basePrice: n(json['basePrice'] ?? json['BasePrice']),
      isDirectSale:
          json['isDirectSale'] == true || json['IsDirectSale'] == true,
      isBaseUnit: json['isBaseUnit'] == true || json['IsBaseUnit'] == true,
    );
  }

  Map<String, dynamic> toUpsertJson() => {
        'unitName': unitName,
        'conversionRate': conversionRate,
        'basePrice': basePrice,
        'isDirectSale': isDirectSale,
      };
}

class PosProductAttribute {
  final String attributeId;
  final String attributeName;
  final String value;

  PosProductAttribute({
    required this.attributeId,
    required this.attributeName,
    required this.value,
  });

  factory PosProductAttribute.fromJson(Map<String, dynamic> json) {
    return PosProductAttribute(
      attributeId: (json['attributeId'] ?? json['AttributeId'] ?? '').toString(),
      attributeName:
          (json['attributeName'] ?? json['AttributeName'] ?? '').toString(),
      value: (json['value'] ?? json['Value'] ?? '').toString(),
    );
  }

  Map<String, dynamic> toInputJson() => {
        'attributeId': attributeId.isEmpty ? null : attributeId,
        'attributeName': attributeName,
        'value': value,
      };
}

class PosStockTransaction {
  final String id;
  final String productId;
  final String? variantId;
  final String? variantName;
  final String? unitName;
  final String productName;
  final String productCode;
  final String transactionType;
  final double qtyChange;
  final double qtyAfter;
  final String? referenceNo;
  final String? note;
  final String? stockReceiptId;
  final String? saleOrderId;
  final String? stockIssueId;
  final String? stockCountId;
  final String? purchaseReturnId;
  final double? unitCost;
  final double? lineAmount;
  final String? partnerName;
  final String? createdBy;
  final DateTime? createdAt;

  PosStockTransaction({
    required this.id,
    required this.productId,
    this.variantId,
    this.variantName,
    this.unitName,
    required this.productName,
    required this.productCode,
    required this.transactionType,
    this.qtyChange = 0,
    this.qtyAfter = 0,
    this.referenceNo,
    this.note,
    this.stockReceiptId,
    this.saleOrderId,
    this.stockIssueId,
    this.stockCountId,
    this.purchaseReturnId,
    this.unitCost,
    this.lineAmount,
    this.partnerName,
    this.createdBy,
    this.createdAt,
  });

  factory PosStockTransaction.fromJson(Map<String, dynamic> json) {
    double n(dynamic v) =>
        v is num ? v.toDouble() : double.tryParse('$v') ?? 0;
    return PosStockTransaction(
      id: (json['id'] ?? json['Id'] ?? '').toString(),
      productId: (json['productId'] ?? json['ProductId'] ?? '').toString(),
      variantId: (json['variantId'] ?? json['VariantId'])?.toString(),
      variantName: json['variantName'] ?? json['VariantName'] as String?,
      unitName: json['unitName'] ?? json['UnitName'] as String?,
      productName: (json['productName'] ?? json['ProductName'] ?? '').toString(),
      productCode: (json['productCode'] ?? json['ProductCode'] ?? '').toString(),
      transactionType:
          (json['transactionType'] ?? json['TransactionType'] ?? '').toString(),
      qtyChange: n(json['qtyChange'] ?? json['QtyChange']),
      qtyAfter: n(json['qtyAfter'] ?? json['QtyAfter']),
      referenceNo: json['referenceNo'] ?? json['ReferenceNo'] as String?,
      note: json['note'] ?? json['Note'] as String?,
      stockReceiptId:
          (json['stockReceiptId'] ?? json['StockReceiptId'])?.toString(),
      saleOrderId: (json['saleOrderId'] ?? json['SaleOrderId'])?.toString(),
      stockIssueId:
          (json['stockIssueId'] ?? json['StockIssueId'])?.toString(),
      stockCountId:
          (json['stockCountId'] ?? json['StockCountId'])?.toString(),
      purchaseReturnId:
          (json['purchaseReturnId'] ?? json['PurchaseReturnId'])?.toString(),
      unitCost: json['unitCost'] != null || json['UnitCost'] != null
          ? n(json['unitCost'] ?? json['UnitCost'])
          : null,
      lineAmount: json['lineAmount'] != null || json['LineAmount'] != null
          ? n(json['lineAmount'] ?? json['LineAmount'])
          : null,
      partnerName: json['partnerName'] ?? json['PartnerName'] as String?,
      createdBy: json['createdBy'] ?? json['CreatedBy'] as String?,
      createdAt: parseApiUtcDateTime(json['createdAt'] ?? json['CreatedAt']),
    );
  }
}

class PosProduct {
  final String id;
  final String productCode;
  final String? barcode;
  final String name;
  final String? categoryId;
  final String? categoryName;
  final String? categoryPath;
  final String? brandId;
  final String? brandName;
  final String? storageLocationId;
  final String? storageLocationName;
  final String? supplierId;
  final String? supplierName;
  final PosProductType productType;
  final String? description;
  final String? imageUrl;
  final double costPrice;
  final double basePrice;
  final double vatRate;
  final bool vatExempt;
  final double onHandQty;
  final double reservedQty;
  final double minStockQty;
  final double maxStockQty;
  final double? weight;
  final String weightUnit;
  final String baseUnitName;
  final bool isDirectSale;
  final bool isFavorite;
  final bool isActive;
  final int variantCount;
  final List<PosProductVariant>? variants;
  final double? avgDailySales;
  final DateTime? estimatedStockoutDate;
  final List<PosProductUnit>? units;
  final List<PosProductAttribute>? attributes;
  final List<String> saleQuickNotes;
  final List<PosComboLine>? comboLines;
  final double? sellableQty;
  final int? warrantyMonths;
  final bool requiresSerial;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  PosProduct({
    required this.id,
    required this.productCode,
    this.barcode,
    required this.name,
    this.categoryId,
    this.categoryName,
    this.categoryPath,
    this.brandId,
    this.brandName,
    this.storageLocationId,
    this.storageLocationName,
    this.supplierId,
    this.supplierName,
    this.productType = PosProductType.goods,
    this.description,
    this.imageUrl,
    this.costPrice = 0,
    this.basePrice = 0,
    this.vatRate = 8,
    this.vatExempt = false,
    this.onHandQty = 0,
    this.reservedQty = 0,
    this.minStockQty = 0,
    this.maxStockQty = 0,
    this.weight,
    this.weightUnit = 'g',
    this.baseUnitName = 'Cái',
    this.isDirectSale = true,
    this.isFavorite = false,
    this.isActive = true,
    this.variantCount = 0,
    this.variants,
    this.avgDailySales,
    this.estimatedStockoutDate,
    this.units,
    this.attributes,
    this.saleQuickNotes = const [],
    this.comboLines,
    this.sellableQty,
    this.warrantyMonths,
    this.requiresSerial = false,
    this.createdAt,
    this.updatedAt,
  });

  factory PosProduct.fromJson(Map<String, dynamic> json) {
    DateTime? dt(dynamic v) => parseApiUtcDateTime(v);

    double numVal(dynamic v) {
      if (v == null) return 0;
      if (v is num) return v.toDouble();
      return double.tryParse(v.toString()) ?? 0;
    }

    return PosProduct(
      id: (json['id'] ?? json['Id'] ?? '').toString(),
      productCode: (json['productCode'] ?? json['ProductCode'] ?? '').toString(),
      barcode: json['barcode'] ?? json['Barcode'] as String?,
      name: (json['name'] ?? json['Name'] ?? '').toString(),
      categoryId: (json['categoryId'] ?? json['CategoryId'])?.toString(),
      categoryName: json['categoryName'] ?? json['CategoryName'] as String?,
      categoryPath: json['categoryPath'] ?? json['CategoryPath'] as String?,
      brandId: (json['brandId'] ?? json['BrandId'])?.toString(),
      brandName: json['brandName'] ?? json['BrandName'] as String?,
      storageLocationId:
          (json['storageLocationId'] ?? json['StorageLocationId'])?.toString(),
      storageLocationName:
          json['storageLocationName'] ?? json['StorageLocationName'] as String?,
      supplierId: (json['supplierId'] ?? json['SupplierId'])?.toString(),
      supplierName: json['supplierName'] ?? json['SupplierName'] as String?,
      productType: posProductTypeFromString(
          (json['productType'] ?? json['ProductType'])?.toString()),
      description: json['description'] ?? json['Description'] as String?,
      imageUrl: json['imageUrl'] ?? json['ImageUrl'] as String?,
      costPrice: numVal(json['costPrice'] ?? json['CostPrice']),
      basePrice: numVal(json['basePrice'] ?? json['BasePrice']),
      vatRate: numVal(json['vatRate'] ?? json['VatRate']),
      vatExempt: json['vatExempt'] == true || json['VatExempt'] == true,
      onHandQty: numVal(json['onHandQty'] ?? json['OnHandQty']),
      reservedQty: numVal(json['reservedQty'] ?? json['ReservedQty']),
      minStockQty: numVal(json['minStockQty'] ?? json['MinStockQty']),
      maxStockQty: numVal(json['maxStockQty'] ?? json['MaxStockQty']),
      weight: json['weight'] != null || json['Weight'] != null
          ? numVal(json['weight'] ?? json['Weight'])
          : null,
      weightUnit: (json['weightUnit'] ?? json['WeightUnit'] ?? 'g').toString(),
      baseUnitName:
          (json['baseUnitName'] ?? json['BaseUnitName'] ?? 'Cái').toString(),
      isDirectSale: json['isDirectSale'] == true || json['IsDirectSale'] == true,
      isFavorite: json['isFavorite'] == true || json['IsFavorite'] == true,
      isActive: json['isActive'] != false && json['IsActive'] != false,
      variantCount: (json['variantCount'] ?? json['VariantCount'] as num?)?.toInt() ?? 0,
      variants: json['variants'] != null || json['Variants'] != null
          ? ((json['variants'] ?? json['Variants']) as List)
              .map((e) => PosProductVariant.fromJson(e as Map<String, dynamic>))
              .toList()
          : null,
      avgDailySales: json['avgDailySales'] != null || json['AvgDailySales'] != null
          ? numVal(json['avgDailySales'] ?? json['AvgDailySales'])
          : null,
      estimatedStockoutDate: dt(
          json['estimatedStockoutDate'] ?? json['EstimatedStockoutDate']),
      units: json['units'] != null || json['Units'] != null
          ? ((json['units'] ?? json['Units']) as List)
              .map((e) => PosProductUnit.fromJson(e as Map<String, dynamic>))
              .toList()
          : null,
      attributes: json['attributes'] != null || json['Attributes'] != null
          ? ((json['attributes'] ?? json['Attributes']) as List)
              .map((e) => PosProductAttribute.fromJson(e as Map<String, dynamic>))
              .toList()
          : null,
      saleQuickNotes: parsePosStringList(
          json['saleQuickNotes'] ?? json['SaleQuickNotes']),
      comboLines: json['comboLines'] != null || json['ComboLines'] != null
          ? ((json['comboLines'] ?? json['ComboLines']) as List)
              .whereType<Map>()
              .map((e) => PosComboLine.fromJson(Map<String, dynamic>.from(e)))
              .toList()
          : null,
      sellableQty: json['sellableQty'] != null || json['SellableQty'] != null
          ? numVal(json['sellableQty'] ?? json['SellableQty'])
          : null,
      warrantyMonths: json['warrantyMonths'] != null || json['WarrantyMonths'] != null
          ? (json['warrantyMonths'] ?? json['WarrantyMonths'] as num?)?.toInt()
          : null,
      requiresSerial:
          json['requiresSerial'] == true || json['RequiresSerial'] == true,
      createdAt: dt(json['createdAt'] ?? json['CreatedAt']),
      updatedAt: dt(json['updatedAt'] ?? json['UpdatedAt']),
    );
  }

  Map<String, dynamic> toUpsertJson({
    String? imageBase64,
    String? imageUrl,
    List<Map<String, dynamic>>? attributes,
  }) {
    return {
      'productCode': productCode.trim().isEmpty ? null : productCode.trim(),
      'barcode': barcode?.trim().isEmpty == true ? null : barcode?.trim(),
      'name': name.trim(),
      'categoryId': categoryId,
      'brandId': brandId,
      'storageLocationId': storageLocationId,
      'supplierId': supplierId,
      'productType': productType == PosProductType.service
          ? 1
          : productType == PosProductType.combo
              ? 2
              : 0,
      'description': description?.trim(),
      if (imageUrl != null && imageUrl.isNotEmpty) 'imageUrl': imageUrl,
      if (imageBase64 != null && imageBase64.isNotEmpty)
        'imageBase64': imageBase64,
      'costPrice': costPrice,
      'basePrice': basePrice,
      'vatRate': vatExempt ? 0 : vatRate,
      'vatExempt': vatExempt,
      'onHandQty': onHandQty,
      'reservedQty': reservedQty,
      'minStockQty': minStockQty,
      'maxStockQty': maxStockQty,
      'weight': weight,
      'weightUnit': weightUnit,
      'baseUnitName': baseUnitName,
      'isDirectSale': isDirectSale,
      'isFavorite': isFavorite,
      if (saleQuickNotes.isNotEmpty) 'saleQuickNotes': saleQuickNotes,
      if (attributes != null) 'attributes': attributes,
      if (warrantyMonths != null && warrantyMonths! > 0) 'warrantyMonths': warrantyMonths,
      if (requiresSerial) 'requiresSerial': true,
    };
  }

  bool get hasWarranty => (warrantyMonths ?? 0) > 0;

  bool get needsSerialCapture =>
      productType == PosProductType.goods && requiresSerial;

  bool get needsWarrantyRegistration =>
      productType == PosProductType.goods && (requiresSerial || hasWarranty);

  PosProduct copyWith({
    String? id,
    String? productCode,
    String? barcode,
    String? name,
    String? categoryId,
    String? brandId,
    String? storageLocationId,
    String? supplierId,
    PosProductType? productType,
    String? description,
    String? imageUrl,
    double? costPrice,
    double? basePrice,
    double? vatRate,
    bool? vatExempt,
    double? onHandQty,
    double? reservedQty,
    double? minStockQty,
    double? maxStockQty,
    double? weight,
    String? weightUnit,
    String? baseUnitName,
    bool? isDirectSale,
    bool? isFavorite,
    List<PosProductVariant>? variants,
    List<PosProductUnit>? units,
    List<PosComboLine>? comboLines,
    double? sellableQty,
  }) {
    return PosProduct(
      id: id ?? this.id,
      productCode: productCode ?? this.productCode,
      barcode: barcode ?? this.barcode,
      name: name ?? this.name,
      categoryId: categoryId ?? this.categoryId,
      categoryName: categoryName,
      categoryPath: categoryPath,
      brandId: brandId ?? this.brandId,
      brandName: brandName,
      storageLocationId: storageLocationId ?? this.storageLocationId,
      storageLocationName: storageLocationName,
      supplierId: supplierId ?? this.supplierId,
      supplierName: supplierName,
      productType: productType ?? this.productType,
      description: description ?? this.description,
      imageUrl: imageUrl ?? this.imageUrl,
      costPrice: costPrice ?? this.costPrice,
      basePrice: basePrice ?? this.basePrice,
      vatRate: vatRate ?? this.vatRate,
      vatExempt: vatExempt ?? this.vatExempt,
      onHandQty: onHandQty ?? this.onHandQty,
      reservedQty: reservedQty ?? this.reservedQty,
      minStockQty: minStockQty ?? this.minStockQty,
      maxStockQty: maxStockQty ?? this.maxStockQty,
      weight: weight ?? this.weight,
      weightUnit: weightUnit ?? this.weightUnit,
      baseUnitName: baseUnitName ?? this.baseUnitName,
      isDirectSale: isDirectSale ?? this.isDirectSale,
      isFavorite: isFavorite ?? this.isFavorite,
      units: units ?? this.units,
      variants: variants ?? this.variants,
      comboLines: comboLines ?? this.comboLines,
      sellableQty: sellableQty ?? this.sellableQty,
      saleQuickNotes: this.saleQuickNotes,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }

  PosProduct copyWithVariants(List<PosProductVariant> variants) =>
      copyWith(variants: variants);

  Map<String, dynamic> toSellCacheJson() => {
        'id': id,
        'productCode': productCode,
        'barcode': barcode,
        'name': name,
        'categoryId': categoryId,
        'categoryName': categoryName,
        'productType': productType.name,
        'costPrice': costPrice,
        'basePrice': basePrice,
        'vatRate': vatRate,
        'vatExempt': vatExempt,
        'onHandQty': onHandQty,
        'reservedQty': reservedQty,
        'imageUrl': imageUrl,
        'baseUnitName': baseUnitName,
        'isDirectSale': isDirectSale,
        'isFavorite': isFavorite,
        'variantCount': variantCount,
        'saleQuickNotes': saleQuickNotes,
        'updatedAt': updatedAt?.toUtc().toIso8601String(),
        if (sellableQty != null) 'sellableQty': sellableQty,
        if (comboLines != null)
          'comboLines': comboLines!.map((c) => {
                'componentProductId': c.componentProductId,
                'componentProductCode': c.componentProductCode,
                'componentProductName': c.componentProductName,
                'qty': c.qty,
                'componentOnHandQty': c.componentOnHandQty,
                'componentBasePrice': c.componentBasePrice,
              }).toList(),
        if (units != null)
          'units': units!.map((u) => {
                'id': u.id,
                'unitName': u.unitName,
                'conversionRate': u.conversionRate,
                'basePrice': u.basePrice,
                'isDirectSale': u.isDirectSale,
                'isBaseUnit': u.isBaseUnit,
              }).toList(),
        if (variants != null)
          'variants': variants!.map((v) => {
                'id': v.id,
                'skuCode': v.skuCode,
                'barcode': v.barcode,
                'name': v.name,
                'attributeJson': v.attributeJson,
                'costPrice': v.costPrice,
                'basePrice': v.basePrice,
                'onHandQty': v.onHandQty,
                'isActive': v.isActive,
              }).toList(),
      };
}

class PosComboLine {
  final String id;
  final String componentProductId;
  final String componentProductCode;
  final String componentProductName;
  final double qty;
  final double componentOnHandQty;
  final double componentBasePrice;

  PosComboLine({
    required this.id,
    required this.componentProductId,
    this.componentProductCode = '',
    this.componentProductName = '',
    this.qty = 1,
    this.componentOnHandQty = 0,
    this.componentBasePrice = 0,
  });

  factory PosComboLine.fromJson(Map<String, dynamic> json) {
    double n(dynamic v) =>
        v is num ? v.toDouble() : double.tryParse('$v') ?? 0;
    return PosComboLine(
      id: (json['id'] ?? json['Id'] ?? '').toString(),
      componentProductId:
          (json['componentProductId'] ?? json['ComponentProductId'] ?? '')
              .toString(),
      componentProductCode:
          (json['componentProductCode'] ?? json['ComponentProductCode'] ?? '')
              .toString(),
      componentProductName:
          (json['componentProductName'] ?? json['ComponentProductName'] ?? '')
              .toString(),
      qty: n(json['qty'] ?? json['Qty']),
      componentOnHandQty:
          n(json['componentOnHandQty'] ?? json['ComponentOnHandQty']),
      componentBasePrice:
          n(json['componentBasePrice'] ?? json['ComponentBasePrice']),
    );
  }
}

class PosStockReceiptLine {
  final String productId;
  final String productCode;
  final String productName;
  final double qty;
  final double costPrice;
  final double lineTotal;

  PosStockReceiptLine({
    required this.productId,
    this.productCode = '',
    required this.productName,
    this.qty = 0,
    this.costPrice = 0,
    this.lineTotal = 0,
  });

  factory PosStockReceiptLine.fromJson(Map<String, dynamic> json) {
    double n(dynamic v) =>
        v is num ? v.toDouble() : double.tryParse('$v') ?? 0;
    return PosStockReceiptLine(
      productId: (json['productId'] ?? json['ProductId'] ?? '').toString(),
      productCode:
          (json['productCode'] ?? json['ProductCode'] ?? '').toString(),
      productName: (json['productName'] ?? json['ProductName'] ?? '').toString(),
      qty: n(json['qty'] ?? json['Qty']),
      costPrice: n(json['costPrice'] ?? json['CostPrice']),
      lineTotal: n(json['lineTotal'] ?? json['LineTotal']),
    );
  }
}

class PosProductVariant {
  final String id;
  final String skuCode;
  final String? barcode;
  final String name;
  final String? attributeJson;
  final double costPrice;
  final double basePrice;
  final double onHandQty;
  final bool isActive;

  PosProductVariant({
    required this.id,
    required this.skuCode,
    this.barcode,
    required this.name,
    this.attributeJson,
    this.costPrice = 0,
    this.basePrice = 0,
    this.onHandQty = 0,
    this.isActive = true,
  });

  factory PosProductVariant.fromJson(Map<String, dynamic> json) {
    double n(dynamic v) =>
        v is num ? v.toDouble() : double.tryParse('$v') ?? 0;
    return PosProductVariant(
      id: (json['id'] ?? json['Id'] ?? '').toString(),
      skuCode: (json['skuCode'] ?? json['SkuCode'] ?? '').toString(),
      barcode: json['barcode'] ?? json['Barcode'] as String?,
      name: (json['name'] ?? json['Name'] ?? '').toString(),
      attributeJson: json['attributeJson'] ?? json['AttributeJson'] as String?,
      costPrice: n(json['costPrice'] ?? json['CostPrice']),
      basePrice: n(json['basePrice'] ?? json['BasePrice']),
      onHandQty: n(json['onHandQty'] ?? json['OnHandQty']),
      isActive: json['isActive'] != false && json['IsActive'] != false,
    );
  }

  Map<String, dynamic> toUpsertJson() => {
        if (skuCode.trim().isNotEmpty) 'skuCode': skuCode.trim(),
        'barcode': barcode?.trim(),
        'name': name.trim(),
        'attributeJson': attributeJson,
        'costPrice': costPrice,
        'basePrice': basePrice,
        'onHandQty': onHandQty,
      };
}

class PosStockReceipt {
  final String id;
  final String receiptNo;
  final String? supplierId;
  final String? supplierName;
  final String? note;
  final double totalQty;
  final double totalCost;
  final DateTime createdAt;
  final String? createdBy;
  final List<PosStockReceiptLine> lines;

  PosStockReceipt({
    required this.id,
    required this.receiptNo,
    this.supplierId,
    this.supplierName,
    this.note,
    this.totalQty = 0,
    this.totalCost = 0,
    required this.createdAt,
    this.createdBy,
    this.lines = const [],
  });

  factory PosStockReceipt.fromJson(Map<String, dynamic> json) {
    double n(dynamic v) =>
        v is num ? v.toDouble() : double.tryParse('$v') ?? 0;
    final rawLines = json['lines'] ?? json['Lines'];
    return PosStockReceipt(
      id: (json['id'] ?? json['Id'] ?? '').toString(),
      receiptNo: (json['receiptNo'] ?? json['ReceiptNo'] ?? '').toString(),
      supplierId: (json['supplierId'] ?? json['SupplierId'])?.toString(),
      supplierName: json['supplierName'] ?? json['SupplierName'] as String?,
      note: json['note'] ?? json['Note'] as String?,
      totalQty: n(json['totalQty'] ?? json['TotalQty']),
      totalCost: n(json['totalCost'] ?? json['TotalCost']),
      createdAt: parseApiUtcDateTime(json['createdAt'] ?? json['CreatedAt']) ??
          DateTime.now(),
      createdBy: json['createdBy'] ?? json['CreatedBy'] as String?,
      lines: rawLines is List
          ? rawLines
              .map((e) =>
                  PosStockReceiptLine.fromJson(e as Map<String, dynamic>))
              .toList()
          : [],
    );
  }
}
