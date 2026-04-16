/// System Admin Models for SuperAdmin dashboard
library;

class SystemDashboard {
  final int totalStores;
  final int activeStores;
  final int inactiveStores;
  final int totalUsers;
  final int totalDevices;
  final int onlineDevices;
  final int offlineDevices;
  final int totalAttendanceToday;
  final List<StoreStat> topStoresByUsers;
  final List<RecentActivity> recentActivities;

  SystemDashboard({
    required this.totalStores,
    required this.activeStores,
    required this.inactiveStores,
    required this.totalUsers,
    required this.totalDevices,
    required this.onlineDevices,
    required this.offlineDevices,
    required this.totalAttendanceToday,
    required this.topStoresByUsers,
    required this.recentActivities,
  });

  factory SystemDashboard.fromJson(Map<String, dynamic> json) {
    return SystemDashboard(
      totalStores: json['totalStores'] ?? 0,
      activeStores: json['activeStores'] ?? 0,
      inactiveStores: json['inactiveStores'] ?? 0,
      totalUsers: json['totalUsers'] ?? 0,
      totalDevices: json['totalDevices'] ?? 0,
      onlineDevices: json['onlineDevices'] ?? 0,
      offlineDevices: json['offlineDevices'] ?? 0,
      totalAttendanceToday: json['totalAttendanceToday'] ?? 0,
      topStoresByUsers: (json['topStoresByUsers'] as List<dynamic>?)
              ?.map((e) => StoreStat.fromJson(e))
              .toList() ??
          [],
      recentActivities: (json['recentActivities'] as List<dynamic>?)
              ?.map((e) => RecentActivity.fromJson(e))
              .toList() ??
          [],
    );
  }
}

class StoreStat {
  final String id;
  final String name;
  final String code;
  final int userCount;
  final int deviceCount;
  final bool isActive;

  StoreStat({
    required this.id,
    required this.name,
    required this.code,
    required this.userCount,
    required this.deviceCount,
    required this.isActive,
  });

  factory StoreStat.fromJson(Map<String, dynamic> json) {
    return StoreStat(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      code: json['code'] ?? '',
      userCount: json['userCount'] ?? 0,
      deviceCount: json['deviceCount'] ?? 0,
      isActive: json['isActive'] ?? true,
    );
  }
}

class RecentActivity {
  final String id;
  final String activityType;
  final String description;
  final String? storeName;
  final String? userName;
  final DateTime createdAt;

  RecentActivity({
    required this.id,
    required this.activityType,
    required this.description,
    this.storeName,
    this.userName,
    required this.createdAt,
  });

  factory RecentActivity.fromJson(Map<String, dynamic> json) {
    return RecentActivity(
      id: json['id'] ?? '',
      activityType: json['activityType'] ?? '',
      description: json['description'] ?? '',
      storeName: json['storeName'],
      userName: json['userName'],
      createdAt: json['createdAt'] != null
          ? DateTime.parse(json['createdAt'])
          : DateTime.now(),
    );
  }
}

class StoreDetail {
  final String id;
  final String name;
  final String code;
  final String? description;
  final String? address;
  final String? phone;
  final bool isActive;
  final String? ownerId;
  final String? ownerName;
  final String? ownerEmail;
  final int userCount;
  final int deviceCount;
  final int employeeCount;
  final DateTime createdAt;
  final DateTime? updatedAt;

  StoreDetail({
    required this.id,
    required this.name,
    required this.code,
    this.description,
    this.address,
    this.phone,
    required this.isActive,
    this.ownerId,
    this.ownerName,
    this.ownerEmail,
    required this.userCount,
    required this.deviceCount,
    required this.employeeCount,
    required this.createdAt,
    this.updatedAt,
  });

  factory StoreDetail.fromJson(Map<String, dynamic> json) {
    return StoreDetail(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      code: json['code'] ?? '',
      description: json['description'],
      address: json['address'],
      phone: json['phone'],
      isActive: json['isActive'] ?? true,
      ownerId: json['ownerId'],
      ownerName: json['ownerName'],
      ownerEmail: json['ownerEmail'],
      userCount: json['userCount'] ?? 0,
      deviceCount: json['deviceCount'] ?? 0,
      employeeCount: json['employeeCount'] ?? 0,
      createdAt: json['createdAt'] != null
          ? DateTime.parse(json['createdAt'])
          : DateTime.now(),
      updatedAt:
          json['updatedAt'] != null ? DateTime.parse(json['updatedAt']) : null,
    );
  }
}

class SystemUser {
  final String id;
  final String email;
  final String fullName;
  final String role;
  final String? storeId;
  final String? storeName;
  final String? storeCode;
  final bool isActive;
  final DateTime createdAt;
  final DateTime? lastLoginAt;

  SystemUser({
    required this.id,
    required this.email,
    required this.fullName,
    required this.role,
    this.storeId,
    this.storeName,
    this.storeCode,
    required this.isActive,
    required this.createdAt,
    this.lastLoginAt,
  });

  factory SystemUser.fromJson(Map<String, dynamic> json) {
    return SystemUser(
      id: json['id'] ?? '',
      email: json['email'] ?? '',
      fullName: json['fullName'] ?? '',
      role: json['role'] ?? '',
      storeId: json['storeId'],
      storeName: json['storeName'],
      storeCode: json['storeCode'],
      isActive: json['isActive'] ?? true,
      createdAt: json['createdAt'] != null
          ? DateTime.parse(json['createdAt'])
          : DateTime.now(),
      lastLoginAt: json['lastLoginAt'] != null
          ? DateTime.parse(json['lastLoginAt'])
          : null,
    );
  }
}

class SystemDevice {
  final String id;
  final String serialNumber;
  final String name;
  final String? ipAddress;
  final bool isOnline;
  final String? storeId;
  final String? storeName;
  final String? storeCode;
  final DateTime? lastSyncAt;
  final DateTime createdAt;

  SystemDevice({
    required this.id,
    required this.serialNumber,
    required this.name,
    this.ipAddress,
    required this.isOnline,
    this.storeId,
    this.storeName,
    this.storeCode,
    this.lastSyncAt,
    required this.createdAt,
  });

  factory SystemDevice.fromJson(Map<String, dynamic> json) {
    return SystemDevice(
      id: json['id'] ?? '',
      serialNumber: json['serialNumber'] ?? '',
      name: json['name'] ?? '',
      ipAddress: json['ipAddress'],
      isOnline: json['isOnline'] ?? false,
      storeId: json['storeId'],
      storeName: json['storeName'],
      storeCode: json['storeCode'],
      lastSyncAt: json['lastSyncAt'] != null
          ? DateTime.parse(json['lastSyncAt'])
          : null,
      createdAt: json['createdAt'] != null
          ? DateTime.parse(json['createdAt'])
          : DateTime.now(),
    );
  }
}
