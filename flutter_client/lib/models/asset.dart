// Asset Management Models for Flutter
// Quản lý tài sản

// ==================== ENUMS ====================
enum AssetStatus {
  active,       // Đang sử dụng
  inMaintenance, // Đang bảo trì
  broken,       // Hỏng
  disposed,     // Đã thanh lý
  lost,         // Đã mất
  inStock       // Trong kho
}

enum AssetType {
  electronics,  // Thiết bị điện tử
  furniture,    // Nội thất
  vehicle,      // Phương tiện
  tool,         // Công cụ dụng cụ
  machinery,    // Máy móc
  software,     // Phần mềm
  other         // Khác
}

enum AssetTransferType {
  assignment,   // Cấp mới
  transfer,     // Chuyển giao
  returnAsset,  // Thu hồi
  maintenance,  // Bảo trì
  disposal      // Thanh lý
}

enum InventoryCondition {
  good,         // Tốt
  fair,         // Bình thường
  poor,         // Kém
  damaged,      // Hỏng
  notFound      // Không tìm thấy
}

// Helper functions
String getAssetStatusLabel(AssetStatus status) {
  switch (status) {
    case AssetStatus.active: return 'Đang sử dụng';
    case AssetStatus.inMaintenance: return 'Đang bảo trì';
    case AssetStatus.broken: return 'Hỏng';
    case AssetStatus.disposed: return 'Đã thanh lý';
    case AssetStatus.lost: return 'Đã mất';
    case AssetStatus.inStock: return 'Trong kho';
  }
}

String getAssetTypeLabel(AssetType type) {
  switch (type) {
    case AssetType.electronics: return 'Thiết bị điện tử';
    case AssetType.furniture: return 'Nội thất';
    case AssetType.vehicle: return 'Phương tiện';
    case AssetType.tool: return 'Công cụ dụng cụ';
    case AssetType.machinery: return 'Máy móc';
    case AssetType.software: return 'Phần mềm';
    case AssetType.other: return 'Khác';
  }
}

String getTransferTypeLabel(AssetTransferType type) {
  switch (type) {
    case AssetTransferType.assignment: return 'Cấp mới';
    case AssetTransferType.transfer: return 'Chuyển giao';
    case AssetTransferType.returnAsset: return 'Thu hồi';
    case AssetTransferType.maintenance: return 'Bảo trì';
    case AssetTransferType.disposal: return 'Thanh lý';
  }
}

String getConditionLabel(InventoryCondition condition) {
  switch (condition) {
    case InventoryCondition.good: return 'Tốt';
    case InventoryCondition.fair: return 'Bình thường';
    case InventoryCondition.poor: return 'Kém';
    case InventoryCondition.damaged: return 'Hỏng';
    case InventoryCondition.notFound: return 'Không tìm thấy';
  }
}

AssetStatus parseAssetStatus(dynamic value) {
  if (value == null) return AssetStatus.inStock;
  final index = value is int ? value : int.tryParse(value.toString()) ?? 5;
  return AssetStatus.values[index.clamp(0, AssetStatus.values.length - 1)];
}

AssetType parseAssetType(dynamic value) {
  if (value == null) return AssetType.other;
  final index = value is int ? value : int.tryParse(value.toString()) ?? 6;
  return AssetType.values[index.clamp(0, AssetType.values.length - 1)];
}

AssetTransferType parseTransferType(dynamic value) {
  if (value == null) return AssetTransferType.assignment;
  final index = value is int ? value : int.tryParse(value.toString()) ?? 0;
  return AssetTransferType.values[index.clamp(0, AssetTransferType.values.length - 1)];
}

InventoryCondition? parseCondition(dynamic value) {
  if (value == null) return null;
  final index = value is int ? value : int.tryParse(value.toString());
  if (index == null) return null;
  return InventoryCondition.values[index.clamp(0, InventoryCondition.values.length - 1)];
}

// ==================== MODELS ====================

class AssetCategory {
  final String id;
  final String categoryCode;
  final String name;
  final String? description;
  final String? parentCategoryId;
  final String? parentCategoryName;
  final int assetCount;
  final bool isActive;
  final DateTime createdAt;
  final List<AssetCategory>? subCategories;

