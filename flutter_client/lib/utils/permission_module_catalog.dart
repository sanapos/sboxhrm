/// Guid module cố định (khớp PermissionConfiguration seed trên API).
class PermissionModuleCatalog {
  PermissionModuleCatalog._();

  static const Map<String, String> idsByModule = {
    'Dashboard': '11111111-1111-1111-1111-111111111001',
    'Employee': '11111111-1111-1111-1111-111111111002',
    'Attendance': '11111111-1111-1111-1111-111111111003',
    'Leave': '11111111-1111-1111-1111-111111111004',
    'Shift': '11111111-1111-1111-1111-111111111005',
    'Salary': '11111111-1111-1111-1111-111111111006',
    'Payslip': '11111111-1111-1111-1111-111111111007',
    'Device': '11111111-1111-1111-1111-111111111008',
    'Report': '11111111-1111-1111-1111-111111111009',
    'Settings': '11111111-1111-1111-1111-111111111010',
    'Account': '11111111-1111-1111-1111-111111111011',
    'Role': '11111111-1111-1111-1111-111111111012',
    'Store': '11111111-1111-1111-1111-111111111013',
    'Allowance': '11111111-1111-1111-1111-111111111014',
    'Holiday': '11111111-1111-1111-1111-111111111015',
    'Insurance': '11111111-1111-1111-1111-111111111016',
    'Tax': '11111111-1111-1111-1111-111111111017',
    'Advance': '11111111-1111-1111-1111-111111111018',
    'Notification': '11111111-1111-1111-1111-111111111019',
    'Department': '11111111-1111-1111-1111-111111111020',
    'Overtime': '11111111-1111-1111-1111-111111111021',
    'AttendanceCorrection': '11111111-1111-1111-1111-111111111022',
    'WorkSchedule': '11111111-1111-1111-1111-111111111023',
    'ShiftSwap': '11111111-1111-1111-1111-111111111024',
    'ShiftTemplate': '11111111-1111-1111-1111-111111111025',
    'ShiftSalaryLevel': '11111111-1111-1111-1111-111111111026',
    'Benefit': '11111111-1111-1111-1111-111111111027',
    'Transaction': '11111111-1111-1111-1111-111111111028',
    'CashTransaction': '11111111-1111-1111-1111-111111111029',
    'BankAccount': '11111111-1111-1111-1111-111111111030',
    'HrDocument': '11111111-1111-1111-1111-111111111031',
    'Task': '11111111-1111-1111-1111-111111111032',
    'KPI': '11111111-1111-1111-1111-111111111033',
    'Asset': '11111111-1111-1111-1111-111111111034',
    'Geofence': '11111111-1111-1111-1111-111111111035',
    'OrgChart': '11111111-1111-1111-1111-111111111036',
    'Branch': '11111111-1111-1111-1111-111111111037',
    'Communication': '11111111-1111-1111-1111-111111111038',
    'DeviceUser': '11111111-1111-1111-1111-111111111039',
    'UserManagement': '11111111-1111-1111-1111-111111111040',
    'DepartmentPermission': '11111111-1111-1111-1111-111111111041',
    'FieldCheckIn': '11111111-1111-1111-1111-111111111042',
    'Home': '11111111-1111-1111-1111-111111111043',
    'SalarySettings': '11111111-1111-1111-1111-111111111044',
    'AttendanceSummary': '11111111-1111-1111-1111-111111111045',
    'AttendanceByShift': '11111111-1111-1111-1111-111111111046',
    'AttendanceApproval': '11111111-1111-1111-1111-111111111047',
    'ScheduleApproval': '11111111-1111-1111-1111-111111111048',
    'Payroll': '11111111-1111-1111-1111-111111111049',
    'BonusPenalty': '11111111-1111-1111-1111-111111111050',
    'PenaltyTickets': '11111111-1111-1111-1111-111111111051',
    'AdvanceRequests': '11111111-1111-1111-1111-111111111052',
    'Production': '11111111-1111-1111-1111-111111111053',
    'MobileDeviceRegistration': '11111111-1111-1111-1111-111111111054',
    'MobileAttendanceApproval': '11111111-1111-1111-1111-111111111055',
    'Meal': '11111111-1111-1111-1111-111111111056',
    'AttendanceReport': '11111111-1111-1111-1111-111111111058',
    'SettingsHub': '11111111-1111-1111-1111-111111111060',
    'ShiftSetup': '11111111-1111-1111-1111-111111111061',
    'MobileAttendance': '11111111-1111-1111-1111-111111111062',
    'PenaltySetup': '11111111-1111-1111-1111-111111111063',
    'SystemSettings': '11111111-1111-1111-1111-111111111064',
    'NotificationSettings': '11111111-1111-1111-1111-111111111065',
    'AIGemini': '11111111-1111-1111-1111-111111111067',
    'ProductSalary': '11111111-1111-1111-1111-111111111068',
    'Feedback': '11111111-1111-1111-1111-111111111069',
    'PenaltyReport': '11111111-1111-1111-1111-111111111070',
    'AdvanceReport': '11111111-1111-1111-1111-111111111071',
    'LeaveReport': '11111111-1111-1111-1111-111111111072',
    'CashReport': '11111111-1111-1111-1111-111111111073',
    'AssetReport': '11111111-1111-1111-1111-111111111074',
    'DashboardAttendanceOverview': '11111111-1111-1111-1111-111111111075',
    'DashboardHrInsights': '11111111-1111-1111-1111-111111111076',
    'DashboardTodaySchedule': '11111111-1111-1111-1111-111111111077',
    'DashboardRealtimeAttendance': '11111111-1111-1111-1111-111111111078',
    'DashboardAbsent': '11111111-1111-1111-1111-111111111079',
    'DashboardLateEarly': '11111111-1111-1111-1111-111111111080',
    'DashboardKpiPanel': '11111111-1111-1111-1111-111111111081',
    'DashboardInternalNews': '11111111-1111-1111-1111-111111111082',
    'PosProducts': '11111111-1111-1111-1111-111111111083',
    'PosSalesReport': '11111111-1111-1111-1111-111111111084',
  };

