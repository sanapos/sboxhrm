class DeviceUser {
  final String id;
  final String pin;
  final String name;
  final String? cardNumber;
  final String? password;
  final int privilege;
  final bool isActive;
  final String deviceId;
  final String? deviceName;
  final String? employeeId;
  final String? employeeName;
  final int fingerprintCount;
  final int copyableFingerprintCount;
  final int faceCount;

  DeviceUser({
    required this.id,
    required this.pin,
    required this.name,
    this.cardNumber,
    this.password,
    this.privilege = 0,
    this.isActive = true,
    required this.deviceId,
    this.deviceName,
    this.employeeId,
    this.employeeName,
    this.fingerprintCount = 0,
    this.copyableFingerprintCount = 0,
    this.faceCount = 0,
  });

  factory DeviceUser.fromJson(Map<String, dynamic> json) {
    return DeviceUser(
      id: json['id']?.toString() ?? '',
      pin: json['pin']?.toString() ?? '',
      name: json['name'] ?? '',
      cardNumber: json['cardNumber'],
      password: json['password'],
      privilege: json['privilege'] ?? 0,
      isActive: json['isActive'] ?? true,
      deviceId: json['deviceId']?.toString() ?? '',
      deviceName: json['deviceName'],
      employeeId: json['employee']?['id']?.toString(),
      employeeName: json['employee']?['fullName'],
      fingerprintCount: json['fingerprintCount'] ?? 0,
      copyableFingerprintCount:
          json['copyableFingerprintCount'] ?? json['CopyableFingerprintCount'] ?? 0,
      faceCount: json['faceCount'] ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'pin': pin,
      'name': name,
      'cardNumber': cardNumber,
      'password': password,
      'privilege': privilege,
      'isActive': isActive,
      'deviceId': deviceId,
    };
  }

  // Privilege levels - ZKTeco chỉ có 2 loại: 0=User, 14=Admin
  String get privilegeText {
    return privilege == 14 ? 'Quản trị viên' : 'Người dùng';
  }

  DeviceUser copyWith({
    String? id,
    String? pin,
    String? name,
    String? cardNumber,
    String? password,
    int? privilege,
    bool? isActive,
    String? deviceId,
    String? deviceName,
    String? employeeId,
    String? employeeName,
    int? fingerprintCount,
    int? copyableFingerprintCount,
    int? faceCount,
  }) {
    return DeviceUser(
      id: id ?? this.id,
      pin: pin ?? this.pin,
      name: name ?? this.name,
      cardNumber: cardNumber ?? this.cardNumber,
      password: password ?? this.password,
      privilege: privilege ?? this.privilege,
      isActive: isActive ?? this.isActive,
      deviceId: deviceId ?? this.deviceId,
      deviceName: deviceName ?? this.deviceName,
      employeeId: employeeId ?? this.employeeId,
      employeeName: employeeName ?? this.employeeName,
      fingerprintCount: fingerprintCount ?? this.fingerprintCount,
      copyableFingerprintCount:
          copyableFingerprintCount ?? this.copyableFingerprintCount,
      faceCount: faceCount ?? this.faceCount,
    );
  }

  /// File vân tay đã trên server, Copy được.
  bool get fingerprintReady => copyableFingerprintCount > 0;

  /// Máy đã enroll nhưng file chưa lên server.
  bool get fingerprintSyncing => fingerprintCount > copyableFingerprintCount;

  String get fingerprintStatusLabel {
    if (copyableFingerprintCount > 0) {
      if (fingerprintSyncing) {
        return '$copyableFingerprintCount vân tay (đang đồng bộ thêm)';
      }
      return '$copyableFingerprintCount vân tay';
    }
    if (fingerprintCount > 0) return 'Đang đồng bộ vân tay';
    return '0 vân tay';
  }
}