  AssetCategory({
    required this.id,
    required this.categoryCode,
    required this.name,
    this.description,
    this.parentCategoryId,
    this.parentCategoryName,
    this.assetCount = 0,
    this.isActive = true,
    required this.createdAt,
    this.subCategories,
  });

  factory AssetCategory.fromJson(Map<String, dynamic> json) {
    return AssetCategory(
      id: json['id'] ?? '',
      categoryCode: json['categoryCode'] ?? '',
      name: json['name'] ?? '',
      description: json['description'],
      parentCategoryId: json['parentCategoryId'],
      parentCategoryName: json['parentCategoryName'],
      assetCount: json['assetCount'] ?? 0,
      isActive: json['isActive'] ?? true,
      createdAt: DateTime.tryParse(json['createdAt'] ?? '') ?? DateTime.now(),
      subCategories: (json['subCategories'] as List?)
          ?.map((e) => AssetCategory.fromJson(e))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'categoryCode': categoryCode,
    'name': name,
    'description': description,
    'parentCategoryId': parentCategoryId,
  };
}

class Asset {
  final String id;
  final String assetCode;
  final String? qrCode;
  final String name;
  final String? description;
  final String? serialNumber;
  final String? model;
  final String? brand;
  final String? size;
  final String? color;
  final AssetType assetType;
  final String assetTypeName;
  final String? categoryId;
  final String? categoryName;
  final AssetStatus status;
  final String statusName;
  final int quantity;
  final String unit;
  final double purchasePrice;
  final String currency;
  final DateTime? purchaseDate;
  final String? supplier;
  final String? invoiceNumber;
  final int? warrantyMonths;
  final DateTime? warrantyExpiry;
  final bool isWarrantyExpired;
  final int daysUntilWarrantyExpiry;
  final String? location;
  final String? notes;
  final double? depreciationRate;
  final double? currentValue;
  final String? currentAssigneeId;
  final String? currentAssigneeName;
  final DateTime? assignedDate;
  final bool isActive;
  final DateTime createdAt;
  final String? createdBy;
  final List<AssetImage>? images;
  final String? primaryImageUrl;
  final List<AssetTransfer>? transferHistory;

  Asset({
    required this.id,
    required this.assetCode,
    this.qrCode,
    required this.name,
    this.description,
    this.serialNumber,
    this.model,
    this.brand,
    this.size,
    this.color,
    required this.assetType,
    this.assetTypeName = '',
    this.categoryId,
    this.categoryName,
    required this.status,
    this.statusName = '',
    this.quantity = 1,
    this.unit = 'Cái',
    required this.purchasePrice,
    this.currency = 'VND',
    this.purchaseDate,
    this.supplier,
    this.invoiceNumber,
    this.warrantyMonths,
    this.warrantyExpiry,
    this.isWarrantyExpired = false,
    this.daysUntilWarrantyExpiry = 0,
    this.location,
    this.notes,
    this.depreciationRate,
    this.currentValue,
    this.currentAssigneeId,
    this.currentAssigneeName,
    this.assignedDate,
    this.isActive = true,
    required this.createdAt,
    this.createdBy,
    this.images,
    this.primaryImageUrl,
    this.transferHistory,
  });

  factory Asset.fromJson(Map<String, dynamic> json) {
    return Asset(
      id: json['id'] ?? '',
      assetCode: json['assetCode'] ?? '',
      qrCode: json['qrCode'],
      name: json['name'] ?? '',
      description: json['description'],
      serialNumber: json['serialNumber'],
      model: json['model'],
      brand: json['brand'],
      size: json['size'],
      color: json['color'],
      assetType: parseAssetType(json['assetType']),
      assetTypeName: json['assetTypeName'] ?? '',
      categoryId: json['categoryId'],
      categoryName: json['categoryName'],
      status: parseAssetStatus(json['status']),
      statusName: json['statusName'] ?? '',
      quantity: json['quantity'] ?? 1,
      unit: json['unit'] ?? 'Cái',
      purchasePrice: (json['purchasePrice'] ?? 0).toDouble(),
      currency: json['currency'] ?? 'VND',
      purchaseDate: json['purchaseDate'] != null ? DateTime.tryParse(json['purchaseDate']) : null,
      supplier: json['supplier'],
      invoiceNumber: json['invoiceNumber'],
      warrantyMonths: json['warrantyMonths'],
      warrantyExpiry: json['warrantyExpiry'] != null ? DateTime.tryParse(json['warrantyExpiry']) : null,
      isWarrantyExpired: json['isWarrantyExpired'] ?? false,
      daysUntilWarrantyExpiry: json['daysUntilWarrantyExpiry'] ?? 0,
      location: json['location'],
      notes: json['notes'],
      depreciationRate: json['depreciationRate']?.toDouble(),
      currentValue: json['currentValue']?.toDouble(),
      currentAssigneeId: json['currentAssigneeId'],
      currentAssigneeName: json['currentAssigneeName'],
      assignedDate: json['assignedDate'] != null ? DateTime.tryParse(json['assignedDate']) : null,
      isActive: json['isActive'] ?? true,
      createdAt: DateTime.tryParse(json['createdAt'] ?? '') ?? DateTime.now(),
      createdBy: json['createdBy'],
      images: (json['images'] as List?)?.map((e) => AssetImage.fromJson(e)).toList(),
      primaryImageUrl: json['primaryImageUrl'],
      transferHistory: (json['transferHistory'] as List?)?.map((e) => AssetTransfer.fromJson(e)).toList(),
    );
  }

