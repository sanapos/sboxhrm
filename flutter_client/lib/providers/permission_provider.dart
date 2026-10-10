import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/api_service.dart';
import '../utils/dashboard_permission_modules.dart';
import '../utils/permission_modules.dart';
import '../utils/store_role_helper.dart';

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

  /// Lần tải đầu lỗi (chưa có quyền nào) — UI không chờ mãi.
  bool get loadFailed => _loadError && !_isLoaded;
  bool get isLoading => _isLoading;

  /// App POS độc lập: nếu API quyền trống / lỗi, vẫn cho bán hàng + hàng hóa.
  void ensurePosSellDefaults() {
    if (_isSuperUser) {
      _isLoaded = true;
      _loadError = false;
      return;
    }
    const defaults = <String>[
      'PosSell',
      'PosProducts',
      'PosSaleOrders',
      'PosSalesReport',
      'CashTransaction',
    ];
    var changed = false;
    for (final code in defaults) {
      final existing = _permissions[code];
      if (existing == null || !existing.canView) {
        _permissions[code] = _ModulePermission(
          canView: true,
          canCreate: true,
          canEdit: true,
          canDelete: existing?.canDelete ?? false,
          canExport: true,
          canApprove: existing?.canApprove ?? (code == 'PosSell'),
        );
        changed = true;
      }
    }
    _isLoaded = true;
    _loadError = false;
    if (changed) notifyListeners();
  }

  static const _cachePrefix = 'perm_cache_v1:';
  String? _cacheKey;

  /// Quyền lần trước của tài khoản (mở app hiện menu đúng ngay, không «bung» dần khi API trả về).
  Future<bool> _restoreFromCache(String cacheKey, String? role) async {
    try {
      final raw = (await SharedPreferences.getInstance()).getString('$_cachePrefix$cacheKey');
      if (raw == null) return false;
      final m = jsonDecode(raw) as Map<String, dynamic>;
      if ('${m['role'] ?? ''}' != (role ?? '')) return false;
      final perms = <String, _ModulePermission>{};
      (m['p'] as Map<String, dynamic>).forEach((k, v) {
        final f = '$v';
        perms[k] = _ModulePermission(
          canView: f.contains('V'), canCreate: f.contains('C'), canEdit: f.contains('E'),
          canDelete: f.contains('D'), canExport: f.contains('X'), canApprove: f.contains('A'),
        );
      });
      if (perms.isEmpty) return false;
      _permissions = perms;
      _isLoaded = true;
      _loadError = false;
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _saveCache(String? role) async {
    final key = _cacheKey;
    if (key == null || _permissions.isEmpty) return;
    try {
      String flags(_ModulePermission p) => [
            if (p.canView) 'V', if (p.canCreate) 'C', if (p.canEdit) 'E',
            if (p.canDelete) 'D', if (p.canExport) 'X', if (p.canApprove) 'A',
          ].join();
      await (await SharedPreferences.getInstance()).setString(
        '$_cachePrefix$key',
        jsonEncode({'role': role ?? '', 'p': {for (final e in _permissions.entries) e.key: flags(e.value)}}),
      );
    } catch (_) {}
  }

  static bool _samePermissions(Map<String, _ModulePermission> a, Map<String, _ModulePermission> b) {
    if (a.length != b.length) return false;
    for (final e in a.entries) {
      final o = b[e.key];
      if (o == null ||
          o.canView != e.value.canView || o.canCreate != e.value.canCreate || o.canEdit != e.value.canEdit ||
          o.canDelete != e.value.canDelete || o.canExport != e.value.canExport || o.canApprove != e.value.canApprove) {
        return false;
      }
    }
    return true;
  }

  /// Tải quyền hiệu lực từ API.
  /// [cacheKey] (tài khoản + cửa hàng): hiện ngay quyền lần trước, API cập nhật nền —
  /// menu / thanh dưới không nhảy lúc mở app; chỉ vẽ lại khi quyền thật sự đổi.
  Future<void> loadPermissions({String? role, bool freshSession = false, String? cacheKey}) async {
    if (_isLoading && !freshSession) return;
    if (cacheKey != null) _cacheKey = cacheKey;
    if (freshSession) {
      _permissions = {};
      _isLoaded = false;
      _loadError = false;
      _isSuperUser = false;
      if (cacheKey != null &&
          !StoreRoleHelper.isFullAccess(role) &&
          await _restoreFromCache(cacheKey, role)) {
        notifyListeners();
      }
    }
    final before = Map<String, _ModulePermission>.from(_permissions);
    final wasLoaded = _isLoaded;
    _isLoading = true;
    _lastRole = role;
    final normalizedRole = (role ?? '').trim().toLowerCase();

    // Bắt đầu auto-refresh mỗi 10 phút
    _startRefreshTimer();

    try {
      // Chủ cửa hàng (Admin) / SuperAdmin / Đại lý — toàn quyền module (giám đốc theo bảng quyền)
      if (StoreRoleHelper.isFullAccess(role)) {
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

      // Refresh rỗng khi đã có quyền → giữ cache (tránh mất nút/menu giữa ca).
      if (data.isEmpty) {
        debugPrint(
            '⚠️ PermissionProvider: API returned empty list - possible 403 or no modules');
        if (!freshSession && _isLoaded && _permissions.isNotEmpty) {
          debugPrint(
              '⚠️ PermissionProvider: Keeping last-known ${_permissions.length} modules');
          return;
        }
      }

      final fresh = <String, _ModulePermission>{};
      _permissions = fresh;
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
      if (StoreRoleHelper.isPosCashierRole(role) &&
          _permissions['PosSell']?.canView != true) {
        ensurePosSellDefaults();
      }
      unawaited(_saveCache(role));
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
      if (StoreRoleHelper.isPosCashierRole(role)) {
        ensurePosSellDefaults();
      }
    } finally {
      _isLoading = false;
      // Quyền như cũ (thường gặp: bản lưu đúng) → không vẽ lại menu.
      if (!(wasLoaded && _isLoaded && !_loadError && _samePermissions(before, _permissions))) {
        notifyListeners();
      }
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
    // Thông báo cá nhân: xem được thì được xóa thông báo của chính mình.
    if (moduleCode == 'Notification' && action == 'canDelete') {
      if (_flag('Notification', 'canView')) return true;
    }
    if (PermissionModules.attendanceRead.contains(moduleCode) &&
        (action == 'canView' || action == 'canExport')) {
      if (_anyHas(action, PermissionModules.attendanceRead)) return true;
    }
    if (moduleCode == 'LateEarlyReport' &&
        (action == 'canView' || action == 'canExport')) {
      if (_flag('AttendanceByShift', action) ||
          _flag('AttendanceSummary', action)) {
        return true;
      }
    }
    if (moduleCode == 'TravelHoursReport' &&
        (action == 'canView' || action == 'canExport')) {
      if (_flag('AttendanceByShift', action) ||
          _flag('AttendanceSummary', action) ||
          _flag('MobileAttendance', action) ||
          _flag('LateEarlyReport', action)) {
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
    // POS: submodule kho/bán gộp từ PosProducts (cùng action).
    if (moduleCode == 'PosSell' ||
        moduleCode == 'PosPrintTemplates' ||
        moduleCode == 'PosSaleOrders' ||
        moduleCode == 'PosSaleReturns' ||
        moduleCode == 'PosPurchaseReceipts' ||
        moduleCode == 'PosPurchaseReturns' ||
        moduleCode == 'PosStockCounts' ||
        moduleCode == 'PosDamageIssues' ||
        moduleCode == 'PosInternalUseIssues') {
      if (_flag('PosProducts', action)) return true;
    }
    // Trả hàng trên phiếu bán: thu ngân PosSell cùng action vẫn được.
    if (moduleCode == 'PosSaleReturns' && _flag('PosSell', action)) {
      return true;
    }
    // Tra khách / bảo hành khi bán — không mở menu (menu đòi tick riêng).
    if ((moduleCode == 'PosCustomers' || moduleCode == 'PosWarranty') &&
        action == 'canView' &&
        _flag('PosSell', 'canView')) {
      return true;
    }
    // Ca thu ngân: API thanh toán vẫn dùng được; menu đòi tick riêng.
    if (moduleCode == 'PosCashierShift' &&
        action == 'canView' &&
        _flag('PosSell', 'canView')) {
      return true;
    }
    // Xem hàng hóa / mẫu in khi có quyền bán.
    if ((moduleCode == 'PosProducts' || moduleCode == 'PosPrintTemplates') &&
        (action == 'canView' || action == 'canExport') &&
        _flag('PosSell', 'canView')) {
      return true;
    }
    if (moduleCode == 'PosSalesReport' &&
        (action == 'canView' || action == 'canExport')) {
      if (_flag('PosProducts', action) || _flag('PosSalesReport', action)) {
        return true;
      }
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

  /// Order / gọi món / tạm tính (không gồm thanh toán).
  bool canPosOrder() =>
      canCreate('PosSell') ||
      canEdit('PosSell') ||
      canCreate('PosProducts');

  /// Thu ngân — thanh toán / hoàn tất hóa đơn.
  bool canPosPay() => canApprove('PosSell');

  /// Quyền con đã tải từ máy chủ chưa (máy chủ cũ chưa có → dùng quyền cha như trước).
  bool _knows(String moduleCode) => _permissions.containsKey(moduleCode);

  /// Đổi đơn giá tay khi bán (trước đây: quyền thanh toán).
  bool canPosPriceEdit() {
    if (_isSuperUser) return true;
    return _knows('PosSellPriceEdit') ? _flag('PosSellPriceEdit', 'canEdit') : canPosPay();
  }

  /// Chiết khấu dòng / đơn khi bán (trước đây: quyền thanh toán).
  bool canPosDiscount() {
    if (_isSuperUser) return true;
    return _knows('PosSellDiscount') ? _flag('PosSellDiscount', 'canEdit') : canPosPay();
  }

  /// Hủy hóa đơn đã thanh toán (trước đây: quyền thanh toán).
  bool canPosCancelPaid() {
    if (_isSuperUser) return true;
    return _knows('PosSellCancelPaid') ? _flag('PosSellCancelPaid', 'canApprove') : canPosPay();
  }

  /// Thấy giá vốn / giá trị tồn / lãi (trước đây: ai xem hàng hóa đều thấy).
  bool canViewCost() {
    if (_isSuperUser) return true;
    if (!_isLoaded || _loadError) return false;
    return _knows('PosViewCost') ? _flag('PosViewCost', 'canView') : canView('PosProducts');
  }

  /// Module thiết lập POS — tick trên ma trận, không alias từ PosSell.
  static const List<String> posSetupModuleCodes = [
    'SettingsHub',
    'PosPrinters',
    'PosStorePrinters',
    'PosPrintTemplates',
    'PosEInvoice',
    'PosShipping',
    'PosCustomerDisplay',
  ];

  /// Quyền xem đúng module (không suy từ PosSell / PosProducts).
  bool canViewExact(String? moduleCode) {
    if (moduleCode == null || moduleCode.isEmpty) return true;
    if (_isSuperUser) return true;
    if (!_isLoaded || _loadError) return false;
    return _flag(moduleCode, 'canView');
  }

  /// Mở menu Thiết lập khi được tick bất kỳ phần thiết lập POS.
  bool canViewPosSetup() => posSetupModuleCodes.any(canViewExact);

  /// Lưu cửa hàng / ngành hàng / cổng CK / thiết lập POS.
  bool canEditPosSetup() => canEdit('SettingsHub');

  /// Kiểm tra quyền DUYỆT cho một module
  bool canApprove(String? moduleCode) {
    if (moduleCode == null || moduleCode.isEmpty) return true;
    if (_isSuperUser) return true;
    if (!_isLoaded || _loadError) return false;
    return _hasAction(moduleCode, 'canApprove');
  }

  /// Tổng kết cuối ngày / báo cáo POS của mọi nhân viên (không khóa theo tài khoản đang bán).
  bool canViewAllPosStaffReports() =>
      canEdit('PosReportEndOfDay') ||
      canApprove('PosReportEndOfDay') ||
      canEdit('PosSalesReport');

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
