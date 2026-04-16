class DashboardSummary {
  final int totalEmployees;
  final int totalDevices;
  final int onlineDevices;
  final int todayAttendances;
  final int presentToday;
  final int absentToday;
  final int lateToday;
  final double attendanceRate;
  final int activeEmployees;
  final int inactiveEmployees;
  final int todayCheckIns;
  final int todayCheckOuts;
  final int todayAbsences;
  final int todayLateArrivals;
  final double averageAttendanceRate;
  final int offlineDevices;

  DashboardSummary({
    this.totalEmployees = 0,
    this.totalDevices = 0,
    this.onlineDevices = 0,
    this.todayAttendances = 0,
    this.presentToday = 0,
    this.absentToday = 0,
    this.lateToday = 0,
    this.attendanceRate = 0.0,
    this.activeEmployees = 0,
    this.inactiveEmployees = 0,
    this.todayCheckIns = 0,
    this.todayCheckOuts = 0,
    this.todayAbsences = 0,
    this.todayLateArrivals = 0,
    this.averageAttendanceRate = 0.0,
    this.offlineDevices = 0,
  });

  static double _parseAttendanceRate(dynamic value) {
    if (value == null) return 0.0;
    if (value is num) return value.toDouble();
    if (value is Map) {
      return ((value['attendancePercentage'] ?? value['rate'] ?? 0) as num).toDouble();
    }
    return 0.0;
  }

  factory DashboardSummary.fromJson(Map<String, dynamic> json) {
    return DashboardSummary(
      totalEmployees: json['totalEmployees'] ?? 0,
      totalDevices: json['totalDevices'] ?? 0,
      onlineDevices: json['onlineDevices'] ?? 0,
      todayAttendances: json['todayAttendances'] ?? 0,
      presentToday: json['presentToday'] ?? 0,
      absentToday: json['absentToday'] ?? 0,
      lateToday: json['lateToday'] ?? 0,
      attendanceRate: _parseAttendanceRate(json['attendanceRate']),
      activeEmployees: json['activeEmployees'] ?? json['totalEmployees'] ?? 0,
      inactiveEmployees: json['inactiveEmployees'] ?? 0,
      todayCheckIns: json['todayCheckIns'] ?? json['presentToday'] ?? 0,
      todayCheckOuts: json['todayCheckOuts'] ?? 0,
      todayAbsences: json['todayAbsences'] ?? json['absentToday'] ?? 0,
      todayLateArrivals: json['todayLateArrivals'] ?? json['lateToday'] ?? 0,
      averageAttendanceRate: _parseAttendanceRate(json['averageAttendanceRate'] ?? json['attendanceRate']),
      offlineDevices: json['offlineDevices'] ?? 0,
    );
  }
}

class AttendanceTrend {
  final DateTime date;
  final int present;
  final int absent;
  final int late;
  final int total;
  final int totalCheckIns;
  final int lateArrivals;
  final int absences;

  AttendanceTrend({
    required this.date,
    this.present = 0,
    this.absent = 0,
    this.late = 0,
    this.total = 0,
    this.totalCheckIns = 0,
    this.lateArrivals = 0,
    this.absences = 0,
  });

  factory AttendanceTrend.fromJson(Map<String, dynamic> json) {
    return AttendanceTrend(
      date: DateTime.parse(json['date']),
      present: json['present'] ?? 0,
      absent: json['absent'] ?? 0,
      late: json['late'] ?? 0,
      total: json['total'] ?? 0,
      totalCheckIns: json['totalCheckIns'] ?? json['present'] ?? 0,
      lateArrivals: json['lateArrivals'] ?? json['late'] ?? 0,
      absences: json['absences'] ?? json['absent'] ?? 0,
    );
  }
}

class AttendanceRate {
  final int totalEmployeesWithShift;
  final int presentEmployees;
  final int lateEmployees;
  final int absentEmployees;
  final int onLeaveEmployees;
  final double attendancePercentage;

  AttendanceRate({
    this.totalEmployeesWithShift = 0,
    this.presentEmployees = 0,
    this.lateEmployees = 0,
    this.absentEmployees = 0,
    this.onLeaveEmployees = 0,
    this.attendancePercentage = 0.0,
  });
}

class ManagerDashboard {
  final DashboardSummary? summary;
  final List<dynamic> recentAttendances;
  final List<dynamic> alerts;
  final List<TodayEmployee> todayEmployees;