  bool get isAssigned => currentAssigneeId != null;
  bool get warrantyExpiringSoon => daysUntilWarrantyExpiry > 0 && daysUntilWarrantyExpiry <= 30;
}

class AssetImage {
  final String id;
  final String assetId;
  final String imageUrl;
  final String? fileName;
  final String? description;
  final bool isPrimary;
  final int displayOrder;

  AssetImage({
    required this.id,
    required this.assetId,
    required this.imageUrl,
    this.fileName,
    this.description,
    this.isPrimary = false,
    this.displayOrder = 0,
  });

  factory AssetImage.fromJson(Map<String, dynamic> json) {
    return AssetImage(
      id: json['id'] ?? '',
      assetId: json['assetId'] ?? '',
      imageUrl: json['imageUrl'] ?? '',
      fileName: json['fileName'],
      description: json['description'],
      isPrimary: json['isPrimary'] ?? false,
      displayOrder: json['displayOrder'] ?? 0,
    );
  }
}

class AssetTransfer {
  final String id;
  final String assetId;
  final String? assetCode;
  final String? assetName;
  final AssetTransferType transferType;
  final String transferTypeName;
  final String? fromUserId;
  final String? fromUserName;
  final String? toUserId;
  final String? toUserName;
  final int quantity;
  final DateTime transferDate;
  final String? reason;
  final String? notes;
  final String? performedById;
  final String? performedByName;
  final bool isConfirmed;
  final DateTime? confirmedAt;
  final DateTime createdAt;

  AssetTransfer({
    required this.id,
    required this.assetId,
    this.assetCode,
    this.assetName,
    required this.transferType,
    this.transferTypeName = '',
    this.fromUserId,
    this.fromUserName,
    this.toUserId,
    this.toUserName,
    this.quantity = 1,
    required this.transferDate,
    this.reason,
    this.notes,
    this.performedById,
    this.performedByName,
    this.isConfirmed = false,
    this.confirmedAt,
    required this.createdAt,
  });

  factory AssetTransfer.fromJson(Map<String, dynamic> json) {
    return AssetTransfer(
      id: json['id'] ?? '',
      assetId: json['assetId'] ?? '',
      assetCode: json['assetCode'],
      assetName: json['assetName'],
      transferType: parseTransferType(json['transferType']),
      transferTypeName: json['transferTypeName'] ?? '',
      fromUserId: json['fromUserId'],
      fromUserName: json['fromUserName'],
      toUserId: json['toUserId'],
      toUserName: json['toUserName'],
      quantity: json['quantity'] ?? 1,
      transferDate: DateTime.tryParse(json['transferDate'] ?? '') ?? DateTime.now(),
      reason: json['reason'],
      notes: json['notes'],
      performedById: json['performedById'],
      performedByName: json['performedByName'],
      isConfirmed: json['isConfirmed'] ?? false,
      confirmedAt: json['confirmedAt'] != null ? DateTime.tryParse(json['confirmedAt']) : null,
      createdAt: DateTime.tryParse(json['createdAt'] ?? '') ?? DateTime.now(),
    );
  }
}

class AssetInventory {
  final String id;
  final String inventoryCode;
  final String name;
  final String? description;
  final DateTime startDate;
  final DateTime? endDate;
  final int status;
  final String statusName;
  final String? responsibleUserId;
  final String? responsibleUserName;
  final String? notes;
  final int totalAssets;
  final int checkedCount;
  final int issueCount;
  final double progressPercent;
  final DateTime createdAt;
  final List<AssetInventoryItem>? items;

