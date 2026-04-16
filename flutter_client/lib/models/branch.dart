/// Model chi nhánh
class Branch {
  final String id;
  final String code;
  final String name;
  final String? description;
  final String? phone;
  final String? email;
  final String? address;
  final String? city;
  final String? district;
  final String? ward;
  final double? latitude;
  final double? longitude;
  final String? parentBranchId;
  final String? parentBranchName;
  final String? managerId;
  final String? managerName;
  final String? managerPhoto;
  final bool isHeadquarter;
  final int sortOrder;
  final String? taxCode;
  final String? openTime;
  final String? closeTime;
  final int? maxEmployees;
  final bool isActive;
  final int employeeCount;
  final DateTime? createdAt;

  Branch({
    required this.id,
    required this.code,
    required this.name,
    this.description,
    this.phone,
    this.email,
    this.address,
    this.city,
    this.district,
    this.ward,
    this.latitude,
    this.longitude,
    this.parentBranchId,
    this.parentBranchName,
    this.managerId,
    this.managerName,
    this.managerPhoto,
    this.isHeadquarter = false,
    this.sortOrder = 0,
    this.taxCode,
    this.openTime,
    this.closeTime,
    this.maxEmployees,
    this.isActive = true,
    this.employeeCount = 0,
    this.createdAt,
  });

  factory Branch.fromJson(Map<String, dynamic> json) {
    return Branch(
      id: json['id']?.toString() ?? '',
      code: json['code']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      description: json['description']?.toString(),
      phone: json['phone']?.toString(),
      email: json['email']?.toString(),
      address: json['address']?.toString(),
      city: json['city']?.toString(),
      district: json['district']?.toString(),
      ward: json['ward']?.toString(),
      latitude: (json['latitude'] as num?)?.toDouble(),
      longitude: (json['longitude'] as num?)?.toDouble(),
      parentBranchId: json['parentBranchId']?.toString(),
      parentBranchName: json['parentBranchName']?.toString(),
      managerId: json['managerId']?.toString(),
      managerName: json['managerName']?.toString(),
      managerPhoto: json['managerPhoto']?.toString(),
      isHeadquarter: json['isHeadquarter'] as bool? ?? false,
      sortOrder: json['sortOrder'] as int? ?? 0,
      taxCode: json['taxCode']?.toString(),
      openTime: json['openTime']?.toString(),
      closeTime: json['closeTime']?.toString(),
      maxEmployees: json['maxEmployees'] as int?,
      isActive: json['isActive'] as bool? ?? true,
      employeeCount: json['employeeCount'] as int? ?? 0,
      createdAt: json['createdAt'] != null ? DateTime.tryParse(json['createdAt'].toString()) : null,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'code': code,
    'name': name,
    'description': description,
    'phone': phone,
    'email': email,
    'address': address,
    'city': city,
    'district': district,
    'ward': ward,
    'latitude': latitude,
    'longitude': longitude,
    'parentBranchId': parentBranchId,
    'managerId': managerId,
    'isHeadquarter': isHeadquarter,
    'sortOrder': sortOrder,
    'taxCode': taxCode,
    'openTime': openTime,
    'closeTime': closeTime,
    'maxEmployees': maxEmployees,
    'isActive': isActive,
  };

  String get fullAddress {
    final parts = <String>[];
    if (address != null && address!.isNotEmpty) parts.add(address!);
    if (ward != null && ward!.isNotEmpty) parts.add(ward!);
    if (district != null && district!.isNotEmpty) parts.add(district!);
    if (city != null && city!.isNotEmpty) parts.add(city!);
    return parts.join(', ');
  }
}

/// Node cây chi nhánh
class BranchTreeNode {
  final String id;
  final String code;
  final String name;
  final String? address;
  final String? city;
  final String? phone;
  final String? managerName;
  final String? managerPhoto;
  final bool isHeadquarter;
  final bool isActive;
  final int employeeCount;
  final List<BranchTreeNode> children;
  bool isExpanded;

  BranchTreeNode({
    required this.id,
    required this.code,
    required this.name,
    this.address,
    this.city,
    this.phone,
    this.managerName,
    this.managerPhoto,
    this.isHeadquarter = false,
    this.isActive = true,
    this.employeeCount = 0,
    this.children = const [],
    this.isExpanded = true,
  });

  factory BranchTreeNode.fromJson(Map<String, dynamic> json) {
    return BranchTreeNode(
      id: json['id']?.toString() ?? '',
      code: json['code']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      address: json['address']?.toString(),
      city: json['city']?.toString(),
      phone: json['phone']?.toString(),
      managerName: json['managerName']?.toString(),
      managerPhoto: json['managerPhoto']?.toString(),
      isHeadquarter: json['isHeadquarter'] as bool? ?? false,
      isActive: json['isActive'] as bool? ?? true,
      employeeCount: json['employeeCount'] as int? ?? 0,
      children: (json['children'] as List<dynamic>?)
              ?.map((c) => BranchTreeNode.fromJson(c as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }
}

/// Thống kê chi nhánh
class BranchStats {
  final int totalBranches;
  final int activeBranches;
  final int inactiveBranches;
  final int headquarterCount;
  final int totalEmployees;

  BranchStats({
    this.totalBranches = 0,
    this.activeBranches = 0,
    this.inactiveBranches = 0,
    this.headquarterCount = 0,
    this.totalEmployees = 0,
  });

  factory BranchStats.fromJson(Map<String, dynamic> json) {
    return BranchStats(
      totalBranches: json['totalBranches'] as int? ?? 0,
      activeBranches: json['activeBranches'] as int? ?? 0,
      inactiveBranches: json['inactiveBranches'] as int? ?? 0,
      headquarterCount: json['headquarterCount'] as int? ?? 0,
      totalEmployees: json['totalEmployees'] as int? ?? 0,
    );
  }
}

/// Dropdown item
class BranchSelect {
  final String id;
  final String code;
  final String name;
  final bool isHeadquarter;

  BranchSelect({
    required this.id,
    required this.code,
    required this.name,
    this.isHeadquarter = false,
  });

  factory BranchSelect.fromJson(Map<String, dynamic> json) {
    return BranchSelect(
      id: json['id']?.toString() ?? '',
      code: json['code']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      isHeadquarter: json['isHeadquarter'] as bool? ?? false,
    );
  }
}
