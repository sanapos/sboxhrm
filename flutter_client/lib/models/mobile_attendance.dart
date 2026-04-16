// Models cho chấm công Mobile (Face ID + GPS)

class WorkLocation {
  final String id;
  final String name;
  final String address;
  final double latitude;
  final double longitude;
  final int radius; // Bán kính cho phép (mét)
  final bool isActive;
  final bool autoApproveInRange; // Tự động duyệt nếu trong phạm vi
  final String? wifiSsid;
  final String? wifiBssid;
  final String? allowedIpRange;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  WorkLocation({
    required this.id,
    required this.name,
    required this.address,
    required this.latitude,
    required this.longitude,
    this.radius = 100,
    this.isActive = true,
    this.autoApproveInRange = true,
    this.wifiSsid,
    this.wifiBssid,
    this.allowedIpRange,
    this.createdAt,
    this.updatedAt,
  });

  factory WorkLocation.fromJson(Map<String, dynamic> json) {
    return WorkLocation(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      address: json['address'] ?? '',
      latitude: (json['latitude'] ?? 0).toDouble(),
      longitude: (json['longitude'] ?? 0).toDouble(),
      radius: json['radius'] ?? 100,
      isActive: json['isActive'] ?? true,
      autoApproveInRange: json['autoApproveInRange'] ?? true,
      wifiSsid: json['wifiSsid'],
      wifiBssid: json['wifiBssid'],
      allowedIpRange: json['allowedIpRange'],
      createdAt: json['createdAt'] != null ? DateTime.parse(json['createdAt']) : null,
      updatedAt: json['updatedAt'] != null ? DateTime.parse(json['updatedAt']) : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'address': address,
      'latitude': latitude,
      'longitude': longitude,
      'radius': radius,
      'isActive': isActive,
      'autoApproveInRange': autoApproveInRange,
      'wifiSsid': wifiSsid,
      'wifiBssid': wifiBssid,
      'allowedIpRange': allowedIpRange,
    };
  }
}

class FaceRegistration {
  final String id;
  final String odooEmployeeId;
  final String employeeName;
  final String? employeeCode;
  final String? department;
  final List<String> faceImages; // Base64 encoded images
  final String? faceEmbedding; // Face encoding data
  final bool isVerified;
  final DateTime? registeredAt;
  final DateTime? lastVerifiedAt;

  FaceRegistration({
    required this.id,
    required this.odooEmployeeId,
    required this.employeeName,
    this.employeeCode,
    this.department,
    this.faceImages = const [],
    this.faceEmbedding,
    this.isVerified = false,
    this.registeredAt,
    this.lastVerifiedAt,
  });

  factory FaceRegistration.fromJson(Map<String, dynamic> json) {
    return FaceRegistration(
      id: json['id'] ?? '',
      odooEmployeeId: json['odooEmployeeId'] ?? '',
      employeeName: json['employeeName'] ?? '',
      employeeCode: json['employeeCode'],
      department: json['department'],
      faceImages: List<String>.from(json['faceImages'] ?? []),
      faceEmbedding: json['faceEmbedding'],
      isVerified: json['isVerified'] ?? false,
      registeredAt: json['registeredAt'] != null ? DateTime.parse(json['registeredAt']) : null,
      lastVerifiedAt: json['lastVerifiedAt'] != null ? DateTime.parse(json['lastVerifiedAt']) : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'odooEmployeeId': odooEmployeeId,
      'employeeName': employeeName,
      'employeeCode': employeeCode,
      'department': department,
      'faceImages': faceImages,
      'faceEmbedding': faceEmbedding,
      'isVerified': isVerified,
    };
  }
}

class AuthorizedDevice {
  final String id;
  final String deviceId; // Unique device identifier
  final String deviceName;
  final String deviceModel;
  final String? osVersion;
  final String? employeeId;
  final String? employeeName;
  final bool isAuthorized;
  final bool canUseFaceId;
  final bool canUseGps;
  final bool allowOutsideCheckIn;
  final String? wifiBssid;
  final DateTime? authorizedAt;
  final DateTime? lastUsedAt;
  final List<String> faceImages;
  final bool faceVerified;
  final DateTime? faceRegisteredAt;

  AuthorizedDevice({
    required this.id,
    required this.deviceId,
    required this.deviceName,
    required this.deviceModel,
    this.osVersion,
    this.employeeId,
    this.employeeName,
    this.isAuthorized = false,
    this.canUseFaceId = true,
    this.canUseGps = true,
    this.allowOutsideCheckIn = false,
    this.wifiBssid,
    this.authorizedAt,
    this.lastUsedAt,
    this.faceImages = const [],
    this.faceVerified = false,
    this.faceRegisteredAt,
  });