  AssetInventory({
    required this.id,
    required this.inventoryCode,
    required this.name,
    this.description,
    required this.startDate,
    this.endDate,
    this.status = 0,
    this.statusName = '',
    this.responsibleUserId,
    this.responsibleUserName,
    this.notes,
    this.totalAssets = 0,
    this.checkedCount = 0,
    this.issueCount = 0,
    this.progressPercent = 0,
    required this.createdAt,
    this.items,
  });

  factory AssetInventory.fromJson(Map<String, dynamic> json) {
    return AssetInventory(
      id: json['id'] ?? '',
      inventoryCode: json['inventoryCode'] ?? '',
      name: json['name'] ?? '',
      description: json['description'],
      startDate: DateTime.tryParse(json['startDate'] ?? '') ?? DateTime.now(),
      endDate: json['endDate'] != null ? DateTime.tryParse(json['endDate']) : null,
      status: json['status'] ?? 0,
      statusName: json['statusName'] ?? '',
      responsibleUserId: json['responsibleUserId'],
      responsibleUserName: json['responsibleUserName'],
      notes: json['notes'],
      totalAssets: json['totalAssets'] ?? 0,
      checkedCount: json['checkedCount'] ?? 0,
      issueCount: json['issueCount'] ?? 0,
      progressPercent: (json['progressPercent'] ?? 0).toDouble(),
      createdAt: DateTime.tryParse(json['createdAt'] ?? '') ?? DateTime.now(),
      items: (json['items'] as List?)?.map((e) => AssetInventoryItem.fromJson(e)).toList(),
    );
  }

  bool get isInProgress => status == 0;
  bool get isCompleted => status == 1;
  bool get isCancelled => status == 2;
}

class AssetInventoryItem {
  final String id;
  final String inventoryId;
  final String assetId;
  final String? assetCode;
  final String? assetName;
  final bool isChecked;
  final DateTime? checkedAt;
  final String? checkedById;
  final String? checkedByName;
  final InventoryCondition? condition;
  final String? conditionName;
  final int expectedQuantity;
  final int? actualQuantity;
  final bool quantityMismatch;
  final String? actualLocation;
  final bool hasIssue;
  final String? issueDescription;
  final String? notes;

  AssetInventoryItem({
    required this.id,
    required this.inventoryId,
    required this.assetId,
    this.assetCode,
    this.assetName,
    this.isChecked = false,
    this.checkedAt,
    this.checkedById,
    this.checkedByName,
    this.condition,
    this.conditionName,
    this.expectedQuantity = 0,
    this.actualQuantity,
    this.quantityMismatch = false,
    this.actualLocation,
    this.hasIssue = false,
    this.issueDescription,
    this.notes,
  });

  factory AssetInventoryItem.fromJson(Map<String, dynamic> json) {
    return AssetInventoryItem(
      id: json['id'] ?? '',
      inventoryId: json['inventoryId'] ?? '',
      assetId: json['assetId'] ?? '',
      assetCode: json['assetCode'],
      assetName: json['assetName'],
      isChecked: json['isChecked'] ?? false,
      checkedAt: json['checkedAt'] != null ? DateTime.tryParse(json['checkedAt']) : null,
      checkedById: json['checkedById'],
      checkedByName: json['checkedByName'],
      condition: parseCondition(json['condition']),
      conditionName: json['conditionName'],
      expectedQuantity: json['expectedQuantity'] ?? 0,
      actualQuantity: json['actualQuantity'],
      quantityMismatch: json['quantityMismatch'] ?? false,
      actualLocation: json['actualLocation'],
      hasIssue: json['hasIssue'] ?? false,
      issueDescription: json['issueDescription'],
      notes: json['notes'],
    );
  }
}

class AssetStatistics {
  final int totalAssets;
  final int activeAssets;
  final int inStockAssets;
  final int assignedAssets;
  final int maintenanceAssets;
  final int brokenAssets;
  final int disposedAssets;
  final double totalPurchaseValue;
  final double totalCurrentValue;
  final int warrantyExpiringSoon;
  final List<AssetByType>? byType;
  final List<AssetByCategory>? byCategory;
  final List<AssetByAssignee>? byAssignee;
  final List<AssetByStatus>? byStatus;

