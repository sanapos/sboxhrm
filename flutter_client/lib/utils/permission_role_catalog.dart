import 'package:flutter/material.dart';
import 'dashboard_permission_modules.dart';

/// Nhóm chức năng — khớp menu app (Tổng quan tách từng widget, Thiết lập HRM, …).
class PermissionUiGroup {
  final String id;
  final String title;
  final String description;
  final IconData icon;
  final Color color;
  final List<String> moduleCodes;

  const PermissionUiGroup({
    required this.id,
    required this.title,
    required this.description,
    required this.icon,
    required this.color,
    required this.moduleCodes,
  });
}

/// Catalog nhóm cho màn Phân quyền.
class PermissionRoleCatalog {
  PermissionRoleCatalog._();

  /// Module legacy trên DB — ẩn khỏi UI phân quyền.
  /// Module alias thuần API — không hiện trên UI phân quyền.
  static const Set<String> legacyHiddenModules = {
    'Dashboard',
    'Salary',
    'Shift',
    'ShiftTemplate',
    'ShiftSalaryLevel',
    'Report',
    'Account',
    'Store',
    'Transaction',
    'Benefit',
    'GoogleDrive',
  };

  static const List<PermissionUiGroup> groups = [
    PermissionUiGroup(
      id: 'overview_nav',
      title: 'Điều hướng',
      description: 'Trang chủ, thông báo',
      icon: Icons.home_outlined,
      color: Color(0xFF0F172A),
      moduleCodes: ['Home', 'Notification'],
    ),
    PermissionUiGroup(
      id: 'overview_dashboard',
      title: 'Tổng quan (Dashboard)',
      description: 'Từng khối trên bảng điều khiển',
      icon: Icons.dashboard_customize_outlined,
      color: Color(0xFF0284C7),
      moduleCodes: DashboardPermissionModules.allWidgets,
    ),
    PermissionUiGroup(
      id: 'hr_profile',
      title: 'Hồ sơ nhân sự',
      description: 'Nhân viên, phòng ban, nghỉ phép, thiết lập lương',
      icon: Icons.people_outline,
      color: Color(0xFF0284C7),
      moduleCodes: [
        'Employee',
        'Department',
        'Leave',
        'SalarySettings',
        'Payslip',
        'DeviceUser',
        'HrDocument',
        'OrgChart',
      ],
    ),
    PermissionUiGroup(
      id: 'attendance',
      title: 'Chấm công',
      description: 'Chấm thô, lịch, tổng hợp, duyệt, lương',
      icon: Icons.access_time,
      color: Color(0xFF0369A1),
      moduleCodes: [
        'Attendance',
        'WorkSchedule',
        'AttendanceSummary',
        'AttendanceByShift',
        'AttendanceCorrection',
        'AttendanceApproval',
        'MobileAttendanceApproval',
        'ScheduleApproval',
        'Payroll',
        'Overtime',
        'ShiftSwap',
        'MobileDeviceRegistration',
        'MobileAttendance',
        'Meal',
        'FieldCheckIn',
      ],
    ),
    PermissionUiGroup(
      id: 'finance',
      title: 'Tài chính',
      description: 'Thưởng, phạt, ứng lương, thu chi',
      icon: Icons.account_balance_wallet_outlined,
      color: Color(0xFFEC4899),
      moduleCodes: [
        'BonusPenalty',
        'PenaltyTickets',
        'AdvanceRequests',
        'CashTransaction',
        'BankAccount',
      ],
    ),
    PermissionUiGroup(
      id: 'operations',
      title: 'Quản lý vận hành',
      description: 'Tài sản, công việc, truyền thông, KPI, sản lượng',
      icon: Icons.business_center_outlined,
      color: Color(0xFF059669),
      moduleCodes: [
        'Asset',
        'Task',
        'Communication',
        'KPI',
        'Production',
        'Feedback',
      ],
    ),
    PermissionUiGroup(
      id: 'reports',
      title: 'Báo cáo',
      description: 'Nghỉ phép, thu chi, phạt, ứng lương',
      icon: Icons.assessment_outlined,
      color: Color(0xFF7C3AED),
      moduleCodes: [
        'LeaveReport',
        'CashReport',
        'PenaltyReport',
        'AdvanceReport',
        'AssetReport',
        'AttendanceReport',
        'HrReport',
        'PayrollReport',
      ],
    ),
    PermissionUiGroup(
      id: 'hrm_settings',
      title: 'Thiết lập HRM',
      description: 'Trung tâm cài đặt: ca, mobile, lương, máy, hệ thống',
      icon: Icons.tune,
      color: Color(0xFF64748B),
      moduleCodes: [
        'SettingsHub',
        'ShiftSetup',
        'MobileAttendance',
        'Holiday',
        'Device',
        'Allowance',
        'PenaltySetup',
        'Insurance',
        'Tax',
        'ProductSalary',
        'Branch',
        'Geofence',
        'SystemSettings',
        'NotificationSettings',
        'AIGemini',
        'Settings',
      ],
    ),
    PermissionUiGroup(
      id: 'admin',
      title: 'Quản trị hệ thống',
      description: 'Tài khoản, phân quyền',
      icon: Icons.admin_panel_settings_outlined,
      color: Color(0xFF475569),
      moduleCodes: ['UserManagement', 'Role', 'DepartmentPermission'],
    ),
  ];

