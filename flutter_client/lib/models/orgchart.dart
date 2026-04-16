/// Models cho Sơ đồ tổ chức & Luồng duyệt
library;

// ═══════════════════════════════════════════════════════════════
// CHỨC VỤ (OrgPosition)
// ═══════════════════════════════════════════════════════════════

class OrgPosition {
  final String id;
  final String code;
  final String name;
  final String? description;
  final int level;
  final int sortOrder;
  final String? color;
  final String? iconName;
  final bool canApprove;
  final double? maxApprovalAmount;
  final bool isActive;
  final int assignmentCount;

  OrgPosition({
    required this.id,
    required this.code,
    required this.name,
    this.description,
    required this.level,
    required this.sortOrder,
    this.color,
    this.iconName,
    required this.canApprove,
    this.maxApprovalAmount,
    required this.isActive,
    this.assignmentCount = 0,
  });

  factory OrgPosition.fromJson(Map<String, dynamic> json) {
    return OrgPosition(
      id: json['id']?.toString() ?? '',
      code: json['code']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      description: json['description']?.toString(),
      level: json['level'] as int? ?? 0,
      sortOrder: json['sortOrder'] as int? ?? 0,
      color: json['color']?.toString(),
      iconName: json['iconName']?.toString(),
      canApprove: json['canApprove'] as bool? ?? false,
      maxApprovalAmount: json['maxApprovalAmount'] != null
          ? (json['maxApprovalAmount'] as num).toDouble()
          : null,
      isActive: json['isActive'] as bool? ?? true,
      assignmentCount: json['assignmentCount'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
    'code': code,
    'name': name,
    'description': description,
    'level': level,
    'sortOrder': sortOrder,
    'color': color,
    'iconName': iconName,
    'canApprove': canApprove,
    'maxApprovalAmount': maxApprovalAmount,
    'isActive': isActive,
  };

  static String levelName(int level) {
    switch (level) {
      case 1: return 'C-Level';
      case 2: return 'Phó GĐ';
      case 3: return 'Trưởng phòng';
      case 4: return 'Phó phòng';
      case 5: return 'Trưởng nhóm';
      case 6: return 'Nhân viên';
      default: return 'Cấp $level';
    }
  }
}

// ═══════════════════════════════════════════════════════════════
// GÁN CHỨC VỤ (OrgAssignment)
// ═══════════════════════════════════════════════════════════════

class OrgAssignment {
  final String id;
  final String employeeId;
  final String employeeName;
  final String employeeCode;
  final String? employeePhoto;
  final String departmentId;
  final String departmentName;
  final String positionId;
  final String positionName;
  final int positionLevel;
  final String? positionColor;
  final bool isPrimary;
  final DateTime? startDate;
  final DateTime? endDate;
  final String? reportToAssignmentId;
  final String? reportToEmployeeName;
  final bool isActive;
  final int directReportsCount;

  OrgAssignment({
    required this.id,
    required this.employeeId,
    required this.employeeName,
    required this.employeeCode,
    this.employeePhoto,
    required this.departmentId,
    required this.departmentName,
    required this.positionId,
    required this.positionName,
    required this.positionLevel,
    this.positionColor,
    required this.isPrimary,
    this.startDate,
    this.endDate,
    this.reportToAssignmentId,
    this.reportToEmployeeName,
    required this.isActive,
    this.directReportsCount = 0,
  });

  factory OrgAssignment.fromJson(Map<String, dynamic> json) {
    return OrgAssignment(
      id: json['id']?.toString() ?? '',
      employeeId: json['employeeId']?.toString() ?? '',
      employeeName: json['employeeName']?.toString() ?? '',
      employeeCode: json['employeeCode']?.toString() ?? '',
      employeePhoto: json['employeePhoto']?.toString(),
      departmentId: json['departmentId']?.toString() ?? '',
      departmentName: json['departmentName']?.toString() ?? '',
      positionId: json['positionId']?.toString() ?? '',
      positionName: json['positionName']?.toString() ?? '',
      positionLevel: json['positionLevel'] as int? ?? 0,
      positionColor: json['positionColor']?.toString(),
      isPrimary: json['isPrimary'] as bool? ?? true,
      startDate: json['startDate'] != null ? DateTime.tryParse(json['startDate'].toString()) : null,
      endDate: json['endDate'] != null ? DateTime.tryParse(json['endDate'].toString()) : null,
      reportToAssignmentId: json['reportToAssignmentId']?.toString(),
      reportToEmployeeName: json['reportToEmployeeName']?.toString(),
      isActive: json['isActive'] as bool? ?? true,
      directReportsCount: json['directReportsCount'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toCreateJson() => {
    'employeeId': employeeId,
    'departmentId': departmentId,
    'positionId': positionId,
    'isPrimary': isPrimary,
    'startDate': startDate?.toIso8601String(),
    'reportToAssignmentId': reportToAssignmentId,
  };

  Map<String, dynamic> toUpdateJson() => {
    'isPrimary': isPrimary,
    'reportToAssignmentId': reportToAssignmentId,
    'startDate': startDate?.toIso8601String(),
    'endDate': endDate?.toIso8601String(),
    'isActive': isActive,
  };
}

// ═══════════════════════════════════════════════════════════════
// SƠ ĐỒ TỔ CHỨC NODE
// ═══════════════════════════════════════════════════════════════

class OrgChartNode {
  final String id;
  final String nodeType;
  final String name;
  final String code;
  final String? description;
  final int level;
  final List<OrgChartMember> members;
  final List<OrgChartNode> children;
  bool isExpanded;

  OrgChartNode({
    required this.id,
    required this.nodeType,
    required this.name,
    required this.code,
    this.description,
    required this.level,
    required this.members,
    required this.children,
    this.isExpanded = true,
  });

  factory OrgChartNode.fromJson(Map<String, dynamic> json) {
    return OrgChartNode(
      id: json['id']?.toString() ?? '',
      nodeType: json['nodeType']?.toString() ?? 'department',
      name: json['name']?.toString() ?? '',
      code: json['code']?.toString() ?? '',
      description: json['description']?.toString(),
      level: json['level'] as int? ?? 0,
      members: (json['members'] as List<dynamic>?)
          ?.map((m) => OrgChartMember.fromJson(m as Map<String, dynamic>))
          .toList() ?? [],
      children: (json['children'] as List<dynamic>?)
          ?.map((c) => OrgChartNode.fromJson(c as Map<String, dynamic>))
          .toList() ?? [],
    );
  }

  OrgChartMember? get head => members.where((m) => m.isHead).isNotEmpty
      ? members.firstWhere((m) => m.isHead)
      : (members.isNotEmpty ? members.first : null);
}

class OrgChartMember {
  final String assignmentId;
  final String employeeId;
  final String employeeName;
  final String employeeCode;
  final String? employeePhoto;
  final String positionId;
  final String positionName;
  final int positionLevel;
  final String? positionColor;
  final bool isPrimary;
  final String? reportToAssignmentId;
  final bool isHead;

  OrgChartMember({
    required this.assignmentId,
    required this.employeeId,
    required this.employeeName,
    required this.employeeCode,
    this.employeePhoto,
    required this.positionId,
    required this.positionName,
    required this.positionLevel,
    this.positionColor,
    required this.isPrimary,
    this.reportToAssignmentId,
    required this.isHead,
  });

  factory OrgChartMember.fromJson(Map<String, dynamic> json) {
    return OrgChartMember(
      assignmentId: json['assignmentId']?.toString() ?? '',
      employeeId: json['employeeId']?.toString() ?? '',
      employeeName: json['employeeName']?.toString() ?? '',
      employeeCode: json['employeeCode']?.toString() ?? '',
      employeePhoto: json['employeePhoto']?.toString(),
      positionId: json['positionId']?.toString() ?? '',
      positionName: json['positionName']?.toString() ?? '',
      positionLevel: json['positionLevel'] as int? ?? 0,
      positionColor: json['positionColor']?.toString(),
      isPrimary: json['isPrimary'] as bool? ?? true,
      reportToAssignmentId: json['reportToAssignmentId']?.toString(),
      isHead: json['isHead'] as bool? ?? false,
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// THỐNG KÊ
// ═══════════════════════════════════════════════════════════════

class OrgChartStats {
  final int totalDepartments;
  final int totalPositions;
  final int totalAssignments;
  final int totalEmployees;
  final int unassignedEmployees;
  final int totalApprovalFlows;

  OrgChartStats({
    required this.totalDepartments,
    required this.totalPositions,
    required this.totalAssignments,
    required this.totalEmployees,
    required this.unassignedEmployees,
    required this.totalApprovalFlows,
  });

  factory OrgChartStats.fromJson(Map<String, dynamic> json) {
    return OrgChartStats(
      totalDepartments: json['totalDepartments'] as int? ?? 0,
      totalPositions: json['totalPositions'] as int? ?? 0,
      totalAssignments: json['totalAssignments'] as int? ?? 0,
      totalEmployees: json['totalEmployees'] as int? ?? 0,
      unassignedEmployees: json['unassignedEmployees'] as int? ?? 0,
      totalApprovalFlows: json['totalApprovalFlows'] as int? ?? 0,
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// LUỒNG DUYỆT (ApprovalFlow)
// ═══════════════════════════════════════════════════════════════

class ApprovalFlow {
  final String id;
  final String code;
  final String name;
  final String? description;
  final int requestType;
  final String requestTypeName;
  final String? departmentId;
  final String? departmentName;
  final int priority;
  final bool isActive;
  final List<ApprovalStep> steps;

  ApprovalFlow({
    required this.id,
    required this.code,
    required this.name,
    this.description,
    required this.requestType,
    required this.requestTypeName,
    this.departmentId,
    this.departmentName,
    required this.priority,
    required this.isActive,
    required this.steps,
  });

  factory ApprovalFlow.fromJson(Map<String, dynamic> json) {
    return ApprovalFlow(
      id: json['id']?.toString() ?? '',
      code: json['code']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      description: json['description']?.toString(),
      requestType: json['requestType'] as int? ?? 0,
      requestTypeName: json['requestTypeName']?.toString() ?? '',
      departmentId: json['departmentId']?.toString(),
      departmentName: json['departmentName']?.toString(),
      priority: json['priority'] as int? ?? 0,
      isActive: json['isActive'] as bool? ?? true,
      steps: (json['steps'] as List<dynamic>?)
          ?.map((s) => ApprovalStep.fromJson(s as Map<String, dynamic>))
          .toList() ?? [],
    );
  }

  Map<String, dynamic> toJson() => {
    'code': code,
    'name': name,
    'description': description,
    'requestType': requestType,
    'departmentId': departmentId,
    'priority': priority,
    'isActive': isActive,
    'steps': steps.map((s) => s.toJson()).toList(),
  };

  static String requestTypeName2(int type) {
    switch (type) {
      case 1: return 'Nghỉ phép';
      case 2: return 'Tăng ca';
      case 3: return 'Tạm ứng';
      case 4: return 'Sửa chấm công';
      case 5: return 'Đổi ca';
      case 6: return 'Mua sắm tài sản';
      case 7: return 'Thu chi';
      case 8: return 'Công việc';
      case 9: return 'Tài liệu HR';
      case 99: return 'Khác';
      default: return 'Loại $type';
    }
  }

  static List<Map<String, dynamic>> allRequestTypes() => [
    {'value': 1, 'label': 'Nghỉ phép'},
    {'value': 2, 'label': 'Tăng ca'},
    {'value': 3, 'label': 'Tạm ứng'},
    {'value': 4, 'label': 'Sửa chấm công'},
    {'value': 5, 'label': 'Đổi ca'},
    {'value': 6, 'label': 'Mua sắm tài sản'},
    {'value': 7, 'label': 'Thu chi'},
    {'value': 8, 'label': 'Công việc'},
    {'value': 9, 'label': 'Tài liệu HR'},
    {'value': 99, 'label': 'Khác'},
  ];
}

class ApprovalStep {
  final String id;
  final int stepOrder;
  final String name;
  final int approverType;
  final String approverTypeName;
  final String? approverPositionId;
  final String? approverPositionName;
  final String? approverEmployeeId;
  final String? approverEmployeeName;
  final bool isRequired;
  final int? maxWaitHours;
  final int timeoutAction;
  final String timeoutActionName;
  final bool isActive;

  ApprovalStep({
    required this.id,
    required this.stepOrder,
    required this.name,
    required this.approverType,
    required this.approverTypeName,
    this.approverPositionId,
    this.approverPositionName,
    this.approverEmployeeId,
    this.approverEmployeeName,
    required this.isRequired,
    this.maxWaitHours,
    required this.timeoutAction,
    required this.timeoutActionName,
    required this.isActive,
  });

  factory ApprovalStep.fromJson(Map<String, dynamic> json) {
    return ApprovalStep(
      id: json['id']?.toString() ?? '',
      stepOrder: json['stepOrder'] as int? ?? 0,
      name: json['name']?.toString() ?? '',
      approverType: json['approverType'] as int? ?? 1,
      approverTypeName: json['approverTypeName']?.toString() ?? '',
      approverPositionId: json['approverPositionId']?.toString(),
      approverPositionName: json['approverPositionName']?.toString(),
      approverEmployeeId: json['approverEmployeeId']?.toString(),
      approverEmployeeName: json['approverEmployeeName']?.toString(),
      isRequired: json['isRequired'] as bool? ?? true,
      maxWaitHours: json['maxWaitHours'] as int?,
      timeoutAction: json['timeoutAction'] as int? ?? 1,
      timeoutActionName: json['timeoutActionName']?.toString() ?? '',
      isActive: json['isActive'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toJson() => {
    'name': name,
    'approverType': approverType,
    'approverPositionId': approverPositionId,
    'approverEmployeeId': approverEmployeeId,
    'isRequired': isRequired,
    'maxWaitHours': maxWaitHours,
    'timeoutAction': timeoutAction,
  };

  static String approverTypeName2(int type) {
    switch (type) {
      case 1: return 'Quản lý trực tiếp';
      case 2: return 'Theo chức vụ';
      case 3: return 'Nhân viên cụ thể';
      case 4: return 'Trưởng phòng';
      case 5: return 'Cấp trên bất kỳ';
      default: return 'Loại $type';
    }
  }

  static String timeoutActionName2(int action) {
    switch (action) {
      case 1: return 'Chuyển cấp cao hơn';
      case 2: return 'Tự động duyệt';
      case 3: return 'Tự động từ chối';
      case 4: return 'Không làm gì';
      default: return 'Hành động $action';
    }
  }
}

// ═══════════════════════════════════════════════════════════════
// NHÂN VIÊN CHƯA GÁN CHỨC VỤ
// ═══════════════════════════════════════════════════════════════

class UnassignedEmployee {
  final String id;
  final String employeeCode;
  final String fullName;
  final String? photoUrl;
  final String? departmentName;
  final String? position;
  final String companyEmail;

  UnassignedEmployee({
    required this.id,
    required this.employeeCode,
    required this.fullName,
    this.photoUrl,
    this.departmentName,
    this.position,
    required this.companyEmail,
  });

  factory UnassignedEmployee.fromJson(Map<String, dynamic> json) {
    return UnassignedEmployee(
      id: json['id']?.toString() ?? '',
      employeeCode: json['employeeCode']?.toString() ?? '',
      fullName: json['fullName']?.toString() ?? '',
      photoUrl: json['photoUrl']?.toString(),
      departmentName: json['departmentName']?.toString(),
      position: json['position']?.toString(),
      companyEmail: json['companyEmail']?.toString() ?? '',
    );
  }
}