  AttendanceRate get attendanceRate {
    if (summary == null) return AttendanceRate();
    return AttendanceRate(
      totalEmployeesWithShift: summary!.activeEmployees,
      presentEmployees: summary!.presentToday,
      lateEmployees: summary!.lateToday,
      absentEmployees: summary!.absentToday,
      onLeaveEmployees: 0,
      attendancePercentage: summary!.attendanceRate,
    );
  }

  ManagerDashboard({
    this.summary,
    this.recentAttendances = const [],
    this.alerts = const [],
    this.todayEmployees = const [],
  });

  factory ManagerDashboard.fromJson(Map<String, dynamic> json) {
    return ManagerDashboard(
      summary: json['summary'] != null ? DashboardSummary.fromJson(json['summary']) : null,
      recentAttendances: json['recentAttendances'] ?? [],
      alerts: json['alerts'] ?? [],
      todayEmployees: (json['todayEmployees'] as List?)?.map((e) => TodayEmployee.fromJson(e)).toList() ?? [],
    );
  }
}

class EmployeePerformance {
  final String employeeId;
  final String employeeName;
  final String? employeeCode;
  final String? department;
  final String? position;
  final double attendanceRate;
  final int totalDays;
  final int presentDays;
  final int lateDays;
  final int absentDays;
  final String? status;
  final int? onTimeDays;
  final double? punctualityRate;
  final String? averageLateTime;

  String get fullName => employeeName;

  EmployeePerformance({
    required this.employeeId,
    required this.employeeName,
    this.employeeCode,
    this.department,
    this.position,
    this.attendanceRate = 0.0,
    this.totalDays = 0,
    this.presentDays = 0,
    this.lateDays = 0,
    this.absentDays = 0,
    this.status,
    this.onTimeDays,
    this.punctualityRate,
    this.averageLateTime,
  });

  factory EmployeePerformance.fromJson(Map<String, dynamic> json) {
    return EmployeePerformance(
      employeeId: json['employeeId']?.toString() ?? '',
      employeeName: json['employeeName'] ?? json['fullName'] ?? '',
      employeeCode: json['employeeCode'],
      department: json['department'],
      position: json['position'],
      attendanceRate: (json['attendanceRate'] ?? 0.0).toDouble(),
      totalDays: json['totalDays'] ?? 0,
      presentDays: json['presentDays'] ?? 0,
      lateDays: json['lateDays'] ?? 0,
      absentDays: json['absentDays'] ?? 0,
      status: json['status'],
      onTimeDays: json['onTimeDays'],
      punctualityRate: json['punctualityRate'] != null ? (json['punctualityRate']).toDouble() : null,
      averageLateTime: json['averageLateTime']?.toString(),
    );
  }
}

class DepartmentStatistics {
  final String departmentId;
  final String departmentName;
  final int totalEmployees;
  final int presentToday;
  final int absentToday;
  final int lateToday;
  final double attendanceRate;
  final int? activeToday;
  final double? punctualityRate;

  String get department => departmentName;

  DepartmentStatistics({
    required this.departmentId,
    required this.departmentName,
    this.totalEmployees = 0,
    this.presentToday = 0,
    this.absentToday = 0,
    this.lateToday = 0,
    this.attendanceRate = 0.0,
    this.activeToday,
    this.punctualityRate,
  });

  factory DepartmentStatistics.fromJson(Map<String, dynamic> json) {
    return DepartmentStatistics(
      departmentId: json['departmentId']?.toString() ?? '',
      departmentName: json['departmentName'] ?? json['department'] ?? '',
      totalEmployees: json['totalEmployees'] ?? 0,
      presentToday: json['presentToday'] ?? 0,
      absentToday: json['absentToday'] ?? 0,
      lateToday: json['lateToday'] ?? 0,
      attendanceRate: (json['attendanceRate'] ?? 0.0).toDouble(),
      activeToday: json['activeToday'],
      punctualityRate: json['punctualityRate'] != null ? (json['punctualityRate']).toDouble() : null,
    );
  }
}

class DeviceStatus {
  final String deviceId;
  final String deviceName;
  final String? serialNumber;
  final String? ipAddress;
  final bool isOnline;
  final DateTime? lastOnline;
  final String? location;
  final int? userCount;
  final int? todayAttendances;

  String get status => isOnline ? 'online' : 'offline';

  DeviceStatus({
    required this.deviceId,
    required this.deviceName,
    this.serialNumber,
    this.ipAddress,
    this.isOnline = false,
    this.lastOnline,
    this.location,
    this.userCount,
    this.todayAttendances,
  });

