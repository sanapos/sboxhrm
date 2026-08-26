/// Parse datetime string từ server (lưu UTC, không có timezone indicator) thành UTC DateTime
DateTime? parseDeviceUtc(dynamic value) {
  if (value == null) return null;
  var raw = value.toString().trim();
  if (raw.isEmpty) return null;
  // .NET often emits 7 fractional digits; Dart parses up to 6.
  raw = raw.replaceFirstMapped(
      RegExp(r'\.(\d{7,})'),
      (m) => '.${m.group(1)!.substring(0, 6)}');
  if (!raw.contains('Z') && !raw.contains('+')) raw = '${raw}Z';
  return DateTime.tryParse(raw)?.toUtc();
}

/// Cùng cửa sổ 2 phút với ADMS monitor / refresh-status.
bool isLastOnlineFresh(dynamic lastOnline) {
  final dt = lastOnline is DateTime
      ? lastOnline.toUtc()
      : parseDeviceUtc(lastOnline);
  if (dt == null) return false;
  return DateTime.now().toUtc().difference(dt).inSeconds < 120;
}

class Device {
  final String id;
  final String deviceName;
  final String serialNumber;
  final String? ipAddress;
  final int port;
  final bool isActive;
  final String? location;
  final String? description;
  final DateTime? lastOnline;
  final int? userCount;
  final int? attendanceCount;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final String? deviceStatus;
  final bool? isClaimed;
  final String? ownerId;

  /// ADMS capability (Phase 0/1)
  final String? engineProfile;
  final String? platform;
  final String? firmwareVersion;
  final bool? supportsUserQuery;
  final bool? supportsAttendanceQuery;
  final bool? supportsEnrollFingerprint;
  final bool? supportsFaceUpdate;
  final bool preferStampSync;
  final bool allowEnrollFingerprintUi;
  final bool allowEnrollFaceUi;
  final String? capabilityNotes;

  Device({
    required this.id,
    required this.deviceName,
    required this.serialNumber,
    this.ipAddress,
    this.port = 4370,
    this.isActive = true,
    this.location,
    this.description,
    this.lastOnline,
    this.userCount,
    this.attendanceCount,
    this.createdAt,
    this.updatedAt,
    this.deviceStatus,
    this.isClaimed,
    this.ownerId,
    this.engineProfile,
    this.platform,
    this.firmwareVersion,
    this.supportsUserQuery,
    this.supportsAttendanceQuery,
    this.supportsEnrollFingerprint,
    this.supportsFaceUpdate,
    this.preferStampSync = false,
    this.allowEnrollFingerprintUi = true,
    this.allowEnrollFaceUi = false,
    this.capabilityNotes,
  });

  // Check if device is online — same 2-minute window as ADMS monitor / settings.
  bool get isOnline => isLastOnlineFresh(lastOnline);

  /// Device has never connected to the server (lastOnline is null)
  bool get hasNeverConnected => lastOnline == null;

  factory Device.fromJson(Map<String, dynamic> json) {
    return Device(
      id: json['id']?.toString() ?? '',
      deviceName: json['deviceName'] ?? '',
      serialNumber: json['serialNumber'] ?? '',
      ipAddress: json['ipAddress'],
      port: json['port'] ?? 4370,
      isActive: json['isActive'] ?? true,
      location: json['location'],
      description: json['description'],
      lastOnline:
          json['lastOnline'] != null ? parseDeviceUtc(json['lastOnline']) : null,
      userCount: json['userCount'],
      attendanceCount: json['attendanceCount'],
      createdAt:
          json['createdAt'] != null ? parseDeviceUtc(json['createdAt']) : null,
      updatedAt:
          json['updatedAt'] != null ? parseDeviceUtc(json['updatedAt']) : null,
      deviceStatus: json['deviceStatus'],
      isClaimed: json['isClaimed'],
      ownerId: json['ownerId'],
      engineProfile: json['engineProfile']?.toString(),
      platform: json['platform']?.toString(),
      firmwareVersion: json['firmwareVersion']?.toString(),
      supportsUserQuery: json['supportsUserQuery'] as bool?,
      supportsAttendanceQuery: json['supportsAttendanceQuery'] as bool?,
      supportsEnrollFingerprint: json['supportsEnrollFingerprint'] as bool?,
      supportsFaceUpdate: json['supportsFaceUpdate'] as bool?,
      preferStampSync: json['preferStampSync'] == true,
      allowEnrollFingerprintUi: json['allowEnrollFingerprintUi'] != false,
      allowEnrollFaceUi: json['allowEnrollFaceUi'] == true ||
          json['supportsFaceUpdate'] == true,
      capabilityNotes: json['capabilityNotes']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'deviceName': deviceName,
      'serialNumber': serialNumber,
      'ipAddress': ipAddress,
      'port': port,
      'isActive': isActive,
      'location': location,
      'description': description,
      'deviceStatus': deviceStatus,
      'isClaimed': isClaimed,
      'ownerId': ownerId,
      if (lastOnline != null) 'lastOnline': lastOnline!.toIso8601String(),
      if (createdAt != null) 'createdAt': createdAt!.toIso8601String(),
      if (updatedAt != null) 'updatedAt': updatedAt!.toIso8601String(),
      if (engineProfile != null) 'engineProfile': engineProfile,
      if (platform != null) 'platform': platform,
      if (firmwareVersion != null) 'firmwareVersion': firmwareVersion,
      'preferStampSync': preferStampSync,
      'allowEnrollFingerprintUi': allowEnrollFingerprintUi,
      'allowEnrollFaceUi': allowEnrollFaceUi,
      if (supportsFaceUpdate != null) 'supportsFaceUpdate': supportsFaceUpdate,
      if (capabilityNotes != null) 'capabilityNotes': capabilityNotes,
    };
  }
}

class DeviceInfo {
  final String? platform;
  final String? firmwareVersion;
  final String? serialNumber;
  final String? macAddress;
  final int? userCount;
  final int? fingerprintCount;
  final int? faceCount;
  final int? attendanceCount;
  final String? deviceName;
  final String? engineProfile;
  final bool? supportsEnrollFingerprint;
  final bool preferStampSync;
  final String? capabilityNotes;

  DeviceInfo({
    this.platform,
    this.firmwareVersion,
    this.serialNumber,
    this.macAddress,
    this.userCount,
    this.fingerprintCount,
    this.faceCount,
    this.attendanceCount,
    this.deviceName,
    this.engineProfile,
    this.supportsEnrollFingerprint,
    this.preferStampSync = false,
    this.capabilityNotes,
  });

  factory DeviceInfo.fromJson(Map<String, dynamic> json) {
    return DeviceInfo(
      platform: json['platform'],
      firmwareVersion: json['firmwareVersion'],
      serialNumber: json['serialNumber'],
      macAddress: json['macAddress'],
      userCount: json['userCount'] ?? json['enrolledUserCount'],
      fingerprintCount: json['fingerprintCount'],
      faceCount: json['faceCount'] ??
          (json['faceTemplateCount'] != null
              ? int.tryParse(json['faceTemplateCount'].toString())
              : null),
      attendanceCount: json['attendanceCount'],
      deviceName: json['deviceName'] ?? json['deviceModelName'],
      engineProfile: json['engineProfile']?.toString(),
      supportsEnrollFingerprint: json['supportsEnrollFingerprint'] as bool?,
      preferStampSync: json['preferStampSync'] == true,
      capabilityNotes: json['capabilityNotes']?.toString(),
    );
  }
}
