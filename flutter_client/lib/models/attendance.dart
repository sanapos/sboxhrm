class Attendance {
  final String id;
  final String? pin;
  final String? employeeId;
  final String? employeeName;
  final String? deviceId;
  final String? deviceName;
  final String? deviceUserName; // Tên trong máy (không dấu)
  final int privilege; // Quyền hạn: 0=User, 14=Admin
  final DateTime attendanceTime;
  final int attendanceState; // 0: CheckIn, 1: CheckOut, etc.
  final int verifyMode; // 0: Password, 1: Fingerprint, 2: Card, 15: Face
  final String? workCode;
  final String? note; // Ghi chú
  final DateTime? createdAt;

  Attendance({
    required this.id,
    this.pin,
    this.employeeId,
    this.employeeName,
    this.deviceId,
    this.deviceName,
    this.deviceUserName,
    this.privilege = 0,
    required this.attendanceTime,
    this.attendanceState = 0,
    this.verifyMode = 0,
    this.workCode,
    this.note,
    this.createdAt,
  });

  // Alias for backward compatibility
  String? get enrollNumber => pin;
  DateTime get punchTime => attendanceTime;
  int get punchType => attendanceState;
  int get verifyType => verifyMode;
  
  // Privilege text
  String get privilegeText {
    switch (privilege) {
      case 14:
        return 'Quản trị viên';
      case 0:
      default:
        return 'Người dùng';
    }
  }

  /// Parse attendance state from int or string enum name.
  /// Backend REST API sends string names ("CheckIn", "CheckOut", etc.)
  /// SignalR sends int values (0, 1, etc.)
  static int _parseAttendanceState(dynamic value) {
    if (value == null) return 0;
    if (value is int) return value;
    if (value is num) return value.toInt();
    final s = value.toString();
    final parsed = int.tryParse(s);
    if (parsed != null) return parsed;
    // Map string enum names to int values (matching C# enum ordinal)
    switch (s) {
      case 'CheckIn': return 0;
      case 'CheckOut': return 1;
      case 'MealIn': return 2;
      case 'MealOut': return 3;
      case 'BreakIn': return 4;
      case 'BreakOut': return 5;
      default: return 0;
    }
  }

  /// Parse verify mode from int or string enum name.
  static int _parseVerifyMode(dynamic value) {
    if (value == null) return 0;
    if (value is int) return value;
    if (value is num) return value.toInt();
    final s = value.toString();
    final parsed = int.tryParse(s);
    if (parsed != null) return parsed;
    switch (s) {
      case 'Password': return 0;
      case 'Finger': return 1;
      case 'Badge': return 2;
      case 'PIN': return 3;
      case 'PINAndFingerprint': return 4;
      case 'FingerAndPassword': return 5;
      case 'BadgeAndFinger': return 6;
      case 'BadgeAndPassword': return 7;
      case 'BadgeAndPasswordAndFinger': return 8;
      case 'PINAndPasswordAndFinger': return 9;
      case 'Face': return 15;
      case 'Manual': return 100;
      case 'Unknown': return -1;
      default: return 0;
    }
  }

  static int _toInt(dynamic value, int defaultValue) {
    if (value == null) return defaultValue;
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString()) ?? defaultValue;
  }

  factory Attendance.fromJson(Map<String, dynamic> json) {
    // Support both camelCase (API/SignalR with camelCase) and PascalCase (SignalR default)
    V? get<V>(String camelKey) {
      final v = json[camelKey];
      if (v != null) return v as V;
      // Try PascalCase: capitalize first letter
      final pascalKey = camelKey[0].toUpperCase() + camelKey.substring(1);
      return json[pascalKey] as V?;
    }

    // Parse attendance time from various possible fields
    DateTime? parsedTime;
    for (final field in ['attendanceTime', 'punchTime', 'checkTime', 'time', 'AttendanceTime', 'PunchTime', 'CheckTime', 'Time']) {
      if (json[field] != null) {
        parsedTime = DateTime.tryParse(json[field].toString());
        if (parsedTime != null) break;
      }
    }
    
    return Attendance(
      id: (get('id'))?.toString() ?? '',
      // PIN from device - support multiple field names
      pin: get('pin') ?? get('enrollNumber') ?? get('userId'),
      // Employee code from HR system - support both employeeCode and employeeId
      employeeId: get<Object>('employeeCode')?.toString() ?? get<Object>('employeeId')?.toString(),
      employeeName: get('userName') ?? get('employeeName') ?? get('name'),
      deviceId: get<Object>('deviceId')?.toString(),
      deviceName: get('deviceName'),
      deviceUserName: get('deviceUserName'),
      privilege: _toInt(get('privilege'), 0),
      attendanceTime: parsedTime ?? DateTime.now(),
      attendanceState: _parseAttendanceState(get('attendanceState') ?? get('punchType') ?? get('checkType')),
      verifyMode: _parseVerifyMode(get('verifyMode') ?? get('verifyType')),
      workCode: get('workCode'),
      note: get('note') ?? get('workCode'),
      createdAt: get<Object>('createdAt') != null
          ? DateTime.tryParse(get<Object>('createdAt').toString())
          : null,
    );
  }

  String get punchTypeText {
    switch (punchType) {
      case 0:
        return 'Vào';
      case 1:
        return 'Ra';
      case 2:
        return 'Nghỉ trưa vào';
      case 3:
        return 'Nghỉ trưa ra';
      case 4:
        return 'Nghỉ giải lao vào';
      case 5:
        return 'Nghỉ giải lao ra';
      default:
        return 'Không xác định';
    }
  }

  String get verifyTypeText {
    switch (verifyType) {
      case -1:
        return 'Không xác định';
      case 0:
        return 'Mật khẩu';
      case 1:
        return 'Vân tay';
      case 2:
        return 'Thẻ';
      case 9:
      case 15:
        return 'Khuôn mặt';
      case 100:
        return 'Thủ công';
      default:
        return 'Khác';
    }
  }
}
