import '../services/api_service.dart';

/// Vai trò tự phục vụ (chỉ dữ liệu của mình) — khớp API IsEmployee: nhân viên, thu ngân, phục vụ, người dùng.
bool isEmployeeUserRole(String? role) {
  final r = role?.trim().toLowerCase();
  return r == 'employee' || r == 'cashier' || r == 'waiter' || r == 'user';
}

/// Chuyển EmployeeBenefitDto (/api/benefits/me) sang định dạng BenefitDto cho tính ca.
Map<String, dynamic>? employeeBenefitToShiftProfile(
    Map<String, dynamic> employeeBenefit) {
  final benefit = employeeBenefit['benefit'];
  if (benefit is! Map) return null;

  final b = Map<String, dynamic>.from(benefit);
  final profile = <String, dynamic>{
    'shiftsPerDay': b['shiftsPerDay'],
    'weeklyOffDays': b['weeklyOffDays'],
    'paidLeaveType': b['paidLeaveType'],
    'holidayMultiplier': b['holidayMultiplier'],
    'holidayOvertimeType': b['holidayOvertimeType'],
    'applyLateEarlyOnRestDayOt': b['applyLateEarlyOnRestDayOt'] ?? true,
    'restDayOtHoursOnly': b['restDayOtHoursOnly'] ?? false,
    'description': b['description'],
    'attendanceMode': b['attendanceMode'],
  };

  var empId = employeeBenefit['employeeId']?.toString() ?? '';
  var empCode = '';
  final emp = employeeBenefit['employee'];
  if (emp is Map) {
    if (empId.isEmpty) empId = emp['id']?.toString() ?? '';
    empCode = emp['employeeCode']?.toString() ?? '';
  }
  if (empId.isEmpty) return null;

  profile['employees'] = [
    {'id': empId, 'employeeCode': empCode},
  ];
  return profile;
}

/// Tải hồ sơ lương cho báo cáo chấm công (batch manager; NV dùng /api/benefits/me).
Future<List<Map<String, dynamic>>> loadAttendanceSalaryProfiles(
  ApiService api, {
  required bool preferSelfServiceApi,
}) async {
  if (preferSelfServiceApi) {
    try {
      final me = await api.getMyEmployeeSalaryProfile();
      if (me != null) {
        final converted = employeeBenefitToShiftProfile(me);
        if (converted != null) return [converted];
      }
    } catch (_) {}
    return [];
  }

  try {
    final profiles = await api.getSalaryProfiles();
    return profiles
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  } catch (_) {
    return [];
  }
}
