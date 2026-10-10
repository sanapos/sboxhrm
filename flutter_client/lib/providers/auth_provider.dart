import '../services/branch_session.dart';
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/api_service.dart';
import '../services/app_icon_badge.dart';
import '../services/fcm_service_stub.dart'
    if (dart.library.io) '../services/fcm_service.dart';
import '../utils/pending_notification_launch.dart';
import '../utils/store_role_helper.dart';
import '../services/global_location_reporter.dart';
import '../services/notification_preferences_cache.dart';
import '../services/session_reset.dart';
import '../config/sbox_app_variant.dart';
import '../models/user.dart';

class AuthProvider extends ChangeNotifier {
  User? _user;
  String? _token;
  bool _isLoading = false;
  bool _isInitializing = true;
  String? _error;

  User? get user => _user;

  /// Chỉ dùng trong test: giả lập người đăng nhập (vai trò quản lý / nhân viên).
  @visibleForTesting
  void debugSetUser(User? u) {
    _user = u;
    _token = u == null ? null : 'test-token';
    notifyListeners();
  }
  User? get currentUser => _user;
  String? get token => _token;
  bool get isLoading => _isLoading;
  bool get isInitializing => _isInitializing;
  bool get isAuthenticated => _token != null && _user != null;
  String? get error => _error;
  String get userRole => _user?.role ?? 'Employee';

  // ─── Đăng nhập thay (Super Admin hỗ trợ khách) ───
  static const _impBackupAccess = 'imp_backup_access';
  static const _impBackupRefresh = 'imp_backup_refresh';
  static const _impLabelKey = 'imp_label';
  String? _impersonationLabel;

  /// Đang đăng nhập thay một tài khoản cửa hàng.
  bool get isImpersonating => _impersonationLabel != null;
  String? get impersonationLabel => _impersonationLabel;