  factory AuthorizedDevice.fromJson(Map<String, dynamic> json) {
    return AuthorizedDevice(
      id: json['id'] ?? '',
      deviceId: json['deviceId'] ?? '',
      deviceName: json['deviceName'] ?? '',
      deviceModel: json['deviceModel'] ?? '',
      osVersion: json['osVersion'],
      employeeId: json['employeeId'],
      employeeName: json['employeeName'],
      isAuthorized: json['isAuthorized'] ?? false,
      canUseFaceId: json['canUseFaceId'] ?? true,
      canUseGps: json['canUseGps'] ?? true,
      allowOutsideCheckIn: json['allowOutsideCheckIn'] ?? false,
      wifiBssid: json['wifiBssid'],
      authorizedAt: json['authorizedAt'] != null ? DateTime.parse(json['authorizedAt']) : null,
      lastUsedAt: json['lastUsedAt'] != null ? DateTime.parse(json['lastUsedAt']) : null,
      faceImages: List<String>.from(json['faceImages'] ?? []),
      faceVerified: json['faceVerified'] ?? false,
      faceRegisteredAt: json['faceRegisteredAt'] != null ? DateTime.parse(json['faceRegisteredAt']) : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'deviceId': deviceId,
      'deviceName': deviceName,
      'deviceModel': deviceModel,
      'osVersion': osVersion,
      'employeeId': employeeId,
      'employeeName': employeeName,
      'isAuthorized': isAuthorized,
      'canUseFaceId': canUseFaceId,
      'canUseGps': canUseGps,
      'allowOutsideCheckIn': allowOutsideCheckIn,
      'wifiBssid': wifiBssid,
    };
  }
}

class MobileAttendanceRecord {
  final String id;
  final String odooEmployeeId;
  final String employeeName;
  final DateTime punchTime;
  final int punchType; // 0: Check-in, 1: Check-out
  final double? latitude;
  final double? longitude;
  final String? locationName;
  final double? distanceFromLocation; // Khoảng cách từ vị trí công ty (mét)
  final String? faceImageUrl;
  final double? faceMatchScore; // Điểm khớp khuôn mặt (0-100)
  final String verifyMethod; // 'face', 'gps', 'face_gps', 'manual'
  final String status; // 'pending', 'approved', 'rejected', 'auto_approved'
  final String? approvedBy;
  final DateTime? approvedAt;
  final String? rejectReason;
  final String? deviceId;
  final String? deviceName;
  final String? note;
  final String? wifiSsid;
  final String? wifiIpAddress;

  MobileAttendanceRecord({
    required this.id,
    required this.odooEmployeeId,
    required this.employeeName,
    required this.punchTime,
    required this.punchType,
    this.latitude,
    this.longitude,
    this.locationName,
    this.distanceFromLocation,
    this.faceImageUrl,
    this.faceMatchScore,
    this.verifyMethod = 'face_gps',
    this.status = 'pending',
    this.approvedBy,
    this.approvedAt,
    this.rejectReason,
    this.deviceId,
    this.deviceName,
    this.note,
    this.wifiSsid,
    this.wifiIpAddress,
  });

  factory MobileAttendanceRecord.fromJson(Map<String, dynamic> json) {
    return MobileAttendanceRecord(
      id: json['id'] ?? '',
      odooEmployeeId: json['odooEmployeeId'] ?? '',
      employeeName: json['employeeName'] ?? '',
      punchTime: DateTime.parse(json['punchTime']),
      punchType: json['punchType'] ?? 0,
      latitude: json['latitude']?.toDouble(),
      longitude: json['longitude']?.toDouble(),
      locationName: json['locationName'],
      distanceFromLocation: json['distanceFromLocation']?.toDouble(),
      faceImageUrl: json['faceImageUrl'],
      faceMatchScore: json['faceMatchScore']?.toDouble(),
      verifyMethod: json['verifyMethod'] ?? 'face_gps',
      status: json['status'] ?? 'pending',
      approvedBy: json['approvedBy'],
      approvedAt: json['approvedAt'] != null ? DateTime.parse(json['approvedAt']) : null,
      rejectReason: json['rejectReason'],
      deviceId: json['deviceId'],
      deviceName: json['deviceName'],
      note: json['note'],
      wifiSsid: json['wifiSsid'],
      wifiIpAddress: json['wifiIpAddress'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'odooEmployeeId': odooEmployeeId,
      'employeeName': employeeName,
      'punchTime': punchTime.toIso8601String(),
      'punchType': punchType,
      'latitude': latitude,
      'longitude': longitude,
      'locationName': locationName,
      'distanceFromLocation': distanceFromLocation,
      'faceImageUrl': faceImageUrl,
      'faceMatchScore': faceMatchScore,
      'verifyMethod': verifyMethod,
      'status': status,
      'approvedBy': approvedBy,
      'approvedAt': approvedAt?.toIso8601String(),
      'rejectReason': rejectReason,
      'deviceId': deviceId,
      'deviceName': deviceName,
      'note': note,
      'wifiSsid': wifiSsid,
      'wifiIpAddress': wifiIpAddress,
    };
  }

  bool get isInRange => distanceFromLocation != null && distanceFromLocation! <= 100;
  bool get isFaceVerified => faceMatchScore != null && faceMatchScore! >= 80;
}

class MobileAttendanceSettings {
  final bool enableFaceId;
  final bool enableGps;
  final bool enableWifi;
  final String verificationMode; // "any" or "all"
  final int gpsRadiusMeters;
  final double minFaceMatchScore;
  final bool autoApproveInRange;
  final bool allowManualApproval;
  final int maxPhotosPerRegistration;
  final bool requireLivenessDetection;
  final int minPunchIntervalMinutes;

