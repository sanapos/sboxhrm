import 'dart:async';
import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../utils/dashboard_permission_modules.dart';
import '../utils/permission_modules.dart';

/// Provider quản lý quyền hiệu lực của user hiện tại.
/// Lưu cache danh sách module permissions (canView, canCreate, canEdit, ...)
/// để các screen dùng kiểm tra ẩn/hiện chức năng.
class PermissionProvider extends ChangeNotifier {
  final ApiService _apiService = ApiService();

  /// Map<moduleCode, ModulePermission>
  Map<String, _ModulePermission> _permissions = {};
  bool _isLoaded = false;
  bool _isLoading = false;
  bool _loadError = false; // API gọi lỗi
  bool _isSuperUser = false; // SuperAdmin/Agent/Admin → toàn quyền
  String? _lastRole;
  Timer? _refreshTimer;

  bool get isLoaded => _isLoaded;
  bool get isLoading => _isLoading;

  /// Tải quyền hiệu lực từ API
  Future<void> loadPermissions({String? role}) async {
    if (_isLoading) return;
    _isLoading = true;
    _lastRole = role;
    final normalizedRole = (role ?? '').trim().toLowerCase();

    // Bắt đầu auto-refresh mỗi 10 phút
    _startRefreshTimer();

    try {
      // SuperAdmin/Agent/Admin có toàn quyền - không cần gọi API
      if (normalizedRole == 'superadmin' || normalizedRole == 'agent' || normalizedRole == 'admin') {
        _isSuperUser = true;
        _permissions = {};
        _loadError = false;
        _isLoaded = true;
        _isLoading = false;
        notifyListeners();
        return;
      }

      _isSuperUser = false;
      debugPrint('🔑 PermissionProvider: Loading permissions for role=$role ...');
      final data = await _apiService.getMyEffectivePermissions();

      _loadError = false;

      if (data.isEmpty) {
        debugPrint('⚠️ PermissionProvider: API returned empty list - possible 403 or no modules');
      }

      _permissions = {};
      for (final item in data) {
        final module = item['module'] as String? ?? '';
        if (module.isEmpty) continue;
        _permissions[module] = _ModulePermission(
          canView: item['canView'] == true,
          canCreate: item['canCreate'] == true,
          canEdit: item['canEdit'] == true,
          canDelete: item['canDelete'] == true,
          canExport: item['canExport'] == true,
          canApprove: item['canApprove'] == true,
        );
      }

      _isLoaded = true;
      final viewableModules = _permissions.entries.where((e) => e.value.canView).map((e) => e.key).toList();
      debugPrint('✅ PermissionProvider: Loaded ${_permissions.length} modules, canView: $viewableModules');
    } catch (e) {
      debugPrint('⚠️ PermissionProvider: Error loading permissions: $e');
      // Keep last-known permissions to avoid intermittent menu disappearance
      // when API errors temporarily (network/token refresh race).
      if (!_isLoaded) {
        _isSuperUser = false;
        _permissions = {};
        _loadError = true;
      } else {
        _loadError = false;
      }
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Menu / điều hướng: màn duyệt cần [canApprove], không alias từ WorkSchedule / AttendanceCorrection.
  bool canViewNav(String? moduleCode) {
    if (moduleCode == null || moduleCode.isEmpty) return true;
    if (_isSuperUser) return true;
    if (PermissionModules.selfServiceModules.contains(moduleCode)) {
      return true;
    }
    if (PermissionModules.approvalNavModules.contains(moduleCode)) {
      return _canAccessApprovalNav(moduleCode);
    }
    if (PermissionModules.explicitNavModules.contains(moduleCode)) {
      if (!_isLoaded || _loadError) return false;
      if (_flag(moduleCode, 'canView')) return true;
      // Module legacy trên DB — vẫn mở Phiếu thưởng khi đã cấp Benefit.
      if (moduleCode == 'BonusPenalty' && _flag('Benefit', 'canView')) {
        return true;
      }
      return false;
    }
    return canView(moduleCode);
  }

  bool _canAccessApprovalNav(String moduleCode) {
    if (!_isLoaded || _loadError) return false;
    switch (moduleCode) {
      case 'AttendanceApproval':
        return canApprove('AttendanceApproval') ||
            canApprove('MobileAttendanceApproval');
      case 'MobileAttendanceApproval':
        return canApprove('MobileAttendanceApproval') ||
            canApprove('AttendanceApproval');
      default:
        return canApprove(moduleCode);
    }
  }

  /// Kiểm tra quyền XEM cho một module
  bool canView(String? moduleCode) {
    if (moduleCode == null || moduleCode.isEmpty) return true;
    if (_isSuperUser) return true;
    if (PermissionModules.selfServiceModules.contains(moduleCode)) {
      return true;
    }
    if (!_isLoaded) return false;
    if (_loadError) return false;
    if (moduleCode == 'Dashboard') {
      return DashboardPermissionModules.canViewNavDashboard(this);
    }
    if (DashboardPermissionModules.allWidgets.contains(moduleCode) &&
        _permissions[DashboardPermissionModules.legacyDashboard]?.canView ==
            true) {
      return true;
    }
    if (moduleCode == 'MobileAttendance') {
      if (_permissions[PermissionModules.mobileAttendanceFromDeviceRegistration]
              ?.canView ==
          true) {
        return true;
      }
      if (_permissions[PermissionModules.mobileAttendanceFromApproval]
              ?.canView ==
          true) {
        return true;
      }
    }
    if (_flag(moduleCode, 'canView')) return true;
    return _resolveAction(moduleCode, 'canView');
  }

  /// Kiểm tra quyền TẠO MỚI cho một module
  bool canCreate(String? moduleCode) {
    if (moduleCode == null || moduleCode.isEmpty) return true;
    if (_isSuperUser) return true;
    if (!_isLoaded || _loadError) return false;
    return _hasAction(moduleCode, 'canCreate');
  }

  /// Kiểm tra quyền CHỈNH SỬA cho một module
  bool canEdit(String? moduleCode) {
    if (moduleCode == null || moduleCode.isEmpty) return true;
    if (_isSuperUser) return true;
    if (!_isLoaded || _loadError) return false;
    return _hasAction(moduleCode, 'canEdit');
  }

  /// Kiểm tra quyền XÓA cho một module
  bool canDelete(String? moduleCode) {
    if (moduleCode == null || moduleCode.isEmpty) return true;
    if (_isSuperUser) return true;
    if (!_isLoaded || _loadError) return false;
    return _hasAction(moduleCode, 'canDelete');
  }

  bool _hasAction(String moduleCode, String action) {
    if (_flag(moduleCode, action)) return true;
    return _resolveAction(moduleCode, action);
  }

  bool _flag(String moduleCode, String action) {
    final perm = _permissions[moduleCode];
    if (perm == null) return false;
    switch (action) {
      case 'canView':
        return perm.canView;
      case 'canCreate':
        return perm.canCreate;
      case 'canEdit':
        return perm.canEdit;
      case 'canDelete':
        return perm.canDelete;
      case 'canExport':
        return perm.canExport;
      case 'canApprove':
        return perm.canApprove;
      default:
        return false;
    }
  }

  bool _anyHas(String action, Iterable<String> codes) {
    for (final c in codes) {
      if (_flag(c, action)) return true;
    }
    return false;
  }

  bool _resolveAction(String moduleCode, String action) {
    if (PermissionModules.attendanceRead.contains(moduleCode) &&
        (action == 'canView' || action == 'canExport')) {
      if (_anyHas(action, PermissionModules.attendanceRead)) return true;
    }
    if (moduleCode == 'AttendanceReport' &&
        (action == 'canView' || action == 'canExport')) {
      if (_anyHas(action, PermissionModules.attendanceRead)) {
        return true;
      }
    }
    if (moduleCode == 'LeaveReport' &&
        (action == 'canView' || action == 'canExport')) {
      if (_flag('Leave', action)) return true;
    }
    if (moduleCode == 'Leave' &&
        (action == 'canView' || action == 'canExport')) {
      if (_flag('LeaveReport', action)) return true;
    }
    if (moduleCode == 'PenaltyReport' &&
        (action == 'canView' || action == 'canExport')) {
      if (_flag('PenaltyTickets', action)) return true;
    }
    if (moduleCode == 'AdvanceReport' &&
        (action == 'canView' || action == 'canExport')) {
      if (_flag('AdvanceRequests', action)) return true;
    }
    if (moduleCode == 'CashReport' &&
        (action == 'canView' || action == 'canExport')) {
      if (_flag('CashTransaction', action)) return true;
    }
    if (moduleCode == 'PayrollReport' &&
        (action == 'canView' || action == 'canExport')) {
      if (_flag('Payroll', action)) return true;
    }
    if (moduleCode == 'Payroll' &&
        (action == 'canView' || action == 'canExport')) {
      if (_flag('PayrollReport', action)) return true;
    }
    if (PermissionModules.attendanceApproval.contains(moduleCode)) {
      if (_anyHas(action, PermissionModules.attendanceApproval)) return true;
    }
    if (PermissionModules.scheduleApproval.contains(moduleCode)) {
      if (_anyHas(action, PermissionModules.scheduleApproval)) return true;
    }
    if (PermissionModules.shiftSetup.contains(moduleCode)) {
      if (_anyHas(action, PermissionModules.shiftSetup)) return true;
    }
    if (PermissionModules.payrollRead.contains(moduleCode) &&
        (action == 'canView' || action == 'canExport')) {
      if (_flag('Payroll', action)) return true;
    }
    if (moduleCode == 'BankAccount' && _flag('CashTransaction', action)) {
      return true;
    }
    if (moduleCode == 'CashTransaction' && _flag('BankAccount', action)) {
      return true;
    }
    if (PermissionModules.financialTransactions.contains(moduleCode)) {
      if (_anyHas(action, PermissionModules.financialTransactions)) return true;
    }
    if (moduleCode == 'Benefit' && _flag('BonusPenalty', action)) return true;
    if (moduleCode == 'BonusPenalty' && _flag('Benefit', action)) return true;
    if (moduleCode == 'AssetReport' &&
        (action == 'canView' || action == 'canExport')) {
      if (_flag('Asset', action)) return true;
    }
    if (moduleCode == 'ProductSalary') {
      if (_flag('Production', action)) return true;
    }
    if (moduleCode == 'Production' && _flag('ProductSalary', action)) {
      return true;
    }
    if (moduleCode == 'MobileAttendance') {
      if ((action == 'canView' || action == 'canCreate') &&
          _flag('MobileDeviceRegistration', 'canView')) {
        return true;
      }
      if ((action == 'canView' || action == 'canApprove') &&
          _flag('MobileAttendanceApproval', action)) {
        return true;
      }
    }
    if (moduleCode == 'MobileDeviceRegistration') {
      if (action == 'canView' && _flag('MobileAttendance', 'canView')) {
        return true;
      }
      if (action != 'canView' && _flag('MobileAttendance', 'canEdit')) {
        return true;
      }
    }
    if (moduleCode == 'Report' && action == 'canView') {
      if (_anyHas('canView', PermissionModules.reportModules)) return true;
    }
    return false;
  }

  /// Kiểm tra quyền XUẤT BÁO CÁO cho một module
  bool canExport(String? moduleCode) {
    if (moduleCode == null || moduleCode.isEmpty) return true;
    if (_isSuperUser) return true;
    if (!_isLoaded || _loadError) return false;
    return _hasAction(moduleCode, 'canExport');
  }

  /// Kiểm tra quyền DUYỆT cho một module
  bool canApprove(String? moduleCode) {
    if (moduleCode == null || moduleCode.isEmpty) return true;
    if (_isSuperUser) return true;
    if (!_isLoaded || _loadError) return false;
    return _hasAction(moduleCode, 'canApprove');
  }

  /// Xóa cache khi logout
  void clear() {
    _permissions = {};
    _isLoaded = false;
    _loadError = false;
    _isSuperUser = false;
    _lastRole = null;
    _refreshTimer?.cancel();
    _refreshTimer = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _refreshTimer = null;
    super.dispose();
  }

  void _startRefreshTimer() {
    _refreshTimer?.cancel();
    _refreshTimer = Timer.periodic(const Duration(minutes: 10), (_) {
      if (_lastRole != null && !_isSuperUser) {
        debugPrint('🔄 PermissionProvider: Auto-refreshing permissions...');
        loadPermissions(role: _lastRole);
      }
    });
  }
}

class _ModulePermission {
  final bool canView;
  final bool canCreate;
  final bool canEdit;
  final bool canDelete;
  final bool canExport;
  final bool canApprove;

  const _ModulePermission({
    this.canView = false,
    this.canCreate = false,
    this.canEdit = false,
    this.canDelete = false,
    this.canExport = false,
    this.canApprove = false,
  });
}