  /// Chuyển sang phiên của người dùng [token] (không có refresh token); lưu phiên Super Admin để quay lại.
  Future<bool> startImpersonation(String token, String label) async {
    final current = await _apiService.readTokenPair();
    if (current.access == null) return false;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_impBackupAccess, current.access!);
    if (current.refresh != null) await prefs.setString(_impBackupRefresh, current.refresh!);
    await prefs.setString(_impLabelKey, label);
    await SessionReset.clearForAccountSwitch();
    await _apiService.writeTokenPair(token, null);
    _token = token;
    _user = _decodeUserFromToken(token);
    _impersonationLabel = label;
    await _fetchAllowedModules(freshSession: true);
    BranchSession.instance.load();
    notifyListeners();
    return _user != null;
  }

  /// Thoát đăng nhập thay, khôi phục phiên Super Admin.
  Future<void> stopImpersonation() async {
    final prefs = await SharedPreferences.getInstance();
    final access = prefs.getString(_impBackupAccess);
    final refresh = prefs.getString(_impBackupRefresh);
    await prefs.remove(_impBackupAccess);
    await prefs.remove(_impBackupRefresh);
    await prefs.remove(_impLabelKey);
    _impersonationLabel = null;
    await SessionReset.clearForAccountSwitch();
    BranchSession.instance.clear();
    if (access == null) {
      await logout();
      return;
    }
    await _apiService.writeTokenPair(access, refresh);
    _token = access;
    _user = _decodeUserFromToken(access);
    notifyListeners();
  }

  final ApiService _apiService = ApiService();
  Completer<bool>? _refreshCompleter;

  /// Get a valid (non-expired) access token, refreshing if necessary
  Future<String?> getValidToken() async {
    if (_token == null) return null;

    // Check if token is about to expire (within 2 minutes)
    if (_isTokenExpiringSoon(_token!)) {
      debugPrint('🔄 AuthProvider: Token expiring soon, attempting refresh...');
      final refreshed = await _tryRefreshToken();
      if (refreshed) {
        debugPrint('✅ AuthProvider: Token refreshed successfully');
      } else {
        debugPrint(
            '⚠️ AuthProvider: Token refresh failed, using current token');
      }
    }
    return _token;
  }

  /// Check if JWT token expires within [marginSeconds] seconds
  bool _isTokenExpiringSoon(String token, {int marginSeconds = 120}) {
    try {
      final parts = token.split('.');
      if (parts.length != 3) return true;
      final payload = parts[1];
      final normalized = base64Url.normalize(payload);
      final decoded = utf8.decode(base64Url.decode(normalized));
      final claims = json.decode(decoded) as Map<String, dynamic>;
      final exp = claims['exp'] as int?;
      if (exp == null) return true;
      final expiryDate = DateTime.fromMillisecondsSinceEpoch(exp * 1000);
      return DateTime.now()
          .isAfter(expiryDate.subtract(Duration(seconds: marginSeconds)));
    } catch (e) {
      return true;
    }
  }

  /// Try to refresh the access token using the stored refresh token
  /// Uses a Completer to prevent concurrent refresh attempts
  Future<bool> _tryRefreshToken() async {
    // If a refresh is already in progress, wait for it
    if (_refreshCompleter != null) {
      return _refreshCompleter!.future;
    }
    _refreshCompleter = Completer<bool>();
    try {
      final result = await _apiService.refreshToken();
      if (result != null) {
        _token = result['accessToken'] ?? result['token'];
        if (_token != null) {
          await _apiService.saveToken(_token!);
          // Also save new refresh token if provided
          final newRefreshToken = result['refreshToken'];
          if (newRefreshToken != null) {
            await _apiService.saveRefreshToken(newRefreshToken);
          }
          // JWT không chứa gói module — giữ allowedModules cũ rồi tải lại nền.
          final previousModules = _user?.allowedModules;
          final previousUserId = _user?.id;
          final decoded = _decodeUserFromToken(_token!);
          if (decoded != null &&
              previousUserId != null &&
              previousUserId == decoded.id &&
              previousModules != null &&
              previousModules.isNotEmpty) {
            _user = decoded.copyWith(allowedModules: previousModules);
          } else {
            _user = decoded;
          }
          notifyListeners();
          // ignore: discarded_futures
          _fetchAllowedModules().then((changed) {
            if (changed && _user != null) notifyListeners();
          });
          _refreshCompleter!.complete(true);
          return true;
        }
      }
      _refreshCompleter!.complete(false);
    } catch (e) {
      debugPrint('❌ AuthProvider: Token refresh error: $e');
      _refreshCompleter!.complete(false);
    } finally {
      _refreshCompleter = null;
    }
    return false;
  }

  AuthProvider() {
    _checkAuthStatus();
    // Register global 401/session-expired handler so expired sessions get logged out.
    ApiService.onUnauthorized = _handleSessionExpired;
    ApiService.onLicenseExpired = _handleLicenseExpired;
  }

  bool _sessionExpiredHandling = false;
  bool _licenseExpiredHandling = false;
  Future<void> _handleSessionExpired() async {
    if (_sessionExpiredHandling) return;
    _sessionExpiredHandling = true;
    try {
      if (_token == null && _user == null) return;
      if (isImpersonating) {
        debugPrint('🚪 AuthProvider: Impersonation token expired → back to Super Admin');
        await stopImpersonation();
        return;
      }
      debugPrint('🚪 AuthProvider: Session expired → auto logout');
      await logout();
    } finally {
      _sessionExpiredHandling = false;
    }
  }

  Future<void> _handleLicenseExpired(String message) async {
    if (_licenseExpiredHandling) return;
    _licenseExpiredHandling = true;
    try {
      if (_token == null && _user == null) return;
      debugPrint('🚪 AuthProvider: Store license expired → auto logout');
      await logout();
      _error = message;
      notifyListeners();
    } finally {
      _licenseExpiredHandling = false;
    }
  }

  /// Kiểm tra license khi app resume — logout ngay nếu cửa hàng hết hạn.
  Future<void> verifyStoreLicense() async {
    if (_token == null) return;
    await _apiService.checkStoreLicenseExpired();
  }

  /// Giới hạn thời gian restore phiên — tránh màn boot kéo dài khi mạng chậm.
  static const Duration _authInitTimeout = Duration(seconds: 12);

  Future<void> _checkAuthStatus() async {
    _isInitializing = true;
    notifyListeners();

    try {
      await _restoreSession().timeout(
        _authInitTimeout,
        onTimeout: () {
          debugPrint(
              '⚠️ [BOOT] Auth restore timed out after ${_authInitTimeout.inSeconds}s');
        },
      );
    } catch (e) {
      debugPrint('❌ [BOOT] Auth restore error: $e');
      _token = null;
      _user = null;
    } finally {
      _isInitializing = false;
      _isLoading = false;
      notifyListeners();
      _runPostAuthSideEffects();
    }
  }

  /// Chỉ khôi phục token/user — không gọi API phụ trước khi hiện UI.
  Future<void> _restoreSession() async {
    final savedToken = await _apiService.getStoredToken();
    if (savedToken == null) return;
    try {
      _impersonationLabel = (await SharedPreferences.getInstance()).getString(_impLabelKey);
    } catch (_) {}

    _token = savedToken;
    _user = _decodeUserFromToken(savedToken);

    if (_isTokenExpiringSoon(savedToken)) {
      debugPrint(
          '🔄 AuthProvider: Stored token expired/expiring, refreshing...');
      final refreshed = await _tryRefreshToken();
      if (!refreshed) {
        debugPrint('⚠️ AuthProvider: Token refresh failed, clearing session');
        _token = null;
        _user = null;
      }
    }

    if (_user != null && !StoreRoleHelper.bypassesPackageFilter(_user!.role)) {
      // Có bản lưu → hiện ngay, tải mới ở _runPostAuthSideEffects (không chặn màn khởi động).
      if (!await _restoreModulesCache()) {
        // Lỗi mạng → danh sách rỗng (menu vẫn hiện, không chờ mãi); tải nền ngay sau sẽ thử lại.
        await _fetchAllowedModules(freshSession: true);
      }
    }
  }

  /// Chạy sau khi UI đã thoát trạng thái initializing.
  void _runPostAuthSideEffects() {
    if (_token == null || _user == null) return;
    // ignore: discarded_futures
    verifyStoreLicense();
    // Vừa tải lúc khôi phục phiên (< 1 phút) thì thôi; chỉ vẽ lại khi gói thật sự đổi.
    final fetchedAt = _modulesFetchedAt;
    if (fetchedAt == null || DateTime.now().difference(fetchedAt) > const Duration(minutes: 1)) {
      // ignore: discarded_futures
      _fetchAllowedModules().then((changed) {
        if (changed && _user != null) notifyListeners();
      });
    }
    // Đăng nhập thay: không đăng ký nhận thông báo / gửi vị trí thay cho người dùng thật.
    if (isImpersonating) return;
    GlobalLocationReporter.instance.startIfEligible(
      employeeId: _user?.employeeId ?? _user?.id,
    );
    // ignore: discarded_futures
    FcmService.instance.registerForCurrentUser();
    // ignore: discarded_futures
    NotificationPreferencesCache.instance.refresh(_apiService);    // ignore: discarded_futures
    BranchSession.instance.load();
  }

  // Decode user info từ JWT token
  User? _decodeUserFromToken(String token) {
    try {
      final parts = token.split('.');
      if (parts.length != 3) return null;

      final payload = parts[1];
      final normalized = base64Url.normalize(payload);
      final decoded = utf8.decode(base64Url.decode(normalized));
      final Map<String, dynamic> claims = json.decode(decoded);

      final employeeIdClaim = claims['employeeId']?.toString();
      return User(
        id: claims[
                'http://schemas.xmlsoap.org/ws/2005/05/identity/claims/nameidentifier'] ??
            '',
        employeeId: employeeIdClaim != null && employeeIdClaim.isNotEmpty
            ? employeeIdClaim
            : null,
        email: claims[
                'http://schemas.xmlsoap.org/ws/2005/05/identity/claims/emailaddress'] ??
            claims['userName'] ??
            '',
        fullName: claims[
                'http://schemas.xmlsoap.org/ws/2005/05/identity/claims/name'] ??
            'User',
        role: claims[
                'http://schemas.microsoft.com/ws/2008/06/identity/claims/role'] ??
            'Employee',
        storeId: claims['storeId'],
      );
    } catch (e) {
      debugPrint('❌ Error decoding JWT: $e');
      return null;
    }
  }

  Future<bool> login(String storeCode, String email, String password) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      try {
        await FcmService.instance.unregisterForLogout();
      } catch (e) {
        debugPrint('FCM pre-login unregister: $e');
      }
      await SessionReset.clearForAccountSwitch();

      debugPrint('🔐 AuthProvider: Attempting login for $storeCode / $email');

      // SuperAdmin/Agent login: no storeCode required
      final response = storeCode.trim().isEmpty
          ? await _apiService.adminLogin(email, password)
          : await _apiService.login(storeCode, email, password);

      if (response['isSuccess'] == true && response['data'] != null) {
        final data = response['data'];
        _token = data['accessToken'] ?? data['token'];

        if (_token != null) {
          debugPrint('✅ AuthProvider: Got token, saving...');
          await _apiService.saveToken(_token!);

          // Save refresh token if provided
          final refreshToken = data['refreshToken'];
          if (refreshToken != null) {
            await _apiService.saveRefreshToken(refreshToken);
          }

          // Decode user từ JWT token
          _user = _decodeUserFromToken(_token!);
          debugPrint(
              '✅ AuthProvider: User decoded - ${_user?.fullName} (${_user?.role})');

          // Fetch allowed modules cho store user
          await _fetchAllowedModules(freshSession: true);

          // Start global location reporting for employees/managers so the
          // manager map can see real-time positions.
          GlobalLocationReporter.instance.startIfEligible(
      employeeId: _user?.employeeId ?? _user?.id,
    );

          // Register FCM device token (push notifications). Best-effort.
          // Also schedule a retry after 35s in case APNs token was not ready yet.
          // ignore: discarded_futures
          FcmService.instance.registerForCurrentUser();
          // ignore: discarded_futures
          NotificationPreferencesCache.instance.refresh(_apiService);
          // ignore: discarded_futures
          BranchSession.instance.load();
          Future.delayed(const Duration(seconds: 35), () {
            FcmService.instance.registerForCurrentUser();
          });
          PendingNotificationLaunch.scheduleConsume(
            adminPortalMode: storeCode.trim().isEmpty,
            agentMode: _user?.role == 'Agent',
          );

          _isLoading = false;
          notifyListeners();
          return true;
        } else {
          debugPrint('❌ AuthProvider: No token in response');
          _error = 'Không nhận được token từ server';
        }
      } else {
        _error = response['message'] ?? 'Đăng nhập thất bại';
        debugPrint('❌ AuthProvider: Login failed - $_error');
      }

      _isLoading = false;
      notifyListeners();
      return false;
    } catch (e) {
      debugPrint('❌ AuthProvider: Exception - $e');
      _error = 'Không thể kết nối đến server: $e';
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  /// Module POS tối thiểu cho app thu ngân độc lập.
  static const _posPackageDefaults = <String>[
    'PosSell',
    'PosProducts',
    'PosSaleOrders',
    'PosSalesReport',
    'CashTransaction',
    'PosCustomers',
  ];

  /// Gộp module POS vào gói — hub không bị «Trống» / chặn bán.
  void ensurePosPackageDefaults() {
    if (_user == null) return;
    if (StoreRoleHelper.bypassesPackageFilter(_user!.role)) return;
    final current = List<String>.from(_user!.allowedModules ?? const []);
    final lower = {for (final m in current) m.toLowerCase()};
    var changed = false;
    for (final code in _posPackageDefaults) {
      if (lower.add(code.toLowerCase())) {
        current.add(code);
        changed = true;
      }
    }
    if (!changed) return;
    _user = _user!.copyWith(allowedModules: current);
    notifyListeners();
  }

  /// Cập nhật họ tên hiển thị sau khi sửa hồ sơ tài khoản (không cần đăng nhập lại).
  void applyLocalProfile({String? fullName}) {
    if (_user == null) return;
    _user = _user!.copyWith(fullName: fullName);
    notifyListeners();
  }

  static const _modulesCachePrefix = 'mods_cache_v1:';
  DateTime? _modulesFetchedAt;

  String? get _modulesCacheKey =>
      _user == null ? null : '$_modulesCachePrefix${_user!.id}:${_user!.storeId ?? ''}';

  /// Chức năng của gói lần trước — menu hiện đúng ngay khi mở app (không nhảy khi API trả về).
  Future<bool> _restoreModulesCache() async {
    final key = _modulesCacheKey;
    if (key == null) return false;
    try {
      final list = (await SharedPreferences.getInstance()).getStringList(key);
      if (list == null || list.isEmpty) return false;
      _user = _user!.copyWith(allowedModules: list);
      return true;
    } catch (_) {
      return false;
    }
  }

  static bool _sameModules(List<String>? a, List<String>? b) {
    if (a == null || b == null) return a == b;
    if (a.length != b.length) return false;
    final sa = {for (final m in a) m.toLowerCase()};
    return b.every((m) => sa.contains(m.toLowerCase()));
  }

  /// Lấy danh sách module được phép từ gói dịch vụ cửa hàng.
  /// Trả true khi danh sách thật sự đổi (nơi gọi mới cần vẽ lại menu).
  Future<bool> _fetchAllowedModules({bool freshSession = false}) async {
    try {
      if (_user == null) return false;
      if (StoreRoleHelper.bypassesPackageFilter(_user!.role)) return false;

      final modules = await _apiService.getMyModules();
      // null = lỗi mạng/API — không xóa module đang có (tránh mất menu giữa ca).
      if (modules == null) {
        debugPrint(
            '⚠️ AuthProvider: getMyModules failed — keeping existing allowedModules');
        if (freshSession) {
          _user = _user!.copyWith(allowedModules: const []);
          if (SboxAppVariant.standalonePos) ensurePosPackageDefaults();
          return true;
        }
        return false;
      }
      _modulesFetchedAt = DateTime.now();
      final key = _modulesCacheKey;
      if (key != null) {
        unawaited(SharedPreferences.getInstance().then((p) => p.setStringList(key, modules)).catchError((_) => false));
      }
      // Như cũ → giữ nguyên danh sách (menu không vẽ lại).
      if (_sameModules(_user!.allowedModules, modules)) return false;
      _user = _user!.copyWith(allowedModules: modules);
      if (SboxAppVariant.standalonePos) ensurePosPackageDefaults();
      debugPrint(
          '✅ AuthProvider: Loaded ${_user!.allowedModules?.length ?? 0} allowed modules');
      return true;
    } catch (e) {
      debugPrint('⚠️ AuthProvider: Error fetching allowed modules: $e');
      if (SboxAppVariant.standalonePos) ensurePosPackageDefaults();
      return false;
    }
  }

  // ignore: unused_element
  Future<void> _fetchCurrentUser() async {
    try {
      final userData = await _apiService.getCurrentUser();
      if (userData != null) {
        _user = User.fromJson(userData);
      }
    } catch (e) {
      debugPrint('Error fetching user: $e');
    }
  }

  Future<void> logout() async {
    _isLoading = true;
    notifyListeners();

    GlobalLocationReporter.instance.stop();
    BranchSession.instance.clear();

    // Unregister FCM token before clearing access token.
    try {
      await FcmService.instance.unregisterForLogout();
    } catch (e) {
      debugPrint('FCM unregister error: $e');
    }

    await AppIconBadge.set(0);
    await SessionReset.clearForAccountSwitch();
    await _apiService.clearToken();
    NotificationPreferencesCache.instance.clear();

    // Clear sensitive credentials but KEEP saved identity (store code + email)
    // so users don't need to re-enter them on next login.
    try {
      final prefs = await SharedPreferences.getInstance();
      // Do NOT remove: saved_store_code, saved_email, admin_saved_email, remember_me, admin_remember_me
      await prefs.remove('saved_password');
      await prefs.remove('admin_saved_password');
      await prefs.remove(_impBackupAccess);
      await prefs.remove(_impBackupRefresh);
      await prefs.remove(_impLabelKey);
    } catch (e) {
      debugPrint('Clear saved credentials error: $e');
    }

    _token = null;
    _user = null;
    _error = null;
    _impersonationLabel = null;

    _isLoading = false;
    notifyListeners();
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }

  @override
  void dispose() {
    // Clear global callback to prevent stale reference after provider is destroyed
    if (ApiService.onUnauthorized == _handleSessionExpired) {
      ApiService.onUnauthorized = null;
    }
    if (ApiService.onLicenseExpired == _handleLicenseExpired) {
      ApiService.onLicenseExpired = null;
    }
    GlobalLocationReporter.instance.stop();
    super.dispose();
  }

  Future<bool> adminLogin(String email, String password) async {
    return login('', email, password);
  }
}
