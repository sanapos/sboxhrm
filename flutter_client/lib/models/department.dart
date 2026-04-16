class Department {
  final String id;
  final String name;
  final String? code;
  final String? description;
  final String? parentId;
  final String? parentName;
  final String? managerId;
  final String? managerName;
  final int? sortOrder;
  final bool isActive;
  final int? employeeCount;
  final int? totalEmployeeCount;
  final int? level;
  final String? hierarchyPath;
  final List<dynamic>? positions;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  // Aliases for screen compatibility
  String? get parentDepartmentId => parentId;
  String? get parentDepartmentName => parentName;
  int? get directEmployeeCount => employeeCount;

  Department({
    required this.id,
    required this.name,
    this.code,
    this.description,
    this.parentId,
    this.parentName,
    this.managerId,
    this.managerName,
    this.sortOrder,
    this.isActive = true,
    this.employeeCount,
    this.totalEmployeeCount,
    this.level,
    this.hierarchyPath,
    this.positions,
    this.createdAt,
    this.updatedAt,
  });

  factory Department.fromJson(Map<String, dynamic> json) {
    return Department(
      id: json['id']?.toString() ?? '',
      name: json['name'] ?? '',
      code: json['code'],
      description: json['description'],
      parentId: json['parentId']?.toString() ?? json['parentDepartmentId']?.toString(),
      parentName: json['parentName'] ?? json['parentDepartmentName'],
      managerId: json['managerId']?.toString(),
      managerName: json['managerName'],
      sortOrder: json['sortOrder'],
      isActive: json['isActive'] ?? true,
      employeeCount: json['employeeCount'] ?? json['directEmployeeCount'],
      totalEmployeeCount: json['totalEmployeeCount'],
      level: json['level'],
      hierarchyPath: json['hierarchyPath'],
      positions: json['positions'] as List<dynamic>?,
      createdAt: json['createdAt'] != null ? DateTime.parse(json['createdAt']) : null,
      updatedAt: json['updatedAt'] != null ? DateTime.parse(json['updatedAt']) : null,
    );
  }

  Map<String, dynamic> toJson() => {
    'name': name,
    'code': code,
    'description': description,
    'parentId': parentId,
    'managerId': managerId,
    'sortOrder': sortOrder,
    'isActive': isActive,
  };
}

class DepartmentTreeNode {
  final String id;
  final String name;
  final String? code;
  final String? parentId;
  final int? level;
  final String? displayName;
  final int? employeeCount;
  final int? totalEmployeeCount;
  final String? managerName;
  final bool isActive;
  final List<DepartmentTreeNode> children;

  int? get directEmployeeCount => employeeCount;

  DepartmentTreeNode({
    required this.id,
    required this.name,
    this.code,
    this.parentId,
    this.level,
    this.displayName,
    this.employeeCount,
    this.totalEmployeeCount,
    this.managerName,
    this.isActive = true,
    this.children = const [],
  });

  factory DepartmentTreeNode.fromJson(Map<String, dynamic> json) {
    return DepartmentTreeNode(
      id: json['id']?.toString() ?? '',
      name: json['name'] ?? '',
      code: json['code'],
      parentId: json['parentId']?.toString(),
      level: json['level'],
      displayName: json['displayName'],
      employeeCount: json['employeeCount'] ?? json['directEmployeeCount'],
      totalEmployeeCount: json['totalEmployeeCount'],
      managerName: json['managerName'],
      isActive: json['isActive'] ?? true,
      children: (json['children'] as List?)
              ?.map((e) => DepartmentTreeNode.fromJson(e))
              .toList() ??
          [],
    );
  }
}

class DepartmentSelectDto {
  final String id;
  final String name;
  final String? code;
  final int? level;
  final String? displayName;
  final String? parentId;

  DepartmentSelectDto({
    required this.id,
    required this.name,
    this.code,
    this.level,
    this.displayName,
    this.parentId,
  });

  factory DepartmentSelectDto.fromJson(Map<String, dynamic> json) {
    return DepartmentSelectDto(
      id: json['id']?.toString() ?? '',
      name: json['name'] ?? '',
      code: json['code'],
      level: json['level'],
      displayName: json['displayName'],
      parentId: json['parentId']?.toString(),
    );
  }
}
