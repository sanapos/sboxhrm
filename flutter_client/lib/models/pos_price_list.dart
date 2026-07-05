class PosPriceList {
  final String id;
  final String name;
  final bool isDefault;
  final bool isActive;
  final int sortOrder;
  final int itemCount;

  const PosPriceList({
    required this.id,
    required this.name,
    this.isDefault = false,
    this.isActive = true,
    this.sortOrder = 0,
    this.itemCount = 0,
  });

  factory PosPriceList.fromJson(Map<String, dynamic> json) => PosPriceList(
        id: '${json['id'] ?? json['Id']}',
        name: '${json['name'] ?? json['Name'] ?? ''}',
        isDefault: json['isDefault'] == true || json['IsDefault'] == true,
        isActive: json['isActive'] != false && json['IsActive'] != false,
        sortOrder: (json['sortOrder'] ?? json['SortOrder'] ?? 0) as int,
        itemCount: (json['itemCount'] ?? json['ItemCount'] ?? 0) as int,
      );
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

  factory PosPriceListItem.fromJson(Map<String, dynamic> json) => PosPriceListItem(
        id: '${json['id'] ?? json['Id']}',
        productId: '${json['productId'] ?? json['ProductId']}',
        variantId: (json['variantId'] ?? json['VariantId'])?.toString(),
        unitId: (json['unitId'] ?? json['UnitId'])?.toString(),
        price: ((json['price'] ?? json['Price'] ?? 0) as num).toDouble(),
        productName: (json['productName'] ?? json['ProductName'])?.toString(),
        variantName: (json['variantName'] ?? json['VariantName'])?.toString(),
        unitName: (json['unitName'] ?? json['UnitName'])?.toString(),
      );
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

  factory PosResolvedPrice.fromJson(Map<String, dynamic> json) => PosResolvedPrice(
        productId: '${json['productId'] ?? json['ProductId']}',
        variantId: (json['variantId'] ?? json['VariantId'])?.toString(),
        unitId: (json['unitId'] ?? json['UnitId'])?.toString(),
        price: ((json['price'] ?? json['Price'] ?? 0) as num).toDouble(),
      );
}
