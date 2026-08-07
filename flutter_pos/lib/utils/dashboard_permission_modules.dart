import '../providers/permission_provider.dart';

/// Các widget trên màn Tổng quan (Dashboard) — phân quyền từng khối.
class DashboardPermissionModules {
  DashboardPermissionModules._();

  static const attendanceOverview = 'DashboardAttendanceOverview';
  static const hrInsights = 'DashboardHrInsights';
  static const todaySchedule = 'DashboardTodaySchedule';
  static const realtimeAttendance = 'DashboardRealtimeAttendance';
  static const absent = 'DashboardAbsent';
  static const lateEarly = 'DashboardLateEarly';
  static const kpiPanel = 'DashboardKpiPanel';
  static const internalNews = 'DashboardInternalNews';

  /// Module cũ (một quyền chung) — ẩn trên UI phân quyền, vẫn hỗ trợ runtime.
  static const legacyDashboard = 'Dashboard';

  static const allWidgets = [
    attendanceOverview,
    hrInsights,
    todaySchedule,
    realtimeAttendance,
    absent,
    lateEarly,
    kpiPanel,
    internalNews,
  ];

  static bool canViewWidget(PermissionProvider perm, String code) {
    if (perm.canView(code)) return true;
    if (perm.canView(legacyDashboard)) return true;
    return false;
  }

  static bool canViewAnyWidget(PermissionProvider perm) {
    for (final c in allWidgets) {
      if (perm.canView(c)) return true;
    }
    return perm.canView(legacyDashboard);
  }

  static bool canViewNavDashboard(PermissionProvider perm) =>
      canViewAnyWidget(perm) || perm.canView(legacyDashboard);
}
