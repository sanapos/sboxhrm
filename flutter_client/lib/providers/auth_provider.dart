import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/api_service.dart';
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
        debugPrint('⚠️ AuthProvider: Token refresh failed, using current token');
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
      return DateTime.now().isAfter(expiryDate.subtract(Duration(seconds: marginSeconds)));
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
          _user = _decodeUserFromToken(_token!);
          notifyListeners();
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
  }

  Future<void> _checkAuthStatus() async {
    _isInitializing = true;
    notifyListeners();

    try {
      final savedToken = await _apiService.getStoredToken();
      if (savedToken != null) {
        _token = savedToken;
        _user = _decodeUserFromToken(savedToken);
        
        // Auto-refresh if token is expired or expiring soon
        if (_isTokenExpiringSoon(savedToken)) {
          debugPrint('🔄 AuthProvider: Stored token expired/expiring, refreshing...');
          final refreshed = await _tryRefreshToken();
          if (!refreshed) {
            debugPrint('⚠️ AuthProvider: Token refresh failed, clearing session');
            _token = null;
            _user = null;
          }
        }
        
        // Fetch allowed modules cho store user
        if (_user != null) {
          await _fetchAllowedModules();
        }
      }
    } catch (e) {
      _token = null;
      _user = null;
    } finally {
      _isInitializing = false;
      _isLoading = false;
      notifyListeners();
    }
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
      
      return User(
        id: claims['http://schemas.xmlsoap.org/ws/2005/05/identity/claims/nameidentifier'] ?? '',
        email: claims['http://schemas.xmlsoap.org/ws/2005/05/identity/claims/emailaddress'] ?? claims['userName'] ?? '',
        fullName: claims['http://schemas.xmlsoap.org/ws/2005/05/identity/claims/name'] ?? 'User',
        role: claims['http://schemas.microsoft.com/ws/2008/06/identity/claims/role'] ?? 'Employee',
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
      debugPrint('🔐 AuthProvider: Attempting login for $storeCode / $email');
      
      // SuperAdmin/Agent login: no storeCode required
      final response = storeCode.trim().isEmpty
          ? await _apiService.adminLogin(email, password)
          : await _apiService.login(storeCode, email, password);
      
      if (response['isSuccess'] == true && response['data'] != null) {
        final data = response['data'];
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
          debugPrint('✅ AuthProvider: User decoded - ${_user?.fullName} (${_user?.role})');
          
          // Fetch allowed modules cho store user
          await _fetchAllowedModules();
          
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
  Future<void> _fetchAllowedModules() async {
    try {
      if (_user == null) return;
      // SuperAdmin/Agent không cần giới hạn module
      if (_user!.role == 'SuperAdmin' || _user!.role == 'Agent') return;
      
      final modules = await _apiService.getMyModules();
      if (modules.isNotEmpty) {
        _user = _user!.copyWith(allowedModules: modules);
        debugPrint('✅ AuthProvider: Loaded ${modules.length} allowed modules');
      } else {
        debugPrint('ℹ️ AuthProvider: No module restrictions (empty list)');
      }
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

    await _apiService.clearToken();

    // Clear saved credentials for security
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('remember_me');
      await prefs.remove('saved_store_code');
      await prefs.remove('saved_email');
      await prefs.remove('saved_password');
      await prefs.remove('admin_remember_me');
      await prefs.remove('admin_saved_email');
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

  Future<bool> adminLogin(String email, String password) async {
    return login('', email, password);
  }
}