  factory DeviceStatus.fromJson(Map<String, dynamic> json) {
    return DeviceStatus(
      deviceId: json['deviceId']?.toString() ?? json['id']?.toString() ?? '',
      deviceName: json['deviceName'] ?? json['name'] ?? '',
      serialNumber: json['serialNumber'],
      ipAddress: json['ipAddress'],
      isOnline: json['isOnline'] ?? false,
      lastOnline: json['lastOnline'] != null
          ? DateTime.tryParse(json['lastOnline'].toString().contains('Z') || json['lastOnline'].toString().contains('+')
              ? json['lastOnline']
              : '${json['lastOnline']}Z')
          : null,
      location: json['location'],
      userCount: json['userCount'],
      todayAttendances: json['todayAttendances'],
    );
  }
}

class TodayEmployee {
  final String employeeId;
  final String employeeName;
  final String? department;
  final String? status;
  final DateTime? checkInTime;
  final DateTime? checkOutTime;
  final DateTime? shiftStartTime;
  final DateTime? shiftEndTime;

  String get fullName => employeeName;

  TodayEmployee({
    required this.employeeId,
    required this.employeeName,
    this.department,
    this.status,
    this.checkInTime,
    this.checkOutTime,
    this.shiftStartTime,
    this.shiftEndTime,
  });

  factory TodayEmployee.fromJson(Map<String, dynamic> json) {
    return TodayEmployee(
      employeeId: json['employeeId']?.toString() ?? '',
      employeeName: json['employeeName'] ?? json['fullName'] ?? '',
      department: json['department'],
      status: json['status'],
      checkInTime: json['checkInTime'] != null ? DateTime.parse(json['checkInTime']) : null,
      checkOutTime: json['checkOutTime'] != null ? DateTime.parse(json['checkOutTime']) : null,
      shiftStartTime: json['shiftStartTime'] != null ? DateTime.tryParse(json['shiftStartTime'].toString()) : null,
      shiftEndTime: json['shiftEndTime'] != null ? DateTime.tryParse(json['shiftEndTime'].toString()) : null,
    );
  }
}

class DashboardData {
  final DashboardSummary summary;
  final List<AttendanceTrend> attendanceTrends;
  final List<EmployeePerformance> topPerformers;
  final List<EmployeePerformance> lateEmployees;
  final List<DepartmentStatistics> departmentStats;
  final List<DeviceStatus> deviceStatuses;
  final List<TodayEmployee> todayEmployees;

  DashboardData({
    required this.summary,
    this.attendanceTrends = const [],
    this.topPerformers = const [],
    this.lateEmployees = const [],
    this.departmentStats = const [],
    this.deviceStatuses = const [],
    this.todayEmployees = const [],
  });

  factory DashboardData.fromJson(Map<String, dynamic> json) {
    return DashboardData(
      summary: DashboardSummary.fromJson(json['summary'] ?? json),
      attendanceTrends: (json['attendanceTrends'] as List?)
              ?.map((e) => AttendanceTrend.fromJson(e))
              .toList() ??
          [],
      topPerformers: (json['topPerformers'] as List?)
              ?.map((e) => EmployeePerformance.fromJson(e))
              .toList() ??
          [],
      lateEmployees: (json['lateEmployees'] as List?)
              ?.map((e) => EmployeePerformance.fromJson(e))
              .toList() ??
          [],
      departmentStats: (json['departmentStats'] as List?)
              ?.map((e) => DepartmentStatistics.fromJson(e))
              .toList() ??
          [],
      deviceStatuses: (json['deviceStatuses'] as List?)
              ?.map((e) => DeviceStatus.fromJson(e))
              .toList() ??
          [],
      todayEmployees: (json['todayEmployees'] as List?)
              ?.map((e) => TodayEmployee.fromJson(e))
              .toList() ??
          [],
    );
  }
}

class SyncAllResult {
  final bool devicesSynced;
  final int devicesCount;
  final bool employeesSynced;
  final int employeesCount;
  final bool attendancesSynced;
  final int attendancesCount;

  SyncAllResult({
    required this.devicesSynced,
    required this.devicesCount,
    required this.employeesSynced,
    required this.employeesCount,
    required this.attendancesSynced,
    required this.attendancesCount,
  });

  factory SyncAllResult.fromJson(Map<String, dynamic> json) {
    return SyncAllResult(
      devicesSynced: json['devicesSynced'] ?? false,
      devicesCount: json['devicesCount'] ?? 0,
      employeesSynced: json['employeesSynced'] ?? false,
      employeesCount: json['employeesCount'] ?? 0,
      attendancesSynced: json['attendancesSynced'] ?? false,
      attendancesCount: json['attendancesCount'] ?? 0,
    );
  }
}
