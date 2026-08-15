import 'package:flutter/material.dart';
import 'dashboard_permission_modules.dart';
import 'permission_module_catalog.dart';
import 'permission_module_labels.dart';
import '../widgets/hrm_page_chrome.dart';

/// Nhóm chức năng — khớp menu app (`main_layout.dart`, `settings_hub_screen.dart`).
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

  /// Module legacy / alias API — ẩn khỏi UI phân quyền.
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
      color: HrmPageChrome.chip,
      moduleCodes: DashboardPermissionModules.allWidgets,
    ),
    PermissionUiGroup(
      id: 'hr_profile',
      title: 'Hồ sơ nhân sự',
      description: 'Nhân viên, phòng ban, thiết lập lương, tài liệu',
      icon: Icons.people_outline,
      color: HrmPageChrome.chip,
      moduleCodes: [
        'Employee',
        'Department',
        'SalarySettings',
        'HrDocument',
        'OrgChart',
      ],
    ),
    PermissionUiGroup(
      id: 'attendance',
      title: 'Chấm công',
      description: 'Chấm thô, lịch, duyệt, mobile, tăng ca, đổi ca',
      icon: Icons.access_time,
      color: Color(0xFF0369A1),
      moduleCodes: [
        'DeviceUser',
        'Leave',
        'Attendance',
        'WorkSchedule',
        'AttendanceCorrection',
        'AttendanceApproval',
        'MobileAttendanceApproval',
        'ScheduleApproval',
        'Overtime',
        'ShiftSwap',
        'MobileDeviceRegistration',
        'MobileAttendance',
      ],
    ),
    PermissionUiGroup(
      id: 'reports',
      title: 'Báo cáo & lương',
      description: 'Tổng hợp công, phiếu lương, báo cáo thống kê',
      icon: Icons.assessment_outlined,
      color: HrmPageChrome.chipMid,
      moduleCodes: [
        'AttendanceSummary',
        'AttendanceByShift',
        'Payslip',
        'Payroll',
        'AttendanceReport',
        'LeaveReport',
        'CashReport',
        'HkdBooks',
        'PenaltyReport',
        'AdvanceReport',
        'BusinessTripReport',
        'AssetReport',
      ],
    ),
    PermissionUiGroup(
      id: 'finance',
      title: 'Tài chính',
      description: 'Thưởng, phạt, ứng lương, thu chi, tài khoản NH',
      icon: Icons.account_balance_wallet_outlined,
      color: HrmPageChrome.chipLight,
      moduleCodes: [
        'BonusPenalty',
        'PenaltyTickets',
        'AdvanceRequests',
        'BusinessTripExpense',
        'CashTransaction',
        'BankAccount',
      ],
    ),
    PermissionUiGroup(
      id: 'pos',
      title: 'POS / Bán hàng',
      description: 'Order, thu ngân, hàng hóa, kho, trả hàng, báo cáo',
      icon: Icons.point_of_sale_outlined,
      color: HrmPageChrome.chipMid,
      moduleCodes: [
        'PosSell',
        'PosProducts',
        'PosPrintTemplates',
        'PosSaleOrders',
        'PosSaleReturns',
        'PosBooking',
        'PosCustomers',
        'PosWarranty',
        'PosCustomerDisplay',
        'PosEInvoice',
        'PosKds',
        'PosQrOrder',
        'PosCashierShift',
        'PosPrinters',
        'PosPurchaseReceipts',
        'PosPurchaseReturns',
        'PosStockCounts',
        'PosDamageIssues',
        'PosInternalUseIssues',
        'PosSalesReport',
        'HkdBooks',
      ],
    ),
    PermissionUiGroup(
      id: 'pos_reports',
      title: 'POS / Báo cáo',
      description: '14 báo cáo POS tách riêng — tick từng loại',
      icon: Icons.bar_chart_outlined,
      color: HrmPageChrome.chipMid,
      moduleCodes: [
        'PosReportRevenue',
        'PosReportSoldGoods',
        'PosReportStock',
        'PosReportPurchases',
        'PosReportPayment',
        'PosReportDebt',
        'PosReportExpiry',
        'PosReportProfit',
        'PosReportExpense',
        'PosReportEndOfDay',
        'PosReportStaffRevenue',
        'PosReportCashbook',
        'PosReportPnl',
        'PosReportVoucher',
      ],
    ),
    PermissionUiGroup(
      id: 'operations',
      title: 'Quản lý vận hành',
      description: 'Chấm cơm, tài sản, công việc, KPI, sản lượng',
      icon: Icons.business_center_outlined,
      color: HrmPageChrome.chip,
      moduleCodes: [
        'Meal',
        'Asset',
        'Task',
        'Communication',
        'KPI',
        'Production',
        'Feedback',
        'FieldCheckIn',
      ],
    ),
    PermissionUiGroup(
      id: 'hrm_settings',
      title: 'Thiết lập HRM',
      description: 'Ca, ngày lễ, máy chấm công, phụ cấp, thuế, chi nhánh',
      icon: Icons.tune,
      color: Color(0xFF64748B),
      moduleCodes: [
        'SettingsHub',
        'ShiftSetup',
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
      description: 'Tài khoản, phân quyền, PQ phòng ban',
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

  /// Danh sách module mặc định cho UI — thứ tự theo nhóm menu.
  static List<Map<String, dynamic>> buildDefaultModuleList({
    Map<String, String>? idsByModule,
  }) {
    final ids = idsByModule ?? PermissionModuleCatalog.idsByModule;
    var order = 0;
    final list = <Map<String, dynamic>>[];
    for (final g in groups) {
      for (final code in g.moduleCodes) {
        if (!showInPermissionUi(code)) continue;
        list.add({
          'id': ids[code],
          'module': code,
          'moduleDisplayName': PermissionModuleLabels.resolve(code),
          'displayOrder': ++order,
        });
      }
    }
    return list;
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
