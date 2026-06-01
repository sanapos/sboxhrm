import '../providers/permission_provider.dart';

/// Xác định dashboard cá nhân (nhân viên) vs dashboard vận hành (quản lý).
class DashboardAccess {
  DashboardAccess._();

  /// Module cho thấy user vận hành / quản lý (không dùng dashboard NV).
  static const _operationsModules = [
    'Employee',
    'Payroll',
    'AttendanceSummary',
    'AttendanceByShift',
    'UserManagement',
    'Role',
    'Device',
    'SettingsHub',
    'AttendanceApproval',
    'ScheduleApproval',
    'MobileAttendanceApproval',
    'KPI',
    'Task',
  ];

  static bool hasOperationsScope(PermissionProvider perm) {
    for (final module in _operationsModules) {
      if (!_permGrantsOperations(perm, module)) continue;
      return true;
    }
    return false;
  }

  static bool _permGrantsOperations(PermissionProvider perm, String module) {
    if (!perm.canView(module)) return false;
    switch (module) {
      case 'Employee':
        return perm.canCreate(module) ||
            perm.canEdit(module) ||
            perm.canDelete(module) ||
            perm.canExport(module);
      case 'Dashboard':
      case 'Home':
      case 'Notification':
      case 'Payslip':
      case 'Attendance':
      case 'Leave':
      case 'Shift':
        return false;
      default:
        return true;
    }
  }

  /// Dashboard kiểu nhân viên: xem tổng quan cá nhân, không phạm vi QL rộng.
  static bool useEmployeeDashboard(
    PermissionProvider perm, {
    String? role,
  }) {
    final r = (role ?? '').trim().toLowerCase();
    if (r == 'superadmin' || r == 'agent' || r == 'admin') return false;
    if (!perm.canView('Dashboard')) return false;

    if (r == 'employee' || r == 'user') return true;

    return !hasOperationsScope(perm);
  }

  /// Tab lương trên mobile: phiếu lương cá nhân trước, tổng hợp lương sau.
  static String? mobilePayTabModule(PermissionProvider perm) {
    if (perm.canView('Payslip')) return 'Payslip';
    if (perm.canView('Payroll')) return 'Payroll';
    return null;
  }

  /// Index màn hình sau khi đăng nhập (khi quyền đã load).
  static int initialNavIndex({
    required PermissionProvider perm,
    required int homeIndex,
    required int dashboardIndex,
    required int payslipIndex,
    required int Function(String moduleCode) indexForModule,
    String? role,
  }) {
    if (!perm.isLoaded) return homeIndex;

    final viewable = _countViewableNavModules(perm, indexForModule);
    if (viewable <= 2 && perm.canView('Dashboard')) {
      return dashboardIndex;
    }
    if (perm.canView('Dashboard') && useEmployeeDashboard(perm, role: role)) {
      return dashboardIndex;
    }
    if (perm.canView('Payslip') &&
        !perm.canView('Dashboard') &&
        !perm.canView('Home')) {
      return payslipIndex;
    }
    return homeIndex;
  }

  static int _countViewableNavModules(
    PermissionProvider perm,
    int Function(String moduleCode) indexForModule,
  ) {
    const codes = [
      'Home',
      'Dashboard',
      'Payslip',
      'Payroll',
      'Attendance',
      'MobileAttendance',
      'Leave',
      'Notification',
    ];
    var n = 0;
    for (final c in codes) {
      if (indexForModule(c) >= 0 && perm.canView(c)) n++;
    }
    return n;
  }
}
