import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/permission_provider.dart';
import 'package:zkteco_flutter_client/widgets/app_responsive_dialog.dart';
import '../services/api_service.dart';
import '../screens/settings_hub_screen.dart';
import '../utils/dashboard_permission_modules.dart';
import '../utils/permission_module_catalog.dart';
import '../utils/permission_module_labels.dart';
import '../utils/permission_role_catalog.dart';
import '../utils/responsive_helper.dart';
import '../widgets/hrm_page_chrome.dart';
import '../widgets/loading_widget.dart';
import '../widgets/notification_overlay.dart';
class RolePermissionsScreen extends StatefulWidget {
  const RolePermissionsScreen({super.key});

  @override
  State<RolePermissionsScreen> createState() => _RolePermissionsScreenState();
}

class _RolePermissionsScreenState extends State<RolePermissionsScreen> {
  PermissionProvider get _perm =>
      Provider.of<PermissionProvider>(context, listen: false);

  final ApiService _apiService = ApiService();
  List<Map<String, dynamic>> _roles = [];
  List<Map<String, dynamic>> _modules = [];
  Map<String, dynamic>? _selectedRolePermissions;
  String? _selectedRoleName;
  bool _isLoading = true;
  bool _isLoadingPermissions = false;
  bool _isSaving = false;

  /// Lọc bảng theo một nhóm (null = tất cả nhóm).
  String? _filterGroupId;

