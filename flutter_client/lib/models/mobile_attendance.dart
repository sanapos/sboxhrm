// Models cho chấm công Mobile (Face ID + GPS)

import 'dart:convert';

double? _jsonOptionalDouble(dynamic value) {
  if (value == null) return null;
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value.trim());
  return null;
}

DateTime? _jsonDateTime(dynamic value) {
  if (value == null) return null;
  if (value is DateTime) return value;
  return DateTime.tryParse(value.toString());
}

String? _optionalUrl(dynamic value) {
  final s = value?.toString().trim();
  if (s == null || s.isEmpty) return null;
  return s;
}

int? _jsonInt(dynamic value) {
  if (value == null) return null;
  if (value is int) return value;
  if (value is num) return value.round();
  return int.tryParse(value.toString());
}

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
      createdAt:
          json['createdAt'] != null ? DateTime.parse(json['createdAt']) : null,
      updatedAt:
          json['updatedAt'] != null ? DateTime.parse(json['updatedAt']) : null,
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
      registeredAt: json['registeredAt'] != null
          ? DateTime.parse(json['registeredAt'])
          : null,
      lastVerifiedAt: json['lastVerifiedAt'] != null
          ? DateTime.parse(json['lastVerifiedAt'])
          : null,
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

class SelectedWorkLocation {
  final String id;
  final String name;
  final String? address;

  const SelectedWorkLocation({
    required this.id,
    required this.name,
    this.address,
  });

  factory SelectedWorkLocation.fromJson(Map<String, dynamic> json) {
    return SelectedWorkLocation(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      address: json['address']?.toString(),
    );
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
  /// Chụp ảnh hiện trường sau chấm (cần bật ở cài đặt cửa hàng + thiết bị).
  final bool requirePhotoProof;
  final String? wifiBssid;
  final DateTime? authorizedAt;
  final DateTime? lastUsedAt;
  final List<String> faceImages;
  final bool faceVerified;
  final DateTime? faceRegisteredAt;
  final List<String> selectedWorkLocationIds;
  final List<SelectedWorkLocation> selectedWorkLocations;

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
    this.requirePhotoProof = false,
    this.wifiBssid,
    this.authorizedAt,
    this.lastUsedAt,
    this.faceImages = const [],
    this.faceVerified = false,
    this.faceRegisteredAt,
    this.selectedWorkLocationIds = const [],
    this.selectedWorkLocations = const [],
  });

  static bool _parseBool(dynamic value, {bool defaultValue = false}) {
    if (value == null) return defaultValue;
    if (value is bool) return value;
    if (value is num) return value != 0;
    final s = value.toString().trim().toLowerCase();
    if (s == 'true' || s == '1') return true;
    if (s == 'false' || s == '0') return false;
    return defaultValue;
  }

  static List<String> _parseSelectedLocationIds(Map<String, dynamic> json) {
    final raw = json['selectedWorkLocationIds'];
    if (raw is List) {
      return raw.map((e) => e.toString()).where((e) => e.isNotEmpty).toList();
    }
    if (raw is String && raw.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          return decoded.map((e) => e.toString()).where((e) => e.isNotEmpty).toList();
        }
      } catch (_) {}
    }
    final dto = json['selectedWorkLocations'];
    if (dto is Map<String, dynamic>) {
      final ids = dto['ids'];
      if (ids is List) {
        return ids.map((e) => e.toString()).where((e) => e.isNotEmpty).toList();
      }
    }
    return const [];
  }

  static List<SelectedWorkLocation> _parseSelectedWorkLocations(
      Map<String, dynamic> json) {
    final dto = json['selectedWorkLocations'];
    if (dto is! Map<String, dynamic>) return const [];
    final locs = dto['locations'];
    if (locs is! List) return const [];
    return locs
        .whereType<Map<String, dynamic>>()
        .map(SelectedWorkLocation.fromJson)
        .where((l) => l.id.isNotEmpty)
        .toList();
  }

  factory AuthorizedDevice.fromJson(Map<String, dynamic> json) {
    return AuthorizedDevice(
      id: json['id']?.toString() ?? '',
      deviceId: json['deviceId']?.toString() ?? '',
      deviceName: json['deviceName']?.toString() ?? '',
      deviceModel: json['deviceModel']?.toString() ?? '',
      osVersion: json['osVersion']?.toString(),
      employeeId: json['employeeId']?.toString(),
      employeeName: json['employeeName']?.toString(),
      isAuthorized: _parseBool(json['isAuthorized'] ?? json['IsAuthorized']),
      canUseFaceId: _parseBool(json['canUseFaceId'] ?? json['CanUseFaceId'], defaultValue: true),
      canUseGps: _parseBool(json['canUseGps'] ?? json['CanUseGps'], defaultValue: true),
      allowOutsideCheckIn:
          _parseBool(json['allowOutsideCheckIn'] ?? json['AllowOutsideCheckIn']),
      requirePhotoProof:
          _parseBool(json['requirePhotoProof'] ?? json['RequirePhotoProof']),
      wifiBssid: json['wifiBssid'],
      authorizedAt: json['authorizedAt'] != null
          ? DateTime.parse(json['authorizedAt'])
          : null,
      lastUsedAt: json['lastUsedAt'] != null
          ? DateTime.parse(json['lastUsedAt'])
          : null,
      faceImages: List<String>.from(json['faceImages'] ?? []),
      faceVerified: json['faceVerified'] ?? false,
      faceRegisteredAt: json['faceRegisteredAt'] != null
          ? DateTime.parse(json['faceRegisteredAt'])
          : null,
      selectedWorkLocationIds: _parseSelectedLocationIds(json),
      selectedWorkLocations: _parseSelectedWorkLocations(json),
    );
  }

  String get selectedWorkLocationsLabel {
    if (selectedWorkLocations.isNotEmpty) {
      return selectedWorkLocations.map((l) => l.name).join(', ');
    }
    if (selectedWorkLocationIds.isNotEmpty) {
      return '${selectedWorkLocationIds.length} vị trí';
    }
    return 'Chưa chọn';
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
      'requirePhotoProof': requirePhotoProof,
      'wifiBssid': wifiBssid,
    };
  }

  AuthorizedDevice copyWith({
    bool? requirePhotoProof,
    bool? allowOutsideCheckIn,
    bool? isAuthorized,
  }) {
    return AuthorizedDevice(
      id: id,
      deviceId: deviceId,
      deviceName: deviceName,
      deviceModel: deviceModel,
      osVersion: osVersion,
      employeeId: employeeId,
      employeeName: employeeName,
      isAuthorized: isAuthorized ?? this.isAuthorized,
      canUseFaceId: canUseFaceId,
      canUseGps: canUseGps,
      allowOutsideCheckIn: allowOutsideCheckIn ?? this.allowOutsideCheckIn,
      requirePhotoProof: requirePhotoProof ?? this.requirePhotoProof,
      wifiBssid: wifiBssid,
      authorizedAt: authorizedAt,
      lastUsedAt: lastUsedAt,
      faceImages: faceImages,
      faceVerified: faceVerified,
      faceRegisteredAt: faceRegisteredAt,
      selectedWorkLocationIds: selectedWorkLocationIds,
      selectedWorkLocations: selectedWorkLocations,
    );
  }
}

