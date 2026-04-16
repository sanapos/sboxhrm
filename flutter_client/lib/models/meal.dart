class MealSession {
  final String id;
  final String name;
  final String? startTime;
  final String? endTime;
  final String? description;
  final bool isActive;
  final String? storeId;
  final DateTime? createdAt;
  final List<MealSessionShift> mealSessionShifts;

  MealSession({
    required this.id,
    required this.name,
    this.startTime,
    this.endTime,
    this.description,
    this.isActive = true,
    this.storeId,
    this.createdAt,
    this.mealSessionShifts = const [],
  });

  factory MealSession.fromJson(Map<String, dynamic> json) {
    return MealSession(
      id: json['id']?.toString() ?? '',
      name: json['name'] ?? '',
      startTime: json['startTime']?.toString(),
      endTime: json['endTime']?.toString(),
      description: json['description'],
      isActive: json['isActive'] ?? true,
      storeId: json['storeId']?.toString(),
      createdAt: json['createdAt'] != null
          ? DateTime.tryParse(json['createdAt'].toString())
          : null,
      mealSessionShifts: (json['mealSessionShifts'] as List?)
              ?.map((e) => MealSessionShift.fromJson(e))
              .toList() ??
          [],
    );
  }
}

class MealSessionShift {
  final String id;
  final String mealSessionId;
  final String shiftTemplateId;
  final String? shiftTemplateName;

  MealSessionShift({
    required this.id,
    required this.mealSessionId,
    required this.shiftTemplateId,
    this.shiftTemplateName,
  });

  factory MealSessionShift.fromJson(Map<String, dynamic> json) {
    return MealSessionShift(
      id: json['id']?.toString() ?? '',
      mealSessionId: json['mealSessionId']?.toString() ?? '',
      shiftTemplateId: json['shiftTemplateId']?.toString() ?? '',
      shiftTemplateName: json['shiftTemplateName'],
    );
  }
}

class MealRecord {
  final String id;
  final String employeeUserId;
  final String employeeName;
  final String? pin;
  final String mealSessionId;
  final String? mealSessionName;
  final DateTime mealTime;
  final DateTime date;
  final String? shiftId;
  final String? deviceId;
  final String? deviceName;
  final String? storeId;
  final DateTime? createdAt;

  MealRecord({
    required this.id,
    required this.employeeUserId,
    required this.employeeName,
    this.pin,
    required this.mealSessionId,
    this.mealSessionName,
    required this.mealTime,
    required this.date,
    this.shiftId,
    this.deviceId,
    this.deviceName,
    this.storeId,
    this.createdAt,
  });

  factory MealRecord.fromJson(Map<String, dynamic> json) {
    return MealRecord(
      id: json['id']?.toString() ?? '',
      employeeUserId: json['employeeUserId']?.toString() ?? '',
      employeeName: json['employeeName'] ?? '',
      pin: json['pin'],
      mealSessionId: json['mealSessionId']?.toString() ?? '',
      mealSessionName: json['mealSessionName'],
      mealTime: DateTime.parse(json['mealTime'].toString()),
      date: DateTime.parse(json['date'].toString()),
      shiftId: json['shiftId']?.toString(),
      deviceId: json['deviceId']?.toString(),
      deviceName: json['deviceName'],
      storeId: json['storeId']?.toString(),
      createdAt: json['createdAt'] != null
          ? DateTime.tryParse(json['createdAt'].toString())
          : null,
    );
  }
}

class MealEstimate {
  final String mealSessionId;
  final String mealSessionName;
  final String? startTime;
  final String? endTime;
  final int estimatedCount;
  final int actualCount;
  final int remaining;

  MealEstimate({
    required this.mealSessionId,
    required this.mealSessionName,
    this.startTime,
    this.endTime,
    this.estimatedCount = 0,
    this.actualCount = 0,
    this.remaining = 0,
  });

  factory MealEstimate.fromJson(Map<String, dynamic> json) {
    return MealEstimate(
      mealSessionId: json['mealSessionId']?.toString() ?? '',
      mealSessionName: json['mealSessionName'] ?? '',
      startTime: json['startTime']?.toString(),
      endTime: json['endTime']?.toString(),
      estimatedCount: json['estimatedCount'] ?? 0,
      actualCount: json['actualCount'] ?? 0,
      remaining: json['remaining'] ?? 0,
    );
  }
}

class MealSummary {
  final DateTime date;
  final List<MealEstimate> sessions;
  final int totalEstimated;
  final int totalActual;

  MealSummary({
    required this.date,
    this.sessions = const [],
    this.totalEstimated = 0,
    this.totalActual = 0,
  });

  factory MealSummary.fromJson(Map<String, dynamic> json) {
    return MealSummary(
      date: DateTime.parse(json['date'].toString()),
      sessions: (json['sessions'] as List?)
              ?.map((e) => MealEstimate.fromJson(e))
              .toList() ??
          [],
      totalEstimated: json['totalEstimated'] ?? 0,
      totalActual: json['totalActual'] ?? 0,
    );
  }
}

class EmployeeMealSummary {
  final String employeeUserId;
  final String employeeName;
  final String? employeeCode;
  final int totalMeals;
  final List<MealDetail> details;

