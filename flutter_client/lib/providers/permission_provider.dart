import 'dart:async';
import 'package:flutter/material.dart';
import '../services/api_service.dart';

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

    // Bắt đầu auto-refresh mỗi 10 phút
    _startRefreshTimer();

    try {
      // SuperAdmin/Agent/Admin có toàn quyền - không cần gọi API
      if (role == 'SuperAdmin' || role == 'Agent' || role == 'Admin') {
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
      _isSuperUser = false;
      _permissions = {};
      _loadError = true;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Kiểm tra quyền XEM cho một module
  bool canView(String? moduleCode) {
    if (moduleCode == null || moduleCode.isEmpty) return true;
    if (_isSuperUser) return true;
    if (!_isLoaded) return true; // Chưa load xong → hiện hết (tránh flash)
    if (_loadError) return false; // API lỗi → ẩn hết (secure default)
    final perm = _permissions[moduleCode];
    if (perm == null) return false; // Module không có trong danh sách → ẩn
    return perm.canView;
  }

  /// Kiểm tra quyền TẠO MỚI cho một module
  bool canCreate(String? moduleCode) {
    if (moduleCode == null || moduleCode.isEmpty) return true;
    if (_isSuperUser) return true;
    if (!_isLoaded) return true;
    if (_loadError) return false;
    return _permissions[moduleCode]?.canCreate ?? false;
  }

  /// Kiểm tra quyền CHỈNH SỬA cho một module
  bool canEdit(String? moduleCode) {
    if (moduleCode == null || moduleCode.isEmpty) return true;
    if (_isSuperUser) return true;
    if (!_isLoaded) return true;
    if (_loadError) return false;
    return _permissions[moduleCode]?.canEdit ?? false;
  }

  /// Kiểm tra quyền XÓA cho một module
  bool canDelete(String? moduleCode) {
    if (moduleCode == null || moduleCode.isEmpty) return true;
    if (_isSuperUser) return true;
    if (!_isLoaded) return true;
    if (_loadError) return false;
    return _permissions[moduleCode]?.canDelete ?? false;
  }

  /// Kiểm tra quyền XUẤT BÁO CÁO cho một module
  bool canExport(String? moduleCode) {
    if (moduleCode == null || moduleCode.isEmpty) return true;
    if (_isSuperUser) return true;
    if (!_isLoaded) return true;
    if (_loadError) return false;
    return _permissions[moduleCode]?.canExport ?? false;
  }

  /// Kiểm tra quyền DUYỆT cho một module
  bool canApprove(String? moduleCode) {
    if (moduleCode == null || moduleCode.isEmpty) return true;
    if (_isSuperUser) return true;
    if (!_isLoaded) return true;
    if (_loadError) return false;
    return _permissions[moduleCode]?.canApprove ?? false;
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