  static Map<String, String> buildLookup([
    Iterable<Map<String, dynamic>>? apiModules,
  ]) {
    final map = <String, String>{};
    for (final e in idsByModule.entries) {
      map[e.key] = e.value;
    }
    if (apiModules != null) {
      for (final m in apiModules) {
        final mod = (m['module'] ?? m['Module'])?.toString();
        final id = (m['id'] ?? m['Id'])?.toString();
        if (mod != null && mod.isNotEmpty && _isGuid(id)) {
          map[mod] = id!;
        }
      }
    }
    return map;
  }

  static bool _isGuid(String? value) {
    if (value == null || value.isEmpty) return false;
    final s = value.trim();
    final dashed = RegExp(
      r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
    );
    if (dashed.hasMatch(s)) return true;
    final compact = RegExp(r'^[0-9a-fA-F]{32}$');
    return compact.hasMatch(s);
  }

  static String? idForModule(String? module, Map<String, String> lookup) {
    if (module == null || module.isEmpty) return null;
    final direct = lookup[module];
    if (direct != null) return direct;
    for (final e in lookup.entries) {
      if (e.key.toLowerCase() == module.toLowerCase()) return e.value;
    }
    for (final e in idsByModule.entries) {
      if (e.key.toLowerCase() == module.toLowerCase()) return e.value;
    }
    return null;
  }

  static List<Map<String, dynamic>> asModuleList() {
    final entries = idsByModule.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    var order = 0;
    return entries
        .map((e) => {
              'id': e.value,
              'module': e.key,
              'moduleDisplayName': e.key,
              'displayOrder': ++order,
            })
        .toList();
  }
}