  MobileAttendanceSettings({
    this.enableFaceId = true,
    this.enableGps = true,
    this.enableWifi = false,
    this.verificationMode = 'all',
    this.gpsRadiusMeters = 100,
    this.minFaceMatchScore = 55.0,
    this.autoApproveInRange = true,
    this.allowManualApproval = true,
    this.maxPhotosPerRegistration = 5,
    this.requireLivenessDetection = true,
    this.minPunchIntervalMinutes = 5,
  });

  factory MobileAttendanceSettings.fromJson(Map<String, dynamic> json) {
    return MobileAttendanceSettings(
      enableFaceId: json['enableFaceId'] ?? true,
      enableGps: json['enableGps'] ?? true,
      enableWifi: json['enableWifi'] ?? false,
      verificationMode: json['verificationMode'] ?? 'all',
      gpsRadiusMeters: json['gpsRadiusMeters'] ?? 100,
      minFaceMatchScore: (json['minFaceMatchScore'] ?? 55.0).toDouble(),
      autoApproveInRange: json['autoApproveInRange'] ?? true,
      allowManualApproval: json['allowManualApproval'] ?? true,
      maxPhotosPerRegistration: json['maxPhotosPerRegistration'] ?? 5,
      requireLivenessDetection: json['requireLivenessDetection'] ?? true,
      minPunchIntervalMinutes: json['minPunchIntervalMinutes'] ?? 5,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'enableFaceId': enableFaceId,
      'enableGps': enableGps,
      'enableWifi': enableWifi,
      'verificationMode': verificationMode,
      'gpsRadiusMeters': gpsRadiusMeters,
      'minFaceMatchScore': minFaceMatchScore,
      'autoApproveInRange': autoApproveInRange,
      'allowManualApproval': allowManualApproval,
      'maxPhotosPerRegistration': maxPhotosPerRegistration,
      'requireLivenessDetection': requireLivenessDetection,
      'minPunchIntervalMinutes': minPunchIntervalMinutes,
    };
  }

  MobileAttendanceSettings copyWith({
    bool? enableFaceId,
    bool? enableGps,
    bool? enableWifi,
    String? verificationMode,
    int? gpsRadiusMeters,
    double? minFaceMatchScore,
    bool? autoApproveInRange,
    bool? allowManualApproval,
    int? maxPhotosPerRegistration,
    bool? requireLivenessDetection,
    int? minPunchIntervalMinutes,
  }) {
    return MobileAttendanceSettings(
      enableFaceId: enableFaceId ?? this.enableFaceId,
      enableGps: enableGps ?? this.enableGps,
      enableWifi: enableWifi ?? this.enableWifi,
      verificationMode: verificationMode ?? this.verificationMode,
      gpsRadiusMeters: gpsRadiusMeters ?? this.gpsRadiusMeters,
      minFaceMatchScore: minFaceMatchScore ?? this.minFaceMatchScore,
      autoApproveInRange: autoApproveInRange ?? this.autoApproveInRange,
      allowManualApproval: allowManualApproval ?? this.allowManualApproval,
      maxPhotosPerRegistration: maxPhotosPerRegistration ?? this.maxPhotosPerRegistration,
      requireLivenessDetection: requireLivenessDetection ?? this.requireLivenessDetection,
      minPunchIntervalMinutes: minPunchIntervalMinutes ?? this.minPunchIntervalMinutes,
    );
  }
}
