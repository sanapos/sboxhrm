class PosPriceList {
  final String id;
  final String name;
  final bool isDefault;
  final bool isActive;
  final int sortOrder;
  final int itemCount;
  final DateTime? validFrom;
  final DateTime? validTo;

  const PosPriceList({
    required this.id,
    required this.name,
    this.isDefault = false,
    this.isActive = true,
    this.sortOrder = 0,
    this.itemCount = 0,
    this.validFrom,
    this.validTo,
  });

  /// Áp dụng cho ngày hóa đơn (theo ValidFrom/ValidTo, null = không giới hạn).
  bool isApplicableOn(DateTime day) {
    final d = DateTime(day.year, day.month, day.day);
    if (validFrom != null) {
      final f = DateTime(validFrom!.year, validFrom!.month, validFrom!.day);
      if (d.isBefore(f)) return false;
    }
    if (validTo != null) {
      final t = DateTime(validTo!.year, validTo!.month, validTo!.day);
      if (d.isAfter(t)) return false;
    }
    return true;
  }

  factory PosPriceList.fromJson(Map<String, dynamic> json) {
    DateTime? parseDate(dynamic v) {
      if (v == null) return null;
      return DateTime.tryParse(v.toString())?.toLocal();
    }

    int asInt(dynamic v) {
      if (v is int) return v;
      if (v is num) return v.toInt();
      return int.tryParse('$v') ?? 0;
    }

    return PosPriceList(
      id: '${json['id'] ?? json['Id']}',
      name: '${json['name'] ?? json['Name'] ?? ''}',
      isDefault: json['isDefault'] == true || json['IsDefault'] == true,
      isActive: json['isActive'] != false && json['IsActive'] != false,
      sortOrder: asInt(json['sortOrder'] ?? json['SortOrder']),
      itemCount: asInt(json['itemCount'] ?? json['ItemCount']),
      validFrom: parseDate(json['validFrom'] ?? json['ValidFrom']),
      validTo: parseDate(json['validTo'] ?? json['ValidTo']),
    );
  }
}

/// Chọn bảng giá mặc định khi bán theo ngày hóa đơn.
PosPriceList? pickDefaultPosPriceList(
  List<PosPriceList> lists, {
  DateTime? at,
}) {
  if (lists.isEmpty) return null;
  final day = at ?? DateTime.now();
  for (final l in lists) {
    if (l.isDefault && l.isApplicableOn(day)) return l;
  }
  for (final l in lists) {
    if (l.validFrom == null && l.validTo == null) return l;
  }
  for (final l in lists) {
    if (l.isApplicableOn(day)) return l;
  }
  return lists.first;
}

class PosPriceListItem {
  final String id;
  final String productId;
  final String? variantId;
  final String? unitId;
  final double price;
  final String? productName;
  final String? variantName;
  final String? unitName;

  const PosPriceListItem({
    required this.id,
    required this.productId,
    this.variantId,
    this.unitId,
    required this.price,
    this.productName,
    this.variantName,
    this.unitName,
  });

  factory PosPriceListItem.fromJson(Map<String, dynamic> json) {
    double asPrice(dynamic v) {
      if (v is num) return v.toDouble();
      return double.tryParse('$v') ?? 0;
    }

    String? asId(dynamic v) {
      if (v == null) return null;
      final s = v.toString().trim();
      if (s.isEmpty || s == 'null') return null;
      return s;
    }

    return PosPriceListItem(
      id: '${json['id'] ?? json['Id']}',
      productId: '${json['productId'] ?? json['ProductId']}',
      variantId: asId(json['variantId'] ?? json['VariantId']),
      unitId: asId(json['unitId'] ?? json['UnitId']),
      price: asPrice(json['price'] ?? json['Price']),
      productName: (json['productName'] ?? json['ProductName'])?.toString(),
      variantName: (json['variantName'] ?? json['VariantName'])?.toString(),
      unitName: (json['unitName'] ?? json['UnitName'])?.toString(),
    );
  }
}

class PosResolvedPrice {
  final String productId;
  final String? variantId;
  final String? unitId;
  final double price;

  const PosResolvedPrice({
    required this.productId,
    this.variantId,
    this.unitId,
    required this.price,
  });

  factory PosResolvedPrice.fromJson(Map<String, dynamic> json) {
    double asPrice(dynamic v) {
      if (v is num) return v.toDouble();
      return double.tryParse('$v') ?? 0;
    }

    String? asId(dynamic v) {
      if (v == null) return null;
      final s = v.toString().trim();
      if (s.isEmpty || s == 'null') return null;
      return s;
    }

    return PosResolvedPrice(
      productId: '${json['productId'] ?? json['ProductId']}',
      variantId: asId(json['variantId'] ?? json['VariantId']),
      unitId: asId(json['unitId'] ?? json['UnitId']),
      price: asPrice(json['price'] ?? json['Price']),
    );
  }
}