String formatSelectedWorkLocationsFromRequest(Map<String, dynamic> req) {
  final dto = req['selectedWorkLocations'];
  if (dto is Map<String, dynamic>) {
    final locs = dto['locations'];
    if (locs is List && locs.isNotEmpty) {
      return locs
          .whereType<Map<String, dynamic>>()
          .map((l) => l['name']?.toString() ?? '')
          .where((n) => n.isNotEmpty)
          .join(', ');
    }
    final ids = dto['ids'];
    if (ids is List && ids.isNotEmpty) {
      return '${ids.length} vị trí';
    }
  }
  return 'Chưa chọn';
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
  final String? sitePhotoUrl;
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
  final String? employeePhotoUrl;

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
    this.sitePhotoUrl,
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
    this.employeePhotoUrl,
  });

  factory MobileAttendanceRecord.fromJson(Map<String, dynamic> json) {
    return MobileAttendanceRecord(
      id: (json['id'] ?? json['Id'] ?? '').toString(),
      odooEmployeeId:
          (json['odooEmployeeId'] ?? json['OdooEmployeeId'] ?? '').toString(),
      employeeName:
          (json['employeeName'] ?? json['EmployeeName'] ?? '').toString(),
      punchTime: _jsonDateTime(json['punchTime'] ?? json['PunchTime']) ??
          DateTime.now(),
      punchType: _jsonInt(json['punchType'] ?? json['PunchType']) ?? 0,
      latitude: _jsonOptionalDouble(json['latitude'] ?? json['Latitude']),
      longitude: _jsonOptionalDouble(json['longitude'] ?? json['Longitude']),
      locationName:
          (json['locationName'] ?? json['LocationName'])?.toString(),
      distanceFromLocation: _jsonOptionalDouble(
          json['distanceFromLocation'] ?? json['DistanceFromLocation']),
      faceImageUrl: _optionalUrl(json['faceImageUrl'] ?? json['FaceImageUrl']),
      sitePhotoUrl: _optionalUrl(json['sitePhotoUrl'] ?? json['SitePhotoUrl']),
      faceMatchScore: _jsonOptionalDouble(
          json['faceMatchScore'] ?? json['FaceMatchScore']),
      verifyMethod: (json['verifyMethod'] ?? json['VerifyMethod'] ?? 'face_gps')
          .toString(),
      status: (json['status'] ?? json['Status'] ?? 'pending').toString(),
      approvedBy: (json['approvedBy'] ?? json['ApprovedBy'])?.toString(),
      approvedAt:
          _jsonDateTime(json['approvedAt'] ?? json['ApprovedAt']),
      rejectReason: (json['rejectReason'] ?? json['RejectReason'])?.toString(),
      deviceId: (json['deviceId'] ?? json['DeviceId'])?.toString(),
      deviceName: (json['deviceName'] ?? json['DeviceName'])?.toString(),
      note: (json['note'] ?? json['Note'])?.toString(),
      wifiSsid: (json['wifiSsid'] ?? json['WifiSsid'])?.toString(),
      wifiIpAddress:
          (json['wifiIpAddress'] ?? json['WifiIpAddress'])?.toString(),
      employeePhotoUrl:
          (json['employeePhotoUrl'] ?? json['EmployeePhotoUrl'])?.toString(),
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
      'sitePhotoUrl': sitePhotoUrl,
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
      'employeePhotoUrl': employeePhotoUrl,
    };
  }

  bool get hasGpsLocation {
    final lat = latitude;
    final lng = longitude;
    if (lat == null || lng == null) return false;
    return lat.abs() > 1e-5 || lng.abs() > 1e-5;
  }

  bool get isInRange =>
      distanceFromLocation != null && distanceFromLocation! <= 100;
  bool get isFaceVerified => faceMatchScore != null && faceMatchScore! >= 80;

  bool get hasSitePhoto =>
      sitePhotoUrl != null && sitePhotoUrl!.trim().isNotEmpty;

  MobileAttendanceRecord copyWith({String? sitePhotoUrl}) {
    return MobileAttendanceRecord(
      id: id,
      odooEmployeeId: odooEmployeeId,
      employeeName: employeeName,
      punchTime: punchTime,
      punchType: punchType,
      latitude: latitude,
      longitude: longitude,
      locationName: locationName,
      distanceFromLocation: distanceFromLocation,
      faceImageUrl: faceImageUrl,
      sitePhotoUrl: sitePhotoUrl ?? this.sitePhotoUrl,
      faceMatchScore: faceMatchScore,
      verifyMethod: verifyMethod,
      status: status,
      approvedBy: approvedBy,
      approvedAt: approvedAt,
      rejectReason: rejectReason,
      deviceId: deviceId,
      deviceName: deviceName,
      note: note,
      wifiSsid: wifiSsid,
      wifiIpAddress: wifiIpAddress,
      employeePhotoUrl: employeePhotoUrl,
    );
  }
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
  final bool requirePhotoProof;
  final int minPunchIntervalMinutes;

  MobileAttendanceSettings({
    this.enableFaceId = true,
    this.enableGps = true,
    this.enableWifi = false,
    this.verificationMode = 'all',
    this.gpsRadiusMeters = 100,
    this.minFaceMatchScore = 80.0,
    this.autoApproveInRange = true,
    this.allowManualApproval = true,
    this.maxPhotosPerRegistration = 5,
    this.requireLivenessDetection = true,
    this.requirePhotoProof = false,
    this.minPunchIntervalMinutes = 5,
  });

  factory MobileAttendanceSettings.fromJson(Map<String, dynamic> json) {
    return MobileAttendanceSettings(
      enableFaceId: json['enableFaceId'] ?? true,
      enableGps: json['enableGps'] ?? true,
      enableWifi: json['enableWifi'] ?? false,
      verificationMode: json['verificationMode'] ?? 'all',
      gpsRadiusMeters: json['gpsRadiusMeters'] ?? 100,
      minFaceMatchScore: (json['minFaceMatchScore'] ?? 80.0).toDouble(),
      autoApproveInRange: json['autoApproveInRange'] ?? true,
      allowManualApproval: json['allowManualApproval'] ?? true,
      maxPhotosPerRegistration: json['maxPhotosPerRegistration'] ?? 5,
      // Server now returns both keys; prefer the new one but fall back.
      requireLivenessDetection: json['enableLivenessDetection'] ??
          json['requireLivenessDetection'] ??
          true,
      requirePhotoProof: AuthorizedDevice._parseBool(
          json['requirePhotoProof'] ?? json['RequirePhotoProof']),
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
      'requirePhotoProof': requirePhotoProof,
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
    bool? requirePhotoProof,
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
      maxPhotosPerRegistration:
          maxPhotosPerRegistration ?? this.maxPhotosPerRegistration,
      requireLivenessDetection:
          requireLivenessDetection ?? this.requireLivenessDetection,
      requirePhotoProof: requirePhotoProof ?? this.requirePhotoProof,
      minPunchIntervalMinutes:
          minPunchIntervalMinutes ?? this.minPunchIntervalMinutes,
    );
  }
}
