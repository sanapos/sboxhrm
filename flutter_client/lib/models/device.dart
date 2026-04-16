/// Parse datetime string từ server (lưu UTC, không có timezone indicator) thành UTC DateTime
DateTime? _parseUtc(dynamic value) {
  if (value == null) return null;
  final raw = value.toString();
  // Nếu không có timezone → server lưu UTC → thêm Z
  final dateStr = (raw.contains('Z') || raw.contains('+')) ? raw : '${raw}Z';
  return DateTime.tryParse(dateStr);
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
  });

  // Check if device is online - always compute from lastOnline timestamp
  bool get isOnline {
    // Luôn tính từ lastOnline thay vì tin vào deviceStatus cached trong DB
    if (lastOnline == null) return false;
    return DateTime.now().toUtc().difference(lastOnline!.toUtc()).inSeconds < 90;
  }

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
      lastOnline: json['lastOnline'] != null
          ? _parseUtc(json['lastOnline'])
          : null,
      userCount: json['userCount'],
      attendanceCount: json['attendanceCount'],
      createdAt: json['createdAt'] != null
          ? _parseUtc(json['createdAt'])
          : null,
      updatedAt: json['updatedAt'] != null
          ? _parseUtc(json['updatedAt'])
          : null,
      deviceStatus: json['deviceStatus'],
      isClaimed: json['isClaimed'],
      ownerId: json['ownerId'],
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
  });

  factory DeviceInfo.fromJson(Map<String, dynamic> json) {
    return DeviceInfo(
      platform: json['platform'],
      firmwareVersion: json['firmwareVersion'],
      serialNumber: json['serialNumber'],
      macAddress: json['macAddress'],
      userCount: json['userCount'],
      fingerprintCount: json['fingerprintCount'],
      faceCount: json['faceCount'],
      attendanceCount: json['attendanceCount'],
      deviceName: json['deviceName'],
    );
  }
}