  AssetStatistics({
    this.totalAssets = 0,
    this.activeAssets = 0,
    this.inStockAssets = 0,
    this.assignedAssets = 0,
    this.maintenanceAssets = 0,
    this.brokenAssets = 0,
    this.disposedAssets = 0,
    this.totalPurchaseValue = 0,
    this.totalCurrentValue = 0,
    this.warrantyExpiringSoon = 0,
    this.byType,
    this.byCategory,
    this.byAssignee,
    this.byStatus,
  });

  factory AssetStatistics.fromJson(Map<String, dynamic> json) {
    return AssetStatistics(
      totalAssets: json['totalAssets'] ?? 0,
      activeAssets: json['activeAssets'] ?? 0,
      inStockAssets: json['inStockAssets'] ?? 0,
      assignedAssets: json['assignedAssets'] ?? 0,
      maintenanceAssets: json['maintenanceAssets'] ?? 0,
      brokenAssets: json['brokenAssets'] ?? 0,
      disposedAssets: json['disposedAssets'] ?? 0,
      totalPurchaseValue: (json['totalPurchaseValue'] ?? 0).toDouble(),
      totalCurrentValue: (json['totalCurrentValue'] ?? 0).toDouble(),
      warrantyExpiringSoon: json['warrantyExpiringSoon'] ?? 0,
      byType: (json['byType'] as List?)?.map((e) => AssetByType.fromJson(e)).toList(),
      byCategory: (json['byCategory'] as List?)?.map((e) => AssetByCategory.fromJson(e)).toList(),
      byAssignee: (json['byAssignee'] as List?)?.map((e) => AssetByAssignee.fromJson(e)).toList(),
      byStatus: (json['byStatus'] as List?)?.map((e) => AssetByStatus.fromJson(e)).toList(),
    );
  }
}

class AssetByType {
  final AssetType assetType;
  final String assetTypeName;
  final int count;
  final double totalValue;

  AssetByType({
    required this.assetType,
    this.assetTypeName = '',
    this.count = 0,
    this.totalValue = 0,
  });

  factory AssetByType.fromJson(Map<String, dynamic> json) {
    return AssetByType(
      assetType: parseAssetType(json['assetType']),
      assetTypeName: json['assetTypeName'] ?? '',
      count: json['count'] ?? 0,
      totalValue: (json['totalValue'] ?? 0).toDouble(),
    );
  }
}

class AssetByCategory {
  final String? categoryId;
  final String categoryName;
  final int count;
  final double totalValue;

  AssetByCategory({
    this.categoryId,
    this.categoryName = '',
    this.count = 0,
    this.totalValue = 0,
  });

  factory AssetByCategory.fromJson(Map<String, dynamic> json) {
    return AssetByCategory(
      categoryId: json['categoryId'],
      categoryName: json['categoryName'] ?? '',
      count: json['count'] ?? 0,
      totalValue: (json['totalValue'] ?? 0).toDouble(),
    );
  }
}

class AssetByAssignee {
  final String? assigneeId;
  final String assigneeName;
  final int count;
  final double totalValue;

  AssetByAssignee({
    this.assigneeId,
    this.assigneeName = '',
    this.count = 0,
    this.totalValue = 0,
  });

  factory AssetByAssignee.fromJson(Map<String, dynamic> json) {
    return AssetByAssignee(
      assigneeId: json['assigneeId'],
      assigneeName: json['assigneeName'] ?? '',
      count: json['count'] ?? 0,
      totalValue: (json['totalValue'] ?? 0).toDouble(),
    );
  }
}

class AssetByStatus {
  final AssetStatus status;
  final String statusName;
  final int count;

  AssetByStatus({
    required this.status,
    this.statusName = '',
    this.count = 0,
  });

  factory AssetByStatus.fromJson(Map<String, dynamic> json) {
    return AssetByStatus(
      status: parseAssetStatus(json['status']),
      statusName: json['statusName'] ?? '',
      count: json['count'] ?? 0,
    );
  }
}