  static String? groupIdForModule(String? module) {
    if (module == null || module.isEmpty) return null;
    for (final g in groups) {
      if (g.moduleCodes.contains(module)) return g.id;
    }
    return 'other';
  }

  static PermissionUiGroup? groupById(String id) {
    for (final g in groups) {
      if (g.id == id) return g;
    }
    return null;
  }

  static bool showInPermissionUi(String? module) {
    if (module == null || module.isEmpty) return false;
    return !legacyHiddenModules.contains(module);
  }

  static List<Map<String, dynamic>> sortForUi(
    List<Map<String, dynamic>> permissions,
  ) {
    final visible = permissions
        .where((p) => showInPermissionUi(p['module'] as String?))
        .toList();
    int orderKey(Map<String, dynamic> p) {
      final mod = p['module'] as String? ?? '';
      for (var gi = 0; gi < groups.length; gi++) {
        final idx = groups[gi].moduleCodes.indexOf(mod);
        if (idx >= 0) return gi * 100 + idx;
      }
      return 9000 + (p['displayOrder'] as int? ?? 999);
    }

    visible.sort((a, b) => orderKey(a).compareTo(orderKey(b)));
    return visible;
  }

  /// Áp dụng nhanh cho một nhóm module (menu ⋮ trên từng nhóm).
  static void applyToPermissionsList(
    List<Map<String, dynamic>> permissions, {
    required List<String> moduleCodes,
    required PermissionBundleLevel level,
    required bool Function(String?, String) moduleSupports,
  }) {
    final codes = moduleCodes.toSet();
    for (final p in permissions) {
      final mod = p['module'] as String?;
      if (mod == null || !codes.contains(mod)) continue;
      _applyLevel(p, mod, level, moduleSupports);
    }
  }

  static void _applyLevel(
    Map<String, dynamic> p,
    String mod,
    PermissionBundleLevel level,
    bool Function(String?, String) moduleSupports,
  ) {
    void setFlag(String key, bool value) {
      if (moduleSupports(mod, key)) p[key] = value;
    }

    switch (level) {
      case PermissionBundleLevel.none:
        for (final k in [
          'canView',
          'canCreate',
          'canEdit',
          'canDelete',
          'canExport',
          'canApprove',
        ]) {
          setFlag(k, false);
        }
        break;
      case PermissionBundleLevel.viewOnly:
        setFlag('canView', true);
        setFlag('canCreate', false);
        setFlag('canEdit', false);
        setFlag('canDelete', false);
        setFlag('canExport', false);
        setFlag('canApprove', false);
        break;
      case PermissionBundleLevel.operate:
        setFlag('canView', true);
        setFlag('canCreate', true);
        setFlag('canEdit', true);
        setFlag('canDelete', false);
        setFlag('canExport', true);
        setFlag('canApprove', false);
        break;
      case PermissionBundleLevel.full:
        setFlag('canView', true);
        setFlag('canCreate', true);
        setFlag('canEdit', true);
        setFlag('canDelete', true);
        setFlag('canExport', true);
        setFlag('canApprove', true);
        break;
    }
  }
}

/// Mức quyền khi áp dụng nhanh cho cả nhóm (không phải gói mẫu).
enum PermissionBundleLevel { none, viewOnly, operate, full }
