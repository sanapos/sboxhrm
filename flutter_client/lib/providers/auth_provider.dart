import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/api_service.dart';
import '../services/fcm_service_stub.dart'
    if (dart.library.io) '../services/fcm_service.dart';
import '../utils/pending_notification_launch.dart';
import '../utils/store_role_helper.dart';
import '../services/global_location_reporter.dart';
import '../services/notification_preferences_cache.dart';
import '../services/session_reset.dart';
import '../models/user.dart';

class AuthProvider extends ChangeNotifier {
  User? _user;
  String? _token;
  bool _isLoading = false;
  bool _isInitializing = true;
  String? _error;

  User? get user => _user;
  User? get currentUser => _user;
  String? get token => _token;
  bool get isLoading => _isLoading;
  bool get isInitializing => _isInitializing;
  bool get isAuthenticated => _token != null && _user != null;
  String? get error => _error;
  String get userRole => _user?.role ?? 'Employee';

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
          _fetchAllowedModules().then((_) {
            if (_user != null) notifyListeners();
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
      await _fetchAllowedModules();
    }
  }

  /// Chạy sau khi UI đã thoát trạng thái initializing.
  void _runPostAuthSideEffects() {
    if (_token == null || _user == null) return;
    // ignore: discarded_futures
    verifyStoreLicense();
    // ignore: discarded_futures
    _fetchAllowedModules().then((_) {
      if (_user != null) notifyListeners();
    });
    GlobalLocationReporter.instance.startIfEligible(
      employeeId: _user?.employeeId ?? _user?.id,
    );
    // ignore: discarded_futures
    FcmService.instance.registerForCurrentUser();
    // ignore: discarded_futures
    NotificationPreferencesCache.instance.refresh(_apiService);
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
      await SessionReset.clearForAccountSwitch();

      debugPrint('🔐 AuthProvider: Attempting login for $storeCode / $email');

      // SuperAdmin/Agent login: no storeCode required
      final response = storeCode.trim().isEmpty
          ? await _apiService.adminLogin(email, password)
          : await _apiService.login(storeCode, email, password);

      if (response['isSuccess'] == true && response['data'] != null) {
        final data = response['data'];
        // Hủy FCM token của phiên cũ trước khi ghi token mới (tránh push nhầm tài khoản).
        try {
          await FcmService.instance.unregisterForLogout();
        } catch (e) {
          debugPrint('FCM pre-login unregister: $e');
        }

        // Hỗ trợ cả accessToken và token
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

  /// Lấy danh sách module được phép từ gói dịch vụ cửa hàng
  Future<void> _fetchAllowedModules({bool freshSession = false}) async {
    try {
      if (_user == null) return;
      if (StoreRoleHelper.bypassesPackageFilter(_user!.role)) return;

      final modules = await _apiService.getMyModules();
      // null = lỗi mạng/API — không xóa module đang có (tránh mất menu giữa ca).
      if (modules == null) {
        debugPrint(
            '⚠️ AuthProvider: getMyModules failed — keeping existing allowedModules');
        if (freshSession) {
          _user = _user!.copyWith(allowedModules: const []);
        }
        return;
      }
      _user = _user!.copyWith(allowedModules: modules);
      debugPrint('✅ AuthProvider: Loaded ${modules.length} allowed modules');
    } catch (e) {
      debugPrint('⚠️ AuthProvider: Error fetching allowed modules: $e');
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

    // Unregister FCM token before clearing access token.
    try {
      await FcmService.instance.unregisterForLogout();
    } catch (e) {
      debugPrint('FCM unregister error: $e');
    }

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
    } catch (e) {
      debugPrint('Clear saved credentials error: $e');
    }

    _token = null;
    _user = null;
    _error = null;

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