  EmployeeMealSummary({
    required this.employeeUserId,
    required this.employeeName,
    this.employeeCode,
    this.totalMeals = 0,
    this.details = const [],
  });

  factory EmployeeMealSummary.fromJson(Map<String, dynamic> json) {
    return EmployeeMealSummary(
      employeeUserId: json['employeeUserId']?.toString() ?? '',
      employeeName: json['employeeName'] ?? '',
      employeeCode: json['employeeCode'],
      totalMeals: json['totalMeals'] ?? 0,
      details: (json['details'] as List?)
              ?.map((e) => MealDetail.fromJson(e))
              .toList() ??
          [],
    );
  }
}

class MealDetail {
  final DateTime date;
  final String mealSessionName;
  final DateTime mealTime;

  MealDetail({
    required this.date,
    required this.mealSessionName,
    required this.mealTime,
  });

  factory MealDetail.fromJson(Map<String, dynamic> json) {
    return MealDetail(
      date: DateTime.parse(json['date'].toString()),
      mealSessionName: json['mealSessionName'] ?? '',
      mealTime: DateTime.parse(json['mealTime'].toString()),
    );
  }
}

class MealMenu {
  final String id;
  final DateTime date;
  final int dayOfWeek;
  final String mealSessionId;
  final String? mealSessionName;
  final String? note;
  final bool isActive;
  final String? storeId;
  final DateTime? createdAt;
  final List<MealMenuItem> items;

  MealMenu({
    required this.id,
    required this.date,
    this.dayOfWeek = 0,
    required this.mealSessionId,
    this.mealSessionName,
    this.note,
    this.isActive = true,
    this.storeId,
    this.createdAt,
    this.items = const [],
  });

  factory MealMenu.fromJson(Map<String, dynamic> json) {
    return MealMenu(
      id: json['id']?.toString() ?? '',
      date: DateTime.parse(json['date'].toString()),
      dayOfWeek: json['dayOfWeek'] ?? 0,
      mealSessionId: json['mealSessionId']?.toString() ?? '',
      mealSessionName: json['mealSessionName'],
      note: json['note'],
      isActive: json['isActive'] ?? true,
      storeId: json['storeId']?.toString(),
      createdAt: json['createdAt'] != null
          ? DateTime.tryParse(json['createdAt'].toString())
          : null,
      items: (json['items'] as List?)
              ?.map((e) => MealMenuItem.fromJson(e))
              .toList() ??
          [],
    );
  }
}

class MealMenuItem {
  final String id;
  final String dishName;
  final String? description;
  final String? category;
  final int sortOrder;

  MealMenuItem({
    required this.id,
    required this.dishName,
    this.description,
    this.category,
    this.sortOrder = 0,
  });

  factory MealMenuItem.fromJson(Map<String, dynamic> json) {
    return MealMenuItem(
      id: json['id']?.toString() ?? '',
      dishName: json['dishName'] ?? '',
      description: json['description'],
      category: json['category'],
      sortOrder: json['sortOrder'] ?? 0,
    );
  }
}

class MealRegistration {
  final String id;
  final String mealSessionId;
  final DateTime date;
  final bool isRegistered;
  final DateTime? registeredAt;
  final DateTime? cancelledAt;
  final String? note;

  MealRegistration({
    required this.id,
    required this.mealSessionId,
    required this.date,
    this.isRegistered = true,
    this.registeredAt,
    this.cancelledAt,
    this.note,
  });

  factory MealRegistration.fromJson(Map<String, dynamic> json) {
    return MealRegistration(
      id: json['id']?.toString() ?? '',
      mealSessionId: json['mealSessionId']?.toString() ?? '',
      date: DateTime.parse(json['date'].toString()),
      isRegistered: json['isRegistered'] ?? true,
      registeredAt: json['registeredAt'] != null
          ? DateTime.tryParse(json['registeredAt'].toString())
          : null,
      cancelledAt: json['cancelledAt'] != null
          ? DateTime.tryParse(json['cancelledAt'].toString())
          : null,
      note: json['note'],
    );
  }
}

class RegistrationSummary {
  final DateTime date;
  final int totalRegistered;
  final List<SessionRegistrationSummary> sessions;

  RegistrationSummary({
    required this.date,
    this.totalRegistered = 0,
    this.sessions = const [],
  });

  factory RegistrationSummary.fromJson(Map<String, dynamic> json) {
    return RegistrationSummary(
      date: DateTime.parse(json['date'].toString()),
      totalRegistered: json['totalRegistered'] ?? 0,
      sessions: (json['sessions'] as List?)
              ?.map((e) => SessionRegistrationSummary.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }
}

class SessionRegistrationSummary {
  final String mealSessionId;
  final String mealSessionName;
  final int registeredCount;
  final int cancelledCount;

  SessionRegistrationSummary({
    required this.mealSessionId,
    required this.mealSessionName,
    this.registeredCount = 0,
    this.cancelledCount = 0,
  });

  factory SessionRegistrationSummary.fromJson(Map<String, dynamic> json) {
    return SessionRegistrationSummary(
      mealSessionId: json['mealSessionId']?.toString() ?? '',
      mealSessionName: json['mealSessionName'] ?? '',
      registeredCount: json['registeredCount'] ?? 0,
      cancelledCount: json['cancelledCount'] ?? 0,
    );
  }
}