  /// Back của Settings Hub khi drill-down danh sách quyền (mobile + embedded).
  VoidCallback? _savedHubBack;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    if (_savedHubBack != null) {
      SettingsHubScreen.internalBackCallback = _savedHubBack;
    }
    super.dispose();
  }

  void _updateEmbeddedBack() {
    if (!mounted || !HrmPageChrome.isEmbedded || !Responsive.isMobile(context)) {
      return;
    }
    if (_selectedRolePermissions != null) {
      _savedHubBack ??= SettingsHubScreen.internalBackCallback;
      SettingsHubScreen.internalBackCallback = () {
        if (!mounted) return;
        setState(() {
          _selectedRoleName = null;
          _selectedRolePermissions = null;
        });
        SettingsHubScreen.internalBackCallback = _savedHubBack;
        _savedHubBack = null;
      };
    } else if (_savedHubBack != null) {
      SettingsHubScreen.internalBackCallback = _savedHubBack;
      _savedHubBack = null;
    }
  }

  static bool _isLegacyDashboardModule(String? module) =>
      module == DashboardPermissionModules.legacyDashboard ||
      DashboardPermissionModules.allWidgets.contains(module ?? '');

  static const List<String> _systemRoleOrder = [
    'Admin',
    'Director',
    'Accountant',
    'DepartmentHead',
    'Manager',
    'Employee',
    'User',
  ];

  List<Map<String, dynamic>> _sortRoles(List<Map<String, dynamic>> roles) {
    int orderKey(String? name) {
      if (name == null) return 999;
      final i = _systemRoleOrder.indexWhere(
          (r) => r.toLowerCase() == name.toLowerCase());
      return i >= 0 ? i : 100 + name.toLowerCase().codeUnitAt(0);
    }

    final sorted = List<Map<String, dynamic>>.from(roles);
    sorted.sort((a, b) {
      final ka = orderKey(a['roleName'] as String?);
      final kb = orderKey(b['roleName'] as String?);
      final c = ka.compareTo(kb);
      if (c != 0) return c;
      return ((a['roleDisplayName'] ?? '') as String)
          .compareTo((b['roleDisplayName'] ?? '') as String);
    });
    return sorted;
  }

  /// Gộp module từ API với catalog UI (8 khối Tổng quan, …) — DB có thể chưa seed kịp.
  List<Map<String, dynamic>> _ensureUiModules(
      List<Map<String, dynamic>> apiModules) {
    final byModule = <String, Map<String, dynamic>>{};
    for (final m in apiModules) {
      final mod = m['module'] as String?;
      if (mod != null && mod.isNotEmpty) {
        byModule[mod] = Map<String, dynamic>.from(m);
      }
    }

    void upsert(Map<String, dynamic> def) {
      final mod = def['module'] as String?;
      if (mod == null || !PermissionRoleCatalog.showInPermissionUi(mod)) return;
      final existing = byModule[mod];
      if (existing != null) {
        byModule[mod] = {
          ...existing,
          'moduleDisplayName': PermissionModuleLabels.resolve(
            mod,
            def['moduleDisplayName'] as String? ??
                existing['moduleDisplayName'] as String?,
          ),
          'displayOrder': existing['displayOrder'] ?? def['displayOrder'],
        };
        return;
      }
      final copy = Map<String, dynamic>.from(def);
      copy['moduleDisplayName'] = PermissionModuleLabels.resolve(
        mod,
        def['moduleDisplayName'] as String?,
      );
      final guid = PermissionModuleCatalog.idsByModule[mod];
      if (guid != null) copy['id'] = guid;
      byModule[mod] = copy;
    }

    for (final def in _getAllModules()) {
      upsert(def);
    }
    for (final g in PermissionRoleCatalog.groups) {
      for (final code in g.moduleCodes) {
        if (byModule.containsKey(code)) continue;
        final fromDefs = _getAllModules()
            .where((m) => m['module'] == code)
            .cast<Map<String, dynamic>?>()
            .firstOrNull;
        if (fromDefs != null) {
          upsert(fromDefs);
        } else {
          upsert({
            'id': PermissionModuleCatalog.idsByModule[code] ?? '',
            'module': code,
            'moduleDisplayName': code,
            'displayOrder': 999,
          });
        }
      }
    }

    final list = byModule.values.toList();
    list.sort((a, b) =>
        ((a['displayOrder'] as int?) ?? 999)
            .compareTo((b['displayOrder'] as int?) ?? 999));
    return list;
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final results = await Future.wait([
        _apiService.getRoles(),
        _apiService.getPermissionModules(),
      ]);
      setState(() {
        _roles = _sortRoles(List<Map<String, dynamic>>.from(results[0]));
        _modules = _ensureUiModules(List<Map<String, dynamic>>.from(results[1]));
      });

      // Fallback: if API returns empty, use defaults
      if (_roles.isEmpty) {
        _loadSampleData();
      }
      if (_modules.isEmpty) {
        setState(() => _modules = _ensureUiModules(_getAllModules()));
      }
    } catch (e) {
      // Use sample data
      _loadSampleData();
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _loadSampleData() {
    setState(() {
      _roles = _sortRoles([
        {
          'roleName': 'Admin',
          'roleDisplayName': 'Quản trị viên',
          'permissionCount': 42
        },
        {
          'roleName': 'Director',
          'roleDisplayName': 'Giám đốc',
          'permissionCount': 42
        },
        {
          'roleName': 'Accountant',
          'roleDisplayName': 'Kế toán',
          'permissionCount': 42
        },
        {
          'roleName': 'DepartmentHead',
          'roleDisplayName': 'Trưởng phòng',
          'permissionCount': 42
        },
        {
          'roleName': 'Manager',
          'roleDisplayName': 'Quản lý',
          'permissionCount': 42
        },
        {
          'roleName': 'Employee',
          'roleDisplayName': 'Nhân viên',
          'permissionCount': 42
        },
        {
          'roleName': 'User',
          'roleDisplayName': 'Người dùng',
          'permissionCount': 42
        },
      ]);
      _modules = _ensureUiModules(_getAllModules());
    });
  }

  /// Định nghĩa các quyền thực sự có nghĩa cho từng module.
  /// Quyền KHÔNG có trong set sẽ bị ẩn (hiển thị dấu trừ) trong bảng phân quyền.
  static const Map<String, Set<String>> _moduleCapabilities = {
    // ── TỔNG QUAN ──
    'Home': {'canView'},
    'Notification': {'canView'},
    'DashboardAttendanceOverview': {'canView'},
    'DashboardHrInsights': {'canView'},
    'DashboardTodaySchedule': {'canView'},
    'DashboardRealtimeAttendance': {'canView'},
    'DashboardAbsent': {'canView'},
    'DashboardLateEarly': {'canView'},
    'DashboardKpiPanel': {'canView'},
    'DashboardInternalNews': {'canView'},
    // ── HỒ SƠ NHÂN SỰ ──
    'Employee': {'canView', 'canCreate', 'canEdit', 'canDelete', 'canExport'},
    'DeviceUser': {'canView', 'canCreate', 'canEdit', 'canDelete'},
    'Department': {'canView', 'canCreate', 'canEdit', 'canDelete'},
    'Leave': {
      'canView',
      'canCreate',
      'canEdit',
      'canDelete',
      'canExport',
      'canApprove',
    },
    'Payslip': {'canView', 'canExport'},
    'Overtime': {'canView', 'canCreate', 'canApprove'},
    'ShiftSwap': {'canView', 'canCreate', 'canApprove'},
    'SalarySettings': {'canView', 'canCreate', 'canEdit', 'canDelete'},
    // ── CHẤM CÔNG ──
    'Attendance': {
      'canView',
      'canCreate',
      'canEdit',
      'canDelete',
      'canExport',
    },
    'AttendanceCorrection': {
      'canView',
      'canCreate',
      'canDelete',
      'canApprove',
    },
    'WorkSchedule': {
      'canView',
      'canCreate',
      'canEdit',
      'canDelete',
      'canApprove'
    },
    'AttendanceSummary': {'canView', 'canExport'},
    'AttendanceByShift': {'canView', 'canExport'},
    'AttendanceApproval': {
      'canView',
      'canApprove',
      'canExport',
      'canDelete',
    },
    'ScheduleApproval': {'canView', 'canApprove'},
    'Payroll': {'canView', 'canExport'},
    // ── TÀI CHÍNH ──
    'BonusPenalty': {
      'canView',
      'canCreate',
      'canEdit',
      'canDelete',
      'canExport',
      'canApprove',
    },
    'PenaltyTickets': {
      'canView',
      'canCreate',
      'canEdit',
      'canDelete',
      'canApprove',
    },
    'AdvanceRequests': {
      'canView',
      'canCreate',
      'canApprove',
      'canExport',
      'canDelete',
    },
    'CashTransaction': {
      'canView',
      'canCreate',
      'canEdit',
      'canDelete',
      'canExport',
      'canApprove',
    },
    'BankAccount': {'canView', 'canCreate', 'canEdit', 'canDelete'},
    // ── QUẢN LÝ VẬN HÀNH ──
    'Asset': {'canView', 'canCreate', 'canEdit', 'canDelete', 'canExport'},
    'Task': {'canView', 'canCreate', 'canEdit', 'canDelete'},
    'Communication': {'canView', 'canCreate', 'canEdit', 'canDelete'},
    'KPI': {
      'canView',
      'canCreate',
      'canEdit',
      'canDelete',
      'canExport',
      'canApprove',
    },
    'Production': {'canView', 'canCreate', 'canEdit', 'canDelete', 'canExport'},
    'MobileDeviceRegistration': {'canView', 'canApprove'},
    'MobileAttendanceApproval': {'canView', 'canApprove'},
    'Meal': {'canView', 'canCreate', 'canEdit', 'canDelete'},
    'FieldCheckIn': {'canView', 'canCreate', 'canEdit', 'canDelete'},
    'Feedback': {'canView', 'canCreate', 'canDelete', 'canApprove'},
    // ── BÁO CÁO — chỉ xem + xuất ──
    'LeaveReport': {'canView', 'canExport'},
    'CashReport': {'canView', 'canExport'},
    'PenaltyReport': {'canView', 'canExport'},
    'AdvanceReport': {'canView', 'canExport'},
    'AssetReport': {'canView', 'canExport'},
    'AttendanceReport': {'canView', 'canExport'},
    'HrReport': {'canView', 'canExport'},
    'PayrollReport': {'canView', 'canExport'},
    // ── CÀI ĐẶT ──
    'SettingsHub': {'canView'},
    'ShiftSetup': {'canView', 'canCreate', 'canEdit', 'canDelete'},
    'MobileAttendance': {
      'canView',
      'canCreate',
      'canEdit',
      'canDelete',
      'canApprove',
    },
    'Holiday': {'canView', 'canCreate', 'canEdit', 'canDelete'},
    'Device': {
      'canView',
      'canCreate',
      'canEdit',
      'canDelete',
      'canApprove',
    },
    'Branch': {'canView', 'canCreate', 'canEdit', 'canDelete'},
    'Geofence': {'canView', 'canCreate', 'canEdit', 'canDelete'},
    'HrDocument': {'canView', 'canCreate', 'canEdit', 'canDelete'},
    'OrgChart': {'canView', 'canCreate', 'canEdit', 'canDelete'},
    'DepartmentPermission': {'canView', 'canCreate', 'canDelete'},
    'Allowance': {'canView', 'canCreate', 'canEdit', 'canDelete'},
    'PenaltySetup': {'canView', 'canCreate', 'canEdit', 'canDelete'},
    'Insurance': {'canView', 'canCreate', 'canEdit', 'canDelete'},
    'Tax': {'canView', 'canCreate', 'canEdit', 'canDelete'},
    'ProductSalary': {'canView', 'canCreate', 'canEdit', 'canDelete'},
    'UserManagement': {'canView', 'canCreate', 'canEdit', 'canDelete'},
    'Role': {'canView', 'canCreate', 'canEdit', 'canDelete'},
    'SystemSettings': {'canView', 'canEdit'},
    'NotificationSettings': {'canView', 'canEdit'},
    'AIGemini': {'canView', 'canEdit'},
    'Settings': {'canView', 'canEdit'},
  };

  /// Trả về true nếu module hỗ trợ quyền này
  static bool _moduleSupports(String? module, String permType) {
    if (module == null) return true;
    final caps = _moduleCapabilities[module];
    if (caps == null) return true; // module lạ → hiện tất cả
    return caps.contains(permType);
  }

  static List<Map<String, dynamic>> _getAllModules() {
    return [
      // ══════════ TỔNG QUAN ══════════
      {
        'id': '001',
        'module': 'Home',
        'moduleDisplayName': 'Trang chủ',
        'displayOrder': 1
      },
      {
        'id': '002',
        'module': 'Notification',
        'moduleDisplayName': 'Thông báo',
        'displayOrder': 2
      },
      // ══════════ HỒ SƠ NHÂN SỰ ══════════
      {
        'id': '075',
        'module': 'DashboardAttendanceOverview',
        'moduleDisplayName': 'Tổng quan chấm công',
        'displayOrder': 4
      },
      {
        'id': '076',
        'module': 'DashboardHrInsights',
        'moduleDisplayName': 'Chỉ số nhân sự & vận hành',
        'displayOrder': 5
      },
      {
        'id': '077',
        'module': 'DashboardTodaySchedule',
        'moduleDisplayName': 'Lịch làm việc hôm nay',
        'displayOrder': 6
      },
      {
        'id': '078',
        'module': 'DashboardRealtimeAttendance',
        'moduleDisplayName': 'Chấm công thời gian thực',
        'displayOrder': 7
      },
      {
        'id': '079',
        'module': 'DashboardAbsent',
        'moduleDisplayName': 'Nhân viên vắng mặt',
        'displayOrder': 8
      },
      {
        'id': '080',
        'module': 'DashboardLateEarly',
        'moduleDisplayName': 'Đi trễ / về sớm',
        'displayOrder': 9
      },
      {
        'id': '081',
        'module': 'DashboardKpiPanel',
        'moduleDisplayName': 'KPI (Dashboard)',
        'displayOrder': 10
      },
      {
        'id': '082',
        'module': 'DashboardInternalNews',
        'moduleDisplayName': 'Bản tin nội bộ',
        'displayOrder': 11
      },
      {
        'id': '004',
        'module': 'Employee',
        'moduleDisplayName': 'Hồ sơ nhân sự',
        'displayOrder': 4
      },
      {
        'id': '005',
        'module': 'DeviceUser',
        'moduleDisplayName': 'Nhân sự chấm công',
        'displayOrder': 5
      },
      {
        'id': '006',
        'module': 'Department',
        'moduleDisplayName': 'Phòng ban',
        'displayOrder': 6
      },
      {
        'id': '007',
        'module': 'Leave',
        'moduleDisplayName': 'Nghỉ phép',
        'displayOrder': 7
      },
      {
        'id': '008',
        'module': 'SalarySettings',
        'moduleDisplayName': 'Thiết lập lương',
        'displayOrder': 8
      },
      {
        'id': '007b',
        'module': 'Payslip',
        'moduleDisplayName': 'Phiếu lương',
        'displayOrder': 8
      },
      // ══════════ CHẤM CÔNG ══════════
      {
        'id': '009',
        'module': 'Attendance',
        'moduleDisplayName': 'Chấm công thô',
        'displayOrder': 9
      },
      {
        'id': '010',
        'module': 'WorkSchedule',
        'moduleDisplayName': 'Lịch làm việc',
        'displayOrder': 10
      },
      {
        'id': '011',
        'module': 'AttendanceSummary',
        'moduleDisplayName': 'Tổng hợp chấm công',
        'displayOrder': 11
      },
      {
        'id': '012',
        'module': 'AttendanceByShift',
        'moduleDisplayName': 'Tổng hợp chấm công theo ca',
        'displayOrder': 12
      },
      {
        'id': '012b',
        'module': 'AttendanceCorrection',
        'moduleDisplayName': 'Chỉnh sửa chấm công',
        'displayOrder': 12
      },
      {
        'id': '013',
        'module': 'AttendanceApproval',
        'moduleDisplayName': 'Duyệt chấm công',
        'displayOrder': 13
      },
      {
        'id': '047b',
        'module': 'MobileAttendanceApproval',
        'moduleDisplayName': 'Duyệt chấm công Mobile',
        'displayOrder': 47
      },
      {
        'id': '014',
        'module': 'ScheduleApproval',
        'moduleDisplayName': 'Duyệt lịch làm việc',
        'displayOrder': 14
      },
      {
        'id': '015',
        'module': 'Payroll',
        'moduleDisplayName': 'Tổng hợp lương',
        'displayOrder': 15
      },
      {
        'id': '021b',
        'module': 'Overtime',
        'moduleDisplayName': 'Tăng ca',
        'displayOrder': 21
      },
      {
        'id': '024b',
        'module': 'ShiftSwap',
        'moduleDisplayName': 'Đổi ca',
        'displayOrder': 24
      },
      // ══════════ TÀI CHÍNH ══════════
      {
        'id': '016',
        'module': 'BonusPenalty',
        'moduleDisplayName': 'Phiếu thưởng',
        'displayOrder': 16
      },
      {
        'id': '043',
        'module': 'PenaltyTickets',
        'moduleDisplayName': 'Phiếu phạt',
        'displayOrder': 43
      },
      {
        'id': '017',
        'module': 'AdvanceRequests',
        'moduleDisplayName': 'Ứng lương',
        'displayOrder': 17
      },
      {
        'id': '018',
        'module': 'CashTransaction',
        'moduleDisplayName': 'Thu chi',
        'displayOrder': 18
      },
      // ══════════ QUẢN LÝ VẬN HÀNH ══════════
      {
        'id': '019',
        'module': 'Asset',
        'moduleDisplayName': 'Tài sản',
        'displayOrder': 19
      },
      {
        'id': '020',
        'module': 'Task',
        'moduleDisplayName': 'Công việc',
        'displayOrder': 20
      },
      {
        'id': '021',
        'module': 'Communication',
        'moduleDisplayName': 'Truyền thông',
        'displayOrder': 21
      },
      {
        'id': '022',
        'module': 'KPI',
        'moduleDisplayName': 'KPI',
        'displayOrder': 22
      },
      {
        'id': '044',
        'module': 'Production',
        'moduleDisplayName': 'Sản lượng',
        'displayOrder': 43
      },
      {
        'id': '045',
        'module': 'MobileDeviceRegistration',
        'moduleDisplayName': 'Đăng ký chấm công Mobile',
        'displayOrder': 46
      },
      {
        'id': '047',
        'module': 'Meal',
        'moduleDisplayName': 'Chấm cơm',
        'displayOrder': 48
      },
      {
        'id': '048',
        'module': 'FieldCheckIn',
        'moduleDisplayName': 'Check-in điểm bán',
        'displayOrder': 49
      },
      // ══════════ BÁO CÁO ══════════
      {
        'id': '051',
        'module': 'LeaveReport',
        'moduleDisplayName': 'Báo cáo nghỉ phép',
        'displayOrder': 51
      },
      {
        'id': '052',
        'module': 'CashReport',
        'moduleDisplayName': 'Báo cáo thu chi',
        'displayOrder': 52
      },
      {
        'id': '053',
        'module': 'PenaltyReport',
        'moduleDisplayName': 'Báo cáo phạt',
        'displayOrder': 53
      },
      {
        'id': '054',
        'module': 'AdvanceReport',
        'moduleDisplayName': 'Báo cáo ứng lương',
        'displayOrder': 54
      },
      {
        'id': '055',
        'module': 'AssetReport',
        'moduleDisplayName': 'Báo cáo tài sản',
        'displayOrder': 55
      },
      {
        'id': '056',
        'module': 'AttendanceReport',
        'moduleDisplayName': 'Báo cáo chấm công',
        'displayOrder': 56
      },
      {
        'id': '057',
        'module': 'HrReport',
        'moduleDisplayName': 'Báo cáo nhân sự',
        'displayOrder': 57
      },
      {
        'id': '058',
        'module': 'PayrollReport',
        'moduleDisplayName': 'Báo cáo lương',
        'displayOrder': 58
      },
      {
        'id': '059',
        'module': 'HrDocument',
        'moduleDisplayName': 'Tài liệu HR',
        'displayOrder': 59
      },
      {
        'id': '060',
        'module': 'OrgChart',
        'moduleDisplayName': 'Sơ đồ tổ chức',
        'displayOrder': 60
      },
      {
        'id': '061',
        'module': 'Branch',
        'moduleDisplayName': 'Chi nhánh',
        'displayOrder': 61
      },
      {
        'id': '062',
        'module': 'Geofence',
        'moduleDisplayName': 'Vùng chấm công',
        'displayOrder': 62
      },
      {
        'id': '063',
        'module': 'BankAccount',
        'moduleDisplayName': 'Tài khoản ngân hàng',
        'displayOrder': 63
      },
      {
        'id': '064',
        'module': 'DepartmentPermission',
        'moduleDisplayName': 'PQ Phòng ban',
        'displayOrder': 64
      },
      // ══════════ CÀI ĐẶT ══════════
      {
        'id': '026',
        'module': 'SettingsHub',
        'moduleDisplayName': 'Thiết lập HRM',
        'displayOrder': 26
      },
      {
        'id': '027',
        'module': 'ShiftSetup',
        'moduleDisplayName': 'Thiết lập ca',
        'displayOrder': 27
      },
      {
        'id': '028',
        'module': 'MobileAttendance',
        'moduleDisplayName': 'Chấm công Mobile',
        'displayOrder': 28
      },
      {
        'id': '029',
        'module': 'Holiday',
        'moduleDisplayName': 'Ngày lễ',
        'displayOrder': 29
      },
      {
        'id': '030',
        'module': 'Device',
        'moduleDisplayName': 'Máy chấm công',
        'displayOrder': 30
      },
      {
        'id': '031',
        'module': 'Allowance',
        'moduleDisplayName': 'Phụ cấp',
        'displayOrder': 31
      },
      {
        'id': '032',
        'module': 'PenaltySetup',
        'moduleDisplayName': 'Phạt',
        'displayOrder': 32
      },
      {
        'id': '033',
        'module': 'Insurance',
        'moduleDisplayName': 'Bảo hiểm',
        'displayOrder': 33
      },
      {
        'id': '034',
        'module': 'Tax',
        'moduleDisplayName': 'Thuế TNCN',
        'displayOrder': 34
      },
      {
        'id': '049',
        'module': 'ProductSalary',
        'moduleDisplayName': 'Lương sản phẩm',
        'displayOrder': 44
      },
      {
        'id': '050',
        'module': 'Feedback',
        'moduleDisplayName': 'Phản ánh / Ý kiến',
        'displayOrder': 45
      },
      {
        'id': '035',
        'module': 'UserManagement',
        'moduleDisplayName': 'Tài khoản',
        'displayOrder': 35
      },
      {
        'id': '036',
        'module': 'Role',
        'moduleDisplayName': 'Phân quyền',
        'displayOrder': 36
      },
      {
        'id': '038',
        'module': 'SystemSettings',
        'moduleDisplayName': 'Hệ thống',
        'displayOrder': 38
      },
      {
        'id': '039',
        'module': 'NotificationSettings',
        'moduleDisplayName': 'Thiết lập thông báo',
        'displayOrder': 39
      },
      {
        'id': '041',
        'module': 'AIGemini',
        'moduleDisplayName': 'Thiết lập AI',
        'displayOrder': 41
      },
      {
        'id': '042',
        'module': 'Settings',
        'moduleDisplayName': 'Cài đặt',
        'displayOrder': 42
      },
    ];
  }

  Future<void> _selectRole(String roleName) async {
    setState(() {
      _selectedRoleName = roleName;
      _isLoadingPermissions = true;
    });

    try {
      // Check if we already have permissions loaded from getRoles() (GET /all)
      final existingRole = _roles.firstWhere(
        (r) =>
            r['roleName'] == roleName &&
            r['permissions'] != null &&
            (r['permissions'] as List).isNotEmpty,
        orElse: () => {},
      );

      if (existingRole.isNotEmpty) {
        setState(() {
          _selectedRolePermissions = Map<String, dynamic>.from(existingRole);
        });
      } else {
        final permissions = await _apiService.getRolePermissions(roleName);
        if (permissions.isNotEmpty && permissions.containsKey('permissions')) {
          setState(() {
            _selectedRolePermissions = Map<String, dynamic>.from(permissions);
          });
        } else {
          _loadSamplePermissions(roleName);
        }
      }
    } catch (e) {
      // Use sample permissions
      _loadSamplePermissions(roleName);
    } finally {
      if (_selectedRolePermissions != null) {
        _normalizeLoadedPermissions();
      }
      setState(() => _isLoadingPermissions = false);
      _updateEmbeddedBack();
    }
  }

  /// Gộp module mới từ API catalog; đồng bộ quyền Dashboard legacy → từng widget.
  void _normalizeLoadedPermissions() {
    if (_selectedRolePermissions == null) return;
    final catalog =
        _ensureUiModules(_modules.isNotEmpty ? _modules : _getAllModules());
    final permissions = List<Map<String, dynamic>>.from(
        _selectedRolePermissions!['permissions'] ?? []);

    for (final m in catalog) {
      final mod = m['module'] as String?;
      if (mod == null || mod == DashboardPermissionModules.legacyDashboard) {
        continue;
      }
      if (permissions.any((p) => p['module'] == mod)) continue;
      permissions.add({
        'permissionId': m['id'],
        'module': mod,
        'moduleDisplayName': m['moduleDisplayName'],
        'displayOrder': m['displayOrder'],
        'canView': false,
        'canCreate': false,
        'canEdit': false,
        'canDelete': false,
        'canExport': false,
        'canApprove': false,
      });
    }

    Map<String, dynamic>? legacy;
    for (final p in permissions) {
      if (p['module'] == DashboardPermissionModules.legacyDashboard) {
        legacy = p;
        break;
      }
    }
    if (legacy != null && legacy['canView'] == true) {
      for (final code in DashboardPermissionModules.allWidgets) {
        final idx = permissions.indexWhere((p) => p['module'] == code);
        if (idx >= 0) {
          permissions[idx] = Map<String, dynamic>.from(permissions[idx]);
          permissions[idx]['canView'] = true;
        }
      }
    }

    // Ẩn module Dashboard cũ trên UI — quyền đã map sang từng widget.
    permissions.removeWhere(
      (p) => p['module'] == DashboardPermissionModules.legacyDashboard,
    );

    for (var i = 0; i < permissions.length; i++) {
      final mod = permissions[i]['module'] as String?;
      final uiName = PermissionModuleLabels.forModule(mod);
      if (uiName == null) continue;
      permissions[i] = Map<String, dynamic>.from(permissions[i]);
      permissions[i]['moduleDisplayName'] = uiName;
    }

    _selectedRolePermissions!['permissions'] = permissions;
  }

  void _loadSamplePermissions(String roleName) {
    final roleDisplay = _roles.firstWhere(
      (r) => r['roleName'] == roleName,
      orElse: () => {'roleDisplayName': roleName},
    )['roleDisplayName'];

    final modules = _modules.isNotEmpty ? _modules : _getAllModules();

    setState(() {
      _selectedRolePermissions = {
        'roleName': roleName,
        'roleDisplayName': roleDisplay,
        'permissions': modules.map((m) {
          final perm = _getDefaultPermission(roleName, m['module'] as String);
          return {
            'permissionId': m['id'],
            'module': m['module'],
            'moduleDisplayName': m['moduleDisplayName'],
            'displayOrder': m['displayOrder'],
            ...perm,
          };
        }).toList(),
      };
    });
  }

  static Map<String, bool> _getDefaultPermission(
      String roleName, String module) {
    switch (roleName.toLowerCase()) {
      case 'admin':
        return {
          'canView': true,
          'canCreate': true,
          'canEdit': true,
          'canDelete': true,
          'canExport': true,
          'canApprove': true
        };

      case 'director':
        if (['Settings', 'Device', 'Geofence', 'DeviceUser'].contains(module)) {
          return {
            'canView': true,
            'canCreate': false,
            'canEdit': false,
            'canDelete': false,
            'canExport': false,
            'canApprove': false
          };
        }
        if (['Store', 'Role', 'UserManagement'].contains(module)) {
          return {
            'canView': true,
            'canCreate': false,
            'canEdit': false,
            'canDelete': false,
            'canExport': true,
            'canApprove': false
          };
        }
        return {
          'canView': true,
          'canCreate': true,
          'canEdit': true,
          'canDelete': true,
          'canExport': true,
          'canApprove': true
        };

      case 'accountant':
        if ([
          'Salary',
          'Payslip',
          'Allowance',
          'Insurance',
          'Tax',
          'Advance',
          'Transaction',
          'CashTransaction',
          'BankAccount',
          'Benefit'
        ].contains(module)) {
          return {
            'canView': true,
            'canCreate': true,
            'canEdit': true,
            'canDelete': true,
            'canExport': true,
            'canApprove': false
          };
        }
        if (['Report', 'Employee', 'Attendance'].contains(module)) {
          return {
            'canView': true,
            'canCreate': false,
            'canEdit': false,
            'canDelete': false,
            'canExport': true,
            'canApprove': false
          };
        }
        if (_isLegacyDashboardModule(module) ||
            [
              'Leave',
              'Shift',
              'Holiday',
              'Overtime',
              'Notification'
            ].contains(module)) {
          return {
            'canView': true,
            'canCreate': false,
            'canEdit': false,
            'canDelete': false,
            'canExport': false,
            'canApprove': false
          };
        }
        return {
          'canView': false,
          'canCreate': false,
          'canEdit': false,
          'canDelete': false,
          'canExport': false,
          'canApprove': false
        };

      case 'departmenthead':
        if ([
          'Employee',
          'Attendance',
          'Leave',
          'Shift',
          'Overtime',
          'AttendanceCorrection',
          'WorkSchedule',
          'ShiftSwap',
          'Task',
          'KPI',
          'HrDocument'
        ].contains(module)) {
          return {
            'canView': true,
            'canCreate': true,
            'canEdit': true,
            'canDelete': false,
            'canExport': true,
            'canApprove': true
          };
        }
        if (['Notification', 'Communication'].contains(module)) {
          return {
            'canView': true,
            'canCreate': true,
            'canEdit': false,
            'canDelete': false,
            'canExport': false,
            'canApprove': false
          };
        }
        if (['Report', 'Salary', 'Payslip'].contains(module)) {
          return {
            'canView': true,
            'canCreate': false,
            'canEdit': false,
            'canDelete': false,
            'canExport': true,
            'canApprove': false
          };
        }
        if (_isLegacyDashboardModule(module) ||
            [
              'Allowance',
              'Holiday',
              'Insurance',
              'Advance',
              'ShiftTemplate',
              'ShiftSalaryLevel',
              'Benefit',
              'Asset',
              'OrgChart',
              'Department'
            ].contains(module)) {
          return {
            'canView': true,
            'canCreate': false,
            'canEdit': false,
            'canDelete': false,
            'canExport': false,
            'canApprove': false
          };
        }
        return {
          'canView': false,
          'canCreate': false,
          'canEdit': false,
          'canDelete': false,
          'canExport': false,
          'canApprove': false
        };

      case 'manager':
        if (['Settings', 'Store', 'Role'].contains(module)) {
          return {
            'canView': true,
            'canCreate': false,
            'canEdit': false,
            'canDelete': false,
            'canExport': false,
            'canApprove': false
          };
        }
        return {
          'canView': true,
          'canCreate': true,
          'canEdit': true,
          'canDelete': false,
          'canExport': true,
          'canApprove': true
        };

      case 'employee':
        if (_isLegacyDashboardModule(module) ||
            ['Attendance', 'Payslip', 'Shift', 'Notification'].contains(module)) {
          return {
            'canView': true,
            'canCreate': false,
            'canEdit': false,
            'canDelete': false,
            'canExport': false,
            'canApprove': false
          };
        }
        if (['Leave', 'ShiftSwap', 'AttendanceCorrection', 'Overtime']
            .contains(module)) {
          return {
            'canView': true,
            'canCreate': true,
            'canEdit': false,
            'canDelete': false,
            'canExport': false,
            'canApprove': false
          };
        }
        if (module == 'Task') {
          return {
            'canView': true,
            'canCreate': false,
            'canEdit': true,
            'canDelete': false,
            'canExport': false,
            'canApprove': false
          };
        }
        return {
          'canView': false,
          'canCreate': false,
          'canEdit': false,
          'canDelete': false,
          'canExport': false,
          'canApprove': false
        };

      case 'user':
        if (_isLegacyDashboardModule(module)) {
          return {
            'canView': true,
            'canCreate': false,
            'canEdit': false,
            'canDelete': false,
            'canExport': false,
            'canApprove': false
          };
        }
        return {
          'canView': false,
          'canCreate': false,
          'canEdit': false,
          'canDelete': false,
          'canExport': false,
          'canApprove': false
        };

      default:
        return {
          'canView': false,
          'canCreate': false,
          'canEdit': false,
          'canDelete': false,
          'canExport': false,
          'canApprove': false
        };
    }
  }

  Future<void> _savePermissions() async {
    if (_selectedRolePermissions == null) return;
    if (!_perm.canEdit('Role')) return;

    setState(() => _isSaving = true);
    try {
      await _apiService.saveRolePermissions(_selectedRolePermissions!);
      appNotification.showSuccess(
        title: 'Thành công',
        message:
            'Đã lưu phân quyền cho ${_selectedRolePermissions!['roleDisplayName']}',
      );
      _loadData(); // Reload to update permission count
    } catch (e) {
      appNotification.showError(
        title: 'Lỗi',
        message: 'Không thể lưu phân quyền: $e',
      );
    } finally {
      setState(() => _isSaving = false);
    }
  }

  void _togglePermission(int index, String permissionType) {
    if (_selectedRolePermissions == null) return;

    setState(() {
      final permissions = List<Map<String, dynamic>>.from(
          _selectedRolePermissions!['permissions']);
      permissions[index] = Map<String, dynamic>.from(permissions[index]);
      permissions[index][permissionType] =
          !(permissions[index][permissionType] ?? false);
      _selectedRolePermissions!['permissions'] = permissions;
    });
  }

  void _toggleAllForModule(int index, bool value) {
    if (_selectedRolePermissions == null) return;

    setState(() {
      final permissions = List<Map<String, dynamic>>.from(
          _selectedRolePermissions!['permissions']);
      permissions[index] = Map<String, dynamic>.from(permissions[index]);
      final mod = permissions[index]['module'] as String?;
      if (_moduleSupports(mod, 'canView')) {
        permissions[index]['canView'] = value;
      }
      if (_moduleSupports(mod, 'canCreate')) {
        permissions[index]['canCreate'] = value;
      }
      if (_moduleSupports(mod, 'canEdit')) {
        permissions[index]['canEdit'] = value;
      }
      if (_moduleSupports(mod, 'canDelete')) {
        permissions[index]['canDelete'] = value;
      }
      if (_moduleSupports(mod, 'canExport')) {
        permissions[index]['canExport'] = value;
      }
      if (_moduleSupports(mod, 'canApprove')) {
        permissions[index]['canApprove'] = value;
      }
      _selectedRolePermissions!['permissions'] = permissions;
    });
  }

  void _setAllPermissions(String permissionType, bool value) {
    if (_selectedRolePermissions == null) return;

    setState(() {
      final permissions = List<Map<String, dynamic>>.from(
          _selectedRolePermissions!['permissions']);
      for (int i = 0; i < permissions.length; i++) {
        permissions[i] = Map<String, dynamic>.from(permissions[i]);
        permissions[i][permissionType] = value;
      }
      _selectedRolePermissions!['permissions'] = permissions;
    });
  }

  // Chọn tất cả quyền cho role
  void _selectAllPermissions() {
    if (_selectedRolePermissions == null) return;

    setState(() {
      final permissions = List<Map<String, dynamic>>.from(
          _selectedRolePermissions!['permissions']);
      for (int i = 0; i < permissions.length; i++) {
        permissions[i] = Map<String, dynamic>.from(permissions[i]);
        permissions[i]['canView'] = true;
        permissions[i]['canCreate'] = true;
        permissions[i]['canEdit'] = true;
        permissions[i]['canDelete'] = true;
        permissions[i]['canExport'] = true;
        permissions[i]['canApprove'] = true;
      }
      _selectedRolePermissions!['permissions'] = permissions;
    });
  }

  List<Map<String, dynamic>> _allPermissions() =>
      List<Map<String, dynamic>>.from(
          _selectedRolePermissions!['permissions'] ?? []);

  List<Map<String, dynamic>> _visiblePermissions() {
    var list = PermissionRoleCatalog.sortForUi(_allPermissions());
    if (_filterGroupId != null) {
      final g = PermissionRoleCatalog.groupById(_filterGroupId!);
      if (g != null) {
        final codes = g.moduleCodes.toSet();
        list = list.where((p) => codes.contains(p['module'])).toList();
      }
    }
    return list;
  }

  int _permissionIndex(String module) {
    final permissions = _allPermissions();
    return permissions.indexWhere((p) => p['module'] == module);
  }

  void _applyGroup(String groupId, PermissionBundleLevel level) {
    final g = PermissionRoleCatalog.groupById(groupId);
    if (g == null || _selectedRolePermissions == null) return;
    setState(() {
      final permissions = _allPermissions();
      PermissionRoleCatalog.applyToPermissionsList(
        permissions,
        moduleCodes: g.moduleCodes,
        level: level,
        moduleSupports: _moduleSupports,
      );
      _selectedRolePermissions!['permissions'] = permissions;
    });
  }

  String _levelLabel(PermissionBundleLevel level) {
    switch (level) {
      case PermissionBundleLevel.none:
        return 'Tắt';
      case PermissionBundleLevel.viewOnly:
        return 'Chỉ xem';
      case PermissionBundleLevel.operate:
        return 'Vận hành';
      case PermissionBundleLevel.full:
        return 'Toàn quyền';
    }
  }

  Widget _buildGroupFilterBar() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: const BoxDecoration(
        color: Color(0xFFF8FAFC),
        border: Border(bottom: BorderSide(color: Color(0xFFE4E4E7))),
      ),
      child: Row(
        children: [
          const Text('Lọc nhóm:',
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF52525B))),
          const SizedBox(width: 8),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  FilterChip(
                    label: const Text('Tất cả'),
                    selected: _filterGroupId == null,
                    onSelected: (_) => setState(() => _filterGroupId = null),
                  ),
                  const SizedBox(width: 6),
                  for (final g in PermissionRoleCatalog.groups)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: FilterChip(
                        avatar: Icon(g.icon, size: 16, color: g.color),
                        label: Text(g.title),
                        selected: _filterGroupId == g.id,
                        onSelected: (_) =>
                            setState(() => _filterGroupId = g.id),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPermissionRow(Map<String, dynamic> perm) {
    final modKey = perm['module'] as String?;
    final globalIndex = _permissionIndex(modKey ?? '');
    if (globalIndex < 0) return const SizedBox.shrink();

    final supportedDesktop = [
      'canView',
      'canCreate',
      'canEdit',
      'canDelete',
      'canExport',
      'canApprove',
    ].where((p) => _moduleSupports(modKey, p));
    final allChecked = supportedDesktop.isNotEmpty &&
        supportedDesktop.every((p) => perm[p] == true);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          SizedBox(
            width: 200,
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: _getModuleColor(perm['module'])
                        .withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Icon(
                    _getModuleIcon(perm['module']),
                    size: 16,
                    color: _getModuleColor(perm['module']),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    perm['moduleDisplayName'] ?? perm['module'],
                    style: const TextStyle(fontWeight: FontWeight.w500),
                  ),
                ),
              ],
            ),
          ),
          _buildPermissionCheckbox(globalIndex, 'canView', perm['canView'] ?? false,
              supported: _moduleSupports(modKey, 'canView')),
          _buildPermissionCheckbox(globalIndex, 'canCreate', perm['canCreate'] ?? false,
              supported: _moduleSupports(modKey, 'canCreate')),
          _buildPermissionCheckbox(globalIndex, 'canEdit', perm['canEdit'] ?? false,
              supported: _moduleSupports(modKey, 'canEdit')),
          _buildPermissionCheckbox(globalIndex, 'canDelete', perm['canDelete'] ?? false,
              supported: _moduleSupports(modKey, 'canDelete')),
          _buildPermissionCheckbox(globalIndex, 'canExport', perm['canExport'] ?? false,
              supported: _moduleSupports(modKey, 'canExport')),
          _buildPermissionCheckbox(globalIndex, 'canApprove', perm['canApprove'] ?? false,
              supported: _moduleSupports(modKey, 'canApprove')),
          SizedBox(
            width: 90,
            child: Center(
              child: Checkbox(
                value: allChecked,
                onChanged: _perm.canEdit('Role')
                    ? (value) =>
                        _toggleAllForModule(globalIndex, value ?? false)
                    : null,
                activeColor: HrmPageChrome.primaryNavy,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGroupedPermissionSections() {
    final visible = _visiblePermissions();
    final byGroup = <String, List<Map<String, dynamic>>>{};
    for (final p in visible) {
      final gid =
          PermissionRoleCatalog.groupIdForModule(p['module'] as String?) ??
              'other';
      byGroup.putIfAbsent(gid, () => []).add(p);
    }

    final sectionOrder = [
      ...PermissionRoleCatalog.groups.map((g) => g.id),
      'other',
    ];

    return Column(
      children: [
        for (final gid in sectionOrder)
          if (byGroup.containsKey(gid)) ...[
            _buildGroupSectionHeader(gid, byGroup[gid]!),
            ...byGroup[gid]!.map(_buildPermissionRow),
            const Divider(height: 1, color: Color(0xFFE4E4E7)),
          ],
      ],
    );
  }

  Widget _buildGroupSectionHeader(
      String groupId, List<Map<String, dynamic>> items) {
    final g = PermissionRoleCatalog.groupById(groupId);
    final title = g?.title ?? 'Khác';
    final desc = g?.description ?? '';
    final color = g?.color ?? const Color(0xFF94A3B8);
    final icon = g?.icon ?? Icons.folder_outlined;
    final enabledCount =
        items.where((p) => p['canView'] == true).length;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: color.withValues(alpha: 0.06),
      child: Row(
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                        color: color)),
                if (desc.isNotEmpty)
                  Text(desc,
                      style: const TextStyle(
                          fontSize: 11, color: Color(0xFF71717A))),
              ],
            ),
          ),
          Text('$enabledCount/${items.length}',
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: color)),
          const SizedBox(width: 8),
          PopupMenuButton<PermissionBundleLevel>(
            tooltip: 'Áp dụng cho cả nhóm',
            icon: Icon(Icons.more_vert, size: 20, color: color),
            onSelected: (level) {
              if (g != null) _applyGroup(g.id, level);
            },
            itemBuilder: (_) => [
              const PopupMenuItem(
                  value: PermissionBundleLevel.viewOnly,
                  child: Text('Nhóm: Chỉ xem')),
              const PopupMenuItem(
                  value: PermissionBundleLevel.operate,
                  child: Text('Nhóm: Vận hành')),
              const PopupMenuItem(
                  value: PermissionBundleLevel.full,
                  child: Text('Nhóm: Toàn quyền')),
              const PopupMenuItem(
                  value: PermissionBundleLevel.none,
                  child: Text('Nhóm: Tắt hết')),
            ],
          ),
        ],
      ),
    );
  }

  // Bỏ tất cả quyền cho role
  void _deselectAllPermissions() {
    if (_selectedRolePermissions == null) return;

    setState(() {
      final permissions = List<Map<String, dynamic>>.from(
          _selectedRolePermissions!['permissions']);
      for (int i = 0; i < permissions.length; i++) {
        permissions[i] = Map<String, dynamic>.from(permissions[i]);
        permissions[i]['canView'] = false;
        permissions[i]['canCreate'] = false;
        permissions[i]['canEdit'] = false;
        permissions[i]['canDelete'] = false;
        permissions[i]['canExport'] = false;
        permissions[i]['canApprove'] = false;
      }
      _selectedRolePermissions!['permissions'] = permissions;
    });
  }

  void _showAddRoleDialog() {
    final nameController = TextEditingController();
    final displayNameController = TextEditingController();
    final isMobile = Responsive.isMobile(context);
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => ScrollableAlertDialog(
        insetPadding: isMobile
            ? EdgeInsets.zero
            : const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(isMobile ? 0 : 16)),
        title: const Text('Thêm chức danh mới'),
        content: SizedBox(
          width: isMobile ? double.infinity : null,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(
                  labelText: 'Mã chức danh',
                  hintText: 'VD: HRManager, HRSettings...',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: displayNameController,
                decoration: const InputDecoration(
                  labelText: 'Tên hiển thị',
                  hintText: 'VD: HR tổng quan, HR thiết lập...',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: () async {
              if (nameController.text.isEmpty ||
                  displayNameController.text.isEmpty) {
                appNotification.showWarning(
                    title: 'Cảnh báo',
                    message: 'Vui lòng nhập đầy đủ thông tin');
                return;
              }

              // Check if role already exists
              final exists =
                  _roles.any((r) => r['roleName'] == nameController.text);
              if (exists) {
                appNotification.showWarning(
                    title: 'Cảnh báo',
                    message: 'Chức danh "${nameController.text}" đã tồn tại');
                return;
              }

              Navigator.pop(context);

              final defaultModules = _getAllModules();
              final permRows = defaultModules
                  .map((m) => {
                        'permissionId': m['id'],
                        'module': m['module'],
                        'canView': false,
                        'canCreate': false,
                        'canEdit': false,
                        'canDelete': false,
                        'canExport': false,
                        'canApprove': false,
                      })
                  .toList();

              final permissions = permRows
                  .map((p) => {
                        'permissionId': p['permissionId'],
                        'canView': p['canView'],
                        'canCreate': p['canCreate'],
                        'canEdit': p['canEdit'],
                        'canDelete': p['canDelete'],
                        'canExport': p['canExport'],
                        'canApprove': p['canApprove'],
                      })
                  .toList();

              final result = await _apiService.saveRolePermissions({
                'roleName': nameController.text,
                'permissions': permissions,
              });

              if (result['isSuccess'] == true ||
                  (result['statusCode'] != null &&
                      result['statusCode'] < 400)) {
                // Add new role to local list
                setState(() {
                  _roles.add({
                    'roleName': nameController.text,
                    'roleDisplayName': displayNameController.text,
                    'permissionCount': 0,
                  });
                });
                _selectRole(nameController.text);
                appNotification.showSuccess(
                    title: 'Thành công',
                    message:
                        'Đã tạo chức danh "${displayNameController.text}"');
              } else {
                appNotification.showError(
                    title: 'Lỗi',
                    message: result['message'] ?? 'Không thể tạo chức danh');
              }
            },
            style: FilledButton.styleFrom(
              backgroundColor: HrmPageChrome.primaryNavy,
            ),
            child: const Text('Thêm'),
          ),
        ],
      ),
      ),
    );
  }

  Future<void> _deleteRole(String roleName) async {
    if (!_perm.canDelete('Role')) return;
    final defaultRoles = [
      'Admin',
      'Director',
      'Accountant',
      'DepartmentHead',
      'Manager',
      'Employee',
      'User'
    ];
    if (defaultRoles.contains(roleName)) {
      appNotification.showWarning(
        title: 'Không thể xóa',
        message: 'Không thể xóa chức danh mặc định của hệ thống',
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => ScrollableAlertDialog(
        title: const Text('Xác nhận xóa'),
        content: Text(
            'Bạn có chắc muốn xóa chức danh "$roleName" và tất cả quyền liên quan?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFEF4444)),
            child: const Text('Xóa'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      final result = await _apiService.deleteRole(roleName);
      if (result['isSuccess'] == true) {
        appNotification.showSuccess(
          title: 'Thành công',
          message: 'Đã xóa chức danh "$roleName"',
        );
        setState(() {
          _roles.removeWhere((r) => r['roleName'] == roleName);
          if (_selectedRoleName == roleName) {
            _selectedRoleName = null;
            _selectedRolePermissions = null;
          }
        });
      } else {
        appNotification.showError(
          title: 'Lỗi',
          message: result['message'] ?? 'Không thể xóa chức danh',
        );
      }
    } catch (e) {
      appNotification.showError(
        title: 'Lỗi',
        message: 'Không thể xóa chức danh: $e',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final saveAction = _selectedRolePermissions != null && _perm.canEdit('Role')
        ? Padding(
            padding: const EdgeInsets.only(right: 16),
            child: FilledButton.icon(
              onPressed: _isSaving ? null : _savePermissions,
              icon: _isSaving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.save, size: 18),
              label: Text(_isSaving ? 'Đang lưu...' : 'Lưu thay đổi'),
              style: FilledButton.styleFrom(
                backgroundColor: HrmPageChrome.primaryNavy,
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              ),
            ),
          )
        : null;

    final body = _isLoading
        ? const LoadingWidget()
        : Column(
            children: [
              if (HrmPageChrome.isEmbedded)
                HrmPageChrome.embeddedActionBar(
                  actions: saveAction != null ? [saveAction] : [],
                ),
              Expanded(
                child: Responsive.isMobile(context)
                    ? _buildMobileBody()
                    : Row(
                  children: [
                    // Left sidebar - Role list
                    Container(
                      width: 280,
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        border:
                            Border(right: BorderSide(color: Color(0xFFE4E4E7))),
                      ),
                      child: Column(
                        children: [
                          // Header
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: const BoxDecoration(
                              border: Border(
                                  bottom: BorderSide(color: Color(0xFFE4E4E7))),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: HrmPageChrome.primaryNavy
                                        .withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: const Icon(Icons.badge,
                                      color: HrmPageChrome.primaryNavy, size: 20),
                                ),
                                const SizedBox(width: 12),
                                const Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Chức danh',
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 15,
                                          color: Color(0xFF18181B),
                                        ),
                                      ),
                                      Text(
                                        'Chọn để phân quyền',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Color(0xFF71717A),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                if (_perm.canCreate('Role'))
                                  IconButton(
                                    onPressed: _showAddRoleDialog,
                                    icon: const Icon(Icons.add_circle,
                                        color: HrmPageChrome.primaryNavy),
                                    tooltip: 'Thêm chức danh',
                                  ),
                              ],
                            ),
                          ),
                          // Role list
                          Expanded(
                            child: ListView.builder(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              itemCount: _roles.length,
                              itemBuilder: (context, index) {
                                final role = _roles[index];
                                final isSelected =
                                    role['roleName'] == _selectedRoleName;
                                return _buildRoleItem(role, isSelected);
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Right content - Permissions table
                    Expanded(
                      child: _selectedRolePermissions == null
                          ? const Center(
                              child: Text(
                                'Chọn một chức danh để xem và chỉnh sửa quyền',
                                style: TextStyle(color: Color(0xFF71717A)),
                              ),
                            )
                          : _isLoadingPermissions
                              ? const LoadingWidget()
                              : _buildPermissionsTable(),
                    ),
                  ],
                ),
              ),
            ],
          );

    if (HrmPageChrome.isEmbedded) {
      return ColoredBox(color: HrmPageChrome.background, child: body);
    }
    return Scaffold(
      backgroundColor: HrmPageChrome.background,
      appBar: HrmPageChrome.appBar(
        title: 'Phân quyền Chức danh',
        actions: saveAction != null ? [saveAction] : null,
      ),
      body: body,
    );
  }

  // ===== MOBILE BODY =====
  Widget _buildMobileBody() {
    if (_selectedRolePermissions == null) {
      // Step 1: Show role list
      return Column(
        children: [
          if (HrmPageChrome.isEmbedded)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              color: Colors.white,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (_perm.canCreate('Role'))
                    IconButton(
                      onPressed: _showAddRoleDialog,
                      icon: const Icon(Icons.add_circle,
                          color: HrmPageChrome.primaryNavy),
                      tooltip: 'Thêm chức danh',
                    ),
                ],
              ),
            )
          else
            Container(
              padding: const EdgeInsets.all(16),
              decoration: const BoxDecoration(
                color: Colors.white,
                border: Border(bottom: BorderSide(color: Color(0xFFE4E4E7))),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: HrmPageChrome.primaryNavy.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.badge,
                        color: HrmPageChrome.primaryNavy, size: 20),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Chức danh',
                            style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                                color: Color(0xFF18181B))),
                        Text('Chọn để phân quyền',
                            style: TextStyle(
                                fontSize: 12, color: Color(0xFF71717A))),
                      ],
                    ),
                  ),
                  if (_perm.canCreate('Role'))
                    IconButton(
                      onPressed: _showAddRoleDialog,
                      icon: const Icon(Icons.add_circle,
                          color: HrmPageChrome.primaryNavy),
                      tooltip: 'Thêm chức danh',
                    ),
                ],
              ),
            ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: _roles.length,
              itemBuilder: (context, index) {
                final role = _roles[index];
                final isSelected = role['roleName'] == _selectedRoleName;
                return _buildRoleItem(role, isSelected);
              },
            ),
          ),
        ],
      );
    }

    // Step 2: Show permissions for selected role
    final visible = _visiblePermissions();
    return Column(
      children: [
        // Header with back and role info
        Container(
          padding: const EdgeInsets.all(12),
          color: Colors.white,
          child: Row(
            children: [
              if (!HrmPageChrome.isEmbedded)
                IconButton(
                  icon: const Icon(Icons.arrow_back, color: Color(0xFF18181B)),
                  onPressed: () {
                    setState(() {
                      _selectedRoleName = null;
                      _selectedRolePermissions = null;
                    });
                    _updateEmbeddedBack();
                  },
                ),
              if (!HrmPageChrome.isEmbedded) const SizedBox(width: 4),
              Expanded(
                child: Text(
                  _selectedRolePermissions!['roleDisplayName'] ?? '',
                  style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF18181B)),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              TextButton.icon(
                onPressed: _selectAllPermissions,
                icon: const Icon(Icons.check_box, size: 16),
                label: const Text('Tất cả', style: TextStyle(fontSize: 12)),
                style: TextButton.styleFrom(
                  foregroundColor: HrmPageChrome.primaryNavy,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
              ),
              TextButton.icon(
                onPressed: _deselectAllPermissions,
                icon: const Icon(Icons.check_box_outline_blank, size: 16),
                label: const Text('Bỏ', style: TextStyle(fontSize: 12)),
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFFEF4444),
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: _isLoadingPermissions
              ? const LoadingWidget()
              : ListView(
                  padding: const EdgeInsets.all(12),
                  children: [
                    _buildGroupFilterBar(),
                    for (final gid in [
                      ...PermissionRoleCatalog.groups.map((g) => g.id),
                      'other',
                    ]) ...[
                      if (visible.any((p) =>
                          (PermissionRoleCatalog.groupIdForModule(
                                  p['module'] as String?) ??
                              'other') ==
                          gid)) ...[
                        _buildGroupSectionHeader(
                          gid,
                          visible
                              .where((p) =>
                                  (PermissionRoleCatalog.groupIdForModule(
                                          p['module'] as String?) ??
                                      'other') ==
                                  gid)
                              .toList(),
                        ),
                        ...visible
                            .where((p) =>
                                (PermissionRoleCatalog.groupIdForModule(
                                        p['module'] as String?) ??
                                    'other') ==
                                gid)
                            .map((perm) {
                          final modKey = perm['module'] as String?;
                          final index = _permissionIndex(modKey ?? '');
                    // allChecked: chỉ tính các quyền module thực sự hỗ trợ
                    final supportedPerms = [
                      'canView',
                      'canCreate',
                      'canEdit',
                      'canDelete',
                      'canExport',
                      'canApprove'
                    ].where((p) => _moduleSupports(modKey, p));
                    final allChecked = supportedPerms.isNotEmpty &&
                        supportedPerms.every((p) => perm[p] == true);
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                    color: const Color(0xFFE4E4E7)),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.all(6),
                                        decoration: BoxDecoration(
                                          color: _getModuleColor(perm['module'])
                                              .withValues(alpha: 0.1),
                                          borderRadius:
                                              BorderRadius.circular(6),
                                        ),
                                        child: Icon(
                                            _getModuleIcon(perm['module']),
                                            size: 16,
                                            color: _getModuleColor(
                                                perm['module'])),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Text(
                                          perm['moduleDisplayName'] ??
                                              perm['module'],
                                          style: const TextStyle(
                                              fontWeight: FontWeight.w600,
                                              fontSize: 14),
                                        ),
                                      ),
                                      Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(allChecked ? 'Toàn quyền' : '',
                                              style: const TextStyle(
                                                  fontSize: 11,
                                                  color: Color(0xFF71717A))),
                                          Checkbox(
                                            value: allChecked,
                                            onChanged: _perm.canEdit('Role')
                                                ? (value) =>
                                                    _toggleAllForModule(
                                                        index, value ?? false)
                                                : null,
                                            activeColor:
                                                HrmPageChrome.primaryNavy,
                                            materialTapTargetSize:
                                                MaterialTapTargetSize
                                                    .shrinkWrap,
                                            visualDensity:
                                                VisualDensity.compact,
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Wrap(
                                    spacing: 4,
                                    runSpacing: 4,
                                    children: [
                                      if (_moduleSupports(
                                          perm['module'], 'canView'))
                                        _mobilePermChip('Xem', index, 'canView',
                                            perm['canView'] ?? false),
                                      if (_moduleSupports(
                                          perm['module'], 'canCreate'))
                                        _mobilePermChip(
                                            'Thêm',
                                            index,
                                            'canCreate',
                                            perm['canCreate'] ?? false),
                                      if (_moduleSupports(
                                          perm['module'], 'canEdit'))
                                        _mobilePermChip('Sửa', index, 'canEdit',
                                            perm['canEdit'] ?? false),
                                      if (_moduleSupports(
                                          perm['module'], 'canDelete'))
                                        _mobilePermChip(
                                            'Xóa',
                                            index,
                                            'canDelete',
                                            perm['canDelete'] ?? false),
                                      if (_moduleSupports(
                                          perm['module'], 'canExport'))
                                        _mobilePermChip(
                                            'Xuất',
                                            index,
                                            'canExport',
                                            perm['canExport'] ?? false),
                                      if (_moduleSupports(
                                          perm['module'], 'canApprove'))
                                        _mobilePermChip(
                                            'Duyệt',
                                            index,
                                            'canApprove',
                                            perm['canApprove'] ?? false),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          );
                        }),
                        const SizedBox(height: 8),
                      ],
                    ],
                  ],
                ),
        ),
      ],
    );
  }

  Widget _mobilePermChip(String label, int index, String permType, bool value) {
    return GestureDetector(
      onTap: () => _togglePermission(index, permType),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: value
              ? _getPermissionColor(permType).withValues(alpha: 0.1)
              : const Color(0xFFF4F4F5),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
              color: value
                  ? _getPermissionColor(permType).withValues(alpha: 0.3)
                  : const Color(0xFFE4E4E7)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              value ? Icons.check_circle : Icons.circle_outlined,
              size: 14,
              color: value
                  ? _getPermissionColor(permType)
                  : const Color(0xFFA1A1AA),
            ),
            const SizedBox(width: 4),
            Text(label,
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: value
                        ? _getPermissionColor(permType)
                        : const Color(0xFF71717A))),
          ],
        ),
      ),
    );
  }

  Widget _buildRoleItem(Map<String, dynamic> role, bool isSelected) {
    final permissions = role['permissions'] as List?;
    final permCount = permissions != null
        ? permissions.where((p) => p['canView'] == true).length
        : (role['permissionCount'] ?? 0);
    final defaultRoles = [
      'Admin',
      'Director',
      'Accountant',
      'DepartmentHead',
      'Manager',
      'Employee',
      'User'
    ];
    final canDelete = _perm.canDelete('Role') &&
        !defaultRoles.contains(role['roleName']);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: isSelected
            ? HrmPageChrome.primaryNavy.withValues(alpha: 0.1)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isSelected ? HrmPageChrome.primaryNavy : Colors.transparent,
        ),
      ),
      child: ListTile(
        onTap: () => _selectRole(role['roleName']),
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: _getRoleColor(role['roleName']).withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            _getRoleIcon(role['roleName']),
            color: _getRoleColor(role['roleName']),
            size: 20,
          ),
        ),
        title: Text(
          role['roleDisplayName'] ?? role['roleName'],
          style: TextStyle(
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
            color:
                isSelected ? HrmPageChrome.primaryNavy : const Color(0xFF18181B),
          ),
        ),
        subtitle: Text(
          '$permCount module được cấp quyền',
          style: const TextStyle(fontSize: 12, color: Color(0xFF71717A)),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isSelected)
              const Icon(Icons.check_circle,
                  color: HrmPageChrome.primaryNavy, size: 20),
            if (canDelete)
              IconButton(
                onPressed: () => _deleteRole(role['roleName']),
                icon: const Icon(Icons.delete_outline, size: 18),
                color: const Color(0xFFEF4444),
                tooltip: 'Xóa chức danh',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildPermissionsTable() {
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Container(
          padding: const EdgeInsets.all(20),
          decoration: const BoxDecoration(
            color: Colors.white,
            border: Border(bottom: BorderSide(color: Color(0xFFE4E4E7))),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      _getRoleColor(_selectedRoleName ?? ''),
                      _getRoleColor(_selectedRoleName ?? '')
                          .withValues(alpha: 0.7),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  _getRoleIcon(_selectedRoleName ?? ''),
                  color: Colors.white,
                  size: 24,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Phân quyền cho: ${_selectedRolePermissions!['roleDisplayName']}',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF18181B),
                      ),
                    ),
                    Text(
                      'Chọn từng chức năng theo nhóm — lưu khi bấm "Lưu thay đổi"',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey[600],
                      ),
                    ),
                  ],
                ),
              ),
              // Quick select buttons
              Flexible(
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton.icon(
                      onPressed: _selectAllPermissions,
                      icon: const Icon(Icons.check_box, size: 18),
                      label: const Text('Chọn tất cả'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: HrmPageChrome.primaryNavy,
                        side: const BorderSide(color: HrmPageChrome.primaryNavy),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                      ),
                    ),
                    OutlinedButton.icon(
                      onPressed: _deselectAllPermissions,
                      icon: const Icon(Icons.check_box_outline_blank, size: 18),
                      label: const Text('Bỏ tất cả'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFFEF4444),
                        side: const BorderSide(color: Color(0xFFEF4444)),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        ),
        SliverToBoxAdapter(child: _buildGroupFilterBar()),
        SliverPadding(
          padding: const EdgeInsets.all(20),
          sliver: SliverToBoxAdapter(
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE4E4E7)),
              ),
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    decoration: const BoxDecoration(
                      color: Color(0xFFFAFAFA),
                      borderRadius:
                          BorderRadius.vertical(top: Radius.circular(12)),
                      border:
                          Border(bottom: BorderSide(color: Color(0xFFE4E4E7))),
                    ),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 200,
                          child: Text(
                            '${_visiblePermissions().length} chức năng',
                            style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF52525B)),
                          ),
                        ),
                        _buildHeaderCheckbox('Xem danh sách', 'canView'),
                        _buildHeaderCheckbox('Thêm mới', 'canCreate'),
                        _buildHeaderCheckbox('Chỉnh sửa', 'canEdit'),
                        _buildHeaderCheckbox('Xóa', 'canDelete'),
                        _buildHeaderCheckbox('Xuất Excel', 'canExport'),
                        _buildHeaderCheckbox('Phê duyệt', 'canApprove'),
                        const SizedBox(
                            width: 90,
                            child: Text('Toàn quyền',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF52525B)))),
                      ],
                    ),
                  ),
                  _buildGroupedPermissionSections(),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildHeaderCheckbox(String label, String permissionType) {
    final canEdit = _perm.canEdit('Role');
    return SizedBox(
      width: 100,
      child: InkWell(
        onTap: canEdit
            ? () {
                final permissions = List<Map<String, dynamic>>.from(
                    _selectedRolePermissions!['permissions'] ?? []);
                final allSelected =
                    permissions.every((p) => p[permissionType] == true);
                _setAllPermissions(permissionType, !allSelected);
              }
            : null,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Flexible(
              child: Text(
                label,
                style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF52525B),
                    fontSize: 12),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const Icon(Icons.unfold_more, size: 14, color: Color(0xFFA1A1AA)),
          ],
        ),
      ),
    );
  }

  Widget _buildPermissionCheckbox(int index, String permissionType, bool value,
      {bool supported = true}) {
    final canEdit = _perm.canEdit('Role');
    return SizedBox(
      width: 100,
      child: Center(
        child: supported
            ? Checkbox(
                value: value,
                onChanged: canEdit
                    ? (_) => _togglePermission(index, permissionType)
                    : null,
                activeColor: _getPermissionColor(permissionType),
              )
            : const Text('—',
                style: TextStyle(fontSize: 18, color: Color(0xFFD4D4D8))),
      ),
    );
  }

  Color _getRoleColor(String roleName) {
    switch (roleName) {
      case 'Admin':
        return const Color(0xFFEF4444);
      case 'Director':
        return const Color(0xFFD97706);
      case 'Accountant':
        return HrmPageChrome.primaryNavy;
      case 'DepartmentHead':
        return HrmPageChrome.primaryNavy;
      case 'Manager':
        return HrmPageChrome.primaryNavy;
      case 'Employee':
        return HrmPageChrome.primaryNavy;
      case 'User':
        return const Color(0xFF71717A);
      default:
        return const Color(0xFF71717A);
    }
  }

  IconData _getRoleIcon(String roleName) {
    switch (roleName) {
      case 'Admin':
        return Icons.admin_panel_settings;
      case 'Director':
        return Icons.business_center;
      case 'Accountant':
        return Icons.calculate;
      case 'DepartmentHead':
        return Icons.groups;
      case 'Manager':
        return Icons.supervisor_account;
      case 'Employee':
        return Icons.person;
      case 'User':
        return Icons.person_outline;
      default:
        return Icons.badge;
    }
  }

  Color _getModuleColor(String? module) {
    switch (module) {
      case 'DashboardAttendanceOverview':
      case 'DashboardHrInsights':
      case 'DashboardTodaySchedule':
      case 'DashboardRealtimeAttendance':
      case 'DashboardAbsent':
      case 'DashboardLateEarly':
      case 'DashboardKpiPanel':
      case 'DashboardInternalNews':
        return const Color(0xFF0284C7);
      case 'Dashboard':
        return HrmPageChrome.primaryNavy;
      case 'Employee':
        return HrmPageChrome.primaryNavy;
      case 'Attendance':
        return const Color(0xFFF59E0B);
      case 'Leave':
        return HrmPageChrome.primaryNavy;
      case 'Salary':
      case 'Payslip':
        return HrmPageChrome.primaryNavy;
      case 'Device':
        return const Color(0xFFEC4899);
      case 'Report':
        return const Color(0xFF2D5F8B);
      case 'Settings':
        return const Color(0xFF71717A);
      default:
        return const Color(0xFF71717A);
    }
  }

  IconData _getModuleIcon(String? module) {
    switch (module) {
      case 'DashboardAttendanceOverview':
        return Icons.pie_chart_outline;
      case 'DashboardHrInsights':
        return Icons.insights_outlined;
      case 'DashboardTodaySchedule':
        return Icons.calendar_today_outlined;
      case 'DashboardRealtimeAttendance':
        return Icons.sensors;
      case 'DashboardAbsent':
        return Icons.person_off_outlined;
      case 'DashboardLateEarly':
        return Icons.schedule_send_outlined;
      case 'DashboardKpiPanel':
        return Icons.track_changes;
      case 'DashboardInternalNews':
        return Icons.newspaper_outlined;
      case 'Dashboard':
        return Icons.dashboard;
      case 'Employee':
        return Icons.people;
      case 'Attendance':
        return Icons.fingerprint;
      case 'Leave':
        return Icons.event_busy;
      case 'Shift':
        return Icons.schedule;
      case 'Salary':
        return Icons.attach_money;
      case 'Payslip':
        return Icons.receipt_long;
      case 'Device':
        return Icons.devices;
      case 'Report':
        return Icons.assessment;
      case 'Settings':
        return Icons.settings;
      case 'Account':
        return Icons.manage_accounts;
      case 'Role':
        return Icons.security;
      case 'Store':
        return Icons.store;
      case 'Allowance':
        return Icons.card_giftcard;
      case 'Holiday':
        return Icons.celebration;
      case 'Insurance':
        return Icons.health_and_safety;
      case 'Tax':
        return Icons.receipt;
      case 'Advance':
        return Icons.money;
      case 'Notification':
        return Icons.notifications;
      default:
        return Icons.folder;
    }
  }

  Color _getPermissionColor(String permissionType) {
    switch (permissionType) {
      case 'canView':
        return HrmPageChrome.primaryNavy;
      case 'canCreate':
        return HrmPageChrome.primaryNavy;
      case 'canEdit':
        return const Color(0xFFF59E0B);
      case 'canDelete':
        return const Color(0xFFEF4444);
      case 'canExport':
        return HrmPageChrome.primaryNavy;
      case 'canApprove':
        return const Color(0xFFEC4899);
      default:
        return const Color(0xFF71717A);
    }
  }
}
