import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:http_parser/http_parser.dart' show MediaType;
import 'package:shared_preferences/shared_preferences.dart';
import 'api_config.dart';
import '../utils/api_datetime.dart';
import '../utils/app_error_utils.dart';
import '../utils/attendance_correction_dates.dart';
import '../utils/excel_bytes_utils.dart';
import '../models/pos_product.dart';

/// Query phân trang cho API dùng [PaginationRequest] (pageNumber + alias page).
Map<String, String> paginationQueryParams(int page, int pageSize) => {
      'pageNumber': page.toString(),
      'pageSize': pageSize.toString(),
      'page': page.toString(),
    };

class ApiService {
  static final String baseUrl = getApiBaseUrl();
  static const String _tokenKey = 'access_token';
  static const String _refreshTokenKey = 'refresh_token';
  static const Duration _defaultTimeout = Duration(seconds: 8);

  /// Global callback invoked when a 401 is received AND refresh token fails.
  /// AuthProvider registers this to perform auto-logout on session expiry.
  static Future<void> Function()? onUnauthorized;

  /// Invoked when store license expired (403 LICENSE_EXPIRED).
  static Future<void> Function(String message)? onLicenseExpired;

  static const String licenseExpiredCode = 'LICENSE_EXPIRED';

  String? _token;

  // Singleton pattern
  static final ApiService _instance = ApiService._internal();
  factory ApiService() => _instance;
  ApiService._internal();

  Map<String, dynamic> _connectionFailure(Object e, {String? fallback}) =>
      AppErrorUtils.apiFailure(e, fallbackMessage: fallback);

  Future<Map<String, String>> _loginAccessPayload({required bool posApp}) async {
    final prefs = await SharedPreferences.getInstance();
    var key = prefs.getString('sbox_access_device_key') ?? '';
    if (key.isEmpty) {
      key =
          '${DateTime.now().microsecondsSinceEpoch.toRadixString(16)}${prefs.hashCode.abs().toRadixString(16)}';
      await prefs.setString('sbox_access_device_key', key);
    }
    String platform;
    if (kIsWeb) {
      platform = 'web';
    } else if (posApp) {
      platform = 'pos';
    } else if (defaultTargetPlatform == TargetPlatform.iOS) {
      platform = 'ios';
    } else if (defaultTargetPlatform == TargetPlatform.android) {
      platform = 'android';
    } else {
      platform = 'mobile';
    }
    return {
      'clientPlatform': platform,
      'deviceKey': key,
      'deviceName': posApp ? 'POS' : (kIsWeb ? 'Web' : 'HRM'),
    };
  }

  // Headers với token
  Map<String, String> get _headers {
    final headers = {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };
    if (_token != null) {
      headers['Authorization'] = 'Bearer $_token';
    }
    return headers;
  }

  /// Headers for binary downloads (Excel/PDF) — avoid `Accept: application/json`.
  Map<String, String> get _binaryDownloadHeaders {
    final headers = <String, String>{'Accept': '*/*'};
    if (_token != null) {
      headers['Authorization'] = 'Bearer $_token';
    }
    return headers;
  }

  Map<String, dynamic> _parseExcelExportResponse(http.Response response) {
    if (response.statusCode >= 200 && response.statusCode < 300) {
      final bytes = response.bodyBytes;
      if (!isValidXlsxBytes(bytes)) {
        return {
          'isSuccess': false,
          'message': parseNonExcelExportError(bytes) ??
              'File tải về không phải Excel hợp lệ.',
        };
      }
      return {'isSuccess': true, 'data': bytes.toList()};
    }

    final body = utf8.decode(response.bodyBytes, allowMalformed: true);
    try {
      final data = json.decode(body);
      if (data is Map<String, dynamic>) {
        final normalized = _normalizeResponseMap(data);
        return {
          'isSuccess': false,
          'message': normalized['message']?.toString() ??
              'Export thất bại: ${response.statusCode}',
        };
      }
    } catch (_) {}
    return {
      'isSuccess': false,
      'message': body.trim().isNotEmpty
          ? body.trim()
          : 'Export thất bại: ${response.statusCode}',
    };
  }

  Future<Map<String, dynamic>> _getExcelExport(
    Uri uri, {
    Duration timeout = const Duration(seconds: 60),
  }) async {
    try {
      final response = await _retryOnUnauthorized(
        () => http.get(uri, headers: _binaryDownloadHeaders).timeout(timeout),
      );
      return _parseExcelExportResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  /// Header cho CachedNetworkImage (ảnh stores/uploads qua /api/upload/serve).
  Map<String, String>? get imageAuthHeaders =>
      _token != null ? {'Authorization': 'Bearer $_token'} : null;

  /// Path ảnh sản phẩm POS qua API chuyên dụng.
  static String posProductImagePath(String productId) =>
      'pos-product-image:$productId';

  /// CircleAvatar / DecorationImage — có Bearer token.
  ImageProvider storeImageProvider(String pathOrUrl) {
    return NetworkImage(
      getFileUrl(pathOrUrl),
      headers: imageAuthHeaders,
    );
  }

  // Lưu token
  Future<void> saveToken(String token) async {
    _token = token;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tokenKey, token);
  }

  // Lấy token đã lưu
  Future<String?> getStoredToken() async {
    final prefs = await SharedPreferences.getInstance();
    _token = prefs.getString(_tokenKey);
    return _token;
  }

  // Xóa token
  Future<void> clearToken() async {
    _token = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
    await prefs.remove(_refreshTokenKey);
  }

  Future<Map<String, dynamic>> submitLandingConsultation({
    required String name,
    required String phone,
    String? company,
    String? province,
    String? interestedPlan,
    String? notes,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/api/publicconsultations'),
            headers: {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
            body: json.encode({
              'name': name,
              'phone': phone,
              'company': company,
              'province': province,
              'interestedPlan': interestedPlan,
              'notes': notes,
            }),
          )
          .timeout(_defaultTimeout);

      final body = json.decode(response.body) as Map<String, dynamic>;
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return body;
      }
      return body.isNotEmpty
          ? body
          : {
              'isSuccess': false,
              'errors': ['Không thể gửi yêu cầu tư vấn']
            };
    } catch (e) {
      debugPrint('Error submitting landing consultation: $e');
      return {
        'isSuccess': false,
        'errors': ['Không thể gửi yêu cầu tư vấn: $e']
      };
    }
  }

  // Lưu refresh token
  Future<void> saveRefreshToken(String refreshToken) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_refreshTokenKey, refreshToken);
  }

  // Refresh access token using refresh token
  Future<Map<String, dynamic>?> refreshToken() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final refreshTk = prefs.getString(_refreshTokenKey);
      if (refreshTk == null) return null;

      final response = await http
          .post(
            Uri.parse('$baseUrl/api/auth/refresh'),
            headers: {'Content-Type': 'application/json'},
            body: json.encode({'refreshToken': refreshTk}),
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final result = json.decode(response.body);
        if (result is Map<String, dynamic>) {
          final normalized = _normalizeResponseMap(result);
          if (result['isSuccess'] == true && result['data'] != null) {
            final data = result['data'];
            // Update in-memory token
            _token = data['accessToken'] ?? data['token'];
            if (_token != null) {
              await saveToken(_token!);
            }
            // Save new refresh token
            if (data['refreshToken'] != null) {
              await saveRefreshToken(data['refreshToken']);
            }
            return data;
          }
          if (_isLicenseExpiredResponse(response, normalized)) {
            await _triggerLicenseExpired(
              normalized['message']?.toString() ??
                  'Cửa hàng đã hết hạn sử dụng. Vui lòng liên hệ quản trị viên để gia hạn.',
            );
          }
        }
      }
    } catch (e) {
      debugPrint('❌ ApiService: Refresh token error: $e');
    }
    return null;
  }

  /// Tự động retry khi gặp 401: refresh token rồi gửi lại request
  Future<http.Response> _retryOnUnauthorized(
      Future<http.Response> Function() requestFn) async {
    var response = await requestFn();
    if (response.statusCode == 401) {
      debugPrint('🔄 ApiService: Got 401, attempting token refresh...');
      final refreshResult = await refreshToken();
      if (refreshResult != null) {
        debugPrint('✅ ApiService: Token refreshed, retrying request...');
        response = await requestFn();
        // If still 401 after refresh, session is truly expired
        if (response.statusCode == 401) {
          debugPrint('❌ ApiService: Still 401 after refresh → session expired');
          await _triggerSessionExpired();
        }
      } else {
        debugPrint('❌ ApiService: Token refresh failed → session expired');
        await _triggerSessionExpired();
      }
    }
    await _maybeTriggerLicenseExpired(response);
    return response;
  }

  bool _isLicenseExpiredResponse(
      http.Response response, Map<String, dynamic> normalized) {
    final header = response.headers['x-sbox-error-code'] ??
        response.headers['X-SBOX-Error-Code'];
    if (header?.toUpperCase() == licenseExpiredCode) return true;
    final errors = normalized['errors'] ?? normalized['Errors'];
    if (errors is List &&
        errors.any((e) => e.toString().toUpperCase() == licenseExpiredCode)) {
      return true;
    }
    final msg = (normalized['message'] ?? '').toString().toLowerCase();
    return msg.contains('hết hạn sử dụng');
  }

  bool _licenseExpiredTriggered = false;

  Future<void> _maybeTriggerLicenseExpired(http.Response response) async {
    if (response.statusCode != 403) return;
    try {
      final rawBody = utf8.decode(response.bodyBytes, allowMalformed: true);
      if (rawBody.isEmpty) return;
      final data = json.decode(rawBody);
      if (data is! Map<String, dynamic>) return;
      final normalized = _normalizeResponseMap(data);
      if (!_isLicenseExpiredResponse(response, normalized)) return;
      await _triggerLicenseExpired(
          normalized['message']?.toString() ??
              'Cửa hàng đã hết hạn sử dụng. Vui lòng liên hệ quản trị viên để gia hạn.');
    } catch (_) {}
  }

  Future<void> _triggerLicenseExpired(String message) async {
    if (_licenseExpiredTriggered) return;
    _licenseExpiredTriggered = true;
    try {
      final cb = onLicenseExpired;
      if (cb != null) {
        await cb(message);
      }
    } catch (e) {
      debugPrint('❌ ApiService: onLicenseExpired callback error: $e');
    } finally {
      Future<void>.delayed(const Duration(seconds: 10), () {
        _licenseExpiredTriggered = false;
      });
    }
  }

  /// Gọi khi app mở/resume — trả true nếu license đã hết hạn (đã kích logout).
  Future<bool> checkStoreLicenseExpired() async {
    if (_token == null) return false;
    try {
      final response = await http
          .get(
            Uri.parse('$baseUrl/api/store/license-status'),
            headers: _headers,
          )
          .timeout(const Duration(seconds: 8));
      await _maybeTriggerLicenseExpired(response);
      if (response.statusCode == 403) return true;
      final data = _handleResponse(response);
      if (data['isSuccess'] == true && data['data'] is Map) {
        final payload = data['data'] as Map;
        if (payload['isExpired'] == true) {
          await _triggerLicenseExpired(
            payload['message']?.toString() ??
                'Cửa hàng đã hết hạn sử dụng. Vui lòng liên hệ quản trị viên để gia hạn.',
          );
          return true;
        }
      }
    } catch (e) {
      debugPrint('⚠️ checkStoreLicenseExpired: $e');
    }
    return false;
  }

  bool _sessionExpiredTriggered = false;
  DateTime? _lastSessionExpiredAt;

  Future<void> _triggerSessionExpired() async {
    // Use timestamp-based dedup so the flag is never "reset" while user is
    // still on the login screen, preventing double-logout cascades.
    final now = DateTime.now();
    if (_lastSessionExpiredAt != null &&
        now.difference(_lastSessionExpiredAt!).inSeconds < 10) {
      return; // Already triggered recently
    }
    if (_sessionExpiredTriggered) return;
    _sessionExpiredTriggered = true;
    _lastSessionExpiredAt = now;
    try {
      final cb = onUnauthorized;
      if (cb != null) {
        await cb();
      }
    } catch (e) {
      debugPrint('❌ ApiService: onUnauthorized callback error: $e');
    } finally {
      // Re-allow triggering only after a full login cycle (10s window)
      Future<void>.delayed(const Duration(seconds: 10), () {
        _sessionExpiredTriggered = false;
      });
    }
  }

  // ==================== AUTH ====================
  Future<Map<String, dynamic>> login(
      String storeCode, String email, String password) async {
    try {
      debugPrint('🔐 Login attempt to $baseUrl/api/auth/login');
      final access = await _loginAccessPayload(posApp: true);
      final response = await http
          .post(
            Uri.parse('$baseUrl/api/auth/login'),
            headers: {'Content-Type': 'application/json'},
            body: json.encode({
              'storeCode': storeCode,
              'userName': email,
              'password': password,
              ...access,
            }),
          )
          .timeout(const Duration(seconds: 10));
      debugPrint('📥 Login response status: ${response.statusCode}');
      // NOTE: Never log response.body here — it contains access/refresh tokens
      return _handleResponse(response);
    } catch (e) {
      debugPrint('❌ Login error: $e');
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> adminLogin(String email, String password) async {
    try {
      debugPrint('🔐 AdminLogin attempt to $baseUrl/api/auth/AdminLogin');
      final response = await http
          .post(
            Uri.parse('$baseUrl/api/auth/AdminLogin'),
            headers: {'Content-Type': 'application/json'},
            body: json.encode({'userName': email, 'password': password}),
          )
          .timeout(const Duration(seconds: 10));
      debugPrint('📥 AdminLogin response status: ${response.statusCode}');
      // NOTE: Never log response.body here — it contains access/refresh tokens
      return _handleResponse(response);
    } catch (e) {
      debugPrint('❌ AdminLogin error: $e');
      return _connectionFailure(e);
    }
  }

  // Khởi tạo SuperAdmin đầu tiên (chỉ hoạt động khi chưa có SuperAdmin)
  Future<Map<String, dynamic>> setupSuperAdmin(
      String email, String password, String? fullName) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/api/Auth/Setup'),
            headers: {'Content-Type': 'application/json'},
            body: json.encode({
              'email': email,
              'password': password,
              'fullName': fullName,
            }),
          )
          .timeout(const Duration(seconds: 15));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  // Đăng ký cửa hàng mới
  Future<Map<String, dynamic>> register(
      String storeName, String email, String password,
      {required String phoneNumber,
      required String province,
      String? storeCode,
      String? agentCode,
      String? servicePackageId,
      String? sellProfile}) async {
    try {
      debugPrint('📝 Register attempt: $storeName - $email'
          '${agentCode != null && agentCode.isNotEmpty ? ' (agent: $agentCode)' : ''}');
      final body = {
        'storeName': storeName,
        'email': email,
        'password': password,
        'phoneNumber': phoneNumber,
        'province': province,
      };
      if (storeCode != null && storeCode.isNotEmpty) {
        body['storeCode'] = storeCode;
      }
      if (agentCode != null && agentCode.isNotEmpty) {
        body['agentCode'] = agentCode;
      }
      if (servicePackageId != null && servicePackageId.isNotEmpty) {
        body['servicePackageId'] = servicePackageId;
      }
      if (sellProfile != null && sellProfile.isNotEmpty) {
        body['sellProfile'] = sellProfile;
      }
      final response = await http
          .post(
            Uri.parse('$baseUrl/api/auth/register'),
            headers: {'Content-Type': 'application/json'},
            body: json.encode(body),
          )
          .timeout(const Duration(seconds: 10));
      debugPrint('📥 Register response status: ${response.statusCode}');
      return _handleResponse(response);
    } catch (e) {
      debugPrint('❌ Register error: $e');
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> getPublicServicePackages() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/api/auth/publicservicepackages'),
        headers: {'Content-Type': 'application/json'},
      ).timeout(const Duration(seconds: 10));
      return _handleResponse(response);
    } catch (e) {
      return {
        'isSuccess': false,
        'message': 'Không thể tải danh sách gói dịch vụ: $e',
      };
    }
  }

  /// Cài đặt dữ liệu mẫu cho cửa hàng mới đăng ký
  Future<Map<String, dynamic>> seedSampleData(String storeCode) async {
    try {
      debugPrint('🌱 Seeding sample data for store: $storeCode');
      final response = await http.post(
        Uri.parse('$baseUrl/api/sampledata/seed/$storeCode'),
        headers: {'Content-Type': 'application/json'},
      ).timeout(const Duration(seconds: 30));
      debugPrint('📥 Seed response: ${response.statusCode}');
      return _handleResponse(response);
    } catch (e) {
      debugPrint('❌ Seed error: $e');
      return {
        'isSuccess': false,
        'message': 'Không thể cài dữ liệu mẫu: $e',
      };
    }
  }

  /// Xóa toàn bộ dữ liệu mẫu của cửa hàng
  Future<Map<String, dynamic>> deleteSampleData(String storeCode) async {
    try {
      debugPrint('🗑️ Deleting sample data for store: $storeCode');
      final response = await http
          .delete(
            Uri.parse('$baseUrl/api/sampledata/delete/$storeCode'),
            headers: _headers,
          )
          .timeout(const Duration(seconds: 30));
      debugPrint('📥 Delete sample response: ${response.statusCode}');
      return _handleResponse(response);
    } catch (e) {
      debugPrint('❌ Delete sample error: $e');
      return {
        'isSuccess': false,
        'message': 'Không thể xóa dữ liệu mẫu: $e',
      };
    }
  }

  Future<Map<String, dynamic>?> getCurrentUser() async {
    try {
      final response = await http
          .get(
            Uri.parse('$baseUrl/api/auth/me'),
            headers: _headers,
          )
          .timeout(const Duration(seconds: 10));
      final data = _handleResponse(response);
      if (data['isSuccess'] == true) {
        return data['data'];
      }
    } catch (e) {
      debugPrint('Error getting current user: $e');
    }
    return null;
  }

  // ==================== DEVICES ====================
  Future<List<dynamic>> getDevices({bool storeOnly = false}) async {
    try {
      final url = storeOnly
          ? '$baseUrl/api/devices?storeOnly=true'
          : '$baseUrl/api/devices';
      debugPrint('🌐 GET $url');
      debugPrint('🔑 Headers: $_headers');
      final response = await _retryOnUnauthorized(() => http
          .get(
            Uri.parse(url),
            headers: _headers,
          )
          .timeout(const Duration(seconds: 10)));
      debugPrint('📥 Response status: ${response.statusCode}');
      debugPrint('📥 Response body: ${response.body}');
      final data = _handleResponse(response);
      if (data['isSuccess'] == true) {
        final devices = data['data'] ?? [];
        debugPrint('✅ Got ${devices.length} devices');
        return devices;
      }
      debugPrint('⚠️ isSuccess != true: $data');
    } catch (e) {
      debugPrint('❌ Error getting devices: $e');
    }
    return [];
  }

  Future<Map<String, dynamic>?> getDeviceInfo(String deviceId) async {
    try {
      final response = await _retryOnUnauthorized(() => http
          .get(
            Uri.parse('$baseUrl/api/devices/$deviceId/device-info'),
            headers: _headers,
          )
          .timeout(const Duration(seconds: 10)));
      final data = _handleResponse(response);
      if (data['isSuccess'] == true) {
        return data['data'];
      }
    } catch (e) {
      debugPrint('Error getting device info: $e');
    }
    return null;
  }

  /// Refresh trạng thái online/offline của thiết bị từ server
  Future<Map<String, dynamic>?> refreshDeviceStatus(String deviceId) async {
    try {
      final response = await _retryOnUnauthorized(() => http
          .get(
            Uri.parse('$baseUrl/api/devices/$deviceId/refresh-status'),
            headers: _headers,
          )
          .timeout(const Duration(seconds: 5)));
      final data = _handleResponse(response);
      if (data['isSuccess'] == true) {
        return data['data'];
      }
    } catch (e) {
      debugPrint('Error refreshing device status: $e');
    }
    return null;
  }

  /// Kiểm tra thiết bị có online không trước khi gửi lệnh.
  /// Trả về true nếu online, false nếu offline.
  Future<bool> isDeviceOnline(String deviceId) async {
    final status = await refreshDeviceStatus(deviceId);
    if (status == null) return false;
    return status['isOnline'] == true;
  }

  Future<Map<String, dynamic>> createDevice(
      Map<String, dynamic> deviceData) async {
    try {
      final response = await _retryOnUnauthorized(() => http
          .post(
            Uri.parse('$baseUrl/api/devices'),
            headers: _headers,
            body: json.encode(deviceData),
          )
          .timeout(const Duration(seconds: 10)));
      final data = _handleResponse(response);
      if (data['isSuccess'] == true) {
        return {'success': true, 'device': data['data']};
      }
      return {
        'success': false,
        'message': data['message'] ?? 'Lỗi thêm thiết bị',
      };
    } catch (e) {
      debugPrint('Error creating device: $e');
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> deleteDevice(String deviceId) async {
    try {
      final response = await _retryOnUnauthorized(() => http
          .delete(
            Uri.parse('$baseUrl/api/devices/$deviceId'),
            headers: _headers,
          )
          .timeout(const Duration(seconds: 10)));
      final data = _handleResponse(response);
      if (data['isSuccess'] == true) {
        return {'success': true};
      }
      return {
        'success': false,
        'message': data['message'] ?? 'Lỗi xóa thiết bị',
      };
    } catch (e) {
      debugPrint('Error deleting device: $e');
      return _connectionFailure(e);
    }
  }

  Future<bool> toggleDeviceActive(String deviceId) async {
    try {
      final response = await http
          .put(
            Uri.parse('$baseUrl/api/devices/$deviceId/toggle-active'),
            headers: _headers,
          )
          .timeout(const Duration(seconds: 10));
      final data = _handleResponse(response);
      return data['isSuccess'] == true;
    } catch (e) {
      debugPrint('Error toggling device: $e');
      return false;
    }
  }

  Future<bool> updateDevice(
      String deviceId, Map<String, dynamic> updateData) async {
    try {
      final response = await _retryOnUnauthorized(() => http
          .put(
            Uri.parse('$baseUrl/api/devices/$deviceId'),
            headers: _headers,
            body: json.encode(updateData),
          )
          .timeout(const Duration(seconds: 10)));
      final data = _handleResponse(response);
      return data['isSuccess'] == true;
    } catch (e) {
      debugPrint('Error updating device: $e');
      return false;
    }
  }

  // ==================== PENDING / CONNECTED DEVICES ====================
  Future<List<dynamic>> getPendingDevices() async {
    try {
      final response = await _retryOnUnauthorized(() => http
          .get(
            Uri.parse('$baseUrl/api/devices/pending'),
            headers: _headers,
          )
          .timeout(const Duration(seconds: 10)));
      final data = _handleResponse(response);
      if (data['isSuccess'] == true) {
        return data['data'] ?? [];
      }
    } catch (e) {
      debugPrint('Error getting pending devices: $e');
    }
    return [];
  }

  Future<List<dynamic>> getConnectedDevices() async {
    try {
      final response = await _retryOnUnauthorized(() => http
          .get(
            Uri.parse('$baseUrl/api/devices/connected'),
            headers: _headers,
          )
          .timeout(const Duration(seconds: 10)));
      final data = _handleResponse(response);
      if (data['isSuccess'] == true) {
        return data['data'] ?? [];
      }
    } catch (e) {
      debugPrint('Error getting connected devices: $e');
    }
    return [];
  }

  Future<Map<String, dynamic>?> approveDevice(
      String deviceId, String deviceName,
      {String? description, String? location}) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/api/devices/$deviceId/approve'),
            headers: _headers,
            body: json.encode({
              'deviceName': deviceName,
              if (description != null) 'description': description,
              if (location != null) 'location': location,
            }),
          )
          .timeout(const Duration(seconds: 10));
      final data = _handleResponse(response);
      if (data['isSuccess'] == true) {
        return data['data'];
      }
    } catch (e) {
      debugPrint('Error approving device: $e');
    }
    return null;
  }

  Future<bool> rejectDevice(String deviceId) async {
    try {
      final response = await http
          .delete(
            Uri.parse('$baseUrl/api/devices/$deviceId/reject'),
            headers: _headers,
          )
          .timeout(const Duration(seconds: 10));
      final data = _handleResponse(response);
      return data['isSuccess'] == true;
    } catch (e) {
      debugPrint('Error rejecting device: $e');
      return false;
    }
  }

  // ==================== USER CLAIM DEVICE ====================
  Future<List<dynamic>> getMyDevices() async {
    try {
      final response = await http
          .get(
            Uri.parse('$baseUrl/api/devices/my-devices'),
            headers: _headers,
          )
          .timeout(const Duration(seconds: 10));
      final data = _handleResponse(response);
      if (data['isSuccess'] == true) {
        return data['data'] ?? [];
      }
    } catch (e) {
      debugPrint('Error getting my devices: $e');
    }
    return [];
  }

  Future<Map<String, dynamic>> checkSerialNumber(String serialNumber) async {
    try {
      final response = await http
          .get(
            Uri.parse('$baseUrl/api/devices/check-serial/$serialNumber'),
            headers: _headers,
          )
          .timeout(const Duration(seconds: 10));
      final data = _handleResponse(response);
      if (data['isSuccess'] == true) {
        return data['data'] ?? {};
      }
      return {
        'serialNumber': serialNumber,
        'exists': false,
        'isAvailable': false,
        'isClaimed': false,
        'message': data['message'] ?? 'Lỗi kiểm tra thiết bị',
      };
    } catch (e) {
      debugPrint('Error checking serial number: $e');
      final fail = _connectionFailure(e);
      return {
        'serialNumber': serialNumber,
        'exists': false,
        'isAvailable': false,
        'isClaimed': false,
        'error': true,
        'message': fail['message'],
      };
    }
  }

  Future<Map<String, dynamic>> claimDevice({
    required String serialNumber,
    required String deviceName,
    String? description,
    String? location,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/api/devices/claim'),
            headers: _headers,
            body: json.encode({
              'serialNumber': serialNumber,
              'deviceName': deviceName,
              if (description != null) 'description': description,
              if (location != null) 'location': location,
            }),
          )
          .timeout(const Duration(seconds: 10));
      final data = _handleResponse(response);
      if (data['isSuccess'] == true) {
        return {
          'success': true,
          'device': data['data'],
        };
      }
      return {
        'success': false,
        'message': data['message'] ?? 'Lỗi đăng ký thiết bị',
      };
    } catch (e) {
      debugPrint('Error claiming device: $e');
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> unclaimDevice(String deviceId) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/api/devices/$deviceId/unclaim'),
            headers: _headers,
          )
          .timeout(const Duration(seconds: 10));
      final data = _handleResponse(response);
      if (data['isSuccess'] == true) {
        return {'success': true};
      }
      return {
        'success': false,
        'message': data['message'] ?? 'Không thể hủy đăng ký thiết bị',
      };
    } catch (e) {
      debugPrint('Error unclaiming device: $e');
      return _connectionFailure(e);
    }
  }

  // ==================== EMPLOYEES ====================
  /// [page] null = tải hết các trang (tránh chỉ 200–1000 NV đầu).
  Future<List<dynamic>> getEmployees({
    int? page,
    int? pageSize,
    String? branchId,
    bool includeChildBranches = true,
    bool excludeResigned = false,
  }) async {
    final size = pageSize ?? 500;
    if (page != null) {
      return _getEmployeesPage(
          page, size, branchId, includeChildBranches, excludeResigned);
    }
    final all = <dynamic>[];
    for (var p = 1; p <= 50; p++) {
      final items = await _getEmployeesPage(
          p, size, branchId, includeChildBranches, excludeResigned);
      if (items.isEmpty) break;
      all.addAll(items);
      if (items.length < size) break;
    }
    return all;
  }

  /// Danh sách NV cho dropdown/picker — không gồm đã nghỉ việc.
  Future<List<dynamic>> getEmployeesForSelect({
    int? page,
    int? pageSize,
    String? branchId,
    bool includeChildBranches = true,
  }) =>
      getEmployees(
        page: page,
        pageSize: pageSize,
        branchId: branchId,
        includeChildBranches: includeChildBranches,
        excludeResigned: true,
      );

  Future<List<dynamic>> _getEmployeesPage(
    int page,
    int pageSize,
    String? branchId,
    bool includeChildBranches,
    bool excludeResigned,
  ) async {
    try {
      final params = paginationQueryParams(page, pageSize);
      if (branchId != null) {
        params['branchId'] = branchId;
        params['includeChildBranches'] = includeChildBranches.toString();
      }
      if (excludeResigned) params['excludeResigned'] = 'true';
      final uri = Uri.parse('$baseUrl/api/employees')
          .replace(queryParameters: params);
      final response = await http
          .get(uri, headers: _headers)
          .timeout(const Duration(seconds: 15));
      final data = _handleResponse(response);
      if (data['isSuccess'] == true) {
        final responseData = data['data'];
        if (responseData is List) return responseData;
        if (responseData is Map && responseData['items'] != null) {
          return responseData['items'] as List<dynamic>;
        }
      }
    } catch (e) {
      debugPrint('Error getting employees page $page: $e');
    }
    return [];
  }

  /// Full-store birthday list — not filtered by manager scope.
  /// Returns lightweight objects with id, firstName, lastName, department, dateOfBirth, photoUrl.
  Future<List<dynamic>> getBirthdays() async {
    try {
      final uri = Uri.parse('$baseUrl/api/employees/birthdays');
      final response = await http
          .get(uri, headers: _headers)
          .timeout(const Duration(seconds: 10));
      final data = _handleResponse(response);
      if (data['isSuccess'] == true) {
        final d = data['data'];
        if (d is List) return d;
      }
    } catch (e) {
      debugPrint('Error getting birthdays: $e');
    }
    return [];
  }

  /// Returns { 'expiring': [...], 'expired': [...] }
  Future<Map<String, dynamic>> getExpiringContracts(
      {int daysAhead = 30}) async {
    try {
      final uri = Uri.parse(
          '$baseUrl/api/employees/expiring-contracts?daysAhead=$daysAhead');
      final response = await http
          .get(uri, headers: _headers)
          .timeout(const Duration(seconds: 10));
      final data = _handleResponse(response);
      if (data['isSuccess'] == true) {
        final d = data['data'];
        if (d is Map) {
          return {
            'expiring': (d['expiring'] as List?) ?? [],
            'expired': (d['expired'] as List?) ?? [],
          };
        }
      }
    } catch (e) {
      debugPrint('Error getting expiring contracts: $e');
    }
    return {'expiring': [], 'expired': []};
  }

  /// Get current user's own employee profile (Employee role)
  Future<Map<String, dynamic>> getMyEmployee() async {
    try {
      final response = await http
          .get(
            Uri.parse('$baseUrl/api/employees/me'),
            headers: _headers,
          )
          .timeout(const Duration(seconds: 10));
      return _handleResponse(response);
    } catch (e) {
      debugPrint('Error getting my employee: $e');
      return {'isSuccess': false, 'message': e.toString()};
    }
  }

  Future<Map<String, dynamic>> createEmployee(
      Map<String, dynamic> employeeData) async {
    try {
      final response = await _retryOnUnauthorized(
        () => http
            .post(
              Uri.parse('$baseUrl/api/employees'),
              headers: _headers,
              body: json.encode(employeeData),
            )
            .timeout(const Duration(seconds: 15)),
      );
      return _handleResponse(response);
    } catch (e) {
      debugPrint('Error creating employee: $e');
      return _connectionFailure(e);
    }
  }

  Future<bool> updateEmployee(
      String employeeId, Map<String, dynamic> employeeData) async {
    try {
      final response = await http
          .put(
            Uri.parse('$baseUrl/api/employees/$employeeId'),
            headers: _headers,
            body: json.encode(employeeData),
          )
          .timeout(const Duration(seconds: 10));
      final data = _handleResponse(response);
      return data['isSuccess'] != false;
    } catch (e) {
      debugPrint('Error updating employee: $e');
      return false;
    }
  }

  Future<Map<String, dynamic>> deleteEmployee(String employeeId) async {
    try {
      final response = await http
          .delete(
            Uri.parse('$baseUrl/api/employees/$employeeId'),
            headers: _headers,
          )
          .timeout(const Duration(seconds: 10));
      return _handleResponse(response);
    } catch (e) {
      debugPrint('Error deleting employee: $e');
      return {
        'isSuccess': false,
        'message': 'Không thể xóa nhân viên',
      };
    }
  }

  Future<Map<String, dynamic>> getEmployeesDeleteEligibility(
      List<String> employeeIds) async {
    try {
      final ids = employeeIds.where((id) => id.isNotEmpty).toList();
      if (ids.isEmpty) {
        return {'isSuccess': true, 'data': {}};
      }
      final response = await http
          .post(
            Uri.parse('$baseUrl/api/employees/delete-eligibility'),
            headers: _headers,
            body: json.encode({'employeeIds': ids}),
          )
          .timeout(const Duration(seconds: 15));
      return _handleResponse(response);
    } catch (e) {
      debugPrint('Error checking employee delete eligibility: $e');
      return {'isSuccess': false, 'data': {}};
    }
  }

  /// Export employees as Excel — returns raw bytes
  Future<Map<String, dynamic>> exportEmployeesExcel() async {
    return _getExcelExport(
      Uri.parse('$baseUrl/api/employees/export/excel'),
      timeout: const Duration(seconds: 30),
    );
  }

  /// Upload .xlsx file — server parses with ClosedXML (matches SBOX export format).
  Future<Map<String, dynamic>> importEmployeesExcelFile(
      List<int> fileBytes, String fileName) async {
    try {
      debugPrint('📤 Uploading employee Excel: $fileName (${fileBytes.length} bytes)');
      if (!isValidXlsxBytes(fileBytes)) {
        return {
          'success': false,
          'message': 'File không phải Excel (.xlsx) hợp lệ.',
        };
      }
      final uri = Uri.parse('$baseUrl/api/employees/import/excel/file');
      final safeName = fileName.endsWith('.xlsx') || fileName.endsWith('.xls')
          ? fileName
          : '$fileName.xlsx';

      Future<http.Response> sendRequest() async {
        final request = http.MultipartRequest('POST', uri);
        final authHeaders = _headers;
        if (authHeaders.containsKey('Authorization')) {
          request.headers['Authorization'] = authHeaders['Authorization']!;
        }
        request.files.add(http.MultipartFile.fromBytes(
          'file',
          fileBytes,
          filename: safeName,
          contentType: MediaType(
            'application',
            'vnd.openxmlformats-officedocument.spreadsheetml.sheet',
          ),
        ));
        final streamedResponse =
            await request.send().timeout(const Duration(seconds: 120));
        return http.Response.fromStream(streamedResponse);
      }

      final response = await _retryOnUnauthorized(sendRequest);
      debugPrint('📥 Import employees file response: ${response.statusCode}');
      final data = _handleResponse(response);
      if (data['isSuccess'] == true) {
        return {
          'success': true,
          'imported': data['data']?['imported'] ?? 0,
          'updated': data['data']?['updated'] ?? 0,
          'failed': data['data']?['failed'] ?? 0,
          'withDepartment': data['data']?['withDepartment'] ?? 0,
          'errors': data['data']?['errors'] ?? [],
          'message': data['message'] ?? '',
        };
      }
      return {
        'success': false,
        'message': data['message'] ?? 'Import thất bại'
      };
    } catch (e) {
      return {'success': false, 'message': e.toString()};
    }
  }

  /// Import employees from a list of employee records (parsed from Excel)
  Future<Map<String, dynamic>> importEmployeesFromExcel(
      List<Map<String, dynamic>> records) async {
    try {
      debugPrint('📤 Importing ${records.length} employee records');
      final response = await http
          .post(
            Uri.parse('$baseUrl/api/employees/import/excel'),
            headers: _headers,
            body: json.encode(records),
          )
          .timeout(const Duration(seconds: 60));
      debugPrint('📥 Import employees response: ${response.statusCode}');
      final data = _handleResponse(response);
      if (data['isSuccess'] == true) {
        return {
          'success': true,
          'imported': data['data']?['imported'] ?? 0,
          'updated': data['data']?['updated'] ?? 0,
          'failed': data['data']?['failed'] ?? 0,
          'errors': data['data']?['errors'] ?? [],
          'message': data['message'] ?? '',
        };
      }
      return {
        'success': false,
        'message': data['message'] ?? 'Import thất bại'
      };
    } catch (e) {
      return {'success': false, 'message': e.toString()};
    }
  }

  // ==================== ATTENDANCE ====================
  Future<Map<String, dynamic>> getAttendances({
    List<String>? deviceIds,
    DateTime? fromDate,
    DateTime? toDate,
    int page = 1,
    int pageSize = 20,
  }) async {
    try {
      final queryParams = paginationQueryParams(page, pageSize);

      // Sử dụng POST endpoint với body
      final body = <String, dynamic>{
        'deviceIds': deviceIds ?? [],
        'fromDate':
            (fromDate ?? DateTime.now().subtract(const Duration(days: 7)))
                .toIso8601String(),
        'toDate': (toDate ?? DateTime.now()).toIso8601String(),
      };

      final uri = Uri.parse('$baseUrl/api/attendances/devices')
          .replace(queryParameters: queryParams);
      debugPrint('📤 Getting attendances from: $uri with body: $body');

      final response = await _retryOnUnauthorized(() => http
          .post(
            uri,
            headers: _headers,
            body: json.encode(body),
          )
          .timeout(Duration(seconds: pageSize >= 500 ? 45 : 15)));

      debugPrint('📥 Attendance response status: ${response.statusCode}');
      final data = _handleResponse(response);

      if (data['isSuccess'] == true) {
        final responseData = data['data'];
        final map = responseData is Map ? responseData as Map : null;
        return {
          'items': map != null
              ? (map['items'] ?? map['Items'] ?? [])
              : (responseData ?? []),
          'totalCount': _toInt(
              map != null ? (map['totalCount'] ?? map['TotalCount']) : null,
              0),
          'pageNumber': _toInt(
              map != null ? (map['pageNumber'] ?? map['PageNumber']) : null,
              page),
          'pageSize': _toInt(
              map != null ? (map['pageSize'] ?? map['PageSize']) : null,
              pageSize),
        };
      }
      debugPrint('❌ Attendance response error: ${data['message']}');
    } catch (e) {
      debugPrint('Error getting attendances: $e');
    }
    return {'items': [], 'totalCount': 0, 'pageNumber': 1, 'pageSize': 20};
  }

  /// Đếm log chấm công trên server theo thiết bị (theo dõi đồng bộ máy).
  Future<int> getAttendanceLogCount(
    String deviceId, {
    DateTime? fromDate,
    DateTime? toDate,
  }) async {
    try {
      final params = <String, String>{};
      if (fromDate != null) {
        params['fromDate'] = fromDate.toIso8601String();
      }
      if (toDate != null) {
        params['toDate'] = toDate.toIso8601String();
      }
      final uri = Uri.parse('$baseUrl/api/attendances/devices/$deviceId/count')
          .replace(queryParameters: params.isNotEmpty ? params : null);
      final response = await http.get(uri, headers: _headers);
      final data = _handleResponse(response);
      if (data['isSuccess'] == true) {
        final v = data['data'];
        if (v is int) return v;
        if (v is num) return v.toInt();
        return int.tryParse(v?.toString() ?? '') ?? 0;
      }
    } catch (e) {
      debugPrint('Error getAttendanceLogCount: $e');
    }
    return 0;
  }

  /// Create manual attendance record (ghi thẳng AttendanceLogs).
  Future<Map<String, dynamic>> createManualAttendance({
    required String employeeId,
    required DateTime punchTime,
    String? deviceId,
    String? note,
  }) async {
    try {
      debugPrint('📤 Creating manual attendance for employee: $employeeId');

      final body = <String, dynamic>{
        'employeeId': employeeId,
        'punchTime': punchTime.toIso8601String(),
        'verifyType': 100,
        'note': note ?? 'Chấm công thủ công',
        'isManual': true,
      };
      if (deviceId != null && deviceId.isNotEmpty) {
        body['deviceId'] = deviceId;
      }

      final response = await http
          .post(
            Uri.parse('$baseUrl/api/attendances/manual'),
            headers: _headers,
            body: json.encode(body),
          )
          .timeout(const Duration(seconds: 15));

      return _handleResponse(response);
    } catch (e) {
      debugPrint('❌ Error creating manual attendance: $e');
      return _connectionFailure(e);
    }
  }

  /// Import attendances from Excel data
  Future<Map<String, dynamic>> importAttendancesFromExcel(
      List<Map<String, dynamic>> records) async {
    try {
      debugPrint(
          '📤 Importing ${records.length} attendance records from Excel');

      final response = await http
          .post(
            Uri.parse('$baseUrl/api/attendances/import'),
            headers: _headers,
            body: json.encode({'records': records}),
          )
          .timeout(const Duration(seconds: 30));

      debugPrint('📥 Import response: ${response.statusCode}');
      final data = _handleResponse(response);

      if (data['isSuccess'] == true) {
        return {
          'success': true,
          'imported': data['data']?['imported'] ?? records.length,
          'failed': data['data']?['failed'] ?? 0,
          'errors': data['data']?['errors'] ?? [],
        };
      }
      return {
        'success': false,
        'message': data['message'] ?? 'Import failed',
        'errors': data['errors'] ?? [],
      };
    } catch (e) {
      debugPrint('❌ Error importing attendances: $e');
      return {
        'success': false,
        'message': e.toString(),
      };
    }
  }

  /// Delete an attendance record (trả message lỗi từ API khi thất bại).
  Future<Map<String, dynamic>> deleteAttendanceResult(String id) async {
    try {
      debugPrint('📤 Deleting attendance: $id');

      final response = await _retryOnUnauthorized(() => http
          .delete(
            Uri.parse('$baseUrl/api/attendances/$id'),
            headers: _headers,
          )
          .timeout(const Duration(seconds: 15)));

      debugPrint('📥 Delete attendance response: ${response.statusCode}');
      if (response.statusCode == 204) {
        return {'isSuccess': true};
      }
      return _handleResponse(response);
    } catch (e) {
      debugPrint('❌ Error deleting attendance: $e');
      return _connectionFailure(e);
    }
  }

  /// Delete an attendance record
  Future<bool> deleteAttendance(String id) async {
    final r = await deleteAttendanceResult(id);
    return r['isSuccess'] == true;
  }

  /// Update an attendance record
  /// Lưu ý: attendanceState sẽ được backend tự động tính dựa vào vị trí trong ngày
  Future<bool> updateAttendance(
    String id, {
    required DateTime attendanceTime,
  }) async {
    try {
      debugPrint('📤 Updating attendance: $id');

      final response = await _retryOnUnauthorized(() => http
          .put(
            Uri.parse('$baseUrl/api/attendances/$id'),
            headers: _headers,
            body: json.encode({
              'attendanceTime': attendanceTime.toIso8601String(),
            }),
          )
          .timeout(const Duration(seconds: 15)));

      debugPrint('📥 Update attendance response: ${response.statusCode}');
      final data = _handleResponse(response);
      return data['isSuccess'] == true;
    } catch (e) {
      debugPrint('❌ Error updating attendance: $e');
      return false;
    }
  }

  // ==================== DASHBOARD ====================
  /// Get employee dashboard data (AtLeastEmployee)
  Future<Map<String, dynamic>> getEmployeeDashboard(
      {String period = 'week'}) async {
    try {
      final response = await http
          .get(
            Uri.parse('$baseUrl/api/dashboard/employee?period=$period'),
            headers: _headers,
          )
          .timeout(const Duration(seconds: 10));
      return _handleResponse(response);
    } catch (e) {
      debugPrint('Error getting employee dashboard: $e');
      return {'isSuccess': false, 'message': e.toString()};
    }
  }

  Future<Map<String, dynamic>?> getDashboardSummary() async {
    try {
      final response = await http
          .get(
            Uri.parse('$baseUrl/api/dashboard/manager'),
            headers: _headers,
          )
          .timeout(const Duration(seconds: 10));
      final data = _handleResponse(response);
      if (data['isSuccess'] == true) {
        return data['data'];
      }
    } catch (e) {
      debugPrint('Error getting dashboard summary: $e');
    }
    return null;
  }

  Future<List<dynamic>> getAttendanceTrends({int days = 30}) async {
    try {
      final response = await http
          .get(
            Uri.parse('$baseUrl/api/dashboard/attendance-trends?days=$days'),
            headers: _headers,
          )
          .timeout(const Duration(seconds: 10));
      final data = _handleResponse(response);
      if (data['isSuccess'] == true) {
        return data['data'] ?? [];
      }
    } catch (e) {
      debugPrint('Error getting attendance trends: $e');
    }
    return [];
  }

  Future<List<dynamic>> getDeviceStatus() async {
    try {
      final response = await http
          .get(
            Uri.parse('$baseUrl/api/devices'),
            headers: _headers,
          )
          .timeout(const Duration(seconds: 10));
      final data = _handleResponse(response);
      if (data['isSuccess'] == true) {
        return data['data'] ?? [];
      }
    } catch (e) {
      debugPrint('Error getting device status: $e');
    }
    return [];
  }

  // ==================== GOOGLE SHEETS ====================
  Future<bool> testGoogleSheetsConnection() async {
    try {
      final response = await http
          .get(
            Uri.parse('$baseUrl/api/GoogleSheets/test-connection'),
            headers: _headers,
          )
          .timeout(const Duration(seconds: 10));
      final data = _handleResponse(response);
      return data['isSuccess'] == true && data['data'] == true;
    } catch (e) {
      debugPrint('Error testing Google Sheets connection: $e');
      return false;
    }
  }

  Future<bool> initializeGoogleSheets(
      String spreadsheetId, String? credentialsPath) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/api/GoogleSheets/initialize'),
            headers: _headers,
            body: json.encode({
              'spreadsheetId': spreadsheetId,
              if (credentialsPath != null && credentialsPath.isNotEmpty)
                'credentialsPath': credentialsPath,
            }),
          )
          .timeout(const Duration(seconds: 10));
      final data = _handleResponse(response);
      return data['isSuccess'] == true && data['data'] == true;
    } catch (e) {
      debugPrint('Error initializing Google Sheets: $e');
      return false;
    }
  }

  Future<bool> syncDevicesToSheets() async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/api/GoogleSheets/sync-devices'),
            headers: _headers,
          )
          .timeout(const Duration(seconds: 10));
      final data = _handleResponse(response);
      return data['isSuccess'] == true && data['data'] == true;
    } catch (e) {
      debugPrint('Error syncing devices: $e');
      return false;
    }
  }

  Future<bool> syncEmployeesToSheets() async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/api/GoogleSheets/sync-employees'),
            headers: _headers,
          )
          .timeout(const Duration(seconds: 10));
      final data = _handleResponse(response);
      return data['isSuccess'] == true && data['data'] == true;
    } catch (e) {
      debugPrint('Error syncing employees: $e');
      return false;
    }
  }

  Future<bool> syncAttendancesToSheets(String date) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/api/GoogleSheets/sync-attendances'),
            headers: _headers,
            body: json.encode({'date': date}),
          )
          .timeout(const Duration(seconds: 10));
      final data = _handleResponse(response);
      return data['isSuccess'] == true && data['data'] == true;
    } catch (e) {
      debugPrint('Error syncing attendances: $e');
      return false;
    }
  }

  Future<Map<String, dynamic>?> syncAllToSheets() async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/api/GoogleSheets/sync-all'),
            headers: _headers,
          )
          .timeout(const Duration(seconds: 10));
      final data = _handleResponse(response);
      if (data['isSuccess'] == true) {
        return data['data'];
      }
    } catch (e) {
      debugPrint('Error syncing all: $e');
    }
    return null;
  }

  // ==================== DEVICE USERS (User trên máy chấm công) ====================
  Future<List<dynamic>> getDeviceUsers({String? deviceId}) async {
    try {
      final response = await _retryOnUnauthorized(() => http
          .post(
            Uri.parse('$baseUrl/api/deviceusers/devices'),
            headers: _headers,
            body: json.encode({
              'deviceIds': deviceId != null ? [deviceId] : [],
            }),
          )
          .timeout(const Duration(seconds: 10)));
      final data = _handleResponse(response);
      if (data['isSuccess'] == true) {
        return data['data'] ?? [];
      }
    } catch (e) {
      debugPrint('Error getting device users: $e');
    }
    return [];
  }

  Future<List<dynamic>> getDeviceUsersByDeviceIds(
      List<String> deviceIds) async {
    try {
      final response = await _retryOnUnauthorized(() => http
          .post(
            Uri.parse('$baseUrl/api/deviceusers/devices'),
            headers: _headers,
            body: json.encode({
              'deviceIds': deviceIds,
            }),
          )
          .timeout(const Duration(seconds: 10)));
      final data = _handleResponse(response);
      if (data['isSuccess'] == true) {
        return data['data'] ?? [];
      }
    } catch (e) {
      debugPrint('Error getting device users by device IDs: $e');
    }
    return [];
  }

  Future<Map<String, dynamic>> createDeviceUser(
      Map<String, dynamic> userData) async {
    try {
      debugPrint('📤 createDeviceUser Request: ${json.encode(userData)}');
      final response = await _retryOnUnauthorized(() => http
          .post(
            Uri.parse('$baseUrl/api/deviceusers'),
            headers: _headers,
            body: json.encode(userData),
          )
          .timeout(const Duration(seconds: 10)));
      debugPrint('📥 createDeviceUser Response Status: ${response.statusCode}');
      debugPrint('📥 createDeviceUser Response Body: ${response.body}');
      final data = _handleResponse(response);
      return data;
    } catch (e) {
      debugPrint('❌ Error creating device user: $e');
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> updateDeviceUser(
      String deviceUserId, Map<String, dynamic> userData) async {
    try {
      final response = await http
          .put(
            Uri.parse('$baseUrl/api/deviceusers/$deviceUserId'),
            headers: _headers,
            body: json.encode(userData),
          )
          .timeout(const Duration(seconds: 10));
      final data = _handleResponse(response);
      return data;
    } catch (e) {
      debugPrint('Error updating device user: $e');
      return _connectionFailure(e);
    }
  }

  Future<bool> deleteDeviceUser(String deviceUserId) async {
    try {
      final response = await http
          .delete(
            Uri.parse('$baseUrl/api/deviceusers/$deviceUserId'),
            headers: _headers,
          )
          .timeout(const Duration(seconds: 10));
      final data = _handleResponse(response);
      return data['isSuccess'] == true;
    } catch (e) {
      debugPrint('Error deleting device user: $e');
      return false;
    }
  }

  Future<bool> mapDeviceUserToEmployee(
      String deviceUserId, String employeeId) async {
    try {
      final response = await http
          .post(
            Uri.parse(
                '$baseUrl/api/deviceusers/$deviceUserId/map-employee/$employeeId'),
            headers: _headers,
          )
          .timeout(const Duration(seconds: 10));
      final data = _handleResponse(response);
      return data['isSuccess'] == true;
    } catch (e) {
      debugPrint('Error mapping device user to employee: $e');
      return false;
    }
  }

  // Gửi lệnh tải user từ máy chấm công về
  // CommandType enum: SyncDeviceUsers = 8
  Future<bool> sendSyncUsersCommand(String deviceId) async {
    try {
      if (!await isDeviceOnline(deviceId)) {
        debugPrint('❌ Device $deviceId is OFFLINE - cannot sync users');
        return false;
      }
      final url = '$baseUrl/api/devices/$deviceId/commands';
      debugPrint('📤 Sending sync users command');
      debugPrint('📤 URL: $url');
      debugPrint('📤 DeviceId: $deviceId');
      debugPrint('📤 Headers: $_headers');
      debugPrint('📤 Body: {"commandType":8,"priority":10}');

      final response = await http
          .post(
            Uri.parse(url),
            headers: _headers,
            body: json.encode({
              'commandType': 8, // SyncDeviceUsers enum value (0-indexed)
              'priority': 10,
            }),
          )
          .timeout(const Duration(seconds: 10));

      debugPrint('📥 Response status: ${response.statusCode}');
      debugPrint('📥 Response headers: ${response.headers}');
      debugPrint('📥 Response body: ${response.body}');

      final data = _handleResponse(response);
      debugPrint('📥 Parsed data: $data');
      debugPrint('📥 isSuccess: ${data['isSuccess']}');

      return data['isSuccess'] == true;
    } catch (e, stackTrace) {
      debugPrint('❌ Error sending sync users command: $e');
      debugPrint('❌ Stack trace: $stackTrace');
      return false;
    }
  }

  // Gửi lệnh tải chấm công từ máy chấm công về
  // CommandType enum: SyncAttendances = 7
  Future<bool> sendSyncAttendancesCommand(String deviceId) async {
    try {
      // Kiểm tra thiết bị online trước khi gửi lệnh
      if (!await isDeviceOnline(deviceId)) {
        debugPrint('❌ Device $deviceId is OFFLINE - cannot sync');
        return false;
      }

      final url = '$baseUrl/api/devices/$deviceId/commands';
      debugPrint('📤 Sending sync attendances command');
      debugPrint('📤 URL: $url');
      debugPrint('📤 DeviceId: $deviceId');
      debugPrint('📤 Body: {"commandType":7,"priority":10}');

      final response = await http
          .post(
            Uri.parse(url),
            headers: _headers,
            body: json.encode({
              'commandType': 7, // SyncAttendances enum value (0-indexed)
              'priority': 10,
            }),
          )
          .timeout(const Duration(seconds: 10));

      debugPrint('📥 Response status: ${response.statusCode}');
      debugPrint('📥 Response body: ${response.body}');

      final data = _handleResponse(response);
      debugPrint('📥 isSuccess: ${data['isSuccess']}');

      return data['isSuccess'] == true;
    } catch (e, stackTrace) {
      debugPrint('❌ Error sending sync attendances command: $e');
      debugPrint('❌ Stack trace: $stackTrace');
      return false;
    }
  }

  // Đồng bộ Employee vào máy chấm công
  Future<Map<String, dynamic>> syncEmployeeToDevice({
    required String employeeId,
    required String deviceId,
    required String pin,
    String? cardNumber,
    String? password,
    int privilege = 0,
  }) async {
    try {
      if (!await isDeviceOnline(deviceId)) {
        return {
          'isSuccess': false,
          'message':
              'Thiết bị đang offline. Vui lòng kiểm tra kết nối mạng của máy chấm công.'
        };
      }
      // Tạo DeviceUser từ Employee
      final response = await http
          .post(
            Uri.parse('$baseUrl/api/deviceusers'),
            headers: _headers,
            body: json.encode({
              'deviceId': deviceId,
              'pin': pin,
              'name': '', // Sẽ được lấy từ employeeId
              'cardNumber': cardNumber ?? '',
              'password': password ?? '',
              'privilege': privilege,
              'employeeId': employeeId,
            }),
          )
          .timeout(const Duration(seconds: 15));
      final data = _handleResponse(response);
      return data;
    } catch (e) {
      debugPrint('Error syncing employee to device: $e');
      return _connectionFailure(e);
    }
  }

  // Đăng ký vân tay - gửi lệnh ENROLL_FP đến máy chấm công
  Future<bool> enrollFingerprint(String deviceId, String pin,
      [int fingerIndex = 0]) async {
    try {
      if (!await isDeviceOnline(deviceId)) {
        debugPrint('❌ Device $deviceId is OFFLINE - cannot enroll fingerprint');
        return false;
      }
      debugPrint(
          '📤 Enrolling fingerprint for PIN=$pin, FID=$fingerIndex on device $deviceId');
      final response = await http
          .post(
            Uri.parse('$baseUrl/api/devices/$deviceId/commands'),
            headers: _headers,
            body: json.encode({
              'commandType': 9, // EnrollFingerprint
              'pin': pin,
              'fingerIndex': fingerIndex,
              'priority': 10,
            }),
          )
          .timeout(const Duration(seconds: 10));
      final data = _handleResponse(response);
      debugPrint('📥 Enroll fingerprint response: $data');
      return data['isSuccess'] == true;
    } catch (e) {
      debugPrint('Error enrolling fingerprint: $e');
      return false;
    }
  }

  // Đăng ký vân tay - trả về response đầy đủ để lấy commandId
  Future<Map<String, dynamic>?> enrollFingerprintWithResponse(
      String deviceId, String pin,
      [int fingerIndex = 0]) async {
    try {
      if (!await isDeviceOnline(deviceId)) {
        return {
          'isSuccess': false,
          'message':
              'Thiết bị đang offline. Vui lòng kiểm tra kết nối mạng của máy chấm công.'
        };
      }
      debugPrint(
          '📤 Enrolling fingerprint for PIN=$pin, FID=$fingerIndex on device $deviceId');
      final response = await http
          .post(
            Uri.parse('$baseUrl/api/devices/$deviceId/commands'),
            headers: _headers,
            body: json.encode({
              'commandType': 9, // EnrollFingerprint
              'pin': pin,
              'fingerIndex': fingerIndex,
              'priority': 10,
            }),
          )
          .timeout(const Duration(seconds: 10));
      final data = _handleResponse(response);
      debugPrint('📥 Enroll fingerprint response: $data');
      return data;
    } catch (e) {
      debugPrint('Error enrolling fingerprint: $e');
      return null;
    }
  }

  // Lấy trạng thái command
  Future<Map<String, dynamic>?> getCommandStatus(String commandId) async {
    try {
      final response = await http
          .get(
            Uri.parse('$baseUrl/api/devicecommands/$commandId'),
            headers: _headers,
          )
          .timeout(const Duration(seconds: 5));
      final data = _handleResponse(response);
      if (data['isSuccess'] == true && data['data'] != null) {
        return data['data'];
      }
      return null;
    } catch (e) {
      debugPrint('Error getting command status: $e');
      return null;
    }
  }

  // Xóa vân tay - gửi lệnh DATA DELETE FINGERTMP đến máy chấm công
  Future<bool> deleteFingerprint(String deviceId, String pin,
      [int? fingerIndex]) async {
    try {
      if (!await isDeviceOnline(deviceId)) {
        debugPrint('❌ Device $deviceId is OFFLINE - cannot delete fingerprint');
        return false;
      }
      final response = await http
          .post(
            Uri.parse('$baseUrl/api/devices/$deviceId/commands'),
            headers: _headers,
            body: json.encode({
              'commandType': 10, // DeleteFingerprint
              'pin': pin,
              if (fingerIndex != null && fingerIndex >= 0)
                'fingerIndex': fingerIndex,
              'priority': 10,
            }),
          )
          .timeout(const Duration(seconds: 10));
      final data = _handleResponse(response);
      debugPrint('📥 Delete fingerprint response: $data');
      return data['isSuccess'] == true;
    } catch (e) {
      debugPrint('Error deleting fingerprint: $e');
      return false;
    }
  }

  // Lấy danh sách vân tay đã đăng ký của user
  Future<List<Map<String, dynamic>>> getFingerprints(
      String deviceUserId) async {
    try {
      final response = await http
          .get(
            Uri.parse('$baseUrl/api/deviceusers/$deviceUserId/fingerprints'),
            headers: _headers,
          )
          .timeout(const Duration(seconds: 10));
      final data = _handleResponse(response);
      if (data['isSuccess'] == true && data['data'] != null) {
        return List<Map<String, dynamic>>.from(data['data']);
      }
      return [];
    } catch (e) {
      debugPrint('Error getting fingerprints: $e');
      return [];
    }
  }

  // Đồng bộ vân tay từ máy chấm công (DATA QUERY FINGERTMP)
  Future<bool> syncFingerprints(String deviceId) async {
    try {
      if (!await isDeviceOnline(deviceId)) {
        debugPrint('❌ Device $deviceId is OFFLINE - cannot sync fingerprints');
        return false;
      }
      debugPrint('📤 Syncing fingerprints from device $deviceId');
      final response = await http
          .post(
            Uri.parse('$baseUrl/api/devices/$deviceId/commands'),
            headers: _headers,
            body: json.encode({
              'commandType': 11, // SyncFingerprints = enum index 11
              'priority': 10,
            }),
          )
          .timeout(const Duration(seconds: 10));
      final data = _handleResponse(response);
      debugPrint('📥 Sync fingerprints response: $data');
      return data['isSuccess'] == true;
    } catch (e) {
      debugPrint('Error syncing fingerprints: $e');
      return false;
    }
  }

  // ==================== FACE MANAGEMENT ====================

  // Lấy danh sách khuôn mặt đã đăng ký của user
  Future<List<Map<String, dynamic>>> getDeviceUserFaces(
      String deviceUserId) async {
    try {
      final response = await http
          .get(
            Uri.parse('$baseUrl/api/deviceusers/$deviceUserId/faces'),
            headers: _headers,
          )
          .timeout(const Duration(seconds: 10));
      final data = _handleResponse(response);
      if (data['isSuccess'] == true && data['data'] != null) {
        return List<Map<String, dynamic>>.from(data['data']);
      }
      return [];
    } catch (e) {
      debugPrint('Error getting faces: $e');
      return [];
    }
  }

  // Đăng ký khuôn mặt từ xa — ENROLL_FP FID=50 BIODATAFLAG=8 (máy face ZAM70/visible light)
  Future<Map<String, dynamic>?> enrollFaceWithResponse(
      String deviceId, String pin) async {
    try {
      if (!await isDeviceOnline(deviceId)) {
        return {
          'isSuccess': false,
          'message':
              'Thiết bị đang offline. Vui lòng kiểm tra kết nối mạng của máy chấm công.'
        };
      }
      debugPrint('📤 Enrolling FACE for PIN=$pin on device $deviceId');
      final response = await http
          .post(
            Uri.parse('$baseUrl/api/devices/$deviceId/commands'),
            headers: _headers,
            body: json.encode({
              'commandType': 12, // EnrollFace
              'pin': pin,
              'priority': 10,
            }),
          )
          .timeout(const Duration(seconds: 10));
      final data = _handleResponse(response);
      debugPrint('📥 Enroll face response: $data');
      return data;
    } catch (e) {
      debugPrint('Error enrolling face: $e');
      return null;
    }
  }

  // Xóa khuôn mặt — PUSH SDK §7.8 DATA DELETE FACE PIN=...
  Future<bool> deleteDeviceUserFace(String deviceId, String pin) async {
    try {
      if (!await isDeviceOnline(deviceId)) {
        debugPrint('❌ Device $deviceId is OFFLINE - cannot delete face');
        return false;
      }
      debugPrint('📤 Deleting face for PIN=$pin on device $deviceId');
      final response = await http
          .post(
            Uri.parse('$baseUrl/api/devices/$deviceId/commands'),
            headers: _headers,
            body: json.encode({
              'commandType': 13, // DeleteFace
              'pin': pin,
              'priority': 10,
            }),
          )
          .timeout(const Duration(seconds: 10));
      final data = _handleResponse(response);
      debugPrint('📥 Delete face response: $data');
      return data['isSuccess'] == true;
    } catch (e) {
      debugPrint('Error deleting face: $e');
      return false;
    }
  }

  // ==================== WORK SCHEDULES ====================

  // Lấy danh sách lịch làm việc
  Future<Map<String, dynamic>> getWorkSchedules({
    int page = 1,
    int pageSize = 50,
    String? employeeUserId,
    String? employeeId,
    String? shiftId,
    DateTime? fromDate,
    DateTime? toDate,
    bool? isDayOff,
  }) async {
    try {
      final empId = employeeUserId ?? employeeId;
      final params = {
        'page': page.toString(),
        'pageSize': pageSize.toString(),
        if (empId != null) 'employeeUserId': empId,
        if (shiftId != null) 'shiftId': shiftId,
        if (fromDate != null) 'fromDate': fromDate.toIso8601String(),
        if (toDate != null) 'toDate': toDate.toIso8601String(),
        if (isDayOff != null) 'isDayOff': isDayOff.toString(),
      };
      final uri = Uri.parse('$baseUrl/api/workschedules')
          .replace(queryParameters: params);
      debugPrint('📤 Getting work schedules: $uri');
      final response = await http
          .get(uri, headers: _headers)
          .timeout(const Duration(seconds: 15));
      return _handleResponse(response);
    } catch (e) {
      debugPrint('Error getting work schedules: $e');
      return _connectionFailure(e);
    }
  }

  /// Get current user's own work schedules (Employee role)
  Future<Map<String, dynamic>> getMyWorkSchedules({
    DateTime? fromDate,
    DateTime? toDate,
    int pageSize = 50,
  }) async {
    try {
      final params = <String, String>{
        'pageSize': pageSize.toString(),
      };
      if (fromDate != null) params['fromDate'] = fromDate.toIso8601String();
      if (toDate != null) params['toDate'] = toDate.toIso8601String();
      final uri = Uri.parse('$baseUrl/api/workschedules/my')
          .replace(queryParameters: params.isNotEmpty ? params : null);
      final response = await http
          .get(uri, headers: _headers)
          .timeout(const Duration(seconds: 15));
      return _handleResponse(response);
    } catch (e) {
      debugPrint('Error getting my work schedules: $e');
      return _connectionFailure(e);
    }
  }

  // Lấy lịch làm việc theo ID
  Future<Map<String, dynamic>> getWorkScheduleById(String id) async {
    try {
      final response = await http
          .get(
            Uri.parse('$baseUrl/api/workschedules/$id'),
            headers: _headers,
          )
          .timeout(const Duration(seconds: 10));
      return _handleResponse(response);
    } catch (e) {
      debugPrint('Error getting work schedule: $e');
      return _connectionFailure(e);
    }
  }

  // Tạo lịch làm việc
  Future<Map<String, dynamic>> createWorkSchedule(
      Map<String, dynamic> data) async {
    try {
      debugPrint('📤 Creating work schedule: $data');
      final response = await http
          .post(
            Uri.parse('$baseUrl/api/workschedules'),
            headers: _headers,
            body: json.encode(data),
          )
          .timeout(const Duration(seconds: 10));
      return _handleResponse(response);
    } catch (e) {
      debugPrint('Error creating work schedule: $e');
      return _connectionFailure(e);
    }
  }

  // Tạo lịch làm việc hàng loạt
  Future<Map<String, dynamic>> bulkCreateWorkSchedules(
      Map<String, dynamic> data) async {
    try {
      debugPrint('📤 Bulk creating work schedules: $data');
      final response = await http
          .post(
            Uri.parse('$baseUrl/api/workschedules/bulk'),
            headers: _headers,
            body: json.encode(data),
          )
          .timeout(const Duration(seconds: 30));
      return _handleResponse(response);
    } catch (e) {
      debugPrint('Error bulk creating work schedules: $e');
      return _connectionFailure(e);
    }
  }

  // Cập nhật lịch làm việc
  Future<Map<String, dynamic>> updateWorkSchedule(
      String id, Map<String, dynamic> data) async {
    try {
      debugPrint('📤 Updating work schedule $id: $data');
      final response = await http
          .put(
            Uri.parse('$baseUrl/api/workschedules/$id'),
            headers: _headers,
            body: json.encode(data),
          )
          .timeout(const Duration(seconds: 10));
      return _handleResponse(response);
    } catch (e) {
      debugPrint('Error updating work schedule: $e');
      return _connectionFailure(e);
    }
  }

  // Xóa lịch làm việc
  Future<Map<String, dynamic>> deleteWorkSchedule(String id) async {
    try {
      debugPrint('📤 Deleting work schedule $id');
      final response = await http
          .delete(
            Uri.parse('$baseUrl/api/workschedules/$id'),
            headers: _headers,
          )
          .timeout(const Duration(seconds: 10));
      return _handleResponse(response);
    } catch (e) {
      debugPrint('Error deleting work schedule: $e');
      return _connectionFailure(e);
    }
  }

  // Lấy danh sách ca làm việc (shifts)
  Future<List<dynamic>> getShifts() async {
    try {
      debugPrint('📋 Getting shifts from: $baseUrl/api/shifts/templates');
      final response = await _retryOnUnauthorized(() => http
          .get(
            Uri.parse('$baseUrl/api/shifts/templates'),
            headers: _headers,
          )
          .timeout(const Duration(seconds: 10)));
      debugPrint('📋 Shifts response: ${response.body}');
      final data = _handleResponse(response);
      if (data['isSuccess'] == true && data['data'] != null) {
        debugPrint('📋 Shifts data: ${data['data']}');
        return data['data'] as List<dynamic>;
      }
      debugPrint('📋 Shifts: No data or isSuccess=false');
      return [];
    } catch (e) {
      debugPrint('❌ Error getting shifts: $e');
      return [];
    }
  }

  // Tạo ca làm việc
  Future<Map<String, dynamic>> createShift(Map<String, dynamic> data) async {
    try {
      debugPrint('📝 Creating shift: $data');
      final response = await _retryOnUnauthorized(() => http
          .post(
            Uri.parse('$baseUrl/api/shifts/templates'),
            headers: _headers,
            body: json.encode(data),
          )
          .timeout(const Duration(seconds: 10)));
      debugPrint(
          '📝 Create shift response: ${response.statusCode} - ${response.body}');
      return _handleResponse(response);
    } catch (e) {
      debugPrint('❌ Error creating shift: $e');
      return _connectionFailure(e);
    }
  }

  // Cập nhật ca làm việc
  Future<Map<String, dynamic>> updateShift(
      String id, Map<String, dynamic> data) async {
    try {
      final response = await _retryOnUnauthorized(() => http
          .put(
            Uri.parse('$baseUrl/api/shifts/templates/$id'),
            headers: _headers,
            body: json.encode(data),
          )
          .timeout(const Duration(seconds: 10)));
      return _handleResponse(response);
    } catch (e) {
      debugPrint('Error updating shift: $e');
      return _connectionFailure(e);
    }
  }

  // Xóa ca làm việc
  Future<Map<String, dynamic>> deleteShift(String id) async {
    try {
      final response = await _retryOnUnauthorized(() => http
          .delete(
            Uri.parse('$baseUrl/api/shifts/templates/$id'),
            headers: _headers,
          )
          .timeout(const Duration(seconds: 10)));
      return _handleResponse(response);
    } catch (e) {
      debugPrint('Error deleting shift: $e');
      return _connectionFailure(e);
    }
  }

  // ==================== SCHEDULE REGISTRATIONS ====================

  // Lấy danh sách đăng ký lịch
  Future<Map<String, dynamic>> getScheduleRegistrations({
    int page = 1,
    int pageSize = 50,
    String? employeeUserId,
    String? employeeId,
    int? status,
    DateTime? fromDate,
    DateTime? toDate,
  }) async {
    try {
      final empId = employeeUserId ?? employeeId;
      final params = {
        'page': page.toString(),
        'pageSize': pageSize.toString(),
        if (empId != null) 'employeeUserId': empId,
        if (status != null) 'status': status.toString(),
        if (fromDate != null) 'fromDate': fromDate.toIso8601String(),
        if (toDate != null) 'toDate': toDate.toIso8601String(),
      };
      final uri = Uri.parse('$baseUrl/api/workschedules/registrations')
          .replace(queryParameters: params);
      debugPrint('📤 Getting schedule registrations: $uri');
      final response = await http
          .get(uri, headers: _headers)
          .timeout(const Duration(seconds: 15));
      return _handleResponse(response);
    } catch (e) {
      debugPrint('Error getting schedule registrations: $e');
      return _connectionFailure(e);
    }
  }

  // Lấy đăng ký lịch của nhân viên hiện tại
  Future<Map<String, dynamic>> getMyScheduleRegistrations({
    int pageSize = 50,
    DateTime? fromDate,
    DateTime? toDate,
  }) async {
    try {
      final params = <String, String>{
        'pageSize': pageSize.toString(),
      };
      if (fromDate != null) params['fromDate'] = fromDate.toIso8601String();
      if (toDate != null) params['toDate'] = toDate.toIso8601String();
      final uri = Uri.parse('$baseUrl/api/workschedules/registrations/my')
          .replace(queryParameters: params.isNotEmpty ? params : null);
      debugPrint('📤 Getting my schedule registrations: $uri');
      final response = await http
          .get(uri, headers: _headers)
          .timeout(const Duration(seconds: 15));
      return _handleResponse(response);
    } catch (e) {
      debugPrint('Error getting my schedule registrations: $e');
      return _connectionFailure(e);
    }
  }

  // Tạo đăng ký lịch
  Future<Map<String, dynamic>> createScheduleRegistration(
      Map<String, dynamic> data) async {
    try {
      debugPrint('📤 Creating schedule registration: $data');
      final response = await http
          .post(
            Uri.parse('$baseUrl/api/workschedules/registrations'),
            headers: _headers,
            body: json.encode(data),
          )
          .timeout(const Duration(seconds: 10));
      return _handleResponse(response);
    } catch (e) {
      debugPrint('Error creating schedule registration: $e');
      return _connectionFailure(e);
    }
  }

  // Duyệt/Từ chối đăng ký lịch
  Future<Map<String, dynamic>> approveScheduleRegistration(
      String id, Map<String, dynamic> data) async {
    try {
      debugPrint('📤 Approving schedule registration $id: $data');
      final response = await http
          .post(
            Uri.parse('$baseUrl/api/workschedules/registrations/$id/approve'),
            headers: _headers,
            body: json.encode(data),
          )
          .timeout(const Duration(seconds: 10));
      return _handleResponse(response);
    } catch (e) {
      debugPrint('Error approving schedule registration: $e');
      return _connectionFailure(e);
    }
  }

  // Xóa đăng ký lịch
  Future<Map<String, dynamic>> deleteScheduleRegistration(String id) async {
    try {
      debugPrint('📤 Deleting schedule registration $id');
      final response = await http
          .delete(
            Uri.parse('$baseUrl/api/workschedules/registrations/$id'),
            headers: _headers,
          )
          .timeout(const Duration(seconds: 10));
      return _handleResponse(response);
    } catch (e) {
      debugPrint('Error deleting schedule registration: $e');
      return _connectionFailure(e);
    }
  }

  // Hoàn duyệt đăng ký lịch (undo approval)
  Future<Map<String, dynamic>> undoScheduleRegistrationApproval(
      String id) async {
    try {
      debugPrint('📤 Undo approval schedule registration $id');
      final response = await http
          .post(
            Uri.parse(
                '$baseUrl/api/workschedules/registrations/$id/undo-approval'),
            headers: _headers,
          )
          .timeout(const Duration(seconds: 10));
      return _handleResponse(response);
    } catch (e) {
      debugPrint('Error undoing schedule registration approval: $e');
      return _connectionFailure(e);
    }
  }

  // ==================== SCHEDULE NOTIFICATIONS & STAFFING QUOTAS ====================

  // Gửi nhắc nhở đăng ký lịch làm việc
  Future<Map<String, dynamic>> sendScheduleReminder(
      Map<String, dynamic> data) async {
    try {
      debugPrint('📤 Sending schedule reminder');
      final response = await http
          .post(
            Uri.parse('$baseUrl/api/workschedules/send-reminder'),
            headers: _headers,
            body: json.encode(data),
          )
          .timeout(const Duration(seconds: 15));
      return _handleResponse(response);
    } catch (e) {
      debugPrint('Error sending schedule reminder: $e');
      return _connectionFailure(e);
    }
  }

  // Yêu cầu bổ sung nhân viên cho ca
  Future<Map<String, dynamic>> requestShiftCoverage(
      Map<String, dynamic> data) async {
    try {
      debugPrint('📤 Requesting shift coverage');
      final response = await http
          .post(
            Uri.parse('$baseUrl/api/workschedules/request-coverage'),
            headers: _headers,
            body: json.encode(data),
          )
          .timeout(const Duration(seconds: 15));
      return _handleResponse(response);
    } catch (e) {
      debugPrint('Error requesting shift coverage: $e');
      return _connectionFailure(e);
    }
  }

  // Lấy danh sách định mức nhân sự
  Future<Map<String, dynamic>> getStaffingQuotas() async {
    try {
      debugPrint('📤 Getting staffing quotas');
      final response = await http
          .get(
            Uri.parse('$baseUrl/api/workschedules/staffing-quotas'),
            headers: _headers,
          )
          .timeout(const Duration(seconds: 10));
      return _handleResponse(response);
    } catch (e) {
      debugPrint('Error getting staffing quotas: $e');
      return _connectionFailure(e);
    }
  }

  // Tạo/cập nhật định mức nhân sự
  Future<Map<String, dynamic>> upsertStaffingQuota(
      Map<String, dynamic> data) async {
    try {
      debugPrint('📤 Upserting staffing quota');
      final response = await http
          .post(
            Uri.parse('$baseUrl/api/workschedules/staffing-quotas'),
            headers: _headers,
            body: json.encode(data),
          )
          .timeout(const Duration(seconds: 10));
      return _handleResponse(response);
    } catch (e) {
      debugPrint('Error upserting staffing quota: $e');
      return _connectionFailure(e);
    }
  }

  // Xóa định mức nhân sự
  Future<Map<String, dynamic>> deleteStaffingQuota(String id) async {
    try {
      debugPrint('📤 Deleting staffing quota $id');
      final response = await http
          .delete(
            Uri.parse('$baseUrl/api/workschedules/staffing-quotas/$id'),
            headers: _headers,
          )
          .timeout(const Duration(seconds: 10));
      return _handleResponse(response);
    } catch (e) {
      debugPrint('Error deleting staffing quota: $e');
      return _connectionFailure(e);
    }
  }

  // ==================== BENEFITS / SALARY PROFILES ====================

  // Get all salary profiles (benefits)
  Future<List<dynamic>> getSalaryProfiles() async {
    try {
      final response = await http
          .get(
            Uri.parse('$baseUrl/api/benefits'),
            headers: _headers,
          )
          .timeout(const Duration(seconds: 10));
      final result = _handleResponse(response);
      return result['data'] ?? [];
    } catch (e) {
      debugPrint('Error getting salary profiles: $e');
      return [];
    }
  }

  // Get salary profile by ID
  Future<Map<String, dynamic>?> getSalaryProfileById(String id) async {
    try {
      final response = await http
          .get(
            Uri.parse('$baseUrl/api/benefits/$id'),
            headers: _headers,
          )
          .timeout(const Duration(seconds: 10));
      final result = _handleResponse(response);
      if (result['isSuccess'] == true) {
        return result['data'];
      }
      return null;
    } catch (e) {
      debugPrint('Error getting salary profile: $e');
      return null;
    }
  }

  // Create salary profile
  Future<Map<String, dynamic>> createSalaryProfile(
      Map<String, dynamic> data) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/api/benefits'),
            headers: _headers,
            body: json.encode(data),
          )
          .timeout(const Duration(seconds: 10));
      return _handleResponse(response);
    } catch (e) {
      debugPrint('Error creating salary profile: $e');
      return _connectionFailure(e);
    }
  }

  // Update salary profile
  Future<Map<String, dynamic>> updateSalaryProfile(
      String id, Map<String, dynamic> data) async {
    try {
      final response = await http
          .put(
            Uri.parse('$baseUrl/api/benefits/$id'),
            headers: _headers,
            body: json.encode(data),
          )
          .timeout(const Duration(seconds: 10));
      return _handleResponse(response);
    } catch (e) {
      debugPrint('Error updating salary profile: $e');
      return _connectionFailure(e);
    }
  }

  // Delete salary profile
  Future<Map<String, dynamic>> deleteSalaryProfile(String id) async {
    try {
      final response = await http
          .delete(
            Uri.parse('$baseUrl/api/benefits/$id'),
            headers: _headers,
          )
          .timeout(const Duration(seconds: 10));
      return _handleResponse(response);
    } catch (e) {
      debugPrint('Error deleting salary profile: $e');
      return _connectionFailure(e);
    }
  }

  // Get employee salary profiles (employees with their benefits)
  Future<List<dynamic>> getEmployeeSalaryProfiles() async {
    try {
      final response = await http
          .get(
            Uri.parse('$baseUrl/api/benefits/employees'),
            headers: _headers,
          )
          .timeout(const Duration(seconds: 10));
      final result = _handleResponse(response);
      return result['data'] ?? [];
    } catch (e) {
      debugPrint('Error getting employee salary profiles: $e');
      return [];
    }
  }

  // Hồ sơ lương của user đang đăng nhập (role Employee).
  Future<Map<String, dynamic>?> getMyEmployeeSalaryProfile() async {
    try {
      final response = await http
          .get(
            Uri.parse('$baseUrl/api/benefits/me'),
            headers: _headers,
          )
          .timeout(const Duration(seconds: 10));
      final result = _handleResponse(response);
      return _parseSalaryProfileResponse(result);
    } catch (e) {
      debugPrint('Error getting my employee salary profile: $e');
      return null;
    }
  }

  Map<String, dynamic>? _parseSalaryProfileResponse(Map<String, dynamic> result) {
    if (result['isSuccess'] != true) return null;
    final data = result['data'];
    if (data is Map<String, dynamic> && data.isNotEmpty) {
      return data;
    }
    return null;
  }

  // Get employee salary profile by employee ID
  Future<Map<String, dynamic>?> getEmployeeSalaryProfile(
      String employeeId) async {
    try {
      final response = await http
          .get(
            Uri.parse('$baseUrl/api/benefits/employees/$employeeId'),
            headers: _headers,
          )
          .timeout(const Duration(seconds: 10));
      final result = _handleResponse(response);
      final profile = _parseSalaryProfileResponse(result);
      if (profile != null) return profile;
      // Fallback: NV có thể không có quyền Benefit nhưng /me vẫn trả hồ sơ của mình.
      final me = await getMyEmployeeSalaryProfile();
      if (me == null) return null;
      final meEmpId = me['employeeId']?.toString() ?? '';
      if (meEmpId.isEmpty ||
          meEmpId.toLowerCase() == employeeId.toLowerCase()) {
        return me;
      }
      return null;
    } catch (e) {
      debugPrint('Error getting employee salary profile: $e');
      return null;
    }
  }

  // Assign salary profile to employee
  Future<Map<String, dynamic>> assignSalaryProfile(
      Map<String, dynamic> data) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/api/benefits/assign'),
            headers: _headers,
            body: json.encode(data),
          )
          .timeout(const Duration(seconds: 10));
      return _handleResponse(response);
    } catch (e) {
      debugPrint('Error assigning salary profile: $e');
      return _connectionFailure(e);
    }
  }

  // ==================== STORE MODULES ====================

  /// Lấy danh sách module được phép của cửa hàng hiện tại.
  /// Trả `null` khi lỗi/không thành công — caller giữ cache cũ.
  Future<List<String>?> getMyModules() async {
    try {
      final response = await http
          .get(
            Uri.parse('$baseUrl/api/settings/my-modules'),
            headers: _headers,
          )
          .timeout(const Duration(seconds: 10));
      final result = _handleResponse(response);
      if (result['isSuccess'] == true && result['data'] != null) {
        return List<String>.from(result['data']);
      }
      // Thành công nhưng data null → coi như danh sách rỗng thật.
      if (result['isSuccess'] == true) return <String>[];
    } catch (e) {
      debugPrint('Error getting my modules: $e');
    }
    return null;
  }

  // ==================== SETTINGS ====================

  // Salary Settings
  Future<Map<String, dynamic>> getSalarySettings() async {
    try {
      final response = await http
          .get(
            Uri.parse('$baseUrl/api/settings/salary'),
            headers: _headers,
          )
          .timeout(const Duration(seconds: 10));
      final result = _handleResponse(response);
      return result['data'] ?? {};
    } catch (e) {
      debugPrint('Error getting salary settings: $e');
      return {};
    }
  }

  Future<Map<String, dynamic>> saveSalarySettings(
      Map<String, dynamic> settings) async {
    try {
      final response = await http
          .put(
            Uri.parse('$baseUrl/api/settings/salary'),
            headers: _headers,
            body: json.encode(settings),
          )
          .timeout(const Duration(seconds: 10));
      return _handleResponse(response);
    } catch (e) {
      debugPrint('Error saving salary settings: $e');
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> updateMobileAttendanceRecord({
    required String recordId,
    required DateTime punchTime,
    String? note,
  }) async {
    try {
      final response = await http
          .put(
            Uri.parse('$baseUrl/api/mobile-attendance/records/$recordId'),
            headers: _headers,
            body: json.encode({
              'punchTime': punchTime.toIso8601String(),
              if (note != null) 'note': note,
            }),
          )
          .timeout(const Duration(seconds: 15));
      return _handleResponse(response);
    } catch (e) {
      debugPrint('Error updating mobile attendance record: $e');
      return _connectionFailure(e);
    }
  }

  /// Quản lý bổ sung cặp chấm đi đường (đã duyệt).
  /// [existingStartRecordId] / [existingArriveRecordId]: gắn vào phiếu thiếu, không tạo trùng.
  Future<Map<String, dynamic>> createManualTravelAttendance({
    required String employeeId,
    required DateTime startTime,
    required DateTime arriveTime,
    String? note,
    String? existingStartRecordId,
    String? existingArriveRecordId,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/api/mobile-attendance/manual-travel'),
            headers: _headers,
            body: json.encode({
              'employeeId': employeeId,
              'startTime': startTime.toIso8601String(),
              'arriveTime': arriveTime.toIso8601String(),
              if (note != null && note.isNotEmpty) 'note': note,
              if (existingStartRecordId != null &&
                  existingStartRecordId.isNotEmpty)
                'existingStartRecordId': existingStartRecordId,
              if (existingArriveRecordId != null &&
                  existingArriveRecordId.isNotEmpty)
                'existingArriveRecordId': existingArriveRecordId,
            }),
          )
          .timeout(const Duration(seconds: 20));
      return _handleResponse(response);
    } catch (e) {
      debugPrint('Error creating manual travel attendance: $e');
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> deleteMobileAttendanceRecord(
      String recordId) async {
    try {
      final response = await http
          .delete(
            Uri.parse('$baseUrl/api/mobile-attendance/records/$recordId'),
            headers: _headers,
          )
          .timeout(const Duration(seconds: 15));
      return _handleResponse(response);
    } catch (e) {
      debugPrint('Error deleting mobile attendance record: $e');
      return _connectionFailure(e);
    }
  }

  // Attendance Settings
  Future<Map<String, dynamic>> getAttendanceSettings() async {
    try {
      final response = await http
          .get(
            Uri.parse('$baseUrl/api/settings/attendance'),
            headers: _headers,
          )
          .timeout(const Duration(seconds: 10));
      final result = _handleResponse(response);
      return result['data'] ?? {};
    } catch (e) {
      debugPrint('Error getting attendance settings: $e');
      return {};
    }
  }

  Future<Map<String, dynamic>> saveAttendanceSettings(
      Map<String, dynamic> settings) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/api/settings/attendance'),
            headers: _headers,
            body: json.encode(settings),
          )
          .timeout(const Duration(seconds: 10));
      return _handleResponse(response);
    } catch (e) {
      debugPrint('Error saving attendance settings: $e');
      return _connectionFailure(e);
    }
  }

  // Allowance Settings
  Future<List<dynamic>> getAllowanceSettings() async {
    try {
      final response = await http
          .get(
            Uri.parse('$baseUrl/api/allowances?pageSize=1000'),
            headers: _headers,
          )
          .timeout(const Duration(seconds: 10));
      final result = _handleResponse(response);
      return result['data']?['items'] ?? result['data'] ?? [];
    } catch (e) {
      debugPrint('Error getting allowance settings: $e');
      return [];
    }
  }

  Future<Map<String, dynamic>> createAllowanceSetting(
      Map<String, dynamic> data) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/api/allowances'),
            headers: _headers,
            body: json.encode(data),
          )
          .timeout(const Duration(seconds: 10));
      return _handleResponse(response);
    } catch (e) {
      debugPrint('Error creating allowance: $e');
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> updateAllowanceSetting(
      String id, Map<String, dynamic> data) async {
    try {
      final response = await http
          .put(
            Uri.parse('$baseUrl/api/allowances/$id'),
            headers: _headers,
            body: json.encode(data),
          )
          .timeout(const Duration(seconds: 10));
      return _handleResponse(response);
    } catch (e) {
      debugPrint('Error updating allowance: $e');
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> deleteAllowanceSetting(String id) async {
    try {
      final response = await http
          .delete(
            Uri.parse('$baseUrl/api/allowances/$id'),
            headers: _headers,
          )
          .timeout(const Duration(seconds: 10));
      return _handleResponse(response);
    } catch (e) {
      debugPrint('Error deleting allowance: $e');
      return _connectionFailure(e);
    }
  }

  // Holiday Settings. Pass year=0 to use API's default (current year).
  Future<List<dynamic>> getHolidaySettings(int year) async {
    try {
      // year=0 means "current year" — omit query so backend defaults
      // to DateTime.Now.Year. Otherwise the filter h.Date.Year==0 returns
      // an empty list.
      final url = year > 0
          ? '$baseUrl/api/settings/holidays?year=$year'
          : '$baseUrl/api/settings/holidays';
      final response = await http
          .get(
            Uri.parse(url),
            headers: _headers,
          )
          .timeout(const Duration(seconds: 10));
      final result = _handleResponse(response);
      return result['data'] ?? [];
    } catch (e) {
      debugPrint('Error getting holiday settings: $e');
      return [];
    }
  }

  Future<Map<String, dynamic>> createHolidaySetting(
      Map<String, dynamic> data) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/api/settings/holidays'),
            headers: _headers,
            body: json.encode(data),
          )
          .timeout(const Duration(seconds: 10));
      return _handleResponse(response);
    } catch (e) {
      debugPrint('Error creating holiday: $e');
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> updateHolidaySetting(
      String id, Map<String, dynamic> data) async {
    try {
      final response = await http
          .put(
            Uri.parse('$baseUrl/api/settings/holidays/$id'),
            headers: _headers,
            body: json.encode(data),
          )
          .timeout(const Duration(seconds: 10));
      return _handleResponse(response);
    } catch (e) {
      debugPrint('Error updating holiday: $e');
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> deleteHolidaySetting(String id) async {
    try {
      final response = await http
          .delete(
            Uri.parse('$baseUrl/api/settings/holidays/$id'),
            headers: _headers,
          )
          .timeout(const Duration(seconds: 10));
      return _handleResponse(response);
    } catch (e) {
      debugPrint('Error deleting holiday: $e');
      return _connectionFailure(e);
    }
  }

  // Penalty Settings
  Future<Map<String, dynamic>> getPenaltySettings() async {
    try {
      final response = await http
          .get(
            Uri.parse('$baseUrl/api/settings/penalty'),
            headers: _headers,
          )
          .timeout(const Duration(seconds: 10));
      return _handleResponse(response);
    } catch (e) {
      debugPrint('Error getting penalty settings: $e');
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> savePenaltySettings(
      Map<String, dynamic> data) async {
    try {
      final response = await http
          .put(
            Uri.parse('$baseUrl/api/settings/penalty'),
            headers: _headers,
            body: json.encode(data),
          )
          .timeout(const Duration(seconds: 10));
      return _handleResponse(response);
    } catch (e) {
      debugPrint('Error saving penalty settings: $e');
      return _connectionFailure(e);
    }
  }

  // Legacy methods for compatibility
  Future<List<dynamic>> getPenaltySettingsAsList() async {
    final result = await getPenaltySettings();
    if (result['isSuccess'] == true && result['data'] != null) {
      return [result['data']];
    }
    return [];
  }

  Future<Map<String, dynamic>> createPenaltySetting(
      Map<String, dynamic> data) async {
    return savePenaltySettings(data);
  }

  Future<Map<String, dynamic>> updatePenaltySetting(
      String id, Map<String, dynamic> data) async {
    return savePenaltySettings(data);
  }

  Future<Map<String, dynamic>> deletePenaltySetting(String id) async {
    return {'isSuccess': false, 'message': 'Không hỗ trợ xóa penalty settings'};
  }

  // Insurance Settings
  Future<Map<String, dynamic>> getInsuranceSettings() async {
    try {
      final response = await _retryOnUnauthorized(() => http
          .get(
            Uri.parse('$baseUrl/api/settings/insurance'),
            headers: _headers,
          )
          .timeout(const Duration(seconds: 10)));
      final result = _handleResponse(response);
      return result['data'] ?? {};
    } catch (e) {
      debugPrint('Error getting insurance settings: $e');
      return {};
    }
  }

  Future<Map<String, dynamic>> saveInsuranceSettings(
      Map<String, dynamic> settings) async {
    try {
      final response = await _retryOnUnauthorized(() => http
          .put(
            Uri.parse('$baseUrl/api/settings/insurance'),
            headers: _headers,
            body: json.encode(settings),
          )
          .timeout(const Duration(seconds: 10)));
      return _handleResponse(response);
    } catch (e) {
      debugPrint('Error saving insurance settings: $e');
      return _connectionFailure(e);
    }
  }

  // Tax Settings
  Future<Map<String, dynamic>> getTaxSettings() async {
    try {
      final response = await _retryOnUnauthorized(() => http
          .get(
            Uri.parse('$baseUrl/api/settings/tax'),
            headers: _headers,
          )
          .timeout(const Duration(seconds: 10)));
      final result = _handleResponse(response);
      return result['data'] ?? {};
    } catch (e) {
      debugPrint('Error getting tax settings: $e');
      return {};
    }
  }

  Future<Map<String, dynamic>> saveTaxSettings(
      Map<String, dynamic> settings) async {
    try {
      final response = await _retryOnUnauthorized(() => http
          .put(
            Uri.parse('$baseUrl/api/settings/tax'),
            headers: _headers,
            body: json.encode(settings),
          )
          .timeout(const Duration(seconds: 10)));
      return _handleResponse(response);
    } catch (e) {
      debugPrint('Error saving tax settings: $e');
      return _connectionFailure(e);
    }
  }

  // Employee Tax Deductions
  Future<List<dynamic>> getEmployeeTaxDeductions() async {
    try {
      final response = await http
          .get(
            Uri.parse('$baseUrl/api/settings/tax/employee-deductions'),
            headers: _headers,
          )
          .timeout(const Duration(seconds: 10));
      debugPrint('getEmployeeTaxDeductions status: ${response.statusCode}');
      final result = _handleResponse(response);
      final data = result['data'] ?? [];
      debugPrint(
          'getEmployeeTaxDeductions count: ${data is List ? data.length : 'not a list'}');
      return data is List ? data : [];
    } catch (e) {
      debugPrint('Error getting employee tax deductions: $e');
      return [];
    }
  }

  Future<Map<String, dynamic>> saveEmployeeTaxDeduction(
      Map<String, dynamic> data) async {
    try {
      final response = await http
          .put(
            Uri.parse('$baseUrl/api/settings/tax/employee-deductions'),
            headers: _headers,
            body: json.encode(data),
          )
          .timeout(const Duration(seconds: 10));
      return _handleResponse(response);
    } catch (e) {
      debugPrint('Error saving employee tax deduction: $e');
      return _connectionFailure(e);
    }
  }

  // ==================== PERMISSIONS / ROLE MANAGEMENT ====================

  /// Lấy danh sách các roles (chức danh)
  Future<List<dynamic>> getRoles({String? storeId}) async {
    try {
      final uri = storeId != null
          ? Uri.parse('$baseUrl/api/permission-management/all?storeId=$storeId')
          : Uri.parse('$baseUrl/api/permission-management/all');
      final response = await _retryOnUnauthorized(() => http
          .get(uri, headers: _headers)
          .timeout(const Duration(seconds: 10)));
      final result = _handleResponse(response);
      return result['data'] ?? [];
    } catch (e) {
      debugPrint('Error getting roles: $e');
      return [];
    }
  }

  /// Lấy danh sách các module (permissions)
  Future<List<dynamic>> getPermissionModules() async {
    try {
      final response = await _retryOnUnauthorized(() => http
          .get(
            Uri.parse('$baseUrl/api/permission-management/modules'),
            headers: _headers,
          )
          .timeout(const Duration(seconds: 10)));
      final result = _handleResponse(response);
      return result['data'] ?? [];
    } catch (e) {
      debugPrint('Error getting permission modules: $e');
      return [];
    }
  }

  /// Lấy chi tiết quyền của một role
  Future<Map<String, dynamic>> getRolePermissions(String roleName,
      {String? storeId}) async {
    try {
      final uri = storeId != null
          ? Uri.parse(
              '$baseUrl/api/permission-management/by-role?roleName=$roleName&storeId=$storeId')
          : Uri.parse(
              '$baseUrl/api/permission-management/by-role?roleName=$roleName');
      final response = await _retryOnUnauthorized(() => http
          .get(uri, headers: _headers)
          .timeout(const Duration(seconds: 10)));
      final result = _handleResponse(response);
      return result['data'] ?? {};
    } catch (e) {
      debugPrint('Error getting role permissions: $e');
      return {};
    }
  }

  /// Lưu phân quyền cho role
  Future<Map<String, dynamic>> saveRolePermissions(
      Map<String, dynamic> data) async {
    try {
      final roleName = data['roleName'] ?? '';
      final permissions = data['permissions'] ?? [];
      final response = await _retryOnUnauthorized(() => http
          .put(
            Uri.parse('$baseUrl/api/permission-management/role/$roleName'),
            headers: _headers,
            body: json.encode(permissions),
          )
          .timeout(const Duration(seconds: 10)));
      return _handleResponse(response);
    } catch (e) {
      debugPrint('Error saving role permissions: $e');
      return _connectionFailure(e);
    }
  }

  /// Xóa role
  Future<Map<String, dynamic>> deleteRole(String roleName,
      {String? storeId}) async {
    try {
      final uri = storeId != null
          ? Uri.parse(
              '$baseUrl/api/permission-management/reset/$roleName?storeId=$storeId')
          : Uri.parse('$baseUrl/api/permission-management/reset/$roleName');
      final response = await _retryOnUnauthorized(() => http
          .post(uri, headers: _headers)
          .timeout(const Duration(seconds: 10)));
      return _handleResponse(response);
    } catch (e) {
      debugPrint('Error deleting role: $e');
      return _connectionFailure(e);
    }
  }

  /// Lấy quyền hiệu lực của user hiện tại (role + department, merged).
  /// Ném lỗi khi request thất bại — PermissionProvider giữ cache cũ.
  Future<List<Map<String, dynamic>>> getMyEffectivePermissions() async {
    final response = await _retryOnUnauthorized(() => http
        .get(
          Uri.parse('$baseUrl/api/permission-management/my-permissions'),
          headers: _headers,
        )
        .timeout(const Duration(seconds: 15)));
    final result = _handleResponse(response);
    if (result['isSuccess'] != true) {
      throw Exception(
          result['message']?.toString() ?? 'Không tải được quyền module');
    }
    if (result['data'] != null && result['data'] is List) {
      return List<Map<String, dynamic>>.from(
          (result['data'] as List).map((e) => Map<String, dynamic>.from(e)));
    }
    return [];
  }

  /// Lấy danh sách user (accounts) cho dropdown phân quyền
  Future<List<dynamic>> getUsersForPermission() async {
    try {
      final response = await _retryOnUnauthorized(() => http
          .get(
            Uri.parse('$baseUrl/api/accounts'),
            headers: _headers,
          )
          .timeout(const Duration(seconds: 10)));
      final result = _handleResponse(response);
      return result['data'] ?? [];
    } catch (e) {
      debugPrint('Error getting users: $e');
      return [];
    }
  }

  // Account Management
  Future<List<dynamic>> getAccounts() async {
    try {
      final response = await _retryOnUnauthorized(() => http
          .get(
            Uri.parse('$baseUrl/api/accounts'),
            headers: _headers,
          )
          .timeout(const Duration(seconds: 10)));
      final result = _handleResponse(response);
      return result['data'] ?? [];
    } catch (e) {
      debugPrint('Error getting accounts: $e');
      return [];
    }
  }

  Future<Map<String, dynamic>> createAccount(Map<String, dynamic> data) async {
    try {
      final response = await _retryOnUnauthorized(() => http
          .post(
            Uri.parse('$baseUrl/api/accounts'),
            headers: _headers,
            body: json.encode(data),
          )
          .timeout(const Duration(seconds: 10)));
      return _handleResponse(response);
    } catch (e) {
      debugPrint('Error creating account: $e');
      return _connectionFailure(e);
    }
  }

  /// Đăng ký tài khoản hàng loạt: nhiều nhân viên, 1 mật khẩu, 1 quyền.
  Future<Map<String, dynamic>> createBulkAccounts({
    required List<String> employeeIds,
    required String password,
    required String role,
  }) async {
    try {
      final response = await _retryOnUnauthorized(() => http
          .post(
            Uri.parse('$baseUrl/api/accounts/bulk'),
            headers: _headers,
            body: json.encode({
              'employeeIds': employeeIds,
              'password': password,
              'role': role,
            }),
          )
          .timeout(const Duration(seconds: 120)));
      return _handleResponse(response);
    } catch (e) {
      debugPrint('Error creating bulk accounts: $e');
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> updateAccount(
      String id, Map<String, dynamic> data) async {
    try {
      final response = await _retryOnUnauthorized(() => http
          .put(
            Uri.parse('$baseUrl/api/accounts/$id'),
            headers: _headers,
            body: json.encode(data),
          )
          .timeout(const Duration(seconds: 10)));
      return _handleResponse(response);
    } catch (e) {
      debugPrint('Error updating account: $e');
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> toggleAccountStatus(
      String id, bool isActive) async {
    try {
      final response = await _retryOnUnauthorized(() => http
          .patch(
            Uri.parse('$baseUrl/api/accounts/$id/status'),
            headers: _headers,
            body: json.encode({'isActive': isActive}),
          )
          .timeout(const Duration(seconds: 10)));
      return _handleResponse(response);
    } catch (e) {
      debugPrint('Error toggling account status: $e');
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> resetAccountPassword(
      String id, String newPassword) async {
    try {
      final response = await _retryOnUnauthorized(() => http
          .patch(
            Uri.parse('$baseUrl/api/accounts/$id/password'),
            headers: _headers,
            body: json.encode({'password': newPassword}),
          )
          .timeout(const Duration(seconds: 10)));
      return _handleResponse(response);
    } catch (e) {
      debugPrint('Error resetting password: $e');
      return _connectionFailure(e);
    }
  }

  /// Đổi mật khẩu tài khoản đang đăng nhập (cần mật khẩu hiện tại).
  Future<Map<String, dynamic>> updateOwnPassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    try {
      final response = await _retryOnUnauthorized(() => http
          .put(
            Uri.parse('$baseUrl/api/accounts/profile/password'),
            headers: _headers,
            body: json.encode({
              'currentPassword': currentPassword,
              'newPassword': newPassword,
            }),
          )
          .timeout(const Duration(seconds: 15)));
      return _handleResponse(response);
    } catch (e) {
      debugPrint('Error updating own password: $e');
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> deleteAccount(String id) async {
    try {
      final response = await _retryOnUnauthorized(() => http
          .delete(
            Uri.parse('$baseUrl/api/accounts/$id'),
            headers: _headers,
          )
          .timeout(const Duration(seconds: 10)));
      return _handleResponse(response);
    } catch (e) {
      debugPrint('Error deleting account: $e');
      return _connectionFailure(e);
    }
  }

  // ==================== NOTIFICATIONS ====================

  /// Lấy danh sách thông báo của user
  Future<Map<String, dynamic>> getNotifications({
    int page = 1,
    int pageSize = 20,
    bool? isRead,
    int? type,
  }) async {
    try {
      final queryParams = <String, String>{
        'page': page.toString(),
        'pageSize': pageSize.toString(),
      };
      if (isRead != null) queryParams['isRead'] = isRead.toString();
      if (type != null) queryParams['type'] = type.toString();

      final uri = Uri.parse('$baseUrl/api/notifications')
          .replace(queryParameters: queryParams);
      debugPrint('📨 Getting notifications from: $uri');
      debugPrint('📨 Headers: $_headers');
      final response = await http
          .get(uri, headers: _headers)
          .timeout(const Duration(seconds: 10));
      debugPrint('📨 Notifications response status: ${response.statusCode}');
      debugPrint(
          '📨 Notifications response body: ${response.body.substring(0, response.body.length.clamp(0, 500))}');
      final data = _handleResponse(response);

      if (data['isSuccess'] == true) {
        debugPrint(
            '📨 Notifications loaded successfully: ${data['data']['items']?.length ?? 0} items');
        final responseData = data['data'];
        return {
          'items': responseData is Map ? (responseData['items'] ?? []) : [],
          'totalCount': _toInt(
              responseData is Map ? responseData['totalCount'] : null, 0),
          'pageNumber': _toInt(
              responseData is Map ? responseData['pageNumber'] : null, page),
          'pageSize': _toInt(
              responseData is Map ? responseData['pageSize'] : null, pageSize),
        };
      } else {
        debugPrint('📨 Notifications API failed: ${data['message']}');
      }
    } catch (e) {
      debugPrint('❌ Error getting notifications: $e');
    }
    return {'items': [], 'totalCount': 0, 'pageNumber': 1, 'pageSize': 20};
  }

  /// Lấy tóm tắt thông báo (số chưa đọc)
  Future<Map<String, dynamic>> getNotificationSummary() async {
    try {
      final response = await http
          .get(
            Uri.parse('$baseUrl/api/notifications/summary'),
            headers: _headers,
          )
          .timeout(const Duration(seconds: 10));
      final data = _handleResponse(response);

      if (data['isSuccess'] == true) {
        return data['data'] ?? {'unreadCount': 0, 'totalCount': 0};
      }
    } catch (e) {
      debugPrint('Error getting notification summary: $e');
    }
    return {'unreadCount': 0, 'totalCount': 0};
  }

  /// Đánh dấu thông báo đã đọc
  Future<Map<String, dynamic>> markNotificationAsRead(String id) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/api/notifications/$id/read'),
            headers: _headers,
          )
          .timeout(const Duration(seconds: 10));
      return _handleResponse(response);
    } catch (e) {
      debugPrint('Error marking notification as read: $e');
      return _connectionFailure(e);
    }
  }

  /// Đánh dấu tất cả thông báo đã đọc
  Future<Map<String, dynamic>> markAllNotificationsAsRead() async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/api/notifications/read-all'),
            headers: _headers,
          )
          .timeout(const Duration(seconds: 10));
      return _handleResponse(response);
    } catch (e) {
      debugPrint('Error marking all notifications as read: $e');
      return _connectionFailure(e);
    }
  }

  /// Xóa thông báo
  Future<Map<String, dynamic>> deleteNotification(String id) async {
    try {
      final response = await http
          .delete(
            Uri.parse('$baseUrl/api/notifications/$id'),
            headers: _headers,
          )
          .timeout(const Duration(seconds: 10));
      return _handleResponse(response);
    } catch (e) {
      debugPrint('Error deleting notification: $e');
      return _connectionFailure(e);
    }
  }

  /// Xóa tất cả thông báo
  Future<Map<String, dynamic>> deleteAllNotifications({bool? isRead}) async {
    try {
      String url = '$baseUrl/api/notifications';
      if (isRead != null) {
        url += '?isRead=$isRead';
      }
      final response = await http
          .delete(
            Uri.parse(url),
            headers: _headers,
          )
          .timeout(const Duration(seconds: 30));
      return _handleResponse(response);
    } catch (e) {
      debugPrint('Error deleting all notifications: $e');
      return _connectionFailure(e);
    }
  }

  /// Tạo thông báo (cho Manager/Admin)
  Future<Map<String, dynamic>> createNotification({
    String? targetUserId,
    required int type,
    required String title,
    required String message,
    String? relatedUrl,
    String? relatedEntityId,
    String? relatedEntityType,
  }) async {
    try {
      final body = {
        'targetUserId': targetUserId,
        'type': type,
        'title': title,
        'message': message,
        'relatedUrl': relatedUrl,
        'relatedEntityId': relatedEntityId,
        'relatedEntityType': relatedEntityType,
      };

      final response = await http
          .post(
            Uri.parse('$baseUrl/api/notifications'),
            headers: _headers,
            body: json.encode(body),
          )
          .timeout(const Duration(seconds: 10));
      return _handleResponse(response);
    } catch (e) {
      debugPrint('Error creating notification: $e');
      return _connectionFailure(e);
    }
  }

  // ==================== MOBILE ATTENDANCE ====================

  /// Lấy danh sách địa điểm làm việc
  Future<Map<String, dynamic>> getWorkLocations() async {
    try {
      final response = await http
          .get(
            Uri.parse('$baseUrl/api/mobile-attendance/locations'),
            headers: _headers,
          )
          .timeout(const Duration(seconds: 10));
      return _handleResponse(response);
    } catch (e) {
      debugPrint('Error getting work locations: $e');
      return _connectionFailure(e);
    }
  }

  /// Vị trí active để NV chọn khi đăng ký / đổi thiết bị.
  Future<Map<String, dynamic>> getLocationsForRegistration() async {
    try {
      final response = await http
          .get(
            Uri.parse(
                '$baseUrl/api/mobile-attendance/locations/active-for-registration'),
            headers: _headers,
          )
          .timeout(const Duration(seconds: 10));
      return _handleResponse(response);
    } catch (e) {
      debugPrint('Error getting registration locations: $e');
      return _connectionFailure(e);
    }
  }

  /// Vị trí chấm được phép của một nhân viên (lọc theo gán vị trí).
  Future<Map<String, dynamic>> getPunchWorkLocations({String? employeeId}) async {
    try {
      final params = <String, String>{};
      if (employeeId != null && employeeId.isNotEmpty) {
        params['employeeId'] = employeeId;
      }
      final uri = Uri.parse('$baseUrl/api/mobile-attendance/punch-locations')
          .replace(queryParameters: params.isEmpty ? null : params);
      final response = await http
          .get(uri, headers: _headers)
          .timeout(const Duration(seconds: 10));
      return _handleResponse(response);
    } catch (e) {
      debugPrint('Error getting punch work locations: $e');
      return _connectionFailure(e);
    }
  }

  /// Danh sách nhân viên được gán cho một vị trí chấm.
  Future<Map<String, dynamic>> getLocationEmployees(String locationId) async {
    try {
      final response = await http
          .get(
            Uri.parse(
                '$baseUrl/api/mobile-attendance/locations/$locationId/employees'),
            headers: _headers,
          )
          .timeout(const Duration(seconds: 15));
      return _handleResponse(response);
    } catch (e) {
      debugPrint('Error getting location employees: $e');
      return _connectionFailure(e);
    }
  }

  /// Gán danh sách nhân viên cho một vị trí chấm (thay thế toàn bộ).
  Future<Map<String, dynamic>> setLocationEmployees({
    required String locationId,
    required List<Map<String, String>> employees,
  }) async {
    try {
      final response = await http
          .put(
            Uri.parse(
                '$baseUrl/api/mobile-attendance/locations/$locationId/employees'),
            headers: _headers,
            body: json.encode({
              'employees': employees
                  .map((e) => {
                        'employeeId': e['employeeId'],
                        'employeeName': e['employeeName'],
                      })
                  .toList(),
            }),
          )
          .timeout(const Duration(seconds: 30));
      return _handleResponse(response);
    } catch (e) {
      debugPrint('Error setting location employees: $e');
      return _connectionFailure(e);
    }
  }

  /// Thêm địa điểm làm việc
  Future<Map<String, dynamic>> addWorkLocation({
    required String name,
    required String address,
    required double latitude,
    required double longitude,
    required double radius,
    bool autoApproveInRange = true,
    String? wifiSsid,
    String? wifiBssid,
    String? allowedIpRange,
  }) async {
    try {
      final body = {
        'name': name,
        'address': address,
        'latitude': latitude,
        'longitude': longitude,
        'radius': radius,
        'autoApproveInRange': autoApproveInRange,
      };
      if (wifiSsid != null) body['wifiSsid'] = wifiSsid;
      if (wifiBssid != null) body['wifiBssid'] = wifiBssid;
      if (allowedIpRange != null) body['allowedIpRange'] = allowedIpRange;

      final response = await http
          .post(
            Uri.parse('$baseUrl/api/mobile-attendance/locations'),
            headers: _headers,
            body: json.encode(body),
          )
          .timeout(const Duration(seconds: 10));
      return _handleResponse(response);
    } catch (e) {
      debugPrint('Error adding work location: $e');
      return _connectionFailure(e);
    }
  }

  /// Cập nhật địa điểm làm việc
  Future<Map<String, dynamic>> updateWorkLocation({
    required String id,
    required String name,
    required String address,
    required double latitude,
    required double longitude,
    required double radius,
    bool autoApproveInRange = true,
    String? wifiSsid,
    String? wifiBssid,
    String? allowedIpRange,
  }) async {
    try {
      final body = {
        'name': name,
        'address': address,
        'latitude': latitude,
        'longitude': longitude,
        'radius': radius,
        'autoApproveInRange': autoApproveInRange,
      };
      if (wifiSsid != null) body['wifiSsid'] = wifiSsid;
      if (wifiBssid != null) body['wifiBssid'] = wifiBssid;
      if (allowedIpRange != null) body['allowedIpRange'] = allowedIpRange;

      final response = await http
          .put(
            Uri.parse('$baseUrl/api/mobile-attendance/locations/$id'),
            headers: _headers,
            body: json.encode(body),
          )
          .timeout(const Duration(seconds: 10));
      return _handleResponse(response);
    } catch (e) {
      debugPrint('Error updating work location: $e');
      return _connectionFailure(e);
    }
  }

  /// Xóa địa điểm làm việc
  Future<Map<String, dynamic>> deleteWorkLocation(String id) async {
    try {
      final response = await http
          .delete(
            Uri.parse('$baseUrl/api/mobile-attendance/locations/$id'),
            headers: _headers,
          )
          .timeout(const Duration(seconds: 10));
      return _handleResponse(response);
    } catch (e) {
      debugPrint('Error deleting work location: $e');
      return _connectionFailure(e);
    }
  }

  /// Lấy danh sách đăng ký khuôn mặt
  Future<Map<String, dynamic>> getFaceRegistrations() async {
    try {
      final response = await http
          .get(
            Uri.parse('$baseUrl/api/mobile-attendance/face-registrations'),
            headers: _headers,
          )
          .timeout(const Duration(seconds: 10));
      return _handleResponse(response);
    } catch (e) {
      debugPrint('Error getting face registrations: $e');
      return _connectionFailure(e);
    }
  }

  /// Đăng ký khuôn mặt cho nhân viên
  Future<Map<String, dynamic>> registerFace({
    required String employeeId,
    required String employeeName,
    required List<String> faceImages, // Base64 encoded images
  }) async {
    try {
      final body = {
        'employeeId': employeeId,
        'employeeName': employeeName,
        'faceImages': faceImages,
      };

      final response = await http
          .post(
            Uri.parse('$baseUrl/api/mobile-attendance/face-registrations'),
            headers: _headers,
            body: json.encode(body),
          )
          .timeout(
              const Duration(seconds: 30)); // Longer timeout for image upload
      return _handleResponse(response);
    } catch (e) {
      debugPrint('Error registering face: $e');
      return _connectionFailure(e);
    }
  }

  /// Xóa đăng ký khuôn mặt
  Future<Map<String, dynamic>> deleteFaceRegistration(String id) async {
    try {
      final response = await http
          .delete(
            Uri.parse('$baseUrl/api/mobile-attendance/face-registrations/$id'),
            headers: _headers,
          )
          .timeout(const Duration(seconds: 10));
      return _handleResponse(response);
    } catch (e) {
      debugPrint('Error deleting face registration: $e');
      return _connectionFailure(e);
    }
  }

  /// Lấy danh sách thiết bị được cấp phép
  Future<Map<String, dynamic>> getAuthorizedDevices() async {
    try {
      final response = await http
          .get(
            Uri.parse('$baseUrl/api/mobile-attendance/devices'),
            headers: _headers,
          )
          .timeout(const Duration(seconds: 10));
      return _handleResponse(response);
    } catch (e) {
      debugPrint('Error getting authorized devices: $e');
      return _connectionFailure(e);
    }
  }

  /// Nhân viên đăng ký thiết bị + khuôn mặt (chờ duyệt)
  Future<Map<String, dynamic>> registerMobileDevice({
    required String deviceId,
    required String deviceName,
    required String deviceModel,
    String? osVersion,
    required String employeeId,
    required String employeeName,
    required List<String> faceImages,
    required List<String> selectedWorkLocationIds,
    String? wifiBssid,
  }) async {
    try {
      final body = {
        'deviceId': deviceId,
        'deviceName': deviceName,
        'deviceModel': deviceModel,
        'osVersion': osVersion,
        'employeeId': employeeId,
        'employeeName': employeeName,
        'faceImages': faceImages,
        'selectedWorkLocationIds': selectedWorkLocationIds,
      };
      if (wifiBssid != null) body['wifiBssid'] = wifiBssid;

      final response = await http
          .post(
            Uri.parse('$baseUrl/api/mobile-attendance/register-device'),
            headers: _headers,
            body: json.encode(body),
          )
          .timeout(const Duration(seconds: 30));

      // Handle 409 Conflict (already registered) - return device info
      if (response.statusCode == 409) {
        try {
          final rawBody = utf8.decode(response.bodyBytes, allowMalformed: true);
          final data = json.decode(rawBody);
          if (data is Map<String, dynamic> && data['data'] != null) {
            final payload = data['data'] as Map<String, dynamic>;
            return {
              'isSuccess': false,
              'alreadyRegistered': true,
              'message': payload['message']?.toString() ??
                  'Tài khoản đã đăng ký thiết bị. Mỗi tài khoản chỉ được đăng ký 1 thiết bị.',
              'data': payload,
              'statusCode': 409,
            };
          }
        } catch (_) {}
      }

      return _handleResponse(response);
    } catch (e) {
      debugPrint('Error registering mobile device: $e');
      return _connectionFailure(e);
    }
  }

  /// Nhân viên gửi yêu cầu đổi thiết bị chấm công
  Future<Map<String, dynamic>> requestDeviceChange({
    required String employeeId,
    required String employeeName,
    required String newDeviceId,
    required String newDeviceName,
    required String newDeviceModel,
    String? newOsVersion,
    String? newWifiBssid,
    required List<String> faceImages,
    required List<String> selectedWorkLocationIds,
    String? reason,
  }) async {
    try {
      final body = {
        'employeeId': employeeId,
        'employeeName': employeeName,
        'newDeviceId': newDeviceId,
        'newDeviceName': newDeviceName,
        'newDeviceModel': newDeviceModel,
        'newOsVersion': newOsVersion,
        'newWifiBssid': newWifiBssid,
        'faceImages': faceImages,
        'selectedWorkLocationIds': selectedWorkLocationIds,
        'reason': reason,
      };

      final response = await http
          .post(
            Uri.parse('$baseUrl/api/mobile-attendance/request-device-change'),
            headers: _headers,
            body: json.encode(body),
          )
          .timeout(const Duration(seconds: 30));
      return _handleResponse(response);
    } catch (e) {
      debugPrint('Error requesting device change: $e');
      return _connectionFailure(e);
    }
  }

  /// Nhân viên kiểm tra yêu cầu đổi máy
  Future<Map<String, dynamic>> getMyDeviceChangeRequest(
      {String? employeeId}) async {
    try {
      final uri = employeeId != null
          ? '$baseUrl/api/mobile-attendance/my-device-change-request?employeeId=$employeeId'
          : '$baseUrl/api/mobile-attendance/my-device-change-request';
      final response = await http
          .get(Uri.parse(uri), headers: _headers)
          .timeout(const Duration(seconds: 10));
      return _handleResponse(response);
    } catch (e) {
      debugPrint('Error getting device change request: $e');
      return _connectionFailure(e);
    }
  }

  /// Quản lý lấy danh sách yêu cầu đổi máy
  Future<Map<String, dynamic>> getDeviceChangeRequests({int? status}) async {
    try {
      final uri = status != null
          ? '$baseUrl/api/mobile-attendance/device-change-requests?status=$status'
          : '$baseUrl/api/mobile-attendance/device-change-requests';
      final response = await http
          .get(Uri.parse(uri), headers: _headers)
          .timeout(const Duration(seconds: 10));
      return _handleResponse(response);
    } catch (e) {
      debugPrint('Error getting device change requests: $e');
      return _connectionFailure(e);
    }
  }

  /// Quản lý duyệt/từ chối yêu cầu đổi máy
  Future<Map<String, dynamic>> approveDeviceChange({
    required String requestId,
    required bool approved,
    String? rejectionReason,
  }) async {
    try {
      final body = {
        'approved': approved,
        'rejectionReason': rejectionReason,
      };
      final response = await http
          .post(
            Uri.parse(
                '$baseUrl/api/mobile-attendance/approve-device-change/$requestId'),
            headers: _headers,
            body: json.encode(body),
          )
          .timeout(const Duration(seconds: 10));
      return _handleResponse(response);
    } catch (e) {
      debugPrint('Error approving device change: $e');
      return _connectionFailure(e);
    }
  }

  /// Kiểm tra trạng thái thiết bị của nhân viên hiện tại
  Future<Map<String, dynamic>> getMyDeviceStatus({
    String? employeeId,
    String? currentDeviceId,
  }) async {
    try {
      final params = <String, String>{};
      if (employeeId != null && employeeId.isNotEmpty) {
        params['employeeId'] = employeeId;
      }
      if (currentDeviceId != null && currentDeviceId.isNotEmpty) {
        params['currentDeviceId'] = currentDeviceId;
      }
      final query = params.entries
          .map((e) =>
              '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}')
          .join('&');
      final uri = query.isEmpty
          ? '$baseUrl/api/mobile-attendance/my-device'
          : '$baseUrl/api/mobile-attendance/my-device?$query';
      final response = await http
          .get(
            Uri.parse(uri),
            headers: _headers,
          )
          .timeout(const Duration(seconds: 10));
      return _handleResponse(response);
    } catch (e) {
      debugPrint('Error getting device status: $e');
      return _connectionFailure(e);
    }
  }

  /// Admin duyệt/từ chối đăng ký thiết bị chấm công mobile
  Future<Map<String, dynamic>> approveMobileDevice({
    required String deviceId,
    required bool approved,
    String? rejectionReason,
  }) async {
    try {
      final body = {
        'approved': approved,
        'rejectionReason': rejectionReason,
      };

      final response = await http
          .post(
            Uri.parse(
                '$baseUrl/api/mobile-attendance/approve-device/$deviceId'),
            headers: _headers,
            body: json.encode(body),
          )
          .timeout(const Duration(seconds: 10));
      return _handleResponse(response);
    } catch (e) {
      debugPrint('Error approving device: $e');
      return _connectionFailure(e);
    }
  }

  /// Bật/tắt chụp ảnh hiện trường cho một thiết bị (theo id bản ghi).
  Future<Map<String, dynamic>> setDeviceRequirePhotoProof({
    required String deviceRecordId,
    required bool requirePhotoProof,
  }) async {
    try {
      final response = await http
          .patch(
            Uri.parse(
                '$baseUrl/api/mobile-attendance/devices/$deviceRecordId/require-photo-proof'),
            headers: _headers,
            body: json.encode({'requirePhotoProof': requirePhotoProof}),
          )
          .timeout(const Duration(seconds: 10));
      return _handleResponse(response);
    } catch (e) {
      debugPrint('Error setDeviceRequirePhotoProof: $e');
      return _connectionFailure(e);
    }
  }

  /// Bật/tắt chấm ngoài CT cho một thiết bị (theo id bản ghi).
  Future<Map<String, dynamic>> setDeviceAllowOutsideCheckIn({
    required String deviceRecordId,
    required bool allowOutsideCheckIn,
  }) async {
    try {
      final response = await http
          .patch(
            Uri.parse(
                '$baseUrl/api/mobile-attendance/devices/$deviceRecordId/allow-outside-checkin'),
            headers: _headers,
            body: json.encode({'allowOutsideCheckIn': allowOutsideCheckIn}),
          )
          .timeout(const Duration(seconds: 10));
      return _handleResponse(response);
    } catch (e) {
      debugPrint('Error setDeviceAllowOutsideCheckIn: $e');
      return _connectionFailure(e);
    }
  }

  /// Bật/tắt chấm đi đường cho một thiết bị (theo id bản ghi).
  Future<Map<String, dynamic>> setDeviceAllowTravelCheckIn({
    required String deviceRecordId,
    required bool allowTravelCheckIn,
  }) async {
    try {
      final response = await http
          .patch(
            Uri.parse(
                '$baseUrl/api/mobile-attendance/devices/$deviceRecordId/allow-travel-checkin'),
            headers: _headers,
            body: json.encode({'allowTravelCheckIn': allowTravelCheckIn}),
          )
          .timeout(const Duration(seconds: 10));
      return _handleResponse(response);
    } catch (e) {
      debugPrint('Error setDeviceAllowTravelCheckIn: $e');
      return _connectionFailure(e);
    }
  }

  /// Cấp phép thiết bị
  Future<Map<String, dynamic>> authorizeDevice({
    required String deviceId,
    required String deviceName,
    required String deviceModel,
    required String employeeId,
    required String employeeName,
    bool canUseFaceId = true,
    bool canUseGps = true,
    bool allowOutsideCheckIn = false,
    bool allowTravelCheckIn = false,
    bool requirePhotoProof = false,
  }) async {
    try {
      final body = {
        'deviceId': deviceId,
        'deviceName': deviceName,
        'deviceModel': deviceModel,
        'employeeId': employeeId,
        'employeeName': employeeName,
        'canUseFaceId': canUseFaceId,
        'canUseGps': canUseGps,
        'allowOutsideCheckIn': allowOutsideCheckIn,
        'allowTravelCheckIn': allowTravelCheckIn,
        'requirePhotoProof': requirePhotoProof,
      };

      final response = await http
          .post(
            Uri.parse('$baseUrl/api/mobile-attendance/devices'),
            headers: _headers,
            body: json.encode(body),
          )
          .timeout(const Duration(seconds: 10));
      return _handleResponse(response);
    } catch (e) {
      debugPrint('Error authorizing device: $e');
      return _connectionFailure(e);
    }
  }

  /// Thu hồi quyền thiết bị
  Future<Map<String, dynamic>> revokeDevice(String id) async {
    try {
      final response = await http
          .delete(
            Uri.parse('$baseUrl/api/mobile-attendance/devices/$id'),
            headers: _headers,
          )
          .timeout(const Duration(seconds: 10));
      return _handleResponse(response);
    } catch (e) {
      debugPrint('Error revoking device: $e');
      return _connectionFailure(e);
    }
  }

  /// Gửi chấm công mobile
  Future<Map<String, dynamic>> submitMobileAttendance({
    required String employeeId,
    String? employeeName,
    required int punchType, // 0: check-in, 1: check-out
    required double latitude,
    required double longitude,
    required String faceImage, // Base64 encoded
    double? distanceFromLocation,
    double? faceMatchScore,
    String? deviceId,
    String? wifiSsid,
    String? wifiBssid,
    bool livenessPassed = false,
    String? clientFaceEngine,
    String? sitePhotoBase64,
  }) async {
    try {
      final body = {
        'employeeId': employeeId,
        'employeeName': employeeName ?? '',
        'punchType': punchType,
        'latitude': latitude,
        'longitude': longitude,
        'faceImageUrl': faceImage,
        'distanceFromLocation': distanceFromLocation,
        'faceMatchScore': faceMatchScore,
        'deviceId': deviceId,
        'livenessPassed': livenessPassed,
      };
      if (sitePhotoBase64 != null && sitePhotoBase64.trim().length > 100) {
        body['sitePhotoBase64'] = sitePhotoBase64.trim();
      }
      if (clientFaceEngine != null && clientFaceEngine.isNotEmpty) {
        body['clientFaceEngine'] = clientFaceEngine;
      }
      if (wifiSsid != null) body['wifiSsid'] = wifiSsid;
      if (wifiBssid != null) body['wifiBssid'] = wifiBssid;

      final response = await http
          .post(
            Uri.parse('$baseUrl/api/mobile-attendance/punch'),
            headers: _headers,
            body: json.encode(body),
          )
          .timeout(const Duration(seconds: 60));
      return _handleResponse(response);
    } catch (e) {
      debugPrint('Error submitting mobile attendance: $e');
      return _connectionFailure(e);
    }
  }

  /// GUID từ response punch (bỏ ngoặc, kiểm tra định dạng).
  static String? normalizeMobileRecordIdForUpload(String recordId) {
    var s = recordId.trim();
    if (s.startsWith('{') && s.endsWith('}')) {
      s = s.substring(1, s.length - 1).trim();
    }
    final guid = RegExp(
      r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
    );
    return guid.hasMatch(s) ? s : null;
  }

  /// Upload ảnh hiện trường sau chấm công (khi bật requirePhotoProof).
  Future<Map<String, dynamic>> uploadMobileAttendanceSitePhoto({
    required String recordId,
    required String photoBase64,
  }) async {
    final id = normalizeMobileRecordIdForUpload(recordId);
    if (id == null) {
      return {
        'isSuccess': false,
        'message': 'Mã bản ghi chấm công không hợp lệ ($recordId)',
      };
    }

    final body = json.encode({'sitePhotoBase64': photoBase64});

    Future<http.Response> postTo(String path) => http
        .post(
          Uri.parse('$baseUrl/api/mobile-attendance/$path'),
          headers: _headers,
          body: body,
        )
        .timeout(const Duration(seconds: 60));

    try {
      var response = await postTo('records/$id/site-photo');
      if (response.statusCode == 404) {
        response = await http
            .post(
              Uri.parse('$baseUrl/api/mobile-attendance/upload-site-photo'),
              headers: _headers,
              body: json.encode({
                'recordId': id,
                'sitePhotoBase64': photoBase64,
              }),
            )
            .timeout(const Duration(seconds: 60));
      }

      final result = _handleResponse(response);
      if (response.statusCode == 404 && result['isSuccess'] != true) {
        result['message'] =
            'Máy chủ chưa có API lưu ảnh hiện trường (404). Cần cập nhật backend SBOX lên bản mới nhất.';
      }
      return result;
    } catch (e) {
      debugPrint('Error uploading site photo: $e');
      return _connectionFailure(e);
    }
  }

  /// Chi tiết một bản ghi chấm công mobile (đủ GPS, ảnh, WiFi…).
  Future<Map<String, dynamic>> getMobileAttendanceRecord(String recordId) async {
    try {
      final response = await http
          .get(
            Uri.parse('$baseUrl/api/mobile-attendance/records/$recordId'),
            headers: _headers,
          )
          .timeout(const Duration(seconds: 10));
      return _handleResponse(response);
    } catch (e) {
      debugPrint('Error getting mobile attendance record: $e');
      return _connectionFailure(e);
    }
  }

  /// Lấy lịch sử chấm công mobile
  Future<Map<String, dynamic>> getMobileAttendanceHistory({
    String? employeeId,
    DateTime? fromDate,
    DateTime? toDate,
    String? status,
    /// Comma-separated punch types, e.g. "2,3" for travel.
    String? punchTypes,
    int? pageSize,
  }) async {
    try {
      final queryParams = <String, String>{};
      if (employeeId != null) queryParams['employeeId'] = employeeId;
      if (fromDate != null) {
        queryParams['fromDate'] = fromDate.toIso8601String();
      }
      if (toDate != null) queryParams['toDate'] = toDate.toIso8601String();
      if (status != null) queryParams['status'] = status;
      if (punchTypes != null && punchTypes.trim().isNotEmpty) {
        queryParams['punchTypes'] = punchTypes.trim();
      }
      if (pageSize != null && pageSize > 0) {
        queryParams['pageSize'] = pageSize.toString();
      }

      final uri = Uri.parse('$baseUrl/api/mobile-attendance/history').replace(
          queryParameters: queryParams.isNotEmpty ? queryParams : null);

      final response = await http
          .get(uri, headers: _headers)
          .timeout(const Duration(seconds: 10));
      return _handleResponse(response);
    } catch (e) {
      debugPrint('Error getting mobile attendance history: $e');
      return _connectionFailure(e);
    }
  }

  /// Lấy danh sách chờ duyệt
  Future<Map<String, dynamic>> getPendingMobileAttendance() async {
    try {
      final response = await http
          .get(
            Uri.parse('$baseUrl/api/mobile-attendance/pending'),
            headers: _headers,
          )
          .timeout(const Duration(seconds: 10));
      return _handleResponse(response);
    } catch (e) {
      debugPrint('Error getting pending mobile attendance: $e');
      return _connectionFailure(e);
    }
  }

  /// Duyệt/từ chối chấm công mobile
  Future<Map<String, dynamic>> approveMobileAttendance({
    required String recordId,
    required bool approved,
    String? rejectionReason,
  }) async {
    try {
      final body = {
        'approved': approved,
        'rejectionReason': rejectionReason,
      };

      final response = await http
          .post(
            Uri.parse('$baseUrl/api/mobile-attendance/approve/$recordId'),
            headers: _headers,
            body: json.encode(body),
          )
          .timeout(const Duration(seconds: 10));
      return _handleResponse(response);
    } catch (e) {
      debugPrint('Error approving mobile attendance: $e');
      return _connectionFailure(e);
    }
  }

  /// Lấy cài đặt chấm công mobile (dành cho nhân viên)
  Future<Map<String, dynamic>> getMyMobileSettings() async {
    try {
      final response = await http
          .get(
            Uri.parse('$baseUrl/api/mobile-attendance/my-settings'),
            headers: _headers,
          )
          .timeout(const Duration(seconds: 10));
      return _handleResponse(response);
    } catch (e) {
      debugPrint('Error getting my mobile settings: $e');
      return _connectionFailure(e);
    }
  }

  /// Lấy cài đặt chấm công mobile (dành cho quản lý)
  Future<Map<String, dynamic>> getMobileAttendanceSettings() async {
    try {
      final response = await http
          .get(
            Uri.parse('$baseUrl/api/mobile-attendance/settings'),
            headers: _headers,
          )
          .timeout(const Duration(seconds: 10));
      return _handleResponse(response);
    } catch (e) {
      debugPrint('Error getting mobile attendance settings: $e');
      return _connectionFailure(e);
    }
  }

  /// Cập nhật cài đặt chấm công mobile
  Future<Map<String, dynamic>> updateMobileAttendanceSettings({
    bool? enableFaceId,
    bool? enableGps,
    bool? enableWifi,
    String? verificationMode,
    bool? enableLivenessDetection,
    double? gpsRadiusMeters,
    double? minFaceMatchScore,
    bool? autoApproveInRange,
    bool? allowManualApproval,
    int? maxPunchesPerDay,
    bool? requirePhotoProof,
    int? minPunchIntervalMinutes,
  }) async {
    try {
      final body = <String, dynamic>{};
      if (enableFaceId != null) body['enableFaceId'] = enableFaceId;
      if (enableGps != null) body['enableGps'] = enableGps;
      if (enableWifi != null) body['enableWifi'] = enableWifi;
      if (verificationMode != null) {
        body['verificationMode'] = verificationMode;
      }
      if (enableLivenessDetection != null) {
        body['enableLivenessDetection'] = enableLivenessDetection;
      }
      if (gpsRadiusMeters != null) body['gpsRadiusMeters'] = gpsRadiusMeters;
      if (minFaceMatchScore != null) {
        body['minFaceMatchScore'] = minFaceMatchScore;
      }
      if (autoApproveInRange != null) {
        body['autoApproveInRange'] = autoApproveInRange;
      }
      if (allowManualApproval != null) {
        body['allowManualApproval'] = allowManualApproval;
      }
      if (maxPunchesPerDay != null) body['maxPunchesPerDay'] = maxPunchesPerDay;
      if (requirePhotoProof != null) {
        body['requirePhotoProof'] = requirePhotoProof;
      }
      if (minPunchIntervalMinutes != null) {
        body['minPunchIntervalMinutes'] = minPunchIntervalMinutes;
      }

      final response = await http
          .put(
            Uri.parse('$baseUrl/api/mobile-attendance/settings'),
            headers: _headers,
            body: json.encode(body),
          )
          .timeout(const Duration(seconds: 10));
      return _handleResponse(response);
    } catch (e) {
      debugPrint('Error updating mobile attendance settings: $e');
      return _connectionFailure(e);
    }
  }

  /// Kiểm tra WiFi văn phòng
  Future<Map<String, dynamic>> checkWifi({String? bssid}) async {
    try {
      var url = '$baseUrl/api/mobile-attendance/check-wifi';
      if (bssid != null && bssid.isNotEmpty) {
        url += '?bssid=${Uri.encodeComponent(bssid)}';
      }
      final response = await http
          .get(
            Uri.parse(url),
            headers: _headers,
          )
          .timeout(const Duration(seconds: 10));
      return _handleResponse(response);
    } catch (e) {
      debugPrint('Error checking wifi: $e');
      return _connectionFailure(e);
    }
  }

  /// Xác thực khuôn mặt
  Future<Map<String, dynamic>> verifyFace({
    required String employeeId,
    required String faceImage, // Base64 encoded
  }) async {
    try {
      final body = {
        'employeeId': employeeId,
        'faceImage': faceImage,
      };

      final response = await http
          .post(
            Uri.parse('$baseUrl/api/mobile-attendance/verify-face'),
            headers: _headers,
            body: json.encode(body),
          )
          .timeout(const Duration(seconds: 15));
      return _handleResponse(response);
    } catch (e) {
      debugPrint('Error verifying face: $e');
      return _connectionFailure(e);
    }
  }

  // ==================== ADVANCE REQUESTS ====================

  // Lấy danh sách yêu cầu ứng lương
  Future<Map<String, dynamic>> getAdvanceRequests({
    int page = 1,
    int pageSize = 50,
    String? employeeUserId,
    int? status,
    DateTime? fromDate,
    DateTime? toDate,
  }) async {
    try {
      final params = <String, String>{
        'page': page.toString(),
        'pageSize': pageSize.toString(),
      };
      if (employeeUserId != null) params['employeeUserId'] = employeeUserId;
      if (status != null) params['status'] = status.toString();
      if (fromDate != null) params['fromDate'] = fromDate.toIso8601String();
      if (toDate != null) params['toDate'] = toDate.toIso8601String();

      final uri = Uri.parse('$baseUrl/api/AdvanceRequests')
          .replace(queryParameters: params);
      final response = await http
          .get(uri, headers: _headers)
          .timeout(const Duration(seconds: 15));
      return _handleResponse(response);
    } catch (e) {
      debugPrint('Error getting advance requests: $e');
      return _connectionFailure(e);
    }
  }

  // Tạo yêu cầu ứng lương mới
  Future<Map<String, dynamic>> createAdvanceRequest({
    required double amount,
    String? reason,
    String? note,
    int? forMonth,
    int? forYear,
    String? employeeUserId,
    String? employeeId,
  }) async {
    try {
      final body = {
        'amount': amount,
        'reason': reason ?? '',
        'note': note ?? '',
        if (forMonth != null) 'forMonth': forMonth,
        if (forYear != null) 'forYear': forYear,
        if (employeeUserId != null) 'employeeUserId': employeeUserId,
        if (employeeId != null) 'employeeId': employeeId,
      };
      final response = await http.post(
        Uri.parse('$baseUrl/api/AdvanceRequests'),
        headers: _headers,
        body: json.encode(body),
      );
      return _handleResponse(response);
    } catch (e) {
      debugPrint('Error creating advance request: $e');
      return _connectionFailure(e);
    }
  }

  // Duyệt hoặc từ chối yêu cầu ứng lương
  Future<Map<String, dynamic>> approveAdvanceRequest({
    required String requestId,
    required bool isApproved,
    String? rejectionReason,
    // Số tiền duyệt — cho phép duyệt thấp hơn số tiền yêu cầu. Bỏ trống
    // (null) = duyệt đủ số tiền yêu cầu.
    double? approvedAmount,
  }) async {
    try {
      final body = {
        'requestId': requestId,
        'isApproved': isApproved,
        'rejectionReason': rejectionReason,
        if (approvedAmount != null) 'approvedAmount': approvedAmount,
      };
      final response = await http.post(
        Uri.parse('$baseUrl/api/AdvanceRequests/$requestId/approve'),
        headers: _headers,
        body: json.encode(body),
      );
      return _handleResponse(response);
    } catch (e) {
      debugPrint('Error approving advance request: $e');
      return _connectionFailure(e);
    }
  }

  // Hoàn duyệt yêu cầu ứng lương
  Future<Map<String, dynamic>> undoApproveAdvanceRequest(
      String requestId) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/AdvanceRequests/$requestId/undo-approve'),
        headers: _headers,
      );
      return _handleResponse(response);
    } catch (e) {
      debugPrint('Error undoing advance request approval: $e');
      return _connectionFailure(e);
    }
  }

  // Thanh toán yêu cầu ứng lương
  Future<Map<String, dynamic>> payAdvanceRequest(String requestId,
      {String? paymentMethod}) async {
    try {
      final body = <String, dynamic>{};
      if (paymentMethod != null) body['paymentMethod'] = paymentMethod;
      final response = await http.post(
        Uri.parse('$baseUrl/api/AdvanceRequests/$requestId/pay'),
        headers: _headers,
        body: json.encode(body),
      );
      return _handleResponse(response);
    } catch (e) {
      debugPrint('Error paying advance request: $e');
      return _connectionFailure(e);
    }
  }

  // Xóa yêu cầu ứng lương
  Future<Map<String, dynamic>> deleteAdvanceRequest(String requestId) async {
    try {
      final response = await http.delete(
        Uri.parse('$baseUrl/api/AdvanceRequests/$requestId'),
        headers: _headers,
      );
      return _handleResponse(response);
    } catch (e) {
      debugPrint('Error deleting advance request: $e');
      return _connectionFailure(e);
    }
  }

  // Hủy yêu cầu ứng lương
  Future<Map<String, dynamic>> cancelAdvanceRequest(String requestId) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/AdvanceRequests/$requestId/cancel'),
        headers: _headers,
      );
      return _handleResponse(response);
    } catch (e) {
      debugPrint('Error cancelling advance request: $e');
      return _connectionFailure(e);
    }
  }

  // ==================== BUSINESS TRIP EXPENSE / CÔNG TÁC PHÍ ====================

  Future<Map<String, dynamic>> getBusinessTripCases({
    int page = 1,
    int pageSize = 20,
    String? employeeUserId,
    int? status,
    DateTime? fromDate,
    DateTime? toDate,
    String? categoryId,
  }) async {
    try {
      final params = <String, String>{
        'page': page.toString(),
        'pageSize': pageSize.toString(),
      };
      if (employeeUserId != null) params['employeeUserId'] = employeeUserId;
      if (status != null) params['status'] = status.toString();
      if (fromDate != null) {
        params['fromDate'] = fromDate.toIso8601String().split('T').first;
      }
      if (toDate != null) {
        params['toDate'] = toDate.toIso8601String().split('T').first;
      }
      if (categoryId != null && categoryId.isNotEmpty) {
        params['categoryId'] = categoryId;
      }
      final uri = Uri.parse('$baseUrl/api/BusinessTripCases')
          .replace(queryParameters: params);
      final response = await http
          .get(uri, headers: _headers)
          .timeout(const Duration(seconds: 15));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> getBusinessTripCase(String id) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/api/BusinessTripCases/$id'),
        headers: _headers,
      );
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> createBusinessTripCase(
      Map<String, dynamic> body) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/BusinessTripCases'),
        headers: _headers,
        body: jsonEncode(body),
      );
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> updateBusinessTripCase(
      String id, Map<String, dynamic> body) async {
    try {
      final response = await http.put(
        Uri.parse('$baseUrl/api/BusinessTripCases/$id'),
        headers: _headers,
        body: jsonEncode(body),
      );
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> deleteBusinessTripCase(String id) async {
    try {
      final response = await http.delete(
        Uri.parse('$baseUrl/api/BusinessTripCases/$id'),
        headers: _headers,
      );
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> createBusinessTripAdvance(
      String caseId, Map<String, dynamic> body) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/BusinessTripCases/$caseId/advance'),
        headers: _headers,
        body: jsonEncode(body),
      );
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> approveBusinessTripAdvance(
      String caseId, bool isApproved,
      {String? rejectionReason}) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/BusinessTripCases/$caseId/advance/approve'),
        headers: _headers,
        body: jsonEncode({
          'isApproved': isApproved,
          if (rejectionReason != null) 'rejectionReason': rejectionReason,
        }),
      );
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> payBusinessTripAdvance(String caseId,
      {String? paymentMethod}) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/BusinessTripCases/$caseId/advance/pay'),
        headers: _headers,
        body: jsonEncode(
            paymentMethod != null ? {'paymentMethod': paymentMethod} : {}),
      );
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> saveBusinessTripSettlement(
      String caseId, Map<String, dynamic> body) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/BusinessTripCases/$caseId/settlement'),
        headers: _headers,
        body: jsonEncode(body),
      );
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> approveBusinessTripSettlement(
      String caseId, bool isApproved,
      {String? rejectionReason, bool surplusAsCashRefund = false}) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/BusinessTripCases/$caseId/settlement/approve'),
        headers: _headers,
        body: jsonEncode({
          'isApproved': isApproved,
          if (rejectionReason != null) 'rejectionReason': rejectionReason,
          'surplusAsCashRefund': surplusAsCashRefund,
        }),
      );
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> confirmBusinessTripSurplus(String caseId,
      {bool asAdvanceDebt = true, String? paymentMethod}) async {
    try {
      final response = await http.post(
        Uri.parse(
            '$baseUrl/api/BusinessTripCases/$caseId/settlement/confirm-surplus'),
        headers: _headers,
        body: jsonEncode({
          'asAdvanceDebt': asAdvanceDebt,
          if (paymentMethod != null) 'paymentMethod': paymentMethod,
        }),
      );
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> payBusinessTripSettlementExtra(String caseId,
      {String? paymentMethod}) async {
    try {
      final response = await http.post(
        Uri.parse(
            '$baseUrl/api/BusinessTripCases/$caseId/settlement/pay-extra'),
        headers: _headers,
        body: jsonEncode(
            paymentMethod != null ? {'paymentMethod': paymentMethod} : {}),
      );
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> getBusinessTripExpenseCategories() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/api/BusinessTripCases/categories'),
        headers: _headers,
      );
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> upsertBusinessTripExpenseCategory(
    Map<String, dynamic> body, {
    String? id,
  }) async {
    try {
      final uri = Uri.parse('$baseUrl/api/BusinessTripCases/categories')
          .replace(queryParameters: id != null ? {'id': id} : null);
      final response = await http.post(
        uri,
        headers: _headers,
        body: jsonEncode(body),
      );
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> deleteBusinessTripExpenseCategory(
      String id) async {
    try {
      final response = await http.delete(
        Uri.parse('$baseUrl/api/BusinessTripCases/categories/$id'),
        headers: _headers,
      );
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> seedBusinessTripExpenseCategories() async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/BusinessTripCases/categories/seed-defaults'),
        headers: _headers,
      );
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  // ==================== ASSETS ====================

  Future<Map<String, dynamic>> getAssets({
    int page = 1,
    int pageSize = 20,
    String? search,
    int? status,
    int? assetType,
    String? categoryId,
    String? assigneeId,
    bool? unassignedOnly,
  }) async {
    try {
      final params = <String, String>{
        'page': page.toString(),
        'pageSize': pageSize.toString(),
      };
      if (search != null && search.isNotEmpty) params['search'] = search;
      if (status != null) params['status'] = status.toString();
      if (assetType != null) params['assetType'] = assetType.toString();
      if (categoryId != null) params['categoryId'] = categoryId;
      if (assigneeId != null) params['assigneeId'] = assigneeId;
      if (unassignedOnly == true) params['unassignedOnly'] = 'true';

      final uri =
          Uri.parse('$baseUrl/api/Assets').replace(queryParameters: params);
      final response = await http.get(uri, headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      debugPrint('Error getting assets: $e');
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> createAsset({
    required String assetCode,
    required String name,
    String? description,
    String? serialNumber,
    String? model,
    String? brand,
    String? size,
    String? color,
    int? assetType,
    String? categoryId,
    int? status,
    int? quantity,
    String? unit,
    double? purchasePrice,
    DateTime? purchaseDate,
    String? supplier,
    String? invoiceNumber,
    int? warrantyMonths,
    String? location,
    String? notes,
  }) async {
    try {
      final body = <String, dynamic>{
        'assetCode': assetCode,
        'name': name,
      };
      if (description != null) body['description'] = description;
      if (serialNumber != null) body['serialNumber'] = serialNumber;
      if (model != null) body['model'] = model;
      if (brand != null) body['brand'] = brand;
      if (size != null) body['size'] = size;
      if (color != null) body['color'] = color;
      if (assetType != null) body['assetType'] = assetType;
      if (categoryId != null) body['categoryId'] = categoryId;
      if (status != null) body['status'] = status;
      if (quantity != null) body['quantity'] = quantity;
      if (unit != null) body['unit'] = unit;
      if (purchasePrice != null) body['purchasePrice'] = purchasePrice;
      if (purchaseDate != null) {
        body['purchaseDate'] = purchaseDate.toIso8601String();
      }
      if (supplier != null) body['supplier'] = supplier;
      if (invoiceNumber != null) body['invoiceNumber'] = invoiceNumber;
      if (warrantyMonths != null) body['warrantyMonths'] = warrantyMonths;
      if (location != null) body['location'] = location;
      if (notes != null) body['notes'] = notes;

      final response = await http.post(
        Uri.parse('$baseUrl/api/Assets'),
        headers: _headers,
        body: json.encode(body),
      );
      return _handleResponse(response);
    } catch (e) {
      debugPrint('Error creating asset: $e');
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> updateAsset(
    String assetId, {
    String? assetCode,
    String? name,
    String? description,
    String? serialNumber,
    String? model,
    String? brand,
    String? size,
    String? color,
    int? assetType,
    String? categoryId,
    int? status,
    int? quantity,
    String? unit,
    double? purchasePrice,
    DateTime? purchaseDate,
    String? supplier,
    String? invoiceNumber,
    int? warrantyMonths,
    String? location,
    String? notes,
  }) async {
    try {
      final body = <String, dynamic>{};
      if (assetCode != null) body['assetCode'] = assetCode;
      if (name != null) body['name'] = name;
      if (description != null) body['description'] = description;
      if (serialNumber != null) body['serialNumber'] = serialNumber;
      if (model != null) body['model'] = model;
      if (brand != null) body['brand'] = brand;
      if (size != null) body['size'] = size;
      if (color != null) body['color'] = color;
      if (assetType != null) body['assetType'] = assetType;
      if (categoryId != null) body['categoryId'] = categoryId;
      if (status != null) body['status'] = status;
      if (quantity != null) body['quantity'] = quantity;
      if (unit != null) body['unit'] = unit;
      if (purchasePrice != null) body['purchasePrice'] = purchasePrice;
      if (purchaseDate != null) {
        body['purchaseDate'] = purchaseDate.toIso8601String();
      }
      if (supplier != null) body['supplier'] = supplier;
      if (invoiceNumber != null) body['invoiceNumber'] = invoiceNumber;
      if (warrantyMonths != null) body['warrantyMonths'] = warrantyMonths;
      if (location != null) body['location'] = location;
      if (notes != null) body['notes'] = notes;

      final response = await http.put(
        Uri.parse('$baseUrl/api/Assets/$assetId'),
        headers: _headers,
        body: json.encode(body),
      );
      return _handleResponse(response);
    } catch (e) {
      debugPrint('Error updating asset: $e');
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> deleteAsset(String assetId) async {
    try {
      final response = await http.delete(
        Uri.parse('$baseUrl/api/Assets/$assetId'),
        headers: _headers,
      );
      return _handleResponse(response);
    } catch (e) {
      debugPrint('Error deleting asset: $e');
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> getAssetCategories(
      {bool hierarchical = false}) async {
    try {
      final uri = Uri.parse(
          '$baseUrl/api/Assets/categories${hierarchical ? '?hierarchical=true' : ''}');
      final response = await http.get(uri, headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      debugPrint('Error getting asset categories: $e');
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> createAssetCategory({
    required String categoryCode,
    required String name,
    String? description,
    String? parentCategoryId,
  }) async {
    try {
      final body = <String, dynamic>{
        'categoryCode': categoryCode,
        'name': name,
      };
      if (description != null) body['description'] = description;
      if (parentCategoryId != null) body['parentCategoryId'] = parentCategoryId;

      final response = await http.post(
        Uri.parse('$baseUrl/api/Assets/categories'),
        headers: _headers,
        body: json.encode(body),
      );
      return _handleResponse(response);
    } catch (e) {
      debugPrint('Error creating asset category: $e');
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> updateAssetCategory(
    String categoryId, {
    String? categoryCode,
    String? name,
    String? description,
    String? parentCategoryId,
  }) async {
    try {
      final body = <String, dynamic>{};
      if (categoryCode != null) body['categoryCode'] = categoryCode;
      if (name != null) body['name'] = name;
      if (description != null) body['description'] = description;
      if (parentCategoryId != null) body['parentCategoryId'] = parentCategoryId;

      final response = await http.put(
        Uri.parse('$baseUrl/api/Assets/categories/$categoryId'),
        headers: _headers,
        body: json.encode(body),
      );
      return _handleResponse(response);
    } catch (e) {
      debugPrint('Error updating asset category: $e');
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> deleteAssetCategory(String categoryId) async {
    try {
      final response = await http.delete(
        Uri.parse('$baseUrl/api/Assets/categories/$categoryId'),
        headers: _headers,
      );
      return _handleResponse(response);
    } catch (e) {
      debugPrint('Error deleting asset category: $e');
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> getAssetTransfers(
      {int page = 1, int pageSize = 20}) async {
    try {
      final uri = Uri.parse(
          '$baseUrl/api/Assets/transfers?page=$page&pageSize=$pageSize');
      final response = await http.get(uri, headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      debugPrint('Error getting asset transfers: $e');
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> assignAsset({
    required String assetId,
    required String toUserId,
    String? reason,
    String? notes,
  }) async {
    try {
      final body = <String, dynamic>{
        'assetId': assetId,
        'toUserId': toUserId,
      };
      if (reason != null) body['reason'] = reason;
      if (notes != null) body['notes'] = notes;

      final response = await http.post(
        Uri.parse('$baseUrl/api/Assets/assign'),
        headers: _headers,
        body: json.encode(body),
      );
      return _handleResponse(response);
    } catch (e) {
      debugPrint('Error assigning asset: $e');
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> transferAsset({
    required String assetId,
    required String fromUserId,
    required String toUserId,
    String? reason,
    String? notes,
  }) async {
    try {
      final body = <String, dynamic>{
        'assetId': assetId,
        'fromUserId': fromUserId,
        'toUserId': toUserId,
      };
      if (reason != null) body['reason'] = reason;
      if (notes != null) body['notes'] = notes;

      final response = await http.post(
        Uri.parse('$baseUrl/api/Assets/transfer'),
        headers: _headers,
        body: json.encode(body),
      );
      return _handleResponse(response);
    } catch (e) {
      debugPrint('Error transferring asset: $e');
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> returnAsset({
    required String assetId,
    required String fromUserId,
    String? reason,
    String? notes,
    int? returnCondition,
  }) async {
    try {
      final body = <String, dynamic>{
        'assetId': assetId,
        'fromUserId': fromUserId,
      };
      if (reason != null) body['reason'] = reason;
      if (notes != null) body['notes'] = notes;
      if (returnCondition != null) body['returnCondition'] = returnCondition;

      final response = await http.post(
        Uri.parse('$baseUrl/api/Assets/return'),
        headers: _headers,
        body: json.encode(body),
      );
      return _handleResponse(response);
    } catch (e) {
      debugPrint('Error returning asset: $e');
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> confirmAssetTransfer(String transferId,
      {String? notes}) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/Assets/transfers/$transferId/confirm'),
        headers: _headers,
        body: json.encode(
            {'transferId': transferId, if (notes != null) 'notes': notes}),
      );
      return _handleResponse(response);
    } catch (e) {
      debugPrint('Error confirming asset transfer: $e');
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> getAssetInventories(
      {int page = 1, int pageSize = 20}) async {
    try {
      final uri = Uri.parse(
          '$baseUrl/api/Assets/inventories?page=$page&pageSize=$pageSize');
      final response = await http.get(uri, headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      debugPrint('Error getting asset inventories: $e');
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> createAssetInventory({
    required String name,
    String? description,
    DateTime? startDate,
    DateTime? endDate,
    String? responsibleUserId,
    String? notes,
    List<String>? assetIds,
    List<Map<String, dynamic>>? items,
  }) async {
    try {
      final body = <String, dynamic>{'name': name};
      if (description != null) body['description'] = description;
      if (startDate != null) body['startDate'] = startDate.toIso8601String();
      if (endDate != null) body['endDate'] = endDate.toIso8601String();
      if (responsibleUserId != null) {
        body['responsibleUserId'] = responsibleUserId;
      }
      if (notes != null) body['notes'] = notes;
      if (items != null && items.isNotEmpty) {
        body['items'] = items;
      } else if (assetIds != null && assetIds.isNotEmpty) {
        body['assetIds'] = assetIds;
      }

      final response = await http.post(
        Uri.parse('$baseUrl/api/Assets/inventories'),
        headers: _headers,
        body: json.encode(body),
      );
      return _handleResponse(response);
    } catch (e) {
      debugPrint('Error creating asset inventory: $e');
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> getAssetInventoryHistory(String assetId) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/api/Assets/$assetId/inventory-history'),
        headers: _headers,
      );
      return _handleResponse(response);
    } catch (e) {
      debugPrint('Error getting asset inventory history: $e');
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> getAssetStatistics() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/api/Assets/statistics'),
        headers: _headers,
      );
      return _handleResponse(response);
    } catch (e) {
      debugPrint('Error getting asset statistics: $e');
      return _connectionFailure(e);
    }
  }

  // ==================== FINANCE / HR / PAYROLL REPORTS ====================

  Future<Map<String, dynamic>> getCashReportTransactions({
    DateTime? fromDate,
    DateTime? toDate,
    int? type,
    int page = 1,
    int pageSize = 500,
  }) async {
    try {
      final params = <String, String>{
        'page': page.toString(),
        'pageSize': pageSize.toString(),
      };
      if (fromDate != null) {
        final d = fromDate is DateTime
            ? fromDate
            : DateTime.tryParse(fromDate.toString());
        if (d != null) {
          params['from'] = apiReportRangeStart(d).toIso8601String();
        }
      }
      if (toDate != null) {
        final d =
            toDate is DateTime ? toDate : DateTime.tryParse(toDate.toString());
        if (d != null) {
          params['to'] = apiReportRangeEnd(d).toIso8601String();
        }
      }
      if (type != null) params['type'] = type.toString();
      final uri = Uri.parse('$baseUrl/api/reports/finance/cash-transactions')
          .replace(queryParameters: params);
      final response = await http.get(uri, headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> getPenaltySummaryReport({
    DateTime? from,
    DateTime? to,
    String? department,
  }) async {
    try {
      final params = <String, String>{};
      if (from != null) params['from'] = from.toIso8601String();
      if (to != null) params['to'] = to.toIso8601String();
      if (department != null && department.isNotEmpty) {
        params['department'] = department;
      }
      final uri = Uri.parse('$baseUrl/api/reports/finance/penalty-summary')
          .replace(queryParameters: params.isNotEmpty ? params : null);
      final response = await http.get(uri, headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> getAdvanceDebtReport({
    DateTime? from,
    DateTime? to,
    String? department,
    int? status,
  }) async {
    try {
      final params = <String, String>{};
      if (from != null) params['from'] = from.toIso8601String();
      if (to != null) params['to'] = to.toIso8601String();
      if (department != null && department.isNotEmpty) {
        params['department'] = department;
      }
      if (status != null) params['status'] = status.toString();
      final uri = Uri.parse('$baseUrl/api/reports/finance/advance-debt')
          .replace(queryParameters: params.isNotEmpty ? params : null);
      final response = await http.get(uri, headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> getBusinessTripReport({
    DateTime? from,
    DateTime? to,
    String? department,
    int? status,
  }) async {
    try {
      final params = <String, String>{};
      if (from != null) params['from'] = from.toIso8601String();
      if (to != null) params['to'] = to.toIso8601String();
      if (department != null && department.isNotEmpty) {
        params['department'] = department;
      }
      if (status != null) params['status'] = status.toString();
      final uri = Uri.parse('$baseUrl/api/reports/finance/business-trip')
          .replace(queryParameters: params.isNotEmpty ? params : null);
      final response = await http.get(uri, headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> getAssetReportSummary({
    int? status,
    int? assetType,
    String? categoryId,
  }) async {
    try {
      final params = <String, String>{};
      if (status != null) params['status'] = status.toString();
      if (assetType != null) params['assetType'] = assetType.toString();
      if (categoryId != null) params['categoryId'] = categoryId;
      final uri = Uri.parse('$baseUrl/api/reports/assets/summary').replace(
        queryParameters: params.isNotEmpty ? params : null,
      );
      final response = await http.get(uri, headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      debugPrint('Error getAssetReportSummary: $e');
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> getAssetReportRegister({
    int? status,
    int? assetType,
    String? categoryId,
    String? search,
  }) async {
    try {
      final params = <String, String>{};
      if (status != null) params['status'] = status.toString();
      if (assetType != null) params['assetType'] = assetType.toString();
      if (categoryId != null) params['categoryId'] = categoryId;
      if (search != null && search.isNotEmpty) params['search'] = search;
      final uri = Uri.parse('$baseUrl/api/reports/assets/register').replace(
        queryParameters: params.isNotEmpty ? params : null,
      );
      final response = await http.get(uri, headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      debugPrint('Error getAssetReportRegister: $e');
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> getAssetReportAssignments({
    int? status,
    String? department,
  }) async {
    try {
      final params = <String, String>{};
      if (status != null) params['status'] = status.toString();
      if (department != null && department.isNotEmpty) {
        params['department'] = department;
      }
      final uri = Uri.parse('$baseUrl/api/reports/assets/assignments').replace(
        queryParameters: params.isNotEmpty ? params : null,
      );
      final response = await http.get(uri, headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      debugPrint('Error getAssetReportAssignments: $e');
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> getAssetReportTransfers({
    required DateTime from,
    required DateTime to,
  }) async {
    try {
      final params = <String, String>{
        'from': from.toIso8601String(),
        'to': to.toIso8601String(),
      };
      final uri = Uri.parse('$baseUrl/api/reports/assets/transfers')
          .replace(queryParameters: params);
      final response = await http.get(uri, headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      debugPrint('Error getAssetReportTransfers: $e');
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> getAssetReportStockLedger({
    required DateTime from,
    required DateTime to,
    int? transactionType,
  }) async {
    try {
      final params = <String, String>{
        'from': from.toIso8601String(),
        'to': to.toIso8601String(),
      };
      if (transactionType != null) {
        params['transactionType'] = transactionType.toString();
      }
      final uri = Uri.parse('$baseUrl/api/reports/assets/stock-ledger')
          .replace(queryParameters: params);
      final response = await http.get(uri, headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      debugPrint('Error getAssetReportStockLedger: $e');
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> getAssetReportInventoryVariance({
    String? inventoryId,
    bool onlyVariance = true,
    DateTime? from,
    DateTime? to,
  }) async {
    try {
      final params = <String, String>{
        'onlyVariance': onlyVariance.toString(),
      };
      if (inventoryId != null && inventoryId.isNotEmpty) {
        params['inventoryId'] = inventoryId;
      }
      if (from != null) params['from'] = from.toIso8601String();
      if (to != null) params['to'] = to.toIso8601String();
      final uri = Uri.parse('$baseUrl/api/reports/assets/inventory-variance')
          .replace(queryParameters: params);
      final response = await http.get(uri, headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      debugPrint('Error getAssetReportInventoryVariance: $e');
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> getAssetReportWarrantyExpiring({
    int days = 30,
    bool includeExpired = false,
  }) async {
    try {
      final params = <String, String>{
        'days': days.toString(),
        'includeExpired': includeExpired.toString(),
      };
      final uri = Uri.parse('$baseUrl/api/reports/assets/warranty-expiring')
          .replace(queryParameters: params);
      final response = await http.get(uri, headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      debugPrint('Error getAssetReportWarrantyExpiring: $e');
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> lookupAssetByCode(String code) async {
    try {
      final response = await http.get(
        Uri.parse(
            '$baseUrl/api/Assets/lookup?code=${Uri.encodeComponent(code)}'),
        headers: _headers,
      );
      return _handleResponse(response);
    } catch (e) {
      debugPrint('Error looking up asset: $e');
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> getInventoryDetail(String inventoryId) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/api/Assets/inventories/$inventoryId'),
        headers: _headers,
      );
      return _handleResponse(response);
    } catch (e) {
      debugPrint('Error getting inventory detail: $e');
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> checkInventoryItem({
    required String inventoryItemId,
    int condition = 0,
    int? actualQuantity,
    String? actualLocation,
    bool hasIssue = false,
    String? issueDescription,
    String? notes,
    String? imageUrl,
  }) async {
    try {
      final body = <String, dynamic>{
        'inventoryItemId': inventoryItemId,
        'condition': condition,
        'hasIssue': hasIssue,
      };
      if (actualQuantity != null) body['actualQuantity'] = actualQuantity;
      if (actualLocation != null) body['actualLocation'] = actualLocation;
      if (issueDescription != null) body['issueDescription'] = issueDescription;
      if (imageUrl != null) {
        notes =
            '${notes ?? ''}${notes != null && notes.isNotEmpty ? '\n' : ''}[IMG]$imageUrl[/IMG]';
      }
      if (notes != null) body['notes'] = notes;

      final response = await http.post(
        Uri.parse('$baseUrl/api/Assets/inventories/items/check'),
        headers: _headers,
        body: json.encode(body),
      );
      return _handleResponse(response);
    } catch (e) {
      debugPrint('Error checking inventory item: $e');
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> scanInventoryItem({
    required String inventoryId,
    required String code,
    int condition = 0,
    int? actualQuantity,
    String? actualLocation,
    bool hasIssue = false,
    String? issueDescription,
    String? notes,
    String? imageUrl,
  }) async {
    try {
      final body = <String, dynamic>{
        'code': code,
        'condition': condition,
        'hasIssue': hasIssue,
      };
      if (actualQuantity != null) body['actualQuantity'] = actualQuantity;
      if (actualLocation != null) body['actualLocation'] = actualLocation;
      if (issueDescription != null) body['issueDescription'] = issueDescription;
      if (imageUrl != null) {
        notes =
            '${notes ?? ''}${notes != null && notes.isNotEmpty ? '\n' : ''}[IMG]$imageUrl[/IMG]';
      }
      if (notes != null) body['notes'] = notes;

      final response = await http.post(
        Uri.parse('$baseUrl/api/Assets/inventories/$inventoryId/scan'),
        headers: _headers,
        body: json.encode(body),
      );
      return _handleResponse(response);
    } catch (e) {
      debugPrint('Error scanning inventory item: $e');
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> completeInventory(String inventoryId) async {
    try {
      final response = await http.patch(
        Uri.parse('$baseUrl/api/Assets/inventories/$inventoryId/complete'),
        headers: _headers,
      );
      return _handleResponse(response);
    } catch (e) {
      debugPrint('Error completing inventory: $e');
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> cancelInventory(String inventoryId) async {
    try {
      final response = await http.patch(
        Uri.parse('$baseUrl/api/Assets/inventories/$inventoryId/cancel'),
        headers: _headers,
      );
      return _handleResponse(response);
    } catch (e) {
      debugPrint('Error cancelling inventory: $e');
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> deleteInventory(String inventoryId) async {
    try {
      final response = await http.delete(
        Uri.parse('$baseUrl/api/Assets/inventories/$inventoryId'),
        headers: _headers,
      );
      return _handleResponse(response);
    } catch (e) {
      debugPrint('Error deleting inventory: $e');
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> uploadFile(List<int> fileBytes, String fileName,
      {String folder = 'uploads'}) async {
    try {
      final uri = Uri.parse(
          '$baseUrl/api/Upload/file?folder=${Uri.encodeComponent(folder)}');
      final request = http.MultipartRequest('POST', uri);
      if (_token != null) request.headers['Authorization'] = 'Bearer $_token';

      final ext = fileName.toLowerCase().split('.').last;
      final mimeTypes = {
        'pdf': 'application/pdf',
        'jpg': 'image/jpeg',
        'jpeg': 'image/jpeg',
        'png': 'image/png',
        'gif': 'image/gif',
        'webp': 'image/webp',
      };
      final contentType = mimeTypes[ext] ?? 'application/octet-stream';
      final mediaParts = contentType.split('/');

      request.files.add(http.MultipartFile.fromBytes(
        'file',
        fileBytes,
        filename: fileName,
        contentType: MediaType(mediaParts[0], mediaParts[1]),
      ));
      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);
      return _handleResponse(response);
    } catch (e) {
      debugPrint('Error uploading file: $e');
      return {'isSuccess': false, 'message': 'Lỗi tải ảnh: $e'};
    }
  }

  /// Upload ảnh/video trình chiếu màn hình phụ (tối đa ~50MB).
  Future<Map<String, dynamic>> uploadCustomerDisplayMedia(
    List<int> fileBytes,
    String fileName,
  ) async {
    try {
      final uri = Uri.parse('$baseUrl/api/Upload/customer-display-media');
      final request = http.MultipartRequest('POST', uri);
      if (_token != null) request.headers['Authorization'] = 'Bearer $_token';

      final ext = fileName.toLowerCase().split('.').last;
      final mimeTypes = {
        'jpg': 'image/jpeg',
        'jpeg': 'image/jpeg',
        'png': 'image/png',
        'gif': 'image/gif',
        'webp': 'image/webp',
        'mp4': 'video/mp4',
        'webm': 'video/webm',
        'mov': 'video/quicktime',
      };
      final contentType = mimeTypes[ext] ?? 'application/octet-stream';
      final mediaParts = contentType.split('/');

      request.files.add(http.MultipartFile.fromBytes(
        'file',
        fileBytes,
        filename: fileName.contains('.') ? fileName : '$fileName.mp4',
        contentType: MediaType(mediaParts[0], mediaParts[1]),
      ));
      final streamedResponse =
          await request.send().timeout(const Duration(minutes: 3));
      final response = await http.Response.fromStream(streamedResponse)
          .timeout(const Duration(minutes: 3));
      return _handleResponse(response);
    } catch (e) {
      debugPrint('Error uploading customer-display media: $e');
      return {'isSuccess': false, 'message': 'Lỗi tải media: $e'};
    }
  }

  Future<Map<String, dynamic>> addAssetImage({
    required String assetId,
    required String imageUrl,
    String? fileName,
    String? description,
    bool isPrimary = false,
  }) async {
    try {
      final body = <String, dynamic>{
        'imageUrl': imageUrl,
        'isPrimary': isPrimary,
      };
      if (fileName != null) body['fileName'] = fileName;
      if (description != null) body['description'] = description;

      final response = await http.post(
        Uri.parse('$baseUrl/api/Assets/$assetId/images'),
        headers: _headers,
        body: json.encode(body),
      );
      return _handleResponse(response);
    } catch (e) {
      debugPrint('Error adding asset image: $e');
      return {'isSuccess': false, 'message': 'Lỗi thêm ảnh: $e'};
    }
  }

  // ==================== STOCK TRANSACTIONS ====================

  Future<Map<String, dynamic>> stockIn({
    required String assetId,
    required int quantity,
    String? reason,
    String? referenceCode,
    String? notes,
  }) async {
    try {
      final body = <String, dynamic>{
        'assetId': assetId,
        'transactionType': 0,
        'quantity': quantity,
      };
      if (reason != null) body['reason'] = reason;
      if (referenceCode != null) body['referenceCode'] = referenceCode;
      if (notes != null) body['notes'] = notes;

      final response = await http.post(
        Uri.parse('$baseUrl/api/Assets/stock/in'),
        headers: _headers,
        body: json.encode(body),
      );
      return _handleResponse(response);
    } catch (e) {
      return {'isSuccess': false, 'message': 'Lỗi nhập kho: $e'};
    }
  }

  Future<Map<String, dynamic>> stockOut({
    required String assetId,
    required int quantity,
    String? reason,
    String? referenceCode,
    String? notes,
  }) async {
    try {
      final body = <String, dynamic>{
        'assetId': assetId,
        'transactionType': 1,
        'quantity': quantity,
      };
      if (reason != null) body['reason'] = reason;
      if (referenceCode != null) body['referenceCode'] = referenceCode;
      if (notes != null) body['notes'] = notes;

      final response = await http.post(
        Uri.parse('$baseUrl/api/Assets/stock/out'),
        headers: _headers,
        body: json.encode(body),
      );
      return _handleResponse(response);
    } catch (e) {
      return {'isSuccess': false, 'message': 'Lỗi xuất kho: $e'};
    }
  }

  Future<Map<String, dynamic>> getStockTransactions({
    int page = 1,
    int pageSize = 50,
    String? assetId,
    int? transactionType,
    DateTime? fromDate,
    DateTime? toDate,
    String? search,
  }) async {
    try {
      final params = <String, String>{
        'page': page.toString(),
        'pageSize': pageSize.toString(),
      };
      if (assetId != null) params['assetId'] = assetId;
      if (transactionType != null) {
        params['transactionType'] = transactionType.toString();
      }
      if (fromDate != null) params['fromDate'] = fromDate.toIso8601String();
      if (toDate != null) params['toDate'] = toDate.toIso8601String();
      if (search != null) params['search'] = search;

      final uri = Uri.parse('$baseUrl/api/Assets/stock/transactions')
          .replace(queryParameters: params);
      final response = await http.get(uri, headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return {'isSuccess': false, 'message': 'Lỗi lấy lịch sử: $e'};
    }
  }

  Future<Map<String, dynamic>> getStockSummary() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/api/Assets/stock/summary'),
        headers: _headers,
      );
      return _handleResponse(response);
    } catch (e) {
      return {'isSuccess': false, 'message': 'Lỗi lấy tổng quan kho: $e'};
    }
  }

  // ==================== TRANSACTIONS (BONUS/PENALTY) ====================

  Future<Map<String, dynamic>> getTransactions({
    DateTime? fromDate,
    DateTime? toDate,
    String? type,
    int page = 1,
    int pageSize = 100,
  }) async {
    try {
      final params = <String, String>{
        'page': page.toString(),
        'pageSize': pageSize.toString(),
      };
      if (fromDate != null) params['fromDate'] = fromDate.toIso8601String();
      if (toDate != null) params['toDate'] = toDate.toIso8601String();
      if (type != null) params['type'] = type;

      final uri = Uri.parse('$baseUrl/api/Transactions')
          .replace(queryParameters: params);
      final response = await http
          .get(uri, headers: _headers)
          .timeout(const Duration(seconds: 15));
      return _handleResponse(response);
    } catch (e) {
      debugPrint('Error getting transactions: $e');
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> createTransaction(
      Map<String, dynamic> data) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/Transactions'),
        headers: _headers,
        body: json.encode(data),
      );
      return _handleResponse(response);
    } catch (e) {
      debugPrint('Error creating transaction: $e');
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> updateTransaction(
      String id, Map<String, dynamic> data) async {
    try {
      final response = await http.put(
        Uri.parse('$baseUrl/api/Transactions/$id'),
        headers: _headers,
        body: json.encode(data),
      );
      return _handleResponse(response);
    } catch (e) {
      debugPrint('Error updating transaction: $e');
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> deleteTransaction(String id) async {
    try {
      final response = await http.delete(
        Uri.parse('$baseUrl/api/Transactions/$id'),
        headers: _headers,
      );
      return _handleResponse(response);
    } catch (e) {
      debugPrint('Error deleting transaction: $e');
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> updateTransactionStatus(
    String id,
    String status, {
    String? disbursementMode,
  }) async {
    try {
      final body = <String, dynamic>{'status': status};
      if (disbursementMode != null && disbursementMode.isNotEmpty) {
        body['disbursementMode'] = disbursementMode;
      }
      final response = await http.put(
        Uri.parse('$baseUrl/api/Transactions/$id/status'),
        headers: _headers,
        body: json.encode(body),
      );
      return _handleResponse(response);
    } catch (e) {
      debugPrint('Error updating transaction status: $e');
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> bulkApproveTransactions(
    List<String> ids, {
    String? disbursementMode,
  }) async {
    try {
      final body = <String, dynamic>{'ids': ids};
      if (disbursementMode != null && disbursementMode.isNotEmpty) {
        body['disbursementMode'] = disbursementMode;
      }
      final response = await http.post(
        Uri.parse('$baseUrl/api/Transactions/bulk-approve'),
        headers: _headers,
        body: json.encode(body),
      );
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> bulkPayTransactions(
      List<String> ids, String paymentMethod) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/Transactions/bulk-pay'),
        headers: _headers,
        body: json.encode({'ids': ids, 'paymentMethod': paymentMethod}),
      );
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  // ==================== COMMUNICATIONS / CONTENT ====================

  Future<List<dynamic>> getContentCategories({int? contentType}) async {
    try {
      final params = <String, String>{};
      if (contentType != null) params['contentType'] = contentType.toString();

      final uri = Uri.parse('$baseUrl/api/ContentCategories')
          .replace(queryParameters: params.isNotEmpty ? params : null);
      final response = await http.get(uri, headers: _headers);
      final result = _handleResponse(response);
      if (result['isSuccess'] == true && result['data'] != null) {
        return result['data'] is List ? result['data'] : [];
      }
      return [];
    } catch (e) {
      debugPrint('Error getting content categories: $e');
      return [];
    }
  }

  Future<Map<String, dynamic>> createContentCategory(
      Map<String, dynamic> data) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/ContentCategories'),
        headers: _headers,
        body: json.encode(data),
      );
      return _handleResponse(response);
    } catch (e) {
      debugPrint('Error creating content category: $e');
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> updateContentCategory(
      String id, Map<String, dynamic> data) async {
    try {
      final response = await http.put(
        Uri.parse('$baseUrl/api/ContentCategories/$id'),
        headers: _headers,
        body: json.encode(data),
      );
      return _handleResponse(response);
    } catch (e) {
      debugPrint('Error updating content category: $e');
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> deleteContentCategory(String id) async {
    try {
      final response = await http.delete(
        Uri.parse('$baseUrl/api/ContentCategories/$id'),
        headers: _headers,
      );
      return _handleResponse(response);
    } catch (e) {
      debugPrint('Error deleting content category: $e');
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> getCommunications({
    int? type,
    int? priority,
    int page = 1,
    int pageSize = 50,
    dynamic status,
    String? searchTerm,
    String? sortBy,
    bool? sortDescending,
  }) async {
    try {
      final params = <String, String>{
        'page': page.toString(),
        'pageSize': pageSize.toString(),
      };
      if (type != null) params['type'] = type.toString();
      if (priority != null) params['priority'] = priority.toString();
      if (status != null) params['status'] = status.toString();
      if (searchTerm != null) params['searchTerm'] = searchTerm;
      if (sortBy != null) params['sortBy'] = sortBy;
      if (sortDescending != null) {
        params['sortDescending'] = sortDescending.toString();
      }

      final uri = Uri.parse('$baseUrl/api/communications')
          .replace(queryParameters: params);
      final response = await http.get(uri, headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      debugPrint('Error getting communications: $e');
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> createCommunication(
      Map<String, dynamic> data) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/communications'),
        headers: _headers,
        body: json.encode(data),
      );
      return _handleResponse(response);
    } catch (e) {
      debugPrint('Error creating communication: $e');
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> updateCommunication(
      String id, Map<String, dynamic> data) async {
    try {
      final response = await http.put(
        Uri.parse('$baseUrl/api/communications/$id'),
        headers: _headers,
        body: json.encode(data),
      );
      return _handleResponse(response);
    } catch (e) {
      debugPrint('Error updating communication: $e');
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> deleteCommunication(String id) async {
    try {
      final response = await http.delete(
        Uri.parse('$baseUrl/api/communications/$id'),
        headers: _headers,
      );
      return _handleResponse(response);
    } catch (e) {
      debugPrint('Error deleting communication: $e');
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> publishCommunication(String id) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/communications/$id/publish'),
        headers: _headers,
      );
      return _handleResponse(response);
    } catch (e) {
      debugPrint('Error publishing communication: $e');
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> uploadCommunicationImage(
      List<int> bytes, String fileName) async {
    try {
      // Use base64 endpoint for web compatibility
      if (kIsWeb) {
        final base64Data = base64Encode(bytes);
        final response = await http.post(
          Uri.parse('$baseUrl/api/communications/upload-image-base64'),
          headers: _headers,
          body: json.encode({'base64Data': base64Data, 'fileName': fileName}),
        );
        return _handleResponse(response);
      }

      // Use multipart for native platforms
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('$baseUrl/api/communications/upload-image'),
      );
      if (_token != null) request.headers['Authorization'] = 'Bearer $_token';

      final ext = fileName.toLowerCase().split('.').last;
      final mimeTypes = {
        'jpg': 'image/jpeg',
        'jpeg': 'image/jpeg',
        'png': 'image/png',
        'gif': 'image/gif',
        'webp': 'image/webp',
      };
      final contentType = mimeTypes[ext] ?? 'image/jpeg';
      final mediaParts = contentType.split('/');

      request.files.add(http.MultipartFile.fromBytes(
        'file',
        bytes,
        filename: fileName,
        contentType: MediaType(mediaParts[0], mediaParts[1]),
      ));
      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);
      return _handleResponse(response);
    } catch (e) {
      debugPrint('Error uploading communication image: $e');
      return _connectionFailure(e);
    }
  }

  Stream<String> streamAiCommunicationContent(
      Map<String, dynamic> data) async* {
    try {
      final request = http.Request(
          'POST', Uri.parse('$baseUrl/api/communications/ai-generate'));
      request.headers.addAll(_headers);
      request.body = json.encode(data);
      final streamedResponse = await http.Client().send(request);
      await for (final chunk
          in streamedResponse.stream.transform(utf8.decoder)) {
        yield chunk;
      }
    } catch (e) {
      debugPrint('Error streaming AI content: $e');
      yield '[ERROR]Lỗi kết nối: $e';
    }
  }

  // ==================== DEPARTMENTS ====================
  Future<Map<String, dynamic>> getDepartments(
      {int? pageNumber,
      int? page,
      int? pageSize,
      String? searchTerm,
      bool? isActive}) async {
    try {
      final params = <String, String>{};
      final p = pageNumber ?? page;
      if (p != null) {
        params.addAll(paginationQueryParams(p, pageSize ?? 20));
      } else if (pageSize != null) {
        params['pageSize'] = pageSize.toString();
      }
      if (searchTerm != null) params['searchTerm'] = searchTerm;
      if (isActive != null) params['isActive'] = isActive.toString();
      final uri = Uri.parse('$baseUrl/api/Departments')
          .replace(queryParameters: params.isNotEmpty ? params : null);
      final response = await http.get(uri, headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> getDepartmentTree(
      {bool? includeInactive}) async {
    try {
      final params = <String, String>{};
      if (includeInactive != null) {
        params['includeInactive'] = includeInactive.toString();
      }
      final uri = Uri.parse('$baseUrl/api/Departments/tree')
          .replace(queryParameters: params.isNotEmpty ? params : null);
      final response = await http.get(uri, headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> getDepartmentsForSelect() async {
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/api/Departments/select'), headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> createDepartment(
      {String? code,
      String? name,
      String? description,
      String? parentDepartmentId,
      String? managerId,
      int? sortOrder,
      List<dynamic>? positions}) async {
    try {
      final data = <String, dynamic>{
        if (code != null) 'code': code,
        if (name != null) 'name': name,
        if (description != null) 'description': description,
        if (parentDepartmentId != null)
          'parentDepartmentId': parentDepartmentId,
        if (managerId != null) 'managerId': managerId,
        if (sortOrder != null) 'sortOrder': sortOrder,
        if (positions != null) 'positions': positions,
      };
      final response = await http.post(Uri.parse('$baseUrl/api/Departments'),
          headers: _headers, body: json.encode(data));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> updateDepartment(
      {String? departmentId,
      String? code,
      String? name,
      String? description,
      String? parentDepartmentId,
      String? managerId,
      int? sortOrder,
      bool? isActive,
      List<dynamic>? positions}) async {
    try {
      final data = <String, dynamic>{
        if (code != null) 'code': code,
        if (name != null) 'name': name,
        if (description != null) 'description': description,
        if (parentDepartmentId != null)
          'parentDepartmentId': parentDepartmentId,
        if (managerId != null) 'managerId': managerId,
        if (sortOrder != null) 'sortOrder': sortOrder,
        if (isActive != null) 'isActive': isActive,
        if (positions != null) 'positions': positions,
      };
      final id = departmentId ?? '';
      final response = await http.put(Uri.parse('$baseUrl/api/Departments/$id'),
          headers: _headers, body: json.encode(data));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> deleteDepartment(String id) async {
    try {
      final response = await http
          .delete(Uri.parse('$baseUrl/api/Departments/$id'), headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  // ==================== BRANCHES ====================
  Future<Map<String, dynamic>> getBranches(
      {String? search, bool? isActive}) async {
    try {
      final params = <String, String>{};
      if (search != null) params['search'] = search;
      if (isActive != null) params['isActive'] = isActive.toString();
      final uri = Uri.parse('$baseUrl/api/branches')
          .replace(queryParameters: params.isNotEmpty ? params : null);
      final response = await http.get(uri, headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> getBranchTree() async {
    try {
      final response = await http.get(Uri.parse('$baseUrl/api/branches/tree'),
          headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> getBranchStats() async {
    try {
      final response = await http.get(Uri.parse('$baseUrl/api/branches/stats'),
          headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> getBranchesForSelect() async {
    try {
      final response = await http.get(Uri.parse('$baseUrl/api/branches/select'),
          headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> createBranch(Map<String, dynamic> data) async {
    try {
      final response = await http.post(Uri.parse('$baseUrl/api/branches'),
          headers: _headers, body: json.encode(data));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> updateBranch(
      String id, Map<String, dynamic> data) async {
    try {
      final response = await http.put(Uri.parse('$baseUrl/api/branches/$id'),
          headers: _headers, body: json.encode(data));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> toggleBranchActive(String id) async {
    try {
      final response = await http.put(
          Uri.parse('$baseUrl/api/branches/$id/toggle-active'),
          headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> deleteBranch(String id) async {
    try {
      final response = await http.delete(Uri.parse('$baseUrl/api/branches/$id'),
          headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> getBranchPermissions(String branchId) async {
    try {
      final response = await http.get(
          Uri.parse('$baseUrl/api/branches/$branchId/permissions'),
          headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> createBranchPermission(
      String branchId, Map<String, dynamic> data) async {
    try {
      final response = await http.post(
          Uri.parse('$baseUrl/api/branches/$branchId/permissions'),
          headers: _headers,
          body: jsonEncode(data));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> updateBranchPermission(
      String permId, Map<String, dynamic> data) async {
    try {
      final response = await http.put(
          Uri.parse('$baseUrl/api/branches/permissions/$permId'),
          headers: _headers,
          body: jsonEncode(data));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> deleteBranchPermission(String permId) async {
    try {
      final response = await http.delete(
          Uri.parse('$baseUrl/api/branches/permissions/$permId'),
          headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> getMyBranches() async {
    try {
      final response = await http.get(
          Uri.parse('$baseUrl/api/branches/my-branches'),
          headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  // ==================== LEAVES ====================
  Future<Map<String, dynamic>> getMyLeaves(
      {int? page,
      int? pageSize,
      String? status,
      String? fromDate,
      String? toDate}) async {
    try {
      final params = <String, String>{};
      if (page != null) {
        params.addAll(paginationQueryParams(page, pageSize ?? 20));
      } else if (pageSize != null) {
        params['pageSize'] = pageSize.toString();
      }
      if (status != null) params['status'] = status;
      if (fromDate != null) params['fromDate'] = fromDate;
      if (toDate != null) params['toDate'] = toDate;
      final uri = Uri.parse('$baseUrl/api/Leaves/my-leaves')
          .replace(queryParameters: params.isNotEmpty ? params : null);
      final response = await http.get(uri, headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> getAllLeaves(
      {int? page,
      int? pageSize,
      String? status,
      String? fromDate,
      String? toDate,
      String? employeeId}) async {
    try {
      final params = <String, String>{};
      if (page != null) {
        params.addAll(paginationQueryParams(page, pageSize ?? 20));
      } else if (pageSize != null) {
        params['pageSize'] = pageSize.toString();
      }
      if (status != null) params['status'] = status;
      if (fromDate != null) params['fromDate'] = fromDate;
      if (toDate != null) params['toDate'] = toDate;
      if (employeeId != null) params['employeeId'] = employeeId;
      final uri = Uri.parse('$baseUrl/api/Leaves')
          .replace(queryParameters: params.isNotEmpty ? params : null);
      final response = await http.get(uri, headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> getPendingLeaves(
      {int? page, int? pageSize}) async {
    try {
      final params = <String, String>{};
      if (page != null) {
        params.addAll(paginationQueryParams(page, pageSize ?? 20));
      } else if (pageSize != null) {
        params['pageSize'] = pageSize.toString();
      }
      final uri = Uri.parse('$baseUrl/api/Leaves/pending')
          .replace(queryParameters: params.isNotEmpty ? params : null);
      final response = await http.get(uri, headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> createLeave(
      {List<String>? shiftIds,
      DateTime? startDate,
      DateTime? endDate,
      dynamic type,
      bool? isHalfShift,
      String? reason,
      String? replacementEmployeeId,
      String? employeeUserId,
      String? employeeId,
      bool? countAsWork,
      bool? autoApprove,
      int? sickLeaveMode,
      String? bhxhDocumentNote}) async {
    try {
      if (shiftIds == null || shiftIds.isEmpty) {
        return {'isSuccess': false, 'message': 'Vui lòng chọn ca làm việc'};
      }
      final data = <String, dynamic>{
        'shiftId': shiftIds.first,
        'shiftIds': shiftIds,
        if (startDate != null) 'startDate': startDate.toIso8601String(),
        if (endDate != null) 'endDate': endDate.toIso8601String(),
        if (type != null) 'type': type,
        if (isHalfShift != null) 'isHalfShift': isHalfShift,
        if (reason != null) 'reason': reason,
        if (replacementEmployeeId != null)
          'replacementEmployeeId': replacementEmployeeId,
        if (employeeUserId != null) 'employeeUserId': employeeUserId,
        if (employeeId != null) 'employeeId': employeeId,
        if (countAsWork == true) 'countAsWork': true,
        if (autoApprove == true) 'autoApprove': true,
        if (sickLeaveMode != null) 'sickLeaveMode': sickLeaveMode,
        if (bhxhDocumentNote != null && bhxhDocumentNote.isNotEmpty)
          'bhxhDocumentNote': bhxhDocumentNote,
      };
      final response = await http.post(Uri.parse('$baseUrl/api/Leaves'),
          headers: _headers, body: json.encode(data));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> updateLeave(
      {String? leaveId,
      List<String>? shiftIds,
      DateTime? startDate,
      DateTime? endDate,
      dynamic type,
      bool? isHalfShift,
      String? reason,
      String? replacementEmployeeId,
      String? employeeUserId,
      String? employeeId,
      bool? countAsWork,
      int? sickLeaveMode,
      String? bhxhDocumentNote}) async {
    try {
      if (shiftIds == null || shiftIds.isEmpty) {
        return {'isSuccess': false, 'message': 'Vui lòng chọn ca làm việc'};
      }
      final data = <String, dynamic>{
        'shiftId': shiftIds.first,
        'shiftIds': shiftIds,
        if (startDate != null) 'startDate': startDate.toIso8601String(),
        if (endDate != null) 'endDate': endDate.toIso8601String(),
        if (type != null) 'type': type,
        if (isHalfShift != null) 'isHalfShift': isHalfShift,
        if (reason != null) 'reason': reason,
        if (replacementEmployeeId != null)
          'replacementEmployeeId': replacementEmployeeId,
        if (employeeUserId != null) 'employeeUserId': employeeUserId,
        if (employeeId != null) 'employeeId': employeeId,
        if (countAsWork != null) 'countAsWork': countAsWork,
        if (sickLeaveMode != null) 'sickLeaveMode': sickLeaveMode,
        if (bhxhDocumentNote != null) 'bhxhDocumentNote': bhxhDocumentNote,
      };
      final response = await http.put(Uri.parse('$baseUrl/api/Leaves/$leaveId'),
          headers: _headers, body: json.encode(data));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> cancelLeave(String id) async {
    try {
      final response = await http.delete(Uri.parse('$baseUrl/api/Leaves/$id'),
          headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> getAnnualLeaveBalance(String employeeId) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/api/Leaves/annual-balance/$employeeId'),
        headers: _headers,
      );
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> approveLeave(String id, {bool? countAsWork}) async {
    try {
      final body = countAsWork != null
          ? json.encode({'countAsWork': countAsWork})
          : null;
      final response = await http.post(
          Uri.parse('$baseUrl/api/Leaves/$id/approve'),
          headers: _headers,
          body: body);
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> rejectLeave(String id, [String? reason]) async {
    try {
      final response = await http.post(
          Uri.parse('$baseUrl/api/Leaves/$id/reject'),
          headers: _headers,
          body: json.encode({'rejectionReason': reason ?? ''}));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> undoLeaveApproval(String id) async {
    try {
      final response = await http.post(
          Uri.parse('$baseUrl/api/Leaves/$id/undo-approve'),
          headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> forceDeleteLeave(String id) async {
    try {
      final response = await http.delete(
          Uri.parse('$baseUrl/api/Leaves/$id/force'),
          headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  // ==================== ATTENDANCE CORRECTIONS ====================
  Future<Map<String, dynamic>> getMyAttendanceCorrections(
      {int? page, int? pageSize, dynamic status}) async {
    try {
      final params = <String, String>{};
      if (page != null) {
        params.addAll(paginationQueryParams(page, pageSize ?? 20));
      } else if (pageSize != null) {
        params['pageSize'] = pageSize.toString();
      }
      if (status != null) params['status'] = status.toString();
      final uri = Uri.parse('$baseUrl/api/AttendanceCorrections/my')
          .replace(queryParameters: params.isNotEmpty ? params : null);
      final response = await http.get(uri, headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> getAttendanceCorrections(
      {int? page,
      int? pageSize,
      dynamic status,
      dynamic fromDate,
      dynamic toDate,
      String? employeeUserId}) async {
    try {
      final params = <String, String>{};
      if (page != null) {
        params.addAll(paginationQueryParams(page, pageSize ?? 20));
      } else if (pageSize != null) {
        params['pageSize'] = pageSize.toString();
      }
      if (status != null) params['status'] = status.toString();
      if (fromDate != null) {
        params['fromDate'] = fromDate is DateTime
            ? fromDate.toIso8601String()
            : fromDate.toString();
      }
      if (toDate != null) {
        params['toDate'] =
            toDate is DateTime ? toDate.toIso8601String() : toDate.toString();
      }
      if (employeeUserId != null) params['employeeUserId'] = employeeUserId;
      final uri = Uri.parse('$baseUrl/api/AttendanceCorrections')
          .replace(queryParameters: params.isNotEmpty ? params : null);
      final response = await http.get(uri, headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> createAttendanceCorrection(
      {dynamic action,
      dynamic pin,
      String? employeeName,
      String? employeeCode,
      String? employeeUserId,
      String? attendanceId,
      dynamic oldDate,
      String? oldTime,
      dynamic newDate,
      String? newTime,
      String? newType,
      String? reason,
      String? targetApproverId,
      String? targetApproverName}) async {
    try {
      final data = <String, dynamic>{
        if (action != null)
          'action': action is int ? action : action.toString(),
        if (pin != null) 'pin': pin.toString(),
        if (employeeName != null) 'employeeName': employeeName,
        if (employeeCode != null) 'employeeCode': employeeCode,
        if (employeeUserId != null) 'employeeUserId': employeeUserId,
        if (attendanceId != null) 'attendanceId': attendanceId,
        if (oldDate != null)
          'oldDate': oldDate is DateTime
              ? correctionDateOnly(oldDate as DateTime)
              : oldDate.toString(),
        if (oldTime != null) 'oldTime': oldTime,
        if (newDate != null)
          'newDate': newDate is DateTime
              ? correctionDateOnly(newDate as DateTime)
              : newDate.toString(),
        if (newTime != null) 'newTime': newTime,
        if (newType != null) 'newType': newType,
        if (reason != null) 'reason': reason,
        if (targetApproverId != null) 'targetApproverId': targetApproverId,
        if (targetApproverName != null)
          'targetApproverName': targetApproverName,
      };
      final response = await http.post(
          Uri.parse('$baseUrl/api/AttendanceCorrections'),
          headers: _headers,
          body: json.encode(data));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> approveAttendanceCorrection(
      {required String requestId,
      required bool isApproved,
      String? approverNote}) async {
    try {
      final data = <String, dynamic>{
        'isApproved': isApproved,
        if (approverNote != null) 'approverNote': approverNote
      };
      final response = await http.post(
          Uri.parse('$baseUrl/api/AttendanceCorrections/$requestId/approve'),
          headers: _headers,
          body: json.encode(data));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> undoAttendanceCorrectionApproval(
      String id) async {
    try {
      final requestId = id.toString().trim();
      if (requestId.isEmpty) {
        return {'isSuccess': false, 'message': 'Mã yêu cầu không hợp lệ'};
      }
      final response = await _retryOnUnauthorized(() => http.post(
            Uri.parse(
                '$baseUrl/api/AttendanceCorrections/$requestId/undo-approve'),
            headers: _headers,
          ).timeout(const Duration(seconds: 30)));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> deleteAttendanceCorrection(String id) async {
    try {
      final response = await http.delete(
          Uri.parse('$baseUrl/api/AttendanceCorrections/$id'),
          headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> getAttendanceCorrectionById(String id) async {
    try {
      final response = await http.get(
          Uri.parse('$baseUrl/api/AttendanceCorrections/$id'),
          headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  // ==================== CASH TRANSACTIONS ====================
  Future<Map<String, dynamic>> getCashTransactions(
      {int? page,
      int? pageSize,
      int? pageNumber,
      dynamic type,
      dynamic status,
      dynamic fromDate,
      dynamic toDate,
      dynamic categoryId,
      dynamic accountId}) async {
    try {
      final params = <String, String>{};
      final p = pageNumber ?? page;
      if (p != null) {
        params.addAll(paginationQueryParams(p, pageSize ?? 20));
      } else if (pageSize != null) {
        params['pageSize'] = pageSize.toString();
      }
      if (type != null) params['type'] = type.toString();
      if (status != null) params['status'] = status.toString();
      if (fromDate != null) {
        params['fromDate'] = fromDate is DateTime
            ? fromDate.toIso8601String()
            : fromDate.toString();
      }
      if (toDate != null) {
        params['toDate'] =
            toDate is DateTime ? toDate.toIso8601String() : toDate.toString();
      }
      if (categoryId != null) params['categoryId'] = categoryId.toString();
      if (accountId != null) params['accountId'] = accountId.toString();
      final uri = Uri.parse('$baseUrl/api/CashTransactions')
          .replace(queryParameters: params.isNotEmpty ? params : null);
      final response = await _get(uri);
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> createCashTransaction(
      Map<String, dynamic> data) async {
    try {
      final response = await _post(Uri.parse('$baseUrl/api/CashTransactions'),
          body: json.encode(data));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> updateCashTransaction(
      String id, Map<String, dynamic> data) async {
    try {
      final response = await _put(
          Uri.parse('$baseUrl/api/CashTransactions/$id'),
          body: json.encode(data));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> deleteCashTransaction(String id) async {
    try {
      final response =
          await _delete(Uri.parse('$baseUrl/api/CashTransactions/$id'));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> getFundTransfers({
    DateTime? fromDate,
    DateTime? toDate,
    int page = 1,
    int pageSize = 50,
  }) async {
    try {
      final params = <String, String>{
        'page': '$page',
        'pageSize': '$pageSize',
      };
      if (fromDate != null) params['fromDate'] = fromDate.toIso8601String();
      if (toDate != null) params['toDate'] = toDate.toIso8601String();
      final uri = Uri.parse('$baseUrl/api/CashTransactions/fund-transfers')
          .replace(queryParameters: params);
      final response = await _get(uri);
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> getFundBalances() async {
    try {
      final response =
          await _get(Uri.parse('$baseUrl/api/CashTransactions/fund-balances'));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> createFundTransfer(
      Map<String, dynamic> data) async {
    try {
      final response = await _post(
          Uri.parse('$baseUrl/api/CashTransactions/fund-transfers'),
          body: json.encode(data));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> deleteFundTransfer(String id) async {
    try {
      final response = await _delete(
          Uri.parse('$baseUrl/api/CashTransactions/fund-transfers/$id'));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> updateCashTransactionStatus(
      String id, dynamic statusValue) async {
    try {
      final data = statusValue is Map<String, dynamic>
          ? statusValue
          : {'status': statusValue};
      final response = await _put(
          Uri.parse('$baseUrl/api/CashTransactions/$id/status'),
          body: json.encode(data));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> getCashTransactionSummary(
      {dynamic fromDate, dynamic toDate, String? type}) async {
    try {
      final params = <String, String>{};
      if (fromDate != null) {
        params['fromDate'] = fromDate is DateTime
            ? fromDate.toIso8601String()
            : fromDate.toString();
      }
      if (toDate != null) {
        params['toDate'] =
            toDate is DateTime ? toDate.toIso8601String() : toDate.toString();
      }
      if (type != null) params['type'] = type;
      final uri = Uri.parse('$baseUrl/api/CashTransactions/summary')
          .replace(queryParameters: params.isNotEmpty ? params : null);
      final response = await _get(uri);
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  // ==================== TRANSACTION CATEGORIES ====================
  Future<Map<String, dynamic>> getTransactionCategories() async {
    try {
      final response =
          await _get(Uri.parse('$baseUrl/api/TransactionCategories'));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> createTransactionCategory(
      Map<String, dynamic> data) async {
    try {
      final response = await _post(
          Uri.parse('$baseUrl/api/TransactionCategories'),
          body: json.encode(data));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> updateTransactionCategory(
      String id, Map<String, dynamic> data) async {
    try {
      final response = await _put(
          Uri.parse('$baseUrl/api/TransactionCategories/$id'),
          body: json.encode(data));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> deleteTransactionCategory(String id) async {
    try {
      final response = await _delete(
          Uri.parse('$baseUrl/api/TransactionCategories/$id'));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> initDefaultTransactionCategories() async {
    try {
      final response = await _post(
          Uri.parse('$baseUrl/api/TransactionCategories/init-default'));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  /// Sửa tên danh mục thu chi bị lỗi encoding trong DB (một lần / khi mở màn hình).
  Future<Map<String, dynamic>> repairTransactionCategoryEncoding() async {
    try {
      final response = await _post(
          Uri.parse('$baseUrl/api/TransactionCategories/repair-encoding'));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  // ==================== BANK ACCOUNTS ====================
  Future<Map<String, dynamic>> getBankAccounts() async {
    try {
      final response = await _get(Uri.parse('$baseUrl/api/BankAccounts'));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> createBankAccount(
      Map<String, dynamic> data) async {
    try {
      final response = await _post(Uri.parse('$baseUrl/api/BankAccounts'),
          body: json.encode(data));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> updateBankAccount(
      String id, Map<String, dynamic> data) async {
    try {
      final response = await _put(Uri.parse('$baseUrl/api/BankAccounts/$id'),
          body: json.encode(data));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> setDefaultBankAccount(String id) async {
    try {
      final response =
          await _put(Uri.parse('$baseUrl/api/BankAccounts/$id/set-default'));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> deleteBankAccount(String id) async {
    try {
      final response =
          await _delete(Uri.parse('$baseUrl/api/BankAccounts/$id'));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> getVietQRBanks() async {
    try {
      final response =
          await _get(Uri.parse('$baseUrl/api/BankAccounts/vietqr-banks'));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  // ==================== ORGCHART ====================
  Future<Map<String, dynamic>> getOrgChartTree() async {
    try {
      final response = await http.get(Uri.parse('$baseUrl/api/orgchart/tree'),
          headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> getOrgChartStats() async {
    try {
      final response = await http.get(Uri.parse('$baseUrl/api/orgchart/stats'),
          headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> getOrgPositions() async {
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/api/orgchart/positions'), headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> updateOrgPosition(
      String id, Map<String, dynamic> data) async {
    try {
      final response = await http.put(
          Uri.parse('$baseUrl/api/orgchart/positions/$id'),
          headers: _headers,
          body: json.encode(data));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> deleteOrgPosition(String id) async {
    try {
      final response = await http.delete(
          Uri.parse('$baseUrl/api/orgchart/positions/$id'),
          headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> getOrgAssignments({String? employeeId}) async {
    try {
      final params = <String, String>{};
      if (employeeId != null) params['employeeId'] = employeeId;
      final uri = Uri.parse('$baseUrl/api/orgchart/assignments')
          .replace(queryParameters: params.isNotEmpty ? params : null);
      final response = await http.get(uri, headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> createOrgAssignment(
      Map<String, dynamic> data) async {
    try {
      final response = await http.post(
          Uri.parse('$baseUrl/api/orgchart/assignments'),
          headers: _headers,
          body: json.encode(data));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> updateOrgAssignment(
      String id, Map<String, dynamic> data) async {
    try {
      final response = await http.put(
          Uri.parse('$baseUrl/api/orgchart/assignments/$id'),
          headers: _headers,
          body: json.encode(data));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> deleteOrgAssignment(String id) async {
    try {
      final response = await http.delete(
          Uri.parse('$baseUrl/api/orgchart/assignments/$id'),
          headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> getApprovalFlows() async {
    try {
      final response = await http.get(
          Uri.parse('$baseUrl/api/orgchart/approval-flows'),
          headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> createApprovalFlow(
      Map<String, dynamic> data) async {
    try {
      final response = await http.post(
          Uri.parse('$baseUrl/api/orgchart/approval-flows'),
          headers: _headers,
          body: json.encode(data));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> updateApprovalFlow(
      String id, Map<String, dynamic> data) async {
    try {
      final response = await http.put(
          Uri.parse('$baseUrl/api/orgchart/approval-flows/$id'),
          headers: _headers,
          body: json.encode(data));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> deleteApprovalFlow(String id) async {
    try {
      final response = await http.delete(
          Uri.parse('$baseUrl/api/orgchart/approval-flows/$id'),
          headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> getUnassignedEmployees() async {
    try {
      final response = await http.get(
          Uri.parse('$baseUrl/api/orgchart/unassigned-employees'),
          headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  // ==================== TASKS ====================
  Future<Map<String, dynamic>> getTasks(
      {int? page,
      int? pageSize,
      dynamic status,
      dynamic priority,
      String? assigneeId,
      String? search,
      dynamic taskType,
      dynamic fromDate,
      dynamic toDate,
      bool? isOverdue,
      String? branchId,
      bool? onlyAssignedToMe,
      bool? onlyAssignedByMe}) async {
    try {
      final params = <String, String>{};
      if (page != null) params['page'] = page.toString();
      if (pageSize != null) params['pageSize'] = pageSize.toString();
      if (status != null) params['status'] = status.toString();
      if (priority != null) params['priority'] = priority.toString();
      if (assigneeId != null) params['assigneeId'] = assigneeId;
      if (search != null) params['search'] = search;
      if (taskType != null) params['taskType'] = taskType.toString();
      if (isOverdue == true) params['isOverdue'] = 'true';
      if (branchId != null && branchId.isNotEmpty) params['branchId'] = branchId;
      if (onlyAssignedToMe == true) params['onlyAssignedToMe'] = 'true';
      if (onlyAssignedByMe == true) params['onlyAssignedByMe'] = 'true';
      if (fromDate != null) {
        params['fromDate'] = fromDate is DateTime
            ? fromDate.toIso8601String()
            : fromDate.toString();
      }
      if (toDate != null) {
        params['toDate'] =
            toDate is DateTime ? toDate.toIso8601String() : toDate.toString();
      }
      final uri = Uri.parse('$baseUrl/api/Tasks')
          .replace(queryParameters: params.isNotEmpty ? params : null);
      final response = await http.get(uri, headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> getTaskById(String id) async {
    try {
      final response = await http.get(Uri.parse('$baseUrl/api/Tasks/$id'),
          headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> getMyTasks({
    int? page,
    int? pageSize,
    dynamic status,
    dynamic priority,
    bool? isOverdue,
  }) async {
    try {
      final params = <String, String>{};
      if (page != null) params['page'] = page.toString();
      if (pageSize != null) params['pageSize'] = pageSize.toString();
      if (status != null) params['status'] = status.toString();
      if (priority != null) params['priority'] = priority.toString();
      if (isOverdue == true) params['isOverdue'] = 'true';
      final uri = Uri.parse('$baseUrl/api/Tasks/my')
          .replace(queryParameters: params.isNotEmpty ? params : null);
      final response = await http.get(uri, headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> createTask(
      {String? title,
      String? description,
      dynamic taskType,
      dynamic priority,
      String? assigneeId,
      List<String>? assigneeIds,
      bool requireAcceptance = true,
      dynamic startDate,
      dynamic dueDate,
      double? estimatedHours}) async {
    try {
      final data = <String, dynamic>{
        if (title != null) 'title': title,
        if (description != null) 'description': description,
        if (taskType != null) 'taskType': taskType,
        if (priority != null) 'priority': priority,
        if (assigneeId != null) 'assigneeId': assigneeId,
        if (assigneeIds != null && assigneeIds.isNotEmpty)
          'assigneeIds': assigneeIds,
        'requireAcceptance': requireAcceptance,
        if (startDate != null)
          'startDate':
              startDate is DateTime ? startDate.toIso8601String() : startDate,
        if (dueDate != null)
          'dueDate': dueDate is DateTime ? dueDate.toIso8601String() : dueDate,
        if (estimatedHours != null) 'estimatedHours': estimatedHours,
      };
      final response = await http.post(Uri.parse('$baseUrl/api/Tasks'),
          headers: _headers, body: json.encode(data));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> updateTaskStatus(
      String id, dynamic statusData) async {
    try {
      final data = statusData is Map<String, dynamic>
          ? statusData
          : {'status': statusData};
      final response = await http.patch(
          Uri.parse('$baseUrl/api/Tasks/$id/status'),
          headers: _headers,
          body: json.encode(data));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> updateTaskProgress(
      String id, dynamic progressData) async {
    try {
      final data = progressData is Map<String, dynamic>
          ? progressData
          : {'progress': progressData};
      final response = await http.patch(
          Uri.parse('$baseUrl/api/Tasks/$id/progress'),
          headers: _headers,
          body: json.encode(data));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> batchUpdateTaskStatus(List<String> taskIds,
      [int? status]) async {
    try {
      final data = <String, dynamic>{
        'taskIds': taskIds,
        if (status != null) 'status': status
      };
      final response = await http.post(
          Uri.parse('$baseUrl/api/Tasks/batch/status'),
          headers: _headers,
          body: json.encode(data));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> batchAssignTasks(List<String> taskIds,
      [String? assigneeId]) async {
    try {
      final data = <String, dynamic>{
        'taskIds': taskIds,
        if (assigneeId != null) 'assigneeId': assigneeId
      };
      final response = await http.post(
          Uri.parse('$baseUrl/api/Tasks/batch/assign'),
          headers: _headers,
          body: json.encode(data));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> deleteTask(String id) async {
    try {
      final response = await http.delete(Uri.parse('$baseUrl/api/Tasks/$id'),
          headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> batchDeleteTasks(List<String> taskIds) async {
    try {
      final response = await http.post(
          Uri.parse('$baseUrl/api/Tasks/batch/delete'),
          headers: _headers,
          body: json.encode({'taskIds': taskIds}));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> getTaskKanbanBoard(
      {String? assigneeId,
      dynamic priority,
      String? branchId,
      bool? onlyAssignedToMe}) async {
    try {
      final params = <String, String>{};
      if (assigneeId != null) params['assigneeId'] = assigneeId;
      if (priority != null) params['priority'] = priority.toString();
      if (branchId != null && branchId.isNotEmpty) params['branchId'] = branchId;
      if (onlyAssignedToMe == true) params['onlyAssignedToMe'] = 'true';
      final uri = Uri.parse('$baseUrl/api/Tasks/kanban')
          .replace(queryParameters: params.isNotEmpty ? params : null);
      final response = await http.get(uri, headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> getTaskStatistics(
      {String? assigneeId,
      dynamic priority,
      dynamic fromDate,
      dynamic toDate,
      String? branchId}) async {
    try {
      final params = <String, String>{};
      if (assigneeId != null) params['assigneeId'] = assigneeId;
      if (priority != null) params['priority'] = priority.toString();
      if (branchId != null && branchId.isNotEmpty) params['branchId'] = branchId;
      if (fromDate != null) {
        params['fromDate'] = fromDate is DateTime
            ? fromDate.toIso8601String()
            : fromDate.toString();
      }
      if (toDate != null) {
        params['toDate'] =
            toDate is DateTime ? toDate.toIso8601String() : toDate.toString();
      }
      final uri = Uri.parse('$baseUrl/api/Tasks/statistics')
          .replace(queryParameters: params.isNotEmpty ? params : null);
      final response = await http.get(uri, headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> getTaskHistory(String taskId) async {
    try {
      final response = await http.get(
          Uri.parse('$baseUrl/api/Tasks/$taskId/history'),
          headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> addTaskComment(
      String taskId, dynamic commentData) async {
    try {
      final data = commentData is Map<String, dynamic>
          ? commentData
          : {'content': commentData};
      final response = await http.post(
          Uri.parse('$baseUrl/api/Tasks/$taskId/comments'),
          headers: _headers,
          body: json.encode(data));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> updateTask(
      String id, Map<String, dynamic> data) async {
    try {
      final response = await http.put(Uri.parse('$baseUrl/api/Tasks/$id/full'),
          headers: _headers, body: json.encode(data));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> sendTaskReminder(String taskId,
      {required String sentToId,
      required String message,
      int urgencyLevel = 0}) async {
    try {
      final response =
          await http.post(Uri.parse('$baseUrl/api/Tasks/$taskId/reminders'),
              headers: _headers,
              body: json.encode({
                'taskId': taskId,
                'sentToId': sentToId,
                'message': message,
                'urgencyLevel': urgencyLevel
              }));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> getTaskReminders(String taskId) async {
    try {
      final response = await http.get(
          Uri.parse('$baseUrl/api/Tasks/$taskId/reminders'),
          headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> createTaskEvaluation(String taskId,
      {required int qualityScore,
      required int timelinessScore,
      required int overallScore,
      String? comment}) async {
    try {
      final response =
          await http.post(Uri.parse('$baseUrl/api/Tasks/$taskId/evaluations'),
              headers: _headers,
              body: json.encode({
                'qualityScore': qualityScore,
                'timelinessScore': timelinessScore,
                'overallScore': overallScore,
                if (comment != null) 'comment': comment
              }));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> getTaskEvaluations(String taskId) async {
    try {
      final response = await http.get(
          Uri.parse('$baseUrl/api/Tasks/$taskId/evaluations'),
          headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> getTaskAssignmentDashboard(
      {String? branchId}) async {
    try {
      final params = <String, String>{};
      if (branchId != null && branchId.isNotEmpty) {
        params['branchId'] = branchId;
      }
      final uri = Uri.parse('$baseUrl/api/Tasks/assignment-dashboard').replace(
        queryParameters: params.isNotEmpty ? params : null,
      );
      final response = await http.get(uri, headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      debugPrint('Error getTaskAssignmentDashboard: $e');
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> acceptTask(String id,
      {bool startImmediately = false}) async {
    try {
      final response = await http.patch(
        Uri.parse('$baseUrl/api/Tasks/$id/accept'),
        headers: _headers,
        body: jsonEncode({'startImmediately': startImmediately}),
      );
      return _handleResponse(response);
    } catch (e) {
      debugPrint('Error acceptTask: $e');
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> rejectTask(String id, String reason) async {
    try {
      final response = await http.patch(
        Uri.parse('$baseUrl/api/Tasks/$id/reject'),
        headers: _headers,
        body: jsonEncode({'reason': reason}),
      );
      return _handleResponse(response);
    } catch (e) {
      debugPrint('Error rejectTask: $e');
      return _connectionFailure(e);
    }
  }

  // ==================== REPORTS ====================

  /// Maps Flutter [departmentId] (GUID or department name) to Reports API params.
  void _putReportsDepartmentFilter(Map<String, String> params, String? departmentId) {
    if (departmentId == null || departmentId.trim().isEmpty) return;
    final v = departmentId.trim();
    final isGuid = RegExp(
      r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
    ).hasMatch(v);
    if (isGuid) {
      params['departmentId'] = v;
    } else {
      params['department'] = v;
    }
  }

  void _putReportsBranchFilter(
    Map<String, String> params,
    String? branchId, {
    bool includeChildBranches = true,
  }) {
    final v = branchId?.trim();
    if (v == null || v.isEmpty) return;
    params['branchId'] = v;
    params['includeChildBranches'] = includeChildBranches.toString();
  }

  Future<Map<String, dynamic>> getDailyAttendanceReport(
      {dynamic date,
      String? departmentId,
      String? branchId,
      bool includeChildBranches = true}) async {
    try {
      final params = <String, String>{};
      if (date != null) {
        params['date'] = date is DateTime
            ? date.toIso8601String().split('T').first
            : date.toString();
      }
      _putReportsDepartmentFilter(params, departmentId);
      _putReportsBranchFilter(params, branchId,
          includeChildBranches: includeChildBranches);
      // Work-day window comes solely from AppSettings day_end_time on the server.
      final uri = Uri.parse('$baseUrl/api/Reports/attendance/daily')
          .replace(queryParameters: params.isNotEmpty ? params : null);
      final response = await http.get(uri, headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> getMonthlyAttendanceReport(
      {int? month,
      int? year,
      String? departmentId,
      String? branchId,
      bool includeChildBranches = true}) async {
    try {
      final params = <String, String>{};
      if (month != null) params['month'] = month.toString();
      if (year != null) params['year'] = year.toString();
      _putReportsDepartmentFilter(params, departmentId);
      _putReportsBranchFilter(params, branchId,
          includeChildBranches: includeChildBranches);
      final uri = Uri.parse('$baseUrl/api/Reports/attendance/monthly')
          .replace(queryParameters: params.isNotEmpty ? params : null);
      final response = await http.get(uri, headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> getLateEarlyReport(
      {dynamic fromDate,
      dynamic toDate,
      String? departmentId,
      String? branchId,
      bool includeChildBranches = true,
      dynamic startDate,
      dynamic endDate}) async {
    try {
      final params = <String, String>{};
      final fd = fromDate ?? startDate;
      final td = toDate ?? endDate;
      if (fd != null) {
        params['startDate'] =
            fd is DateTime ? fd.toIso8601String() : fd.toString();
      }
      if (td != null) {
        params['endDate'] =
            td is DateTime ? td.toIso8601String() : td.toString();
      }
      _putReportsDepartmentFilter(params, departmentId);
      _putReportsBranchFilter(params, branchId,
          includeChildBranches: includeChildBranches);
      final uri = Uri.parse('$baseUrl/api/Reports/late-early')
          .replace(queryParameters: params.isNotEmpty ? params : null);
      final response = await http.get(uri, headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> getDepartmentSummaryReport(
      {dynamic fromDate, dynamic toDate, int? year, int? month}) async {
    try {
      final params = <String, String>{};
      if (year != null) params['year'] = year.toString();
      if (month != null) params['month'] = month.toString();
      if (fromDate != null) {
        params['fromDate'] = fromDate is DateTime
            ? fromDate.toIso8601String()
            : fromDate.toString();
      }
      if (toDate != null) {
        params['toDate'] =
            toDate is DateTime ? toDate.toIso8601String() : toDate.toString();
      }
      final uri = Uri.parse('$baseUrl/api/Reports/department-summary')
          .replace(queryParameters: params.isNotEmpty ? params : null);
      final response = await http.get(uri, headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> exportDailyReport(
      {dynamic date,
      String? departmentId,
      String? branchId,
      bool includeChildBranches = true}) async {
    try {
      final params = <String, String>{};
      if (date != null) {
        params['date'] = date is DateTime
            ? date.toIso8601String().split('T').first
            : date.toString();
      }
      _putReportsDepartmentFilter(params, departmentId);
      _putReportsBranchFilter(params, branchId,
          includeChildBranches: includeChildBranches);
      final uri = Uri.parse('$baseUrl/api/Reports/export/daily')
          .replace(queryParameters: params.isNotEmpty ? params : null);
      final response = await http.get(uri, headers: _headers);
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return {'isSuccess': true, 'data': response.body};
      }
      return {
        'isSuccess': false,
        'message': 'Export failed: ${response.statusCode}'
      };
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> exportMonthlyReport(
      {int? month,
      int? year,
      String? departmentId,
      String? branchId,
      bool includeChildBranches = true}) async {
    try {
      final params = <String, String>{};
      if (month != null) params['month'] = month.toString();
      if (year != null) params['year'] = year.toString();
      _putReportsDepartmentFilter(params, departmentId);
      _putReportsBranchFilter(params, branchId,
          includeChildBranches: includeChildBranches);
      final uri = Uri.parse('$baseUrl/api/Reports/export/monthly')
          .replace(queryParameters: params.isNotEmpty ? params : null);
      final response = await http.get(uri, headers: _headers);
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return {'isSuccess': true, 'data': response.body};
      }
      return {
        'isSuccess': false,
        'message': 'Export failed: ${response.statusCode}'
      };
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> exportLateEarlyReport(
      {dynamic fromDate,
      dynamic toDate,
      String? departmentId,
      dynamic startDate,
      dynamic endDate,
      String? branchId,
      bool includeChildBranches = true}) async {
    try {
      final params = <String, String>{};
      final fd = fromDate ?? startDate;
      final td = toDate ?? endDate;
      if (fd != null) {
        params['startDate'] =
            fd is DateTime ? fd.toIso8601String() : fd.toString();
      }
      if (td != null) {
        params['endDate'] =
            td is DateTime ? td.toIso8601String() : td.toString();
      }
      _putReportsDepartmentFilter(params, departmentId);
      _putReportsBranchFilter(params, branchId,
          includeChildBranches: includeChildBranches);
      final uri = Uri.parse('$baseUrl/api/Reports/export/late-early')
          .replace(queryParameters: params.isNotEmpty ? params : null);
      final response = await http.get(uri, headers: _headers);
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return {'isSuccess': true, 'data': response.body};
      }
      return {
        'isSuccess': false,
        'message': 'Export failed: ${response.statusCode}'
      };
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> exportDailyReportExcel(
      {dynamic date,
      String? departmentId,
      String? branchId,
      bool includeChildBranches = true}) async {
    final params = <String, String>{};
    if (date != null) {
      params['date'] = date is DateTime
          ? date.toIso8601String().split('T').first
          : date.toString();
    }
    _putReportsDepartmentFilter(params, departmentId);
    _putReportsBranchFilter(params, branchId,
        includeChildBranches: includeChildBranches);
    return _getExcelExport(
      Uri.parse('$baseUrl/api/Reports/export/excel/daily')
          .replace(queryParameters: params.isNotEmpty ? params : null),
    );
  }

  Future<Map<String, dynamic>> exportMonthlyReportExcel(
      {int? month,
      int? year,
      String? departmentId,
      String? branchId,
      bool includeChildBranches = true}) async {
    final params = <String, String>{};
    if (month != null) params['month'] = month.toString();
    if (year != null) params['year'] = year.toString();
    _putReportsDepartmentFilter(params, departmentId);
    _putReportsBranchFilter(params, branchId,
        includeChildBranches: includeChildBranches);
    return _getExcelExport(
      Uri.parse('$baseUrl/api/Reports/export/excel/monthly')
          .replace(queryParameters: params.isNotEmpty ? params : null),
    );
  }

  Future<Map<String, dynamic>> exportLateEarlyReportExcel(
      {dynamic fromDate,
      dynamic toDate,
      String? departmentId,
      dynamic startDate,
      dynamic endDate,
      String? branchId,
      bool includeChildBranches = true}) async {
    final params = <String, String>{};
    final fd = fromDate ?? startDate;
    final td = toDate ?? endDate;
    if (fd != null) {
      params['startDate'] =
          fd is DateTime ? fd.toIso8601String() : fd.toString();
    }
    if (td != null) {
      params['endDate'] =
          td is DateTime ? td.toIso8601String() : td.toString();
    }
    _putReportsDepartmentFilter(params, departmentId);
    _putReportsBranchFilter(params, branchId,
        includeChildBranches: includeChildBranches);
    return _getExcelExport(
      Uri.parse('$baseUrl/api/Reports/export/excel/late-early')
          .replace(queryParameters: params.isNotEmpty ? params : null),
    );
  }

  Future<Map<String, dynamic>> exportDepartmentSummaryExcel(
      {int? year, int? month}) async {
    final params = <String, String>{};
    if (year != null) params['year'] = year.toString();
    if (month != null) params['month'] = month.toString();
    return _getExcelExport(
      Uri.parse('$baseUrl/api/Reports/export/excel/department')
          .replace(queryParameters: params.isNotEmpty ? params : null),
    );
  }

  Future<Map<String, dynamic>> getOvertimeReport(
      {dynamic startDate,
      dynamic endDate,
      String? department,
      String? branchId,
      bool includeChildBranches = true,
      int? minOvertimeMinutes}) async {
    try {
      final params = <String, String>{};
      if (startDate != null) {
        params['startDate'] = startDate is DateTime
            ? startDate.toIso8601String()
            : startDate.toString();
      }
      if (endDate != null) {
        params['endDate'] = endDate is DateTime
            ? endDate.toIso8601String()
            : endDate.toString();
      }
      if (department != null) params['department'] = department;
      _putReportsBranchFilter(params, branchId,
          includeChildBranches: includeChildBranches);
      if (minOvertimeMinutes != null) {
        params['minOvertimeMinutes'] = minOvertimeMinutes.toString();
      }
      final uri = Uri.parse('$baseUrl/api/Reports/overtime')
          .replace(queryParameters: params.isNotEmpty ? params : null);
      final response = await http.get(uri, headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> exportOvertimeReportExcel(
      {dynamic startDate,
      dynamic endDate,
      String? department,
      String? branchId,
      bool includeChildBranches = true}) async {
    final params = <String, String>{};
    if (startDate != null) {
      params['startDate'] = startDate is DateTime
          ? startDate.toIso8601String()
          : startDate.toString();
    }
    if (endDate != null) {
      params['endDate'] = endDate is DateTime
          ? endDate.toIso8601String()
          : endDate.toString();
    }
    _putReportsDepartmentFilter(params, department);
    _putReportsBranchFilter(params, branchId,
        includeChildBranches: includeChildBranches);
    return _getExcelExport(
      Uri.parse('$baseUrl/api/Reports/export/excel/overtime')
          .replace(queryParameters: params.isNotEmpty ? params : null),
    );
  }

  Future<Map<String, dynamic>> getLeaveReport(
      {dynamic startDate,
      dynamic endDate,
      String? department,
      String? branchId,
      bool includeChildBranches = true}) async {
    try {
      final params = <String, String>{};
      if (startDate != null) {
        params['startDate'] = startDate is DateTime
            ? startDate.toIso8601String()
            : startDate.toString();
      }
      if (endDate != null) {
        params['endDate'] = endDate is DateTime
            ? endDate.toIso8601String()
            : endDate.toString();
      }
      if (department != null) params['department'] = department;
      _putReportsBranchFilter(params, branchId,
          includeChildBranches: includeChildBranches);
      final uri = Uri.parse('$baseUrl/api/Reports/leave-summary')
          .replace(queryParameters: params.isNotEmpty ? params : null);
      final response = await http.get(uri, headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> exportLeaveReportExcel(
      {dynamic startDate,
      dynamic endDate,
      String? department,
      String? branchId,
      bool includeChildBranches = true}) async {
    final params = <String, String>{};
    if (startDate != null) {
      params['startDate'] = startDate is DateTime
          ? startDate.toIso8601String()
          : startDate.toString();
    }
    if (endDate != null) {
      params['endDate'] = endDate is DateTime
          ? endDate.toIso8601String()
          : endDate.toString();
    }
    _putReportsDepartmentFilter(params, department);
    _putReportsBranchFilter(params, branchId,
        includeChildBranches: includeChildBranches);
    return _getExcelExport(
      Uri.parse('$baseUrl/api/Reports/export/excel/leave-summary')
          .replace(queryParameters: params.isNotEmpty ? params : null),
    );
  }

  // ==================== DASHBOARD (EXTENDED) ====================
  Future<Map<String, dynamic>> getFullDashboard({int? trendDays}) async {
    try {
      final params = <String, String>{};
      if (trendDays != null) params['trendDays'] = trendDays.toString();
      final uri = Uri.parse('$baseUrl/api/Dashboard/full')
          .replace(queryParameters: params.isNotEmpty ? params : null);
      final response = await http.get(uri, headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> getManagerDashboard({DateTime? date}) async {
    try {
      final params = <String, String>{};
      if (date != null) params['date'] = date.toIso8601String().split('T')[0];
      final uri = Uri.parse('$baseUrl/api/Dashboard/manager')
          .replace(queryParameters: params.isNotEmpty ? params : null);
      final response = await http.get(uri, headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> getTopPerformers({int? count}) async {
    try {
      final params = <String, String>{};
      if (count != null) params['count'] = count.toString();
      final uri = Uri.parse('$baseUrl/api/Dashboard/top-performers')
          .replace(queryParameters: params.isNotEmpty ? params : null);
      final response = await http.get(uri, headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> getLateEmployees({int? count}) async {
    try {
      final params = <String, String>{};
      if (count != null) params['count'] = count.toString();
      final uri = Uri.parse('$baseUrl/api/Dashboard/late-employees')
          .replace(queryParameters: params.isNotEmpty ? params : null);
      final response = await http.get(uri, headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> getDepartmentStats() async {
    try {
      final response = await http.get(
          Uri.parse('$baseUrl/api/Dashboard/department-stats'),
          headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  // ==================== SYSTEM ADMIN ====================
  Future<Map<String, dynamic>> getSystemDashboard() async {
    try {
      final response = await http.get(
          Uri.parse('$baseUrl/api/system-admin/dashboard'),
          headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> getSystemAdminDashboard(
      {String? fromDate, String? toDate}) async {
    try {
      final params = <String, String>{};
      if (fromDate != null) params['fromDate'] = fromDate;
      if (toDate != null) params['toDate'] = toDate;
      final uri = Uri.parse('$baseUrl/api/system-admin/dashboard')
          .replace(queryParameters: params.isNotEmpty ? params : null);
      final response = await http.get(uri, headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> getSystemStores(
      {int? page,
      int? pageSize,
      String? search,
      String? phone,
      String? agentId,
      String? licenseType,
      String? expiryStatus,
      bool? isActive,
      bool? isLocked}) async {
    try {
      final params = <String, String>{};
      if (page != null) {
        params.addAll(paginationQueryParams(page, pageSize ?? 20));
      } else if (pageSize != null) {
        params['pageSize'] = pageSize.toString();
      }
      if (search != null) params['search'] = search;
      if (phone != null) params['phone'] = phone;
      if (agentId != null) params['agentId'] = agentId;
      if (licenseType != null) params['licenseType'] = licenseType;
      if (expiryStatus != null) params['expiryStatus'] = expiryStatus;
      if (isActive != null) params['isActive'] = isActive.toString();
      if (isLocked != null) params['isLocked'] = isLocked.toString();
      final uri = Uri.parse('$baseUrl/api/system-admin/stores')
          .replace(queryParameters: params.isNotEmpty ? params : null);
      final response = await http.get(uri, headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> getSystemAdminStores(
      {int? page,
      int? pageSize,
      String? search,
      String? phone,
      String? agentId,
      String? licenseType,
      String? expiryStatus,
      bool? isActive,
      bool? isLocked}) async {
    return getSystemStores(
        page: page,
        pageSize: pageSize,
        search: search,
        phone: phone,
        agentId: agentId,
        licenseType: licenseType,
        expiryStatus: expiryStatus,
        isActive: isActive,
        isLocked: isLocked);
  }

  Future<Map<String, dynamic>> getStoreFullDetail(String id) async {
    try {
      final response = await http.get(
          Uri.parse('$baseUrl/api/system-admin/stores/$id/full'),
          headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> toggleStoreStatus(String id) async {
    try {
      final response = await http.post(
          Uri.parse('$baseUrl/api/system-admin/stores/$id/toggle-status'),
          headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> lockStore(String id, [String? reason]) async {
    try {
      final body = reason != null ? json.encode({'reason': reason}) : null;
      final response = await http.post(
          Uri.parse('$baseUrl/api/system-admin/stores/$id/lock'),
          headers: _headers,
          body: body);
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> unlockStore(String id) async {
    try {
      final response = await http.post(
          Uri.parse('$baseUrl/api/system-admin/stores/$id/unlock'),
          headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> updateStore(String id,
      {String? name,
      String? description,
      String? address,
      String? province,
      String? phone}) async {
    try {
      final data = <String, dynamic>{
        if (name != null) 'name': name,
        if (description != null) 'description': description,
        if (address != null) 'address': address,
        if (province != null) 'province': province,
        if (phone != null) 'phone': phone,
      };
      final response = await http.put(
          Uri.parse('$baseUrl/api/system-admin/stores/$id'),
          headers: _headers,
          body: json.encode(data));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> extendStoreSubscription(String id,
      {dynamic daysToAdd, dynamic maxUsers, dynamic maxDevices}) async {
    try {
      final data = <String, dynamic>{
        if (daysToAdd != null) 'daysToAdd': daysToAdd,
        if (maxUsers != null) 'maxUsers': maxUsers,
        if (maxDevices != null) 'maxDevices': maxDevices,
      };
      final response = await http.post(
          Uri.parse('$baseUrl/api/system-admin/stores/$id/extend'),
          headers: _headers,
          body: json.encode(data));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> activateLicenseForStore(
      String storeId, dynamic licenseData) async {
    try {
      final data = licenseData is Map<String, dynamic>
          ? licenseData
          : {'licenseKey': licenseData};
      final response = await http.post(
          Uri.parse(
              '$baseUrl/api/system-admin/stores/$storeId/activate-license'),
          headers: _headers,
          body: json.encode(data));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> getActivatableLicensesForStore(
      String storeId) async {
    try {
      final response = await http.get(
          Uri.parse(
              '$baseUrl/api/system-admin/stores/$storeId/activatable-licenses'),
          headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> deleteAllStoreData(String id) async {
    try {
      final response = await http.delete(
          Uri.parse(
              '$baseUrl/api/system-admin/stores/$id/data?confirmDelete=true'),
          headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> deleteStore(String id) async {
    try {
      final response = await http.delete(
          Uri.parse('$baseUrl/api/system-admin/stores/$id?confirmDelete=true'),
          headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  // ==================== SERVICE PACKAGES ====================

  Future<Map<String, dynamic>> getAvailableModules() async {
    try {
      final response = await http.get(
          Uri.parse(
              '$baseUrl/api/system-admin/service-packages/available-modules'),
          headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> getServicePackages() async {
    try {
      final response = await http.get(
          Uri.parse('$baseUrl/api/system-admin/service-packages'),
          headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> createServicePackage(
      Map<String, dynamic> data) async {
    try {
      final response = await http.post(
          Uri.parse('$baseUrl/api/system-admin/service-packages'),
          headers: _headers,
          body: json.encode(data));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> updateServicePackage(
      String id, Map<String, dynamic> data) async {
    try {
      final response = await http.put(
          Uri.parse('$baseUrl/api/system-admin/service-packages/$id'),
          headers: _headers,
          body: json.encode(data));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> deleteServicePackage(String id) async {
    try {
      final response = await http.delete(
          Uri.parse('$baseUrl/api/system-admin/service-packages/$id'),
          headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> assignPackageToStore(
      String storeId, String packageId) async {
    try {
      final response = await http.post(
          Uri.parse(
              '$baseUrl/api/system-admin/stores/$storeId/assign-package/$packageId'),
          headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> extendStoreDays(String storeId, int days) async {
    try {
      final response = await http.post(
          Uri.parse('$baseUrl/api/system-admin/stores/$storeId/extend-days'),
          headers: _headers,
          body: json.encode({'days': days}));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  // ═══════════════ KEY ACTIVATION PROMOTIONS ═══════════════

  Future<Map<String, dynamic>> getKeyPromotions() async {
    try {
      final response = await http.get(
          Uri.parse('$baseUrl/api/system-admin/key-promotions'),
          headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> createKeyPromotion(
      Map<String, dynamic> data) async {
    try {
      final response = await http.post(
          Uri.parse('$baseUrl/api/system-admin/key-promotions'),
          headers: _headers,
          body: json.encode(data));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> updateKeyPromotion(
      String id, Map<String, dynamic> data) async {
    try {
      final response = await http.put(
          Uri.parse('$baseUrl/api/system-admin/key-promotions/$id'),
          headers: _headers,
          body: json.encode(data));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> deleteKeyPromotion(String id) async {
    try {
      final response = await http.delete(
          Uri.parse('$baseUrl/api/system-admin/key-promotions/$id'),
          headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> bulkActivateLicenses(
      String storeId, List<String> licenseKeys) async {
    try {
      final response = await http.post(
          Uri.parse('$baseUrl/api/system-admin/stores/$storeId/activate-bulk'),
          headers: _headers,
          body: json.encode({'licenseKeys': licenseKeys}));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> previewBulkActivation(
      String storeId, List<String> licenseKeys) async {
    try {
      final response = await http.post(
          Uri.parse(
              '$baseUrl/api/system-admin/stores/$storeId/activate-bulk-preview'),
          headers: _headers,
          body: json.encode({'licenseKeys': licenseKeys}));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> getSystemUsers(
      {int? page,
      int? pageSize,
      String? search,
      String? storeId,
      String? role,
      String? agentId}) async {
    try {
      final params = <String, String>{};
      if (page != null) {
        params.addAll(paginationQueryParams(page, pageSize ?? 20));
      } else if (pageSize != null) {
        params['pageSize'] = pageSize.toString();
      }
      if (search != null) params['search'] = search;
      if (storeId != null) params['storeId'] = storeId;
      if (role != null) params['role'] = role;
      if (agentId != null) params['agentId'] = agentId;
      final uri = Uri.parse('$baseUrl/api/system-admin/users')
          .replace(queryParameters: params.isNotEmpty ? params : null);
      final response = await http.get(uri, headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> getSystemAdminUsers(
      {int? page,
      int? pageSize,
      String? search,
      String? storeId,
      String? role,
      String? agentId}) async {
    return getSystemUsers(
        page: page,
        pageSize: pageSize,
        search: search,
        storeId: storeId,
        role: role,
        agentId: agentId);
  }

  /// Gán một cửa hàng cho đại lý (SuperAdmin).
  Future<Map<String, dynamic>> assignStoreToAgent(
      String agentId, String storeId) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/system-admin/agents/$agentId/stores/$storeId'),
        headers: _headers,
      );
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  /// Gỡ một cửa hàng khỏi đại lý (SuperAdmin).
  Future<Map<String, dynamic>> removeStoreFromAgent(
      String agentId, String storeId) async {
    try {
      final response = await http.delete(
        Uri.parse('$baseUrl/api/system-admin/agents/$agentId/stores/$storeId'),
        headers: _headers,
      );
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  /// Vai trò đã cấu hình phân quyền của một cửa hàng (SuperAdmin).
  Future<Map<String, dynamic>> getSystemAdminStoreRoles(String storeId) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/api/system-admin/stores/$storeId/roles'),
        headers: _headers,
      );
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> createSuperAdmin(
      {String? email, String? password, String? fullName}) async {
    try {
      final data = <String, dynamic>{
        if (email != null) 'email': email,
        if (password != null) 'password': password,
        if (fullName != null) 'fullName': fullName,
      };
      final response = await http.post(
          Uri.parse('$baseUrl/api/system-admin/create-superadmin'),
          headers: _headers,
          body: json.encode(data));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> updateUserCredentials(String userId,
      {String? newEmail, String? newPassword, String? fullName}) async {
    try {
      final data = <String, dynamic>{
        if (newEmail != null) 'newEmail': newEmail,
        if (newPassword != null) 'newPassword': newPassword,
        if (fullName != null) 'fullName': fullName,
      };
      final response = await http.put(
          Uri.parse('$baseUrl/api/system-admin/users/$userId/credentials'),
          headers: _headers,
          body: json.encode(data));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> updateUserRole(
      String userId, String role) async {
    try {
      final response = await http.put(
          Uri.parse('$baseUrl/api/system-admin/users/$userId/role'),
          headers: _headers,
          body: json.encode({'role': role}));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> deleteSystemUser(String userId) async {
    try {
      final response = await http.delete(
          Uri.parse('$baseUrl/api/system-admin/users/$userId'),
          headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> getSystemDevices(
      {int? page,
      int? pageSize,
      bool? isOnline,
      bool? isClaimed,
      String? search,
      String? storeId,
      String? agentId,
      bool? noAgent}) async {
    try {
      final params = <String, String>{};
      if (page != null) {
        params.addAll(paginationQueryParams(page, pageSize ?? 20));
      } else if (pageSize != null) {
        params['pageSize'] = pageSize.toString();
      }
      if (isOnline != null) params['isOnline'] = isOnline.toString();
      if (isClaimed != null) params['isClaimed'] = isClaimed.toString();
      if (search != null) params['search'] = search;
      if (storeId != null) params['storeId'] = storeId;
      if (agentId != null && agentId.isNotEmpty) params['agentId'] = agentId;
      if (noAgent == true) params['noAgent'] = 'true';
      final uri = Uri.parse('$baseUrl/api/system-admin/devices')
          .replace(queryParameters: params.isNotEmpty ? params : null);
      final response = await http.get(uri, headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> getSystemAdminDevices(
      {int? page,
      int? pageSize,
      bool? isOnline,
      bool? isClaimed,
      String? search,
      String? storeId}) async {
    return getSystemDevices(
        page: page,
        pageSize: pageSize,
        isOnline: isOnline,
        isClaimed: isClaimed,
        search: search,
        storeId: storeId);
  }

  Future<Map<String, dynamic>> sendDeviceCommand(
      String deviceId, dynamic commandType,
      {String? command}) async {
    try {
      // Kiểm tra thiết bị online trước khi gửi lệnh
      if (!await isDeviceOnline(deviceId)) {
        return {
          'isSuccess': false,
          'message':
              'Thiết bị đang offline. Vui lòng kiểm tra kết nối mạng của máy chấm công.'
        };
      }
      final data = <String, dynamic>{'commandType': commandType};
      if (command != null) data['command'] = command;
      final response = await _retryOnUnauthorized(() => http.post(
          Uri.parse('$baseUrl/api/devices/$deviceId/commands'),
          headers: _headers,
          body: json.encode(data)));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> unassignSystemDevice(String deviceId) async {
    try {
      final response = await http.put(
          Uri.parse(
              '$baseUrl/api/system-admin/devices/$deviceId/unassign-store'),
          headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> assignSystemDeviceToStore(
      String deviceId, String storeId) async {
    try {
      final response = await http.put(
          Uri.parse(
              '$baseUrl/api/system-admin/devices/$deviceId/assign-store/$storeId'),
          headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  // ==================== LICENSES ====================
  Future<Map<String, dynamic>> getLicenseKeys(
      {int? page,
      int? pageSize,
      String? status,
      bool? isUsed,
      String? agentId,
      String? licenseType,
      bool? isActive,
      String? search}) async {
    try {
      final params = <String, String>{};
      if (page != null) {
        params.addAll(paginationQueryParams(page, pageSize ?? 20));
      } else if (pageSize != null) {
        params['pageSize'] = pageSize.toString();
      }
      if (status != null) params['status'] = status;
      if (isUsed != null) params['isUsed'] = isUsed.toString();
      if (agentId != null) params['agentId'] = agentId;
      if (licenseType != null) params['licenseType'] = licenseType;
      if (isActive != null) params['isActive'] = isActive.toString();
      if (search != null) params['search'] = search;
      final uri = Uri.parse('$baseUrl/api/system-admin/licenses')
          .replace(queryParameters: params.isNotEmpty ? params : null);
      final response = await http.get(uri, headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> createLicenseKey(
      {String? licenseType,
      int? durationDays,
      int? maxUsers,
      int? maxDevices,
      String? notes,
      String? servicePackageId}) async {
    try {
      final data = <String, dynamic>{
        if (licenseType != null) 'licenseType': licenseType,
        if (durationDays != null) 'durationDays': durationDays,
        if (maxUsers != null) 'maxUsers': maxUsers,
        if (maxDevices != null) 'maxDevices': maxDevices,
        if (notes != null) 'notes': notes,
        if (servicePackageId != null) 'servicePackageId': servicePackageId,
      };
      final response = await http.post(
          Uri.parse('$baseUrl/api/system-admin/licenses'),
          headers: _headers,
          body: json.encode(data));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> createBatchLicenseKeys(
      {int? count,
      String? licenseType,
      int? durationDays,
      int? maxUsers,
      int? maxDevices,
      String? servicePackageId}) async {
    try {
      final data = <String, dynamic>{
        if (count != null) 'count': count,
        if (licenseType != null) 'licenseType': licenseType,
        if (durationDays != null) 'durationDays': durationDays,
        if (maxUsers != null) 'maxUsers': maxUsers,
        if (maxDevices != null) 'maxDevices': maxDevices,
        if (servicePackageId != null) 'servicePackageId': servicePackageId,
      };
      final response = await http.post(
          Uri.parse('$baseUrl/api/system-admin/licenses/batch'),
          headers: _headers,
          body: json.encode(data));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> revokeLicenseKey(String id) async {
    try {
      final response = await http.delete(
          Uri.parse('$baseUrl/api/system-admin/licenses/$id'),
          headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> deleteLicenseKeyPermanent(String id) async {
    try {
      final response = await http.delete(
          Uri.parse('$baseUrl/api/system-admin/licenses/$id/permanent'),
          headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> batchRevokeLicenses(dynamic licenseData) async {
    try {
      final data = licenseData is Map<String, dynamic>
          ? licenseData
          : {'licenseKeyIds': licenseData};
      final response = await http.post(
          Uri.parse('$baseUrl/api/system-admin/licenses/batch-revoke'),
          headers: _headers,
          body: json.encode(data));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> exportLicenseKeys(
      {String? status,
      String? format,
      bool? isUsed,
      String? licenseType,
      String? agentId,
      bool? isActive}) async {
    try {
      final params = <String, String>{};
      if (status != null) params['status'] = status;
      if (format != null) params['format'] = format;
      if (isUsed != null) params['isUsed'] = isUsed.toString();
      if (licenseType != null) params['licenseType'] = licenseType;
      if (agentId != null) params['agentId'] = agentId;
      if (isActive != null) params['isActive'] = isActive.toString();
      final uri = Uri.parse('$baseUrl/api/system-admin/licenses/export')
          .replace(queryParameters: params.isNotEmpty ? params : null);
      final response = await http.get(uri, headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> batchAssignLicensesToAgent(
      {required List<String> licenseKeyIds, required String agentId}) async {
    try {
      final response = await http.post(
          Uri.parse('$baseUrl/api/system-admin/licenses/batch-assign-agent'),
          headers: _headers,
          body: json
              .encode({'licenseKeyIds': licenseKeyIds, 'agentId': agentId}));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> batchAssignLicensesToAgentByCount(
      {required String agentId,
      required int count,
      String? servicePackageId,
      String? licenseType}) async {
    try {
      final data = <String, dynamic>{
        'agentId': agentId,
        'count': count,
        if (servicePackageId != null) 'servicePackageId': servicePackageId,
        if (licenseType != null) 'licenseType': licenseType,
      };
      final response = await http.post(
          Uri.parse(
              '$baseUrl/api/system-admin/licenses/batch-assign-agent-by-count'),
          headers: _headers,
          body: json.encode(data));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> batchAssignLicensesToStore(
      {required List<String> licenseKeyIds, required String storeId}) async {
    try {
      final response = await http.post(
          Uri.parse('$baseUrl/api/system-admin/licenses/batch-assign-store'),
          headers: _headers,
          body: json
              .encode({'licenseKeyIds': licenseKeyIds, 'storeId': storeId}));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  // ==================== AGENTS ====================
  Future<Map<String, dynamic>> getSystemAgents(
      {int? page,
      int? pageSize,
      String? search,
      bool? isActive,
      bool? hasStores,
      bool? hasLicenseKeys,
      String? licenseStatus}) async {
    try {
      final params = <String, String>{};
      if (page != null) {
        params.addAll(paginationQueryParams(page, pageSize ?? 20));
      } else if (pageSize != null) {
        params['pageSize'] = pageSize.toString();
      }
      if (search != null) params['search'] = search;
      if (isActive != null) params['isActive'] = isActive.toString();
      if (hasStores != null) params['hasStores'] = hasStores.toString();
      if (hasLicenseKeys != null) {
        params['hasLicenseKeys'] = hasLicenseKeys.toString();
      }
      if (licenseStatus != null) params['licenseStatus'] = licenseStatus;
      final uri = Uri.parse('$baseUrl/api/system-admin/agents')
          .replace(queryParameters: params.isNotEmpty ? params : null);
      final response = await http.get(uri, headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> lookupAgentByCode(String code) async {
    try {
      final uri = Uri.parse(
          '$baseUrl/api/AgentRegistration/lookup/${Uri.encodeComponent(code)}');
      final response =
          await http.get(uri, headers: {'Content-Type': 'application/json'});
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  /// Liên hệ đại lý của cửa hàng (public, theo mã cửa hàng).
  Future<Map<String, dynamic>> getStoreAgentContactByStoreCode(
      String storeCode) async {
    try {
      final uri = Uri.parse(
          '$baseUrl/api/AgentRegistration/store-contact/${Uri.encodeComponent(storeCode.trim())}');
      final response =
          await http.get(uri, headers: {'Content-Type': 'application/json'});
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  /// Liên hệ đại lý của cửa hàng đang đăng nhập.
  Future<Map<String, dynamic>> getStoreAgentContact() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/api/accounts/store-agent-contact'),
        headers: _headers,
      );
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> createAgent(
      {String? name,
      String? code,
      String? email,
      String? phone,
      String? address,
      String? description,
      int? maxStores,
      int? tokenValidDays,
      String? password}) async {
    try {
      final data = <String, dynamic>{
        if (name != null) 'name': name,
        if (code != null) 'code': code,
        if (email != null) 'email': email,
        if (phone != null) 'phone': phone,
        if (address != null) 'address': address,
        if (description != null) 'description': description,
        if (maxStores != null) 'maxStores': maxStores,
        if (tokenValidDays != null) 'tokenValidDays': tokenValidDays,
        if (password != null && password.isNotEmpty) 'password': password,
      };
      final response = await http.post(
          Uri.parse('$baseUrl/api/system-admin/agents'),
          headers: _headers,
          body: json.encode(data));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> updateAgent(
      {String? id,
      String? name,
      String? phone,
      String? email,
      String? address,
      String? description,
      int? maxStores,
      bool? isActive}) async {
    try {
      final data = <String, dynamic>{
        if (name != null) 'name': name,
        if (phone != null) 'phone': phone,
        if (email != null) 'email': email,
        if (address != null) 'address': address,
        if (description != null) 'description': description,
        if (maxStores != null) 'maxStores': maxStores,
        if (isActive != null) 'isActive': isActive,
      };
      final agentId = id ?? '';
      final response = await http.put(
          Uri.parse('$baseUrl/api/system-admin/agents/$agentId'),
          headers: _headers,
          body: json.encode(data));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> adjustAgentRenewalBalance({
    required String agentId,
    int? setBalance,
    int? addDays,
  }) async {
    try {
      final data = <String, dynamic>{
        if (setBalance != null) 'setBalance': setBalance,
        if (addDays != null) 'addDays': addDays,
      };
      final response = await http.post(
          Uri.parse(
              '$baseUrl/api/system-admin/agents/$agentId/renewal-balance'),
          headers: _headers,
          body: json.encode(data));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> regenerateAgentToken(
      {String? agentId, int? validDays}) async {
    try {
      final id = agentId ?? '';
      final body =
          validDays != null ? json.encode({'validDays': validDays}) : null;
      final response = await http.post(
          Uri.parse('$baseUrl/api/system-admin/agents/$id/regenerate-token'),
          headers: _headers,
          body: body);
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> deleteAgent(String agentId) async {
    try {
      final response = await http.delete(
        Uri.parse('$baseUrl/api/system-admin/agents/$agentId'),
        headers: _headers,
      );
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  // ==================== APP SETTINGS ====================
  Future<Map<String, dynamic>> getAppSetting(String key) async {
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/api/settings/app/$key'), headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> upsertAppSetting(
      {required String key,
      required dynamic value,
      String? description,
      String group = 'system',
      String dataType = 'string',
      int displayOrder = 0,
      bool isPublic = false}) async {
    try {
      final data = <String, dynamic>{
        'key': key,
        'value': value?.toString(),
        'description': description,
        'group': group,
        'dataType': dataType,
        'displayOrder': displayOrder,
        'isPublic': isPublic,
      };
      final response = await http.post(Uri.parse('$baseUrl/api/settings/app'),
          headers: _headers, body: json.encode(data));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> getAllAppSettings() async {
    try {
      final response = await http.get(
          Uri.parse('$baseUrl/api/system-admin/settings'),
          headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> initializeAppSettings() async {
    try {
      final response = await http.post(
          Uri.parse('$baseUrl/api/system-admin/settings/initialize'),
          headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> updateAppSettingsBatch(dynamic settings) async {
    try {
      final data = settings is List ? {'settings': settings} : settings;
      final response = await http.put(
          Uri.parse('$baseUrl/api/system-admin/settings/batch'),
          headers: _headers,
          body: json.encode(data));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  // ==================== AUDIT & SYSTEM HEALTH ====================
  Future<Map<String, dynamic>> getAuditLogs(
      {int? page,
      int? pageSize,
      dynamic fromDate,
      dynamic toDate,
      String? action,
      String? entityType,
      String? status,
      String? search}) async {
    try {
      final params = <String, String>{};
      if (page != null) {
        params.addAll(paginationQueryParams(page, pageSize ?? 20));
      } else if (pageSize != null) {
        params['pageSize'] = pageSize.toString();
      }
      if (fromDate != null) {
        params['fromDate'] = fromDate is DateTime
            ? fromDate.toIso8601String()
            : fromDate.toString();
      }
      if (toDate != null) {
        params['toDate'] =
            toDate is DateTime ? toDate.toIso8601String() : toDate.toString();
      }
      if (action != null) params['action'] = action;
      if (entityType != null) params['entityType'] = entityType;
      if (status != null) params['status'] = status;
      if (search != null) params['search'] = search;
      final uri = Uri.parse('$baseUrl/api/system-admin/audit-logs')
          .replace(queryParameters: params.isNotEmpty ? params : null);
      final response = await http.get(uri, headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> getAuditStats() async {
    try {
      final response = await http.get(
          Uri.parse('$baseUrl/api/system-admin/audit-logs/stats'),
          headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> getSystemHealth() async {
    try {
      final response = await http.get(
          Uri.parse('$baseUrl/api/system-admin/system-health'),
          headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  // ==================== DATABASE MANAGEMENT ====================
  Future<Map<String, dynamic>> getDatabaseInfo() async {
    try {
      final response = await http.get(
          Uri.parse('$baseUrl/api/system-admin/database/info'),
          headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> backupDatabase() async {
    try {
      final response = await http.post(
          Uri.parse('$baseUrl/api/system-admin/database/backup'),
          headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> backupStoreData(String storeId) async {
    try {
      final response = await http.post(
          Uri.parse('$baseUrl/api/system-admin/database/backup/store/$storeId'),
          headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> getBackupFiles() async {
    try {
      final response = await http.get(
          Uri.parse('$baseUrl/api/system-admin/database/backups'),
          headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> deleteBackupFile(String fileName) async {
    try {
      final response = await http.delete(
          Uri.parse('$baseUrl/api/system-admin/database/backups/$fileName'),
          headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> restoreDatabase(String fileName) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/system-admin/database/restore'),
        headers: _headers,
        body: json.encode({'fileName': fileName, 'confirmRestore': true}),
      );
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> purgeAllData(String confirmCode) async {
    try {
      final response = await http.delete(
        Uri.parse(
            '$baseUrl/api/system-admin/database/purge-all?confirmCode=$confirmCode'),
        headers: _headers,
      );
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  String getBackupDownloadUrl(String fileName) {
    return '$baseUrl/api/system-admin/database/backups/$fileName/download';
  }

  Future<Map<String, dynamic>> deleteStoreData(String storeId) async {
    try {
      final response = await http.delete(
        Uri.parse(
            '$baseUrl/api/system-admin/stores/$storeId/data?confirmDelete=true'),
        headers: _headers,
      );
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  // ==================== AGENT REGISTRATION ====================
  Future<Map<String, dynamic>> getAgentByRegistrationToken(String token) async {
    try {
      final response = await http.get(
          Uri.parse('$baseUrl/api/AgentRegistration/$token'),
          headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> agentSelfRegister(
      {String? name,
      String? email,
      String? phone,
      String? registrationToken,
      String? password,
      String? confirmPassword,
      String? fullName}) async {
    try {
      final data = <String, dynamic>{
        if (name != null) 'name': name,
        if (fullName != null) 'fullName': fullName,
        if (email != null) 'email': email,
        if (phone != null) 'phone': phone,
        if (password != null) 'password': password,
        if (confirmPassword != null) 'confirmPassword': confirmPassword,
        if (registrationToken != null) 'registrationToken': registrationToken,
      };
      final response = await http.post(
          Uri.parse('$baseUrl/api/AgentRegistration'),
          headers: _headers,
          body: json.encode(data));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  // ==================== AI SETTINGS ====================
  Future<Map<String, dynamic>> getAiProviders() async {
    try {
      final response = await http.get(
          Uri.parse('$baseUrl/api/communications/ai/providers'),
          headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  /// Generic AI text assist (feedback, leave_reason, attendance_reason,
  /// schedule_request, schedule_approval, attendance_report, generic)
  Future<Map<String, dynamic>> aiAssist({
    required String kind,
    required String prompt,
    String? context,
    String? tone,
    String? provider,
    int maxTokens = 1024,
  }) async {
    try {
      final response = await http.post(Uri.parse('$baseUrl/api/ai/assist'),
          headers: _headers,
          body: json.encode({
            'kind': kind,
            'prompt': prompt,
            if (context != null) 'context': context,
            if (tone != null) 'tone': tone,
            if (provider != null) 'provider': provider,
            'maxTokens': maxTokens,
          }));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  /// AI Assistant chat - trợ lý ảo cá nhân với context người dùng.
  Future<Map<String, dynamic>> aiAssistantChat({
    required List<Map<String, String>> messages,
    String? provider,
  }) async {
    try {
      final response =
          await http.post(Uri.parse('$baseUrl/api/ai/assistant/chat'),
              headers: _headers,
              body: json.encode({
                'messages': messages,
                if (provider != null) 'provider': provider,
              }));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> getGeminiConfig() async {
    try {
      final response = await http.get(
          Uri.parse('$baseUrl/api/communications/ai/config'),
          headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> updateGeminiConfig(
      Map<String, dynamic> data) async {
    try {
      final response = await http.post(
          Uri.parse('$baseUrl/api/communications/ai/config'),
          headers: _headers,
          body: json.encode(data));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> testGeminiConnection() async {
    try {
      final response = await http.post(
          Uri.parse('$baseUrl/api/communications/ai/test'),
          headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> getDeepSeekConfig() async {
    try {
      final response = await http.get(
          Uri.parse('$baseUrl/api/communications/ai/deepseek/config'),
          headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> updateDeepSeekConfig(
      Map<String, dynamic> data) async {
    try {
      final response = await http.post(
          Uri.parse('$baseUrl/api/communications/ai/deepseek/config'),
          headers: _headers,
          body: json.encode(data));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> testDeepSeekConnection() async {
    try {
      final response = await http.post(
          Uri.parse('$baseUrl/api/communications/ai/deepseek/test'),
          headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  // ==================== AUTH (EXTENDED) ====================
  Future<Map<String, dynamic>> forgotPassword(
      String storeCode, String email) async {
    try {
      final response = await http.post(
          Uri.parse('$baseUrl/api/Auth/ForgotPassword'),
          headers: {'Content-Type': 'application/json'},
          body: json.encode({'storeCode': storeCode, 'email': email}));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> resetPassword(String email, String token,
      String newPassword, String confirmPassword) async {
    try {
      final response =
          await http.post(Uri.parse('$baseUrl/api/Auth/ResetPassword'),
              headers: {'Content-Type': 'application/json'},
              body: json.encode({
                'email': email,
                'token': token,
                'newPassword': newPassword,
                'confirmPassword': confirmPassword
              }));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> verifyOtp(String storeCode, String email,
      String otp, String newPassword, String confirmPassword) async {
    try {
      final response = await http.post(Uri.parse('$baseUrl/api/Auth/VerifyOtp'),
          headers: {'Content-Type': 'application/json'},
          body: json.encode({
            'storeCode': storeCode,
            'email': email,
            'otp': otp,
            'newPassword': newPassword,
            'confirmPassword': confirmPassword
          }));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  // ==================== DEVICE ATTENDANCE ====================
  Future<Map<String, dynamic>> deleteAttendancesByDevice(
      {required String deviceId, DateTime? fromDate, DateTime? toDate}) async {
    try {
      if (!await isDeviceOnline(deviceId)) {
        return {
          'isSuccess': false,
          'message':
              'Thiết bị đang offline. Vui lòng kiểm tra kết nối mạng của máy chấm công.'
        };
      }
      final params = <String, String>{};
      if (fromDate != null) params['fromDate'] = fromDate.toIso8601String();
      if (toDate != null) params['toDate'] = toDate.toIso8601String();
      final uri = Uri.parse('$baseUrl/api/Attendances/devices/$deviceId')
          .replace(queryParameters: params.isNotEmpty ? params : null);
      final response = await http.delete(uri, headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> syncAttendances(String deviceId,
      {DateTime? fromTime, DateTime? toTime}) async {
    try {
      if (!await isDeviceOnline(deviceId)) {
        return {
          'isSuccess': false,
          'message':
              'Thiết bị đang offline. Vui lòng kiểm tra kết nối mạng của máy chấm công.'
        };
      }
      final body = <String, dynamic>{};
      if (fromTime != null) body['fromTime'] = fromTime.toIso8601String();
      if (toTime != null) body['toTime'] = toTime.toIso8601String();
      final response = await http.post(
          Uri.parse('$baseUrl/api/Attendances/sync/$deviceId'),
          headers: _headers,
          body: body.isNotEmpty ? json.encode(body) : null);
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  // ==================== COMMUNICATION (EXTENDED) ====================
  Future<Map<String, dynamic>> getCommunicationStats() async {
    try {
      final response = await http.get(
          Uri.parse('$baseUrl/api/communications/stats'),
          headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      debugPrint('Error getting communication stats: $e');
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> getCommunicationDetail(String id) async {
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/api/communications/$id'), headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      debugPrint('Error getting communication detail: $e');
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> toggleCommunicationReaction(
      String id, dynamic reactionData) async {
    try {
      final data = reactionData is Map<String, dynamic>
          ? reactionData
          : {'reactionType': reactionData};
      final response = await http.post(
          Uri.parse('$baseUrl/api/communications/$id/reactions'),
          headers: _headers,
          body: json.encode(data));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> generateAiCommunicationContent(
      Map<String, dynamic> data) async {
    try {
      final response = await http.post(
          Uri.parse('$baseUrl/api/communications/ai/generate'),
          headers: _headers,
          body: json.encode(data));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> getCommunicationComments(String id) async {
    try {
      final response = await http.get(
          Uri.parse('$baseUrl/api/communications/$id/comments'),
          headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> addCommunicationComment(
      String id, dynamic commentData) async {
    try {
      final data = commentData is Map<String, dynamic>
          ? commentData
          : {'content': commentData};
      final response = await http.post(
          Uri.parse('$baseUrl/api/communications/$id/comments'),
          headers: _headers,
          body: json.encode(data));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  // ==================== UPLOADS ====================
  Future<Map<String, dynamic>> uploadCccdFront(dynamic imageData,
      [String? fileName]) async {
    try {
      final request = http.MultipartRequest(
          'POST', Uri.parse('$baseUrl/api/Upload/cccd-front'));
      if (_token != null) request.headers['Authorization'] = 'Bearer $_token';
      if (imageData is List<int>) {
        request.files.add(http.MultipartFile.fromBytes('file', imageData,
            filename: fileName ?? 'cccd_front.jpg'));
      }
      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> uploadCccdBack(dynamic imageData,
      [String? fileName]) async {
    try {
      final request = http.MultipartRequest(
          'POST', Uri.parse('$baseUrl/api/Upload/cccd-back'));
      if (_token != null) request.headers['Authorization'] = 'Bearer $_token';
      if (imageData is List<int>) {
        request.files.add(http.MultipartFile.fromBytes('file', imageData,
            filename: fileName ?? 'cccd_back.jpg'));
      }
      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> parseCccdText(dynamic textData) async {
    try {
      final data =
          textData is Map<String, dynamic> ? textData : {'ocrText': textData};
      final response = await http.post(
          Uri.parse('$baseUrl/api/Upload/parse-cccd-text'),
          headers: _headers,
          body: json.encode(data));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  String getFileUrl(String path) {
    var trimmed = path.trim().replaceAll('\\', '/');
    if (trimmed.isEmpty) return '';

    if (trimmed.startsWith('pos-product-image:')) {
      final id = trimmed.substring('pos-product-image:'.length);
      return '$baseUrl/api/pos/products/$id/image';
    }

    // Lấy path tương đối từ URL đầy đủ (tránh host cũ / localhost trong DB).
    if (trimmed.startsWith('http')) {
      try {
        final uri = Uri.parse(trimmed);
        trimmed = uri.path;
      } catch (_) {
        return trimmed;
      }
    }
    if (trimmed.startsWith('/')) trimmed = trimmed.substring(1);
    if (trimmed.startsWith('wwwroot/')) {
      trimmed = trimmed.substring('wwwroot/'.length);
    }

    // Legacy POS: {storeCode}/uploads/pos-products/...
    if (!trimmed.startsWith('stores/') &&
        !trimmed.startsWith('uploads/') &&
        trimmed.contains('uploads/pos-products')) {
      trimmed = 'stores/$trimmed';
    }

    if (trimmed.startsWith('stores/') || trimmed.startsWith('uploads/')) {
      return '$baseUrl/api/upload/serve?path=${Uri.encodeQueryComponent(trimmed)}';
    }

    return '$baseUrl/$trimmed';
  }

  /// URL media màn hình phụ — không cần Bearer (public-serve whitelist).
  String getPublicFileUrl(String? pathOrUrl) {
    if (pathOrUrl == null || pathOrUrl.trim().isEmpty) return '';
    var trimmed = pathOrUrl.trim();
    // URL ngoài (CDN / mp4 trực tiếp) — giữ nguyên.
    if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
      final lower = trimmed.toLowerCase();
      // URL API serve cũ → đổi sang public-serve.
      if (lower.contains('/api/upload/serve')) {
        return trimmed.replaceFirst(
          RegExp(r'/api/upload/serve', caseSensitive: false),
          '/api/upload/public-serve',
        );
      }
      // Host app + path stores/uploads → public-serve.
      try {
        final uri = Uri.parse(trimmed);
        var p = uri.path;
        if (p.startsWith('/')) p = p.substring(1);
        if (p.startsWith('stores/') || p.startsWith('uploads/')) {
          return '$baseUrl/api/upload/public-serve?path=${Uri.encodeQueryComponent(p)}';
        }
      } catch (_) {}
      return trimmed;
    }
    if (trimmed.startsWith('/')) trimmed = trimmed.substring(1);
    if (trimmed.startsWith('wwwroot/')) {
      trimmed = trimmed.substring('wwwroot/'.length);
    }
    if (!trimmed.startsWith('stores/') &&
        !trimmed.startsWith('uploads/') &&
        trimmed.contains('uploads/pos-products')) {
      trimmed = 'stores/$trimmed';
    }
    if (trimmed.startsWith('stores/') || trimmed.startsWith('uploads/')) {
      return '$baseUrl/api/upload/public-serve?path=${Uri.encodeQueryComponent(trimmed)}';
    }
    return getFileUrl(pathOrUrl);
  }

  Future<Map<String, dynamic>> uploadEmployeePhoto(dynamic imageData,
      [String? fileName]) async {
    try {
      final request = http.MultipartRequest(
          'POST', Uri.parse('$baseUrl/api/Upload/employee-photo'));
      if (_token != null) request.headers['Authorization'] = 'Bearer $_token';
      if (imageData is List<int>) {
        request.files.add(http.MultipartFile.fromBytes('file', imageData,
            filename: fileName ?? 'photo.jpg'));
      }
      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  // ==================== KPI ====================
  Future<Map<String, dynamic>> getKpiConfigs() async {
    try {
      final response = await http.get(Uri.parse('$baseUrl/api/kpi/configs'),
          headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> createKpiConfig(
      Map<String, dynamic> data) async {
    try {
      final response = await http.post(Uri.parse('$baseUrl/api/kpi/configs'),
          headers: _headers, body: json.encode(data));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> updateKpiConfig(
      String id, Map<String, dynamic> data) async {
    try {
      final response = await http.put(Uri.parse('$baseUrl/api/kpi/configs/$id'),
          headers: _headers, body: json.encode(data));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> deleteKpiConfig(String id) async {
    try {
      final response = await http
          .delete(Uri.parse('$baseUrl/api/kpi/configs/$id'), headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> getKpiPeriods() async {
    try {
      final response = await http.get(Uri.parse('$baseUrl/api/kpi/periods'),
          headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> createKpiPeriod(
      Map<String, dynamic> data) async {
    try {
      final response = await http.post(Uri.parse('$baseUrl/api/kpi/periods'),
          headers: _headers, body: json.encode(data));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> updateKpiPeriod(
      String id, Map<String, dynamic> data) async {
    try {
      final response = await http.put(Uri.parse('$baseUrl/api/kpi/periods/$id'),
          headers: _headers, body: json.encode(data));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> updateKpiPeriodStatus(
      String id, String status) async {
    try {
      final response = await http.put(
          Uri.parse('$baseUrl/api/kpi/periods/$id/status'),
          headers: _headers,
          body: json.encode({'status': status}));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> deleteKpiPeriod(String id) async {
    try {
      final response = await http
          .delete(Uri.parse('$baseUrl/api/kpi/periods/$id'), headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> getKpiBonusRules() async {
    try {
      final response = await http.get(Uri.parse('$baseUrl/api/kpi/bonus-rules'),
          headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> saveKpiBonusRules(
      List<Map<String, dynamic>> rules) async {
    try {
      final response = await http.post(
          Uri.parse('$baseUrl/api/kpi/bonus-rules'),
          headers: _headers,
          body: json.encode(rules));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> getKpiResults({String? periodId}) async {
    try {
      final params = <String, String>{};
      if (periodId != null) params['periodId'] = periodId;
      final uri = Uri.parse('$baseUrl/api/kpi/results')
          .replace(queryParameters: params.isNotEmpty ? params : null);
      final response = await http.get(uri, headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> saveKpiResults(Map<String, dynamic> data) async {
    try {
      final response = await http.post(Uri.parse('$baseUrl/api/kpi/results'),
          headers: _headers, body: json.encode(data));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> getKpiDashboard() async {
    try {
      final response = await http.get(Uri.parse('$baseUrl/api/kpi/dashboard'),
          headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> getKpiEmployeeTargets({String? periodId}) async {
    try {
      final params = <String, String>{};
      if (periodId != null) params['periodId'] = periodId;
      final uri = Uri.parse('$baseUrl/api/kpi/employee-targets')
          .replace(queryParameters: params.isNotEmpty ? params : null);
      final response = await http.get(uri, headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> saveKpiEmployeeTargets(
      String periodId, List<Map<String, dynamic>> targets) async {
    try {
      final response = await http.post(
          Uri.parse('$baseUrl/api/kpi/employee-targets/batch'),
          headers: _headers,
          body: json.encode({'periodId': periodId, 'targets': targets}));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> deleteKpiEmployeeTarget(String id) async {
    try {
      final response = await http.delete(
          Uri.parse('$baseUrl/api/kpi/employee-targets/$id'),
          headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  // ==================== KPI SALARY ====================
  Future<Map<String, dynamic>> calculateKpiSalary(String periodId) async {
    try {
      final response = await http.post(
          Uri.parse('$baseUrl/api/kpi/salary/calculate'),
          headers: _headers,
          body: json.encode({'periodId': periodId}));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> getKpiSalaries(String periodId) async {
    try {
      final uri = Uri.parse('$baseUrl/api/kpi/salary')
          .replace(queryParameters: {'periodId': periodId});
      final response = await http.get(uri, headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> approveKpiSalaries(
      List<String> salaryIds) async {
    try {
      final response = await http.post(
          Uri.parse('$baseUrl/api/kpi/salary/approve'),
          headers: _headers,
          body: json.encode({'salaryIds': salaryIds}));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  // ==================== KPI GSHEET CONFIG & IMPORT ====================
  Future<Map<String, dynamic>> saveKpiGSheetConfig(
      String periodId, Map<String, dynamic> data) async {
    try {
      final response = await http.post(
          Uri.parse('$baseUrl/api/kpi/gsheet-config/$periodId'),
          headers: _headers,
          body: json.encode(data));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> testKpiGSheetConnection(
      String googleSheetUrl) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/kpi/gsheet-config/test-connection'),
        headers: _headers,
        body: json.encode({'googleSheetUrl': googleSheetUrl}),
      );
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> copyKpiGSheetConfig(
      String periodId, String sourcePeriodId) async {
    try {
      final response = await http.post(
        Uri.parse(
            '$baseUrl/api/kpi/gsheet-config/$periodId/copy-from/$sourcePeriodId'),
        headers: _headers,
      );
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> syncKpiActualsFromGSheet(String periodId) async {
    try {
      final response = await http.post(
          Uri.parse('$baseUrl/api/kpi/sync-actuals/$periodId'),
          headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> getGSheetCredentialsStatus() async {
    try {
      final response = await http.get(
          Uri.parse('$baseUrl/api/kpi/gsheet-config/credentials-status'),
          headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> uploadGSheetCredentials(
      List<int> fileBytes, String fileName) async {
    try {
      final uri =
          Uri.parse('$baseUrl/api/kpi/gsheet-config/upload-credentials');
      final request = http.MultipartRequest('POST', uri);
      final authHeaders = _headers;
      if (authHeaders.containsKey('Authorization')) {
        request.headers['Authorization'] = authHeaders['Authorization']!;
      }
      request.files.add(http.MultipartFile.fromBytes('credentials', fileBytes,
          filename: fileName));
      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> createKpiGSheetTemplate(String periodId) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/kpi/gsheet-config/$periodId/create-template'),
        headers: _headers,
      );
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> writeKpiTargetsToGSheet(String periodId) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/kpi/gsheet-config/$periodId/write-targets'),
        headers: _headers,
      );
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> importKpiExcelActuals(String periodId,
      {List<Map<String, dynamic>>? data}) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/kpi/import-actuals/$periodId'),
        headers: _headers,
        body: json.encode(data ?? []),
      );
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<List<int>?> downloadKpiExcelTemplate(
      String periodId, List<Map<String, dynamic>> targets) async {
    // Tạo file mẫu Excel từ danh sách targets hiện tại
    // Sẽ gọi endpoint backend hoặc tạo local
    try {
      final response = await http.get(
          Uri.parse('$baseUrl/api/kpi/excel-template/$periodId'),
          headers: _headers);
      if (response.statusCode == 200) {
        return response.bodyBytes;
      }
    } catch (e) {
      debugPrint('Download KPI template error: $e');
    }
    return null;
  }

  // ==================== COMMISSION SETTINGS ====================
  Future<Map<String, dynamic>> getCommissionSettings() async {
    try {
      final response = await http.get(
          Uri.parse('$baseUrl/api/settings/app/commission_settings'),
          headers: _headers);
      final result = _handleResponse(response);
      if (result['isSuccess'] == true && result['data'] != null) {
        final value = result['data']['value'];
        if (value != null && value is String) {
          return json.decode(value) as Map<String, dynamic>;
        }
      }
      return {};
    } catch (e) {
      return {};
    }
  }

  Future<Map<String, dynamic>> saveCommissionSettings(
      Map<String, dynamic> settings) async {
    try {
      final response = await http.post(Uri.parse('$baseUrl/api/settings/app'),
          headers: _headers,
          body: json.encode({
            'key': 'commission_settings',
            'value': json.encode(settings),
            'description': 'Cấu hình hoa hồng',
            'group': 'Commission',
            'dataType': 'json',
          }));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  // ==================== OVERTIMES ====================
  Future<Map<String, dynamic>> getOvertimes({
    String? status,
    DateTime? fromDate,
    DateTime? toDate,
    int? month,
    int? year,
    int? page,
    int? pageSize,
  }) async {
    try {
      final params = <String, String>{};
      if (page != null) {
        params.addAll(paginationQueryParams(page, pageSize ?? 20));
      } else if (pageSize != null) {
        params['pageSize'] = pageSize.toString();
      }
      if (status != null) params['status'] = status;
      if (fromDate != null) params['fromDate'] = fromDate.toIso8601String();
      if (toDate != null) params['toDate'] = toDate.toIso8601String();
      if (month != null) params['month'] = month.toString();
      if (year != null) params['year'] = year.toString();
      final uri = Uri.parse('$baseUrl/api/overtimes')
          .replace(queryParameters: params.isNotEmpty ? params : null);
      final response = await http.get(uri, headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> getMyOvertimes() async {
    try {
      final response = await http.get(
          Uri.parse('$baseUrl/api/overtimes/my-overtimes'),
          headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> createOvertime(Map<String, dynamic> data) async {
    try {
      final response = await http.post(Uri.parse('$baseUrl/api/overtimes'),
          headers: _headers, body: json.encode(data));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> updateOvertime(
      String id, Map<String, dynamic> data) async {
    try {
      final response = await http.put(Uri.parse('$baseUrl/api/overtimes/$id'),
          headers: _headers, body: json.encode(data));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> cancelOvertime(String id) async {
    try {
      final response = await http
          .delete(Uri.parse('$baseUrl/api/overtimes/$id'), headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> getPendingOvertimes() async {
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/api/overtimes/pending'), headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> approveOvertime(String id) async {
    try {
      final response = await http.post(
          Uri.parse('$baseUrl/api/overtimes/$id/approve'),
          headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> rejectOvertime(String id,
      {String? reason}) async {
    try {
      final response = await http.post(
          Uri.parse('$baseUrl/api/overtimes/$id/reject'),
          headers: _headers,
          body: json.encode({'reason': reason}));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> completeOvertime(String id) async {
    try {
      final response = await http.post(
          Uri.parse('$baseUrl/api/overtimes/$id/complete'),
          headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> getOvertimeStatistics() async {
    try {
      final response = await http.get(
          Uri.parse('$baseUrl/api/overtimes/statistics'),
          headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  // ==================== PAYSLIPS ====================
  Future<Map<String, dynamic>> getEmployeePayslips(
      String employeeUserId) async {
    try {
      final response = await http.get(
          Uri.parse('$baseUrl/api/payslips/employee/$employeeUserId'),
          headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> getMyPayslips() async {
    try {
      final response = await http.get(
          Uri.parse('$baseUrl/api/payslips/my-payslips'),
          headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> getPayslipById(String id) async {
    try {
      final response = await http.get(Uri.parse('$baseUrl/api/payslips/$id'),
          headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> getPayslipAttendanceSnapshot(String id) async {
    try {
      final response = await http.get(
          Uri.parse('$baseUrl/api/payslips/$id/attendance-snapshot'),
          headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  /// Search payslips in current store (manager/admin).
  Future<Map<String, dynamic>> getStorePayslips({
    int? year,
    int? month,
    String? employeeUserId,
    String? department,
    DateTime? periodStartFrom,
    DateTime? periodEndTo,
  }) async {
    try {
      final params = <String, String>{};
      if (year != null) params['year'] = year.toString();
      if (month != null) params['month'] = month.toString();
      if (employeeUserId != null && employeeUserId.isNotEmpty) {
        params['employeeUserId'] = employeeUserId;
      }
      if (department != null && department.isNotEmpty) {
        params['department'] = department;
      }
      if (periodStartFrom != null) {
        params['periodStartFrom'] = periodStartFrom.toIso8601String();
      }
      if (periodEndTo != null) {
        params['periodEndTo'] = periodEndTo.toIso8601String();
      }
      final uri = Uri.parse('$baseUrl/api/payslips/store')
          .replace(queryParameters: params.isNotEmpty ? params : null);
      final response = await http.get(uri, headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  /// Chốt lương — tạo/cập nhật phiếu lương từ dữ liệu tổng hợp.
  Future<Map<String, dynamic>> finalizePayroll(
      Map<String, dynamic> body) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/payslips/finalize'),
        headers: _headers,
        body: jsonEncode(body),
      );
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  // ==================== SHIFT SWAPS ====================
  Future<Map<String, dynamic>> getShiftSwaps() async {
    try {
      final response = await http.get(Uri.parse('$baseUrl/api/shiftswaps'),
          headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> getShiftSwapsPendingForMe() async {
    try {
      final response = await http.get(
          Uri.parse('$baseUrl/api/shiftswaps/pending-for-me'),
          headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> getShiftSwapsPendingApproval() async {
    try {
      final response = await http.get(
          Uri.parse('$baseUrl/api/shiftswaps/pending-approval'),
          headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> getShiftSwapColleagues() async {
    try {
      final response = await http.get(
          Uri.parse('$baseUrl/api/shiftswaps/colleagues'),
          headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> createShiftSwap({
    required String targetUserId,
    required String requesterShiftId,
    required DateTime requesterDate,
    required String targetShiftId,
    required DateTime targetDate,
    String? reason,
  }) async {
    try {
      final body = <String, dynamic>{
        'targetUserId': targetUserId,
        'requesterShiftId': requesterShiftId,
        'requesterDate': DateTime(
                requesterDate.year, requesterDate.month, requesterDate.day)
            .toIso8601String(),
        'targetShiftId': targetShiftId,
        'targetDate': DateTime(targetDate.year, targetDate.month, targetDate.day)
            .toIso8601String(),
        if (reason != null && reason.isNotEmpty) 'reason': reason,
      };
      final response = await http.post(Uri.parse('$baseUrl/api/shiftswaps'),
          headers: _headers, body: json.encode(body));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> respondToShiftSwap(
    String id, {
    required bool accept,
    String? rejectionReason,
  }) async {
    try {
      final response = await http.post(
          Uri.parse('$baseUrl/api/shiftswaps/$id/respond'),
          headers: _headers,
          body: json.encode({
            'accept': accept,
            if (rejectionReason != null && rejectionReason.isNotEmpty)
              'rejectionReason': rejectionReason,
          }));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> approveShiftSwap(
    String id, {
    bool approve = true,
    String? rejectionReason,
    String? note,
  }) async {
    try {
      final response = await http.post(
          Uri.parse('$baseUrl/api/shiftswaps/$id/approve'),
          headers: _headers,
          body: json.encode({
            'approve': approve,
            if (rejectionReason != null && rejectionReason.isNotEmpty)
              'rejectionReason': rejectionReason,
            if (note != null && note.isNotEmpty) 'note': note,
          }));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> cancelShiftSwap(String id) async {
    try {
      final response = await http
          .delete(Uri.parse('$baseUrl/api/shiftswaps/$id'), headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  // ==================== SHIFTS (Registration/Approval) ====================
  Future<Map<String, dynamic>> getMyShifts() async {
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/api/shifts/my-shifts'), headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> createShiftRegistration(
      Map<String, dynamic> data) async {
    try {
      final response = await http.post(Uri.parse('$baseUrl/api/shifts'),
          headers: _headers, body: json.encode(data));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> deleteShiftRegistration(String id) async {
    try {
      final response = await http.delete(Uri.parse('$baseUrl/api/shifts/$id'),
          headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> getPendingShifts() async {
    try {
      final response = await http.get(Uri.parse('$baseUrl/api/shifts/pending'),
          headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> getManagedShifts() async {
    try {
      final response = await http.get(Uri.parse('$baseUrl/api/shifts/managed'),
          headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> approveShift(String id) async {
    try {
      final response = await http.post(
          Uri.parse('$baseUrl/api/shifts/$id/approve'),
          headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> rejectShift(String id, {String? reason}) async {
    try {
      final response = await http.post(
          Uri.parse('$baseUrl/api/shifts/$id/reject'),
          headers: _headers,
          body: json.encode({'reason': reason}));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> updateShiftTimes(
      String id, Map<String, dynamic> data) async {
    try {
      final response = await http.put(
          Uri.parse('$baseUrl/api/shifts/$id/times'),
          headers: _headers,
          body: json.encode(data));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  // ==================== SHIFT SALARY LEVELS ====================
  Future<Map<String, dynamic>> getShiftSalaryLevels() async {
    try {
      final response = await http.get(
          Uri.parse('$baseUrl/api/shift-salary-levels'),
          headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> createShiftSalaryLevel(
      Map<String, dynamic> data) async {
    try {
      final response = await http.post(
          Uri.parse('$baseUrl/api/shift-salary-levels'),
          headers: _headers,
          body: json.encode(data));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> updateShiftSalaryLevel(
      String id, Map<String, dynamic> data) async {
    try {
      final response = await http.put(
          Uri.parse('$baseUrl/api/shift-salary-levels/$id'),
          headers: _headers,
          body: json.encode(data));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> deleteShiftSalaryLevel(String id) async {
    try {
      final response = await http.delete(
          Uri.parse('$baseUrl/api/shift-salary-levels/$id'),
          headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  // ==================== BIOMETRICS ====================
  Future<Map<String, dynamic>> getBiometricsByDevice(String deviceId) async {
    try {
      final response = await http.get(
          Uri.parse('$baseUrl/api/biometrics/device/$deviceId'),
          headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> getBiometricSummary(String deviceId) async {
    try {
      final response = await http.get(
          Uri.parse('$baseUrl/api/biometrics/device/$deviceId/summary'),
          headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> syncBiometrics(String deviceId) async {
    try {
      if (!await isDeviceOnline(deviceId)) {
        return {
          'isSuccess': false,
          'message':
              'Thiết bị đang offline. Vui lòng kiểm tra kết nối mạng của máy chấm công.'
        };
      }
      final response = await http.post(
          Uri.parse('$baseUrl/api/biometrics/device/$deviceId/sync'),
          headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> cancelBiometricSync(String deviceId) async {
    try {
      final response = await http.post(
          Uri.parse('$baseUrl/api/biometrics/device/$deviceId/cancel-sync'),
          headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> cancelAllBiometricCommands(
      String deviceId) async {
    try {
      final response = await http.post(
          Uri.parse(
              '$baseUrl/api/biometrics/device/$deviceId/cancel-all-commands'),
          headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  // ==================== GEOFENCES ====================
  Future<Map<String, dynamic>> getGeofences() async {
    try {
      final response = await http.get(Uri.parse('$baseUrl/api/geofences'),
          headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> createGeofence(Map<String, dynamic> data) async {
    try {
      final response = await http.post(Uri.parse('$baseUrl/api/geofences'),
          headers: _headers, body: json.encode(data));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> updateGeofence(
      String id, Map<String, dynamic> data) async {
    try {
      final response = await http.put(Uri.parse('$baseUrl/api/geofences/$id'),
          headers: _headers, body: json.encode(data));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> deleteGeofence(String id) async {
    try {
      final response = await http
          .delete(Uri.parse('$baseUrl/api/geofences/$id'), headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> validateGeofenceLocation(
      Map<String, dynamic> data) async {
    try {
      final response = await http.post(
          Uri.parse('$baseUrl/api/geofences/validate'),
          headers: _headers,
          body: json.encode(data));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  // ==================== HR DOCUMENTS ====================
  Future<Map<String, dynamic>> getHrDocuments({
    String? employeeId,
    String? type,
    int? page,
    int? pageSize,
    String? searchTerm,
  }) async {
    try {
      final params = <String, String>{};
      if (page != null) {
        params.addAll(paginationQueryParams(page, pageSize ?? 20));
      } else if (pageSize != null) {
        params['pageSize'] = pageSize.toString();
      }
      if (employeeId != null) params['employeeUserId'] = employeeId;
      if (type != null) params['type'] = type;
      if (searchTerm != null && searchTerm.isNotEmpty) {
        params['searchTerm'] = searchTerm;
      }
      final uri = Uri.parse('$baseUrl/api/hr-documents')
          .replace(queryParameters: params.isNotEmpty ? params : null);
      final response = await http.get(uri, headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> getExpiringDocuments() async {
    try {
      final response = await http.get(
          Uri.parse('$baseUrl/api/hr-documents/expiring'),
          headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> createHrDocument(
      Map<String, dynamic> data) async {
    try {
      final response = await http.post(Uri.parse('$baseUrl/api/hr-documents'),
          headers: _headers, body: json.encode(data));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> updateHrDocument(
      String id, Map<String, dynamic> data) async {
    try {
      final response = await http.put(
          Uri.parse('$baseUrl/api/hr-documents/$id'),
          headers: _headers,
          body: json.encode(data));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> deleteHrDocument(String id) async {
    try {
      final response = await http.delete(
          Uri.parse('$baseUrl/api/hr-documents/$id'),
          headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  // ==================== USER MANAGEMENT ====================
  Future<Map<String, dynamic>> getUsers() async {
    try {
      final response =
          await http.get(Uri.parse('$baseUrl/api/users'), headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> getUserById(String userId) async {
    try {
      final response = await http.get(Uri.parse('$baseUrl/api/users/$userId'),
          headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> changeUserRole(
      String userId, String role) async {
    try {
      final response = await _retryOnUnauthorized(() => http.put(
          Uri.parse('$baseUrl/api/users/$userId/role'),
          headers: _headers,
          body: json.encode({'newRole': role})));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> getAvailableRoles() async {
    try {
      final response = await _retryOnUnauthorized(() => http.get(
          Uri.parse('$baseUrl/api/users/available-roles'),
          headers: _headers));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> lockUser(String userId) async {
    try {
      final response = await _retryOnUnauthorized(() => http.post(
          Uri.parse('$baseUrl/api/users/$userId/lock'),
          headers: _headers));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> unlockUser(String userId) async {
    try {
      final response = await _retryOnUnauthorized(() => http.post(
          Uri.parse('$baseUrl/api/users/$userId/unlock'),
          headers: _headers));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> resetUserPassword(String userId,
      {String? newPassword}) async {
    try {
      final response = await _retryOnUnauthorized(() => http.post(
          Uri.parse('$baseUrl/api/users/$userId/reset-password'),
          headers: _headers,
          body: json.encode({'newPassword': newPassword ?? ''})));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> updateUser(
      String userId, Map<String, dynamic> data) async {
    try {
      final response = await _retryOnUnauthorized(() => http.put(
          Uri.parse('$baseUrl/api/users/$userId'),
          headers: _headers,
          body: json.encode(data)));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> deleteUser(String userId) async {
    try {
      final response = await _retryOnUnauthorized(() => http
          .delete(Uri.parse('$baseUrl/api/users/$userId'), headers: _headers));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  // ==================== HELPER ====================

  /// HTTP GET with default timeout
  Future<http.Response> _get(Uri url, {Map<String, String>? headers}) {
    return http.get(url, headers: headers ?? _headers).timeout(_defaultTimeout);
  }

  /// HTTP POST with default timeout
  Future<http.Response> _post(Uri url,
      {Map<String, String>? headers, Object? body}) {
    return http
        .post(url, headers: headers ?? _headers, body: body)
        .timeout(_defaultTimeout);
  }

  /// HTTP PUT with default timeout
  Future<http.Response> _put(Uri url,
      {Map<String, String>? headers, Object? body}) {
    return http
        .put(url, headers: headers ?? _headers, body: body)
        .timeout(_defaultTimeout);
  }

  /// HTTP DELETE with default timeout
  Future<http.Response> _delete(Uri url, {Map<String, String>? headers}) {
    return http
        .delete(url, headers: headers ?? _headers)
        .timeout(_defaultTimeout);
  }

  Map<String, dynamic> _handleResponse(http.Response response) {
    try {
      final rawBody = utf8.decode(response.bodyBytes, allowMalformed: true);

      // Handle empty body (e.g. 204 No Content)
      if (rawBody.isEmpty) {
        if (response.statusCode >= 200 && response.statusCode < 300) {
          return {'isSuccess': true};
        }
        return {
          'isSuccess': false,
          'message': response.statusCode == 401
              ? 'Phiên đăng nhập hết hạn. Vui lòng đăng nhập lại.'
              : response.statusCode == 403
                  ? 'Bạn không có quyền thực hiện thao tác này.'
                  : response.statusCode == 413
                      ? 'File quá lớn. Vui lòng chọn file nhỏ hơn.'
                      : 'Lỗi: ${response.statusCode}',
          'statusCode': response.statusCode
        };
      }

      final data = json.decode(rawBody);
      if (response.statusCode >= 200 && response.statusCode < 300) {
        if (data is Map<String, dynamic>) {
          return _normalizeResponseMap(data);
        }
        return {'isSuccess': true, 'data': data};
      } else {
        // Extract error message from various API response formats
        String errorMessage = 'Lỗi không xác định';
        if (data is Map<String, dynamic>) {
          final normalized = _normalizeResponseMap(data);
          if (normalized['message'] != null) {
            errorMessage = normalized['message'].toString();
          } else if (normalized['title'] != null) {
            // ASP.NET ProblemDetails format - prefer detail over title (title is often just exception type name)
            errorMessage =
                (normalized['detail'] ?? normalized['title']).toString();
            if (normalized['errors'] is Map) {
              final errors = (normalized['errors'] as Map)
                  .values
                  .expand((v) => v is List ? v : [v])
                  .join(', ');
              if (errors.isNotEmpty) errorMessage = errors;
            }
          }
        }
        final errOut = <String, dynamic>{
          'isSuccess': false,
          'message': _normalizeViText(errorMessage),
          'statusCode': response.statusCode,
        };
        if (data is Map<String, dynamic>) {
          final normalized = _normalizeResponseMap(data);
          if (normalized['data'] != null) errOut['data'] = normalized['data'];
        }
        return errOut;
      }
    } catch (e) {
      // Handle non-JSON responses (e.g. nginx 413 HTML error page)
      String message;
      if (response.statusCode == 413) {
        message = 'File quá lớn. Vui lòng chọn file nhỏ hơn.';
      } else if (response.statusCode == 502 || response.statusCode == 503) {
        message = 'Server đang bảo trì. Vui lòng thử lại sau.';
      } else {
        message = 'Lỗi xử lý dữ liệu (${response.statusCode})';
      }
      return {
        'isSuccess': false,
        'message': message,
        'statusCode': response.statusCode,
      };
    }
  }

  Map<String, dynamic> _normalizeResponseMap(Map<String, dynamic> source) {
    final result = Map<String, dynamic>.from(source);
    if (result['isSuccess'] == null && result['IsSuccess'] != null) {
      result['isSuccess'] = result['IsSuccess'];
    }
    if (result['data'] == null && result['Data'] != null) {
      result['data'] = result['Data'];
    }
    final errors = result['errors'] ?? result['Errors'];
    if ((result['message'] == null ||
            result['message'].toString().isEmpty) &&
        errors is List &&
        errors.isNotEmpty) {
      result['message'] = errors.map((e) => e.toString()).join('; ');
    }
    for (final key in const ['message', 'title', 'detail']) {
      final value = result[key];
      if (value is String) {
        result[key] = _normalizeViText(value);
      }
    }
    return result;
  }

  String _normalizeViText(String input) {
    if (!(input.contains('Ã') || input.contains('Â') || input.contains('â'))) {
      return input;
    }
    try {
      // Map Windows-1252 specific chars (U+0080–U+009F) to their byte values
      // so latin1.encode (which only handles U+0000–U+00FF) won't throw
      const cp1252Extra = {
        '\u20ac': 0x80,
        '\u201a': 0x82,
        '\u0192': 0x83,
        '\u201e': 0x84,
        '\u2026': 0x85,
        '\u2020': 0x86,
        '\u2021': 0x87,
        '\u02c6': 0x88,
        '\u2030': 0x89,
        '\u0160': 0x8a,
        '\u2039': 0x8b,
        '\u0152': 0x8c,
        '\u017d': 0x8e,
        '\u2018': 0x91,
        '\u2019': 0x92,
        '\u201c': 0x93,
        '\u201d': 0x94,
        '\u2022': 0x95,
        '\u2013': 0x96,
        '\u2014': 0x97,
        '\u02dc': 0x98,
        '\u2122': 0x99,
        '\u0161': 0x9a,
        '\u203a': 0x9b,
        '\u0153': 0x9c,
        '\u017e': 0x9e,
        '\u0178': 0x9f,
      };
      final bytes = <int>[];
      for (final ch in input.runes) {
        final c = String.fromCharCode(ch);
        if (cp1252Extra.containsKey(c)) {
          bytes.add(cp1252Extra[c]!);
        } else if (ch <= 0xFF) {
          bytes.add(ch);
        } else {
          // Not a Latin-1/cp1252 char — not mojibake, return original
          return input;
        }
      }
      return utf8.decode(bytes);
    } catch (_) {
      return input;
    }
  }

  /// Safely convert dynamic value to int
  static int _toInt(dynamic value, int defaultValue) {
    if (value == null) return defaultValue;
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString()) ?? defaultValue;
  }

  // ==================== NOTIFICATION PREFERENCES ====================

  /// Lấy danh sách nhóm thông báo
  Future<Map<String, dynamic>> getNotificationCategories() async {
    final response = await http.get(
      Uri.parse('$baseUrl/api/notification-preferences/categories'),
      headers: _headers,
    );
    return _handleResponse(response);
  }

  /// Lấy thiết lập nhận thông báo của user hiện tại
  Future<Map<String, dynamic>> getNotificationPreferences() async {
    final response = await http.get(
      Uri.parse('$baseUrl/api/notification-preferences'),
      headers: _headers,
    );
    return _handleResponse(response);
  }

  /// Cập nhật thiết lập nhận thông báo
  Future<Map<String, dynamic>> updateNotificationPreferences(
      List<Map<String, dynamic>> preferences) async {
    final response = await http.put(
      Uri.parse('$baseUrl/api/notification-preferences'),
      headers: _headers,
      body: jsonEncode({'preferences': preferences}),
    );
    return _handleResponse(response);
  }

  // ==================== PENALTY TICKETS ====================

  /// Quét lại chấm công và tạo phiếu phạt còn thiếu trong khoảng ngày (tối đa 62 ngày).
  Future<Map<String, dynamic>> backfillPenaltyTicketsFromAttendance({
    required DateTime from,
    required DateTime to,
  }) async {
    try {
      String fmt(DateTime d) =>
          '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
      final response = await http
          .post(
            Uri.parse(
                '$baseUrl/api/PenaltyTickets/backfill-from-attendance?from=${fmt(from)}&to=${fmt(to)}'),
            headers: _headers,
          )
          .timeout(const Duration(seconds: 120));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  /// Lấy danh sách phiếu phạt
  Future<Map<String, dynamic>> getPenaltyTickets({
    int page = 1,
    int pageSize = 20,
    String? employeeId,
    String? status,
    String? type,
    DateTime? fromDate,
    DateTime? toDate,
  }) async {
    try {
      var queryParams = 'page=$page&pageSize=$pageSize';
      if (employeeId != null) queryParams += '&employeeId=$employeeId';
      if (status != null) queryParams += '&status=$status';
      if (type != null) queryParams += '&type=$type';
      if (fromDate != null) {
        queryParams += '&fromDate=${fromDate.toIso8601String()}';
      }
      if (toDate != null) queryParams += '&toDate=${toDate.toIso8601String()}';

      final response = await http
          .get(
            Uri.parse('$baseUrl/api/PenaltyTickets?$queryParams'),
            headers: _headers,
          )
          .timeout(const Duration(seconds: 15));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  /// Lấy phiếu phạt của nhân viên đang đăng nhập
  Future<Map<String, dynamic>> getMyPenaltyTickets({
    int page = 1,
    int pageSize = 20,
    DateTime? fromDate,
    DateTime? toDate,
  }) async {
    try {
      var queryParams = 'page=$page&pageSize=$pageSize';
      if (fromDate != null) {
        queryParams += '&fromDate=${fromDate.toIso8601String()}';
      }
      if (toDate != null) queryParams += '&toDate=${toDate.toIso8601String()}';

      final response = await http
          .get(
            Uri.parse('$baseUrl/api/PenaltyTickets/my?$queryParams'),
            headers: _headers,
          )
          .timeout(const Duration(seconds: 15));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  /// Lấy chi tiết phiếu phạt
  Future<Map<String, dynamic>> getPenaltyTicketDetail(String id) async {
    try {
      final response = await http
          .get(
            Uri.parse('$baseUrl/api/PenaltyTickets/$id'),
            headers: _headers,
          )
          .timeout(const Duration(seconds: 10));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  /// Hủy phiếu phạt
  Future<Map<String, dynamic>> cancelPenaltyTicket(String id,
      {String? reason}) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/api/PenaltyTickets/$id/cancel'),
            headers: _headers,
            body: json.encode({'reason': reason ?? ''}),
          )
          .timeout(const Duration(seconds: 10));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  /// Duyệt phiếu phạt thủ công
  Future<Map<String, dynamic>> approvePenaltyTicket(String id,
      {String? note}) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/api/PenaltyTickets/$id/approve'),
            headers: _headers,
            body: json.encode({'note': note ?? ''}),
          )
          .timeout(const Duration(seconds: 10));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  /// Thống kê phiếu phạt
  Future<Map<String, dynamic>> getPenaltyTicketStats(
      {int? month, int? year, String? fromDate, String? toDate}) async {
    try {
      var queryParams = '';
      if (fromDate != null && toDate != null) {
        // Ưu tiên lọc theo khoảng ngày tường minh khi được cung cấp
        queryParams = 'fromDate=$fromDate&toDate=$toDate';
      } else {
        if (month != null) queryParams += 'month=$month&';
        if (year != null) queryParams += 'year=$year';
      }

      final response = await http
          .get(
            Uri.parse('$baseUrl/api/PenaltyTickets/stats?$queryParams'),
            headers: _headers,
          )
          .timeout(const Duration(seconds: 10));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  /// Tạo phiếu phạt thủ công
  Future<Map<String, dynamic>> createPenaltyTicket(
      Map<String, dynamic> data) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/api/PenaltyTickets'),
            headers: _headers,
            body: json.encode(data),
          )
          .timeout(const Duration(seconds: 10));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  /// Sửa phiếu phạt
  Future<Map<String, dynamic>> updatePenaltyTicket(
      String id, Map<String, dynamic> data) async {
    try {
      final response = await http
          .put(
            Uri.parse('$baseUrl/api/PenaltyTickets/$id'),
            headers: _headers,
            body: json.encode(data),
          )
          .timeout(const Duration(seconds: 10));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  /// Xóa phiếu phạt
  Future<Map<String, dynamic>> deletePenaltyTicket(String id) async {
    try {
      final response = await http
          .delete(
            Uri.parse('$baseUrl/api/PenaltyTickets/$id'),
            headers: _headers,
          )
          .timeout(const Duration(seconds: 10));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  /// Hoàn duyệt phiếu phạt
  Future<Map<String, dynamic>> unapprovePenaltyTicket(String id) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/api/PenaltyTickets/$id/unapprove'),
            headers: _headers,
            body: json.encode({}),
          )
          .timeout(const Duration(seconds: 10));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  // ══════════ AGENT PORTAL ══════════

  Future<Map<String, dynamic>> getAgentProfile() async {
    try {
      final response = await http.get(Uri.parse('$baseUrl/api/agent/profile'),
          headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> updateAgentProfile({
    String? phone,
    String? address,
    String? description,
  }) async {
    try {
      final response = await _retryOnUnauthorized(() => http
          .put(
            Uri.parse('$baseUrl/api/agent/profile'),
            headers: _headers,
            body: json.encode({
              'phone': phone,
              'address': address,
              'description': description,
            }),
          )
          .timeout(const Duration(seconds: 15)));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> getAgentStores({int pageSize = 1000}) async {
    try {
      final uri = Uri.parse('$baseUrl/api/agent/stores')
          .replace(queryParameters: {'pageSize': pageSize.toString()});
      final response = await http.get(uri, headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> getAgentReferralLink() async {
    try {
      final response = await http.get(
          Uri.parse('$baseUrl/api/agent/referral-link'),
          headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> getAgentDashboard(
      {String? fromDate, String? toDate}) async {
    try {
      final params = <String, String>{};
      if (fromDate != null) params['fromDate'] = fromDate;
      if (toDate != null) params['toDate'] = toDate;
      final uri = Uri.parse('$baseUrl/api/agent/dashboard')
          .replace(queryParameters: params.isNotEmpty ? params : null);
      final response = await http.get(uri, headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> getAgentDevices({
    String? storeId,
    bool? isOnline,
    String? search,
    int page = 1,
    int pageSize = 50,
  }) async {
    try {
      final params = <String, String>{
        'page': page.toString(),
        'pageSize': pageSize.toString(),
      };
      if (storeId != null && storeId.isNotEmpty) params['storeId'] = storeId;
      if (isOnline != null) params['isOnline'] = isOnline.toString();
      if (search != null && search.isNotEmpty) params['search'] = search;
      final uri = Uri.parse('$baseUrl/api/agent/devices')
          .replace(queryParameters: params);
      final response = await http.get(uri, headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> getAgentMyLicenses({
    int? page,
    int? pageSize,
    bool? isUsed,
    String? licenseType,
    String? search,
  }) async {
    try {
      final params = <String, String>{};
      if (page != null) params['page'] = page.toString();
      if (pageSize != null) params['pageSize'] = pageSize.toString();
      if (isUsed != null) params['isUsed'] = isUsed.toString();
      if (licenseType != null) params['licenseType'] = licenseType;
      if (search != null && search.isNotEmpty) params['search'] = search;
      final uri = Uri.parse('$baseUrl/api/agent/my-licenses')
          .replace(queryParameters: params.isNotEmpty ? params : null);
      final response = await http.get(uri, headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> getAgentAdminUsers({
    String? search,
    String? storeId,
    String? role,
    int pageNumber = 1,
    int pageSize = 500,
  }) async {
    try {
      final params = <String, String>{
        'pageNumber': pageNumber.toString(),
        'pageSize': pageSize.toString(),
      };
      if (search != null && search.isNotEmpty) params['search'] = search;
      if (storeId != null && storeId.isNotEmpty) params['storeId'] = storeId;
      if (role != null && role.isNotEmpty) params['role'] = role;
      final uri = Uri.parse('$baseUrl/api/agent/users')
          .replace(queryParameters: params);
      final response = await http.get(uri, headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> getAgentAdminDevices({
    String? storeId,
    bool? isOnline,
    bool? isClaimed,
    String? search,
    int pageNumber = 1,
    int pageSize = 500,
  }) async {
    try {
      final params = <String, String>{
        'pageNumber': pageNumber.toString(),
        'pageSize': pageSize.toString(),
      };
      if (storeId != null && storeId.isNotEmpty) params['storeId'] = storeId;
      if (isOnline != null) params['isOnline'] = isOnline.toString();
      if (isClaimed != null) params['isClaimed'] = isClaimed.toString();
      if (search != null && search.isNotEmpty) params['search'] = search;
      final uri = Uri.parse('$baseUrl/api/agent/devices/manage')
          .replace(queryParameters: params);
      final response = await http.get(uri, headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> getAgentStoreFullDetail(String id) async {
    try {
      final response = await http.get(
          Uri.parse('$baseUrl/api/agent/stores/$id/full'),
          headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> agentUpdateStore(String id,
      {String? name, String? description, String? address, String? province, String? phone}) async {
    try {
      final body = <String, dynamic>{
        if (name != null) 'name': name,
        if (description != null) 'description': description,
        if (address != null) 'address': address,
        if (province != null) 'province': province,
        if (phone != null) 'phone': phone,
      };
      final response = await http.put(
          Uri.parse('$baseUrl/api/agent/stores/$id'),
          headers: _headers,
          body: json.encode(body));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> agentToggleStoreStatus(String id) async {
    try {
      final response = await http.post(
          Uri.parse('$baseUrl/api/agent/stores/$id/toggle-status'),
          headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> agentLockStore(String id, [String? reason]) async {
    try {
      final response = await http.post(
          Uri.parse('$baseUrl/api/agent/stores/$id/lock'),
          headers: _headers,
          body: json.encode({'reason': reason ?? ''}));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> agentUnlockStore(String id) async {
    try {
      final response = await http.post(
          Uri.parse('$baseUrl/api/agent/stores/$id/unlock'),
          headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> agentExtendStoreDays(String storeId, int days) async {
    try {
      final response = await http.post(
          Uri.parse('$baseUrl/api/agent/stores/$storeId/extend'),
          headers: _headers,
          body: json.encode({'daysToAdd': days}));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> agentActivateLicenseForStore(
      String storeId, dynamic licenseData) async {
    try {
      final data = licenseData is Map<String, dynamic>
          ? licenseData
          : {'licenseKey': licenseData};
      final response = await http.post(
          Uri.parse('$baseUrl/api/agent/stores/$storeId/activate-license'),
          headers: _headers,
          body: json.encode(data));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> getAgentActivatableLicensesForStore(
      String storeId) async {
    try {
      final response = await http.get(
          Uri.parse(
              '$baseUrl/api/agent/stores/$storeId/activatable-licenses'),
          headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> agentUnassignDevice(String deviceId) async {
    try {
      final response = await http.put(
          Uri.parse('$baseUrl/api/agent/devices/$deviceId/unassign-store'),
          headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> agentAssignDeviceToStore(
      String deviceId, String storeId) async {
    try {
      final response = await http.put(
          Uri.parse(
              '$baseUrl/api/agent/devices/$deviceId/assign-store/$storeId'),
          headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> agentUpdateUserCredentials(String userId,
      {String? newEmail, String? newPassword, String? fullName}) async {
    try {
      final body = <String, dynamic>{
        if (newEmail != null) 'newEmail': newEmail,
        if (newPassword != null) 'newPassword': newPassword,
        if (fullName != null) 'fullName': fullName,
      };
      final response = await http.put(
          Uri.parse('$baseUrl/api/agent/users/$userId/credentials'),
          headers: _headers,
          body: json.encode(body));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  // ==================== PRODUCTION / PIECE-RATE SALARY ====================

  // ── Product Groups ──
  Future<Map<String, dynamic>> getProductGroups() async {
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/api/production/groups'), headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> createProductGroup(
      Map<String, dynamic> data) async {
    try {
      final response = await http.post(
          Uri.parse('$baseUrl/api/production/groups'),
          headers: _headers,
          body: json.encode(data));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> updateProductGroup(
      String id, Map<String, dynamic> data) async {
    try {
      final response = await http.put(
          Uri.parse('$baseUrl/api/production/groups/$id'),
          headers: _headers,
          body: json.encode(data));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> deleteProductGroup(String id) async {
    try {
      final response = await http.delete(
          Uri.parse('$baseUrl/api/production/groups/$id'),
          headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  // ── Product Items ──
  Future<Map<String, dynamic>> getProductItems({String? groupId}) async {
    try {
      final params = <String, String>{};
      if (groupId != null) params['groupId'] = groupId;
      final uri = Uri.parse('$baseUrl/api/production/items')
          .replace(queryParameters: params.isNotEmpty ? params : null);
      final response = await http.get(uri, headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> createProductItem(
      Map<String, dynamic> data) async {
    try {
      final response = await http.post(
          Uri.parse('$baseUrl/api/production/items'),
          headers: _headers,
          body: json.encode(data));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> updateProductItem(
      String id, Map<String, dynamic> data) async {
    try {
      final response = await http.put(
          Uri.parse('$baseUrl/api/production/items/$id'),
          headers: _headers,
          body: json.encode(data));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> deleteProductItem(String id) async {
    try {
      final response = await http.delete(
          Uri.parse('$baseUrl/api/production/items/$id'),
          headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  // ── Production Entries ──
  Future<Map<String, dynamic>> getProductionEntries({
    DateTime? fromDate,
    DateTime? toDate,
    String? employeeId,
    String? productGroupId,
    String? productItemId,
    int page = 1,
    int pageSize = 50,
  }) async {
    try {
      final params = <String, String>{
        'page': page.toString(),
        'pageSize': pageSize.toString(),
      };
      if (fromDate != null) params['fromDate'] = fromDate.toIso8601String();
      if (toDate != null) params['toDate'] = toDate.toIso8601String();
      if (employeeId != null) params['employeeId'] = employeeId;
      if (productGroupId != null) params['productGroupId'] = productGroupId;
      if (productItemId != null) params['productItemId'] = productItemId;
      final uri = Uri.parse('$baseUrl/api/production/entries')
          .replace(queryParameters: params);
      final response = await http.get(uri, headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> createProductionEntry(
      Map<String, dynamic> data) async {
    try {
      final response = await http.post(
          Uri.parse('$baseUrl/api/production/entries'),
          headers: _headers,
          body: json.encode(data));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> createProductionEntryBatch(
      List<Map<String, dynamic>> entries) async {
    try {
      final response = await http.post(
          Uri.parse('$baseUrl/api/production/entries/batch'),
          headers: _headers,
          body: json.encode({'entries': entries}));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> updateProductionEntry(
      String id, Map<String, dynamic> data) async {
    try {
      final response = await http.put(
          Uri.parse('$baseUrl/api/production/entries/$id'),
          headers: _headers,
          body: json.encode(data));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> deleteProductionEntry(String id) async {
    try {
      final response = await http.delete(
          Uri.parse('$baseUrl/api/production/entries/$id'),
          headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  // ── Production Export ──
  Future<Map<String, dynamic>> getProductionExport({
    required DateTime fromDate,
    required DateTime toDate,
    String? employeeId,
    String? productGroupId,
  }) async {
    try {
      final params = <String, String>{
        'fromDate': fromDate.toIso8601String(),
        'toDate': toDate.toIso8601String(),
      };
      if (employeeId != null) params['employeeId'] = employeeId;
      if (productGroupId != null) params['productGroupId'] = productGroupId;
      final uri = Uri.parse('$baseUrl/api/production/export')
          .replace(queryParameters: params);
      final response = await http.get(uri, headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  // ── Production Summary ──
  Future<Map<String, dynamic>> getProductionSummary({
    required DateTime fromDate,
    required DateTime toDate,
    String? employeeId,
    String? productGroupId,
  }) async {
    try {
      final params = <String, String>{
        'fromDate': fromDate.toIso8601String(),
        'toDate': toDate.toIso8601String(),
      };
      if (employeeId != null) params['employeeId'] = employeeId;
      if (productGroupId != null) params['productGroupId'] = productGroupId;
      final uri = Uri.parse('$baseUrl/api/production/summary')
          .replace(queryParameters: params);
      final response = await http.get(uri, headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  // ── Production Import ──

  Future<Map<String, dynamic>> importProductionFromExcel(
      Map<String, dynamic> data) async {
    try {
      final response = await http.post(
          Uri.parse('$baseUrl/api/production/import'),
          headers: _headers,
          body: json.encode(data));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> testProductionGSheetConnection(
      Map<String, dynamic> data) async {
    try {
      final response = await http.post(
          Uri.parse('$baseUrl/api/production/gsheet/test-connection'),
          headers: _headers,
          body: json.encode(data));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> getProductionGSheetNames(
      Map<String, dynamic> data) async {
    try {
      final response = await http.post(
          Uri.parse('$baseUrl/api/production/gsheet/sheet-names'),
          headers: _headers,
          body: json.encode(data));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> syncProductionFromGSheet(
      Map<String, dynamic> data) async {
    try {
      final response = await http.post(
          Uri.parse('$baseUrl/api/production/gsheet/sync'),
          headers: _headers,
          body: json.encode(data));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> syncProductionFromGSheetMulti(
      Map<String, dynamic> data) async {
    try {
      final response = await http.post(
          Uri.parse('$baseUrl/api/production/gsheet/sync-multi'),
          headers: _headers,
          body: json.encode(data));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  // ══════════════════ FEEDBACK / Ý KIẾN ══════════════════

  Future<Map<String, dynamic>> getFeedbacks({
    String? status,
    String? category,
    String? senderEmployeeId,
    String? recipientEmployeeId,
    bool? generalMailboxOnly,
    DateTime? fromDate,
    DateTime? toDate,
    int page = 1,
    int pageSize = 20,
  }) async {
    try {
      final params = <String, String>{
        'page': page.toString(),
        'pageSize': pageSize.toString(),
      };
      if (status != null) params['status'] = status;
      if (category != null) params['category'] = category;
      if (senderEmployeeId != null && senderEmployeeId.isNotEmpty) {
        params['senderEmployeeId'] = senderEmployeeId;
      }
      if (generalMailboxOnly == true) {
        params['generalMailboxOnly'] = 'true';
      } else if (recipientEmployeeId != null &&
          recipientEmployeeId.isNotEmpty) {
        params['recipientEmployeeId'] = recipientEmployeeId;
      }
      if (fromDate != null) {
        params['fromDate'] = fromDate.toIso8601String().split('T').first;
      }
      if (toDate != null) {
        params['toDate'] = toDate.toIso8601String().split('T').first;
      }
      final uri =
          Uri.parse('$baseUrl/api/feedback').replace(queryParameters: params);
      final response = await http.get(uri, headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> getMyFeedbacks({
    String? status,
    String? category,
    String? senderEmployeeId,
    String? recipientEmployeeId,
    bool? generalMailboxOnly,
    DateTime? fromDate,
    DateTime? toDate,
  }) async {
    try {
      final params = <String, String>{};
      if (status != null) params['status'] = status;
      if (category != null) params['category'] = category;
      if (senderEmployeeId != null && senderEmployeeId.isNotEmpty) {
        params['senderEmployeeId'] = senderEmployeeId;
      }
      if (generalMailboxOnly == true) {
        params['generalMailboxOnly'] = 'true';
      } else if (recipientEmployeeId != null &&
          recipientEmployeeId.isNotEmpty) {
        params['recipientEmployeeId'] = recipientEmployeeId;
      }
      if (fromDate != null) {
        params['fromDate'] = fromDate.toIso8601String().split('T').first;
      }
      if (toDate != null) {
        params['toDate'] = toDate.toIso8601String().split('T').first;
      }
      final uri = Uri.parse('$baseUrl/api/feedback/my')
          .replace(queryParameters: params.isEmpty ? null : params);
      final response = await http.get(uri, headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> createFeedback(Map<String, dynamic> data) async {
    try {
      final response = await http.post(Uri.parse('$baseUrl/api/feedback'),
          headers: _headers, body: json.encode(data));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> respondFeedback(
      String id, Map<String, dynamic> data) async {
    try {
      final response = await http.put(
          Uri.parse('$baseUrl/api/feedback/$id/respond'),
          headers: _headers,
          body: json.encode(data));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> updateFeedbackStatus(
      String id, String status) async {
    try {
      final response = await http.patch(
          Uri.parse('$baseUrl/api/feedback/$id/status'),
          headers: _headers,
          body: json.encode({'status': status}));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> deleteFeedback(String id) async {
    try {
      final response = await http.delete(Uri.parse('$baseUrl/api/feedback/$id'),
          headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> getFeedbackManagers() async {
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/api/feedback/managers'), headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> getFeedbackReplies(String feedbackId) async {
    try {
      final response = await http.get(
          Uri.parse('$baseUrl/api/feedback/$feedbackId/replies'),
          headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> createFeedbackReply(
      String feedbackId, Map<String, dynamic> data) async {
    try {
      final response = await http.post(
          Uri.parse('$baseUrl/api/feedback/$feedbackId/replies'),
          headers: _headers,
          body: json.encode(data));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> uploadFeedbackImage(String filePath) async {
    try {
      final uri = Uri.parse('$baseUrl/api/feedback/upload-image');
      final request = http.MultipartRequest('POST', uri);
      if (_token != null) request.headers['Authorization'] = 'Bearer $_token';
      request.files.add(await http.MultipartFile.fromPath('file', filePath));
      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);
      return _handleResponse(response);
    } catch (e) {
      return {'isSuccess': false, 'message': 'Lỗi tải ảnh: $e'};
    }
  }

  Future<Map<String, dynamic>> uploadFeedbackReplyImage(
      String feedbackId, String replyId, String filePath) async {
    try {
      final uri =
          Uri.parse('$baseUrl/api/feedback/$feedbackId/replies/$replyId/image');
      final request = http.MultipartRequest('POST', uri);
      if (_token != null) request.headers['Authorization'] = 'Bearer $_token';
      request.files.add(await http.MultipartFile.fromPath('file', filePath));
      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);
      return _handleResponse(response);
    } catch (e) {
      return {'isSuccess': false, 'message': 'Lỗi tải ảnh: $e'};
    }
  }

  // ==================== MEAL TRACKING ====================

  Future<Map<String, dynamic>> getMealSessions() async {
    try {
      final response = await http.get(Uri.parse('$baseUrl/api/meals/sessions'),
          headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> createMealSession(
      Map<String, dynamic> data) async {
    try {
      final response = await http.post(Uri.parse('$baseUrl/api/meals/sessions'),
          headers: _headers, body: jsonEncode(data));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> updateMealSession(
      String id, Map<String, dynamic> data) async {
    try {
      final response = await http.put(
          Uri.parse('$baseUrl/api/meals/sessions/$id'),
          headers: _headers,
          body: jsonEncode(data));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> deleteMealSession(String id) async {
    try {
      final response = await http.delete(
          Uri.parse('$baseUrl/api/meals/sessions/$id'),
          headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> getMealEstimate({String? date}) async {
    try {
      final queryParams = <String, String>{};
      if (date != null) queryParams['date'] = date;
      final uri = Uri.parse('$baseUrl/api/meals/estimate').replace(
          queryParameters: queryParams.isNotEmpty ? queryParams : null);
      final response = await http.get(uri, headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> getMealRecords({
    String? date,
    String? mealSessionId,
    int page = 1,
    int pageSize = 20,
  }) async {
    try {
      final queryParams = paginationQueryParams(page, pageSize);
      if (date != null) queryParams['date'] = date;
      if (mealSessionId != null) queryParams['mealSessionId'] = mealSessionId;
      final uri = Uri.parse('$baseUrl/api/meals/records')
          .replace(queryParameters: queryParams);
      final response = await http.get(uri, headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> getEmployeeMealSummary({
    required String fromDate,
    required String toDate,
    String? employeeUserId,
  }) async {
    try {
      final queryParams = <String, String>{
        'fromDate': fromDate,
        'toDate': toDate,
      };
      if (employeeUserId != null) {
        queryParams['employeeUserId'] = employeeUserId;
      }
      final uri = Uri.parse('$baseUrl/api/meals/summary')
          .replace(queryParameters: queryParams);
      final response = await http.get(uri, headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> getMealMenu(
      {String? date, String? mealSessionId}) async {
    try {
      final queryParams = <String, String>{};
      if (date != null) queryParams['date'] = date;
      if (mealSessionId != null) queryParams['mealSessionId'] = mealSessionId;
      final uri = Uri.parse('$baseUrl/api/meals/menu').replace(
          queryParameters: queryParams.isNotEmpty ? queryParams : null);
      final response = await http.get(uri, headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> getWeeklyMealMenu(
      {String? weekStartDate}) async {
    try {
      final queryParams = <String, String>{};
      if (weekStartDate != null) queryParams['weekStartDate'] = weekStartDate;
      final uri = Uri.parse('$baseUrl/api/meals/menu/weekly').replace(
          queryParameters: queryParams.isNotEmpty ? queryParams : null);
      final response = await http.get(uri, headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> createMealMenu(Map<String, dynamic> data) async {
    try {
      final response = await http.post(Uri.parse('$baseUrl/api/meals/menu'),
          headers: _headers, body: jsonEncode(data));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> updateMealMenu(
      String id, Map<String, dynamic> data) async {
    try {
      final response = await http.put(Uri.parse('$baseUrl/api/meals/menu/$id'),
          headers: _headers, body: jsonEncode(data));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> deleteMealMenu(String id) async {
    try {
      final response = await http
          .delete(Uri.parse('$baseUrl/api/meals/menu/$id'), headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  // ── Meal Registration (đăng ký suất ăn) ──

  Future<Map<String, dynamic>> registerMeal(Map<String, dynamic> data) async {
    try {
      final response = await http.post(Uri.parse('$baseUrl/api/meals/register'),
          headers: _headers, body: jsonEncode(data));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> batchRegisterMeal(
      List<Map<String, dynamic>> registrations) async {
    try {
      final response = await http.post(
          Uri.parse('$baseUrl/api/meals/register/batch'),
          headers: _headers,
          body: jsonEncode({'registrations': registrations}));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> getMyMealRegistrations(
      {DateTime? fromDate, DateTime? toDate}) async {
    try {
      final params = <String, String>{};
      if (fromDate != null) {
        params['fromDate'] = fromDate.toIso8601String().split('T')[0];
      }
      if (toDate != null) {
        params['toDate'] = toDate.toIso8601String().split('T')[0];
      }
      final query = params.isNotEmpty
          ? '?${params.entries.map((e) => '${e.key}=${e.value}').join('&')}'
          : '';
      final response = await http.get(
          Uri.parse('$baseUrl/api/meals/register/my$query'),
          headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> getMealRegistrationSummary(
      {String? date, String? mealSessionId}) async {
    try {
      final params = <String, String>{};
      if (date != null) params['date'] = date;
      if (mealSessionId != null) params['mealSessionId'] = mealSessionId;
      final query = params.isNotEmpty
          ? '?${params.entries.map((e) => '${e.key}=${e.value}').join('&')}'
          : '';
      final response = await http.get(
          Uri.parse('$baseUrl/api/meals/register/summary$query'),
          headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> qrMealCheckIn(
      {String? mealSessionId, String? qrCode}) async {
    try {
      final response =
          await http.post(Uri.parse('$baseUrl/api/meals/checkin/qr'),
              headers: _headers,
              body: jsonEncode({
                if (mealSessionId != null) 'mealSessionId': mealSessionId,
                if (qrCode != null) 'qrCode': qrCode,
              }));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  // --- Meal Debt (Công nợ suất ăn) ---

  Future<Map<String, dynamic>> getMealDebtSummary(
      {String? period, DateTime? from, DateTime? to}) async {
    try {
      final params = <String, String>{};
      if (period != null) params['period'] = period;
      if (from != null) params['from'] = from.toIso8601String();
      if (to != null) params['to'] = to.toIso8601String();
      final uri = Uri.parse('$baseUrl/api/meals/debt/summary')
          .replace(queryParameters: params.isEmpty ? null : params);
      final response = await http.get(uri, headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> getMealDebtHistory(
      {String? employeeUserId, String? period}) async {
    try {
      final params = <String, String>{};
      if (employeeUserId != null) params['employeeUserId'] = employeeUserId;
      if (period != null) params['period'] = period;
      final uri = Uri.parse('$baseUrl/api/meals/debt/history')
          .replace(queryParameters: params.isEmpty ? null : params);
      final response = await http.get(uri, headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> createMealDebt(Map<String, dynamic> data) async {
    try {
      final response = await http.post(Uri.parse('$baseUrl/api/meals/debt'),
          headers: _headers, body: jsonEncode(data));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> batchChargeMeals(String period) async {
    try {
      final response = await http.post(
          Uri.parse('$baseUrl/api/meals/debt/batch-charge'),
          headers: _headers,
          body: jsonEncode({'period': period}));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  // ==================== MEAL DISHES (Master list) ====================

  Future<Map<String, dynamic>> getMealDishes() async {
    try {
      final response = await http.get(Uri.parse('$baseUrl/api/meals/dishes'),
          headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> createMealDish(Map<String, dynamic> data) async {
    try {
      final response = await http.post(Uri.parse('$baseUrl/api/meals/dishes'),
          headers: _headers, body: jsonEncode(data));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> updateMealDish(
      String id, Map<String, dynamic> data) async {
    try {
      final response = await http.put(
          Uri.parse('$baseUrl/api/meals/dishes/$id'),
          headers: _headers,
          body: jsonEncode(data));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> deleteMealDish(String id) async {
    try {
      final response = await http.delete(
          Uri.parse('$baseUrl/api/meals/dishes/$id'),
          headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  // ==================== MEAL RECORDS CRUD ====================

  Future<Map<String, dynamic>> createMealRecord(
      Map<String, dynamic> data) async {
    try {
      final response = await http.post(Uri.parse('$baseUrl/api/meals/records'),
          headers: _headers, body: jsonEncode(data));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> updateMealRecord(
      String id, Map<String, dynamic> data) async {
    try {
      final response = await http.put(
          Uri.parse('$baseUrl/api/meals/records/$id'),
          headers: _headers,
          body: jsonEncode(data));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> deleteMealRecord(String id) async {
    try {
      final response = await http.delete(
          Uri.parse('$baseUrl/api/meals/records/$id'),
          headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  // ==================== MEAL REGISTRATIONS MANAGEMENT ====================

  Future<Map<String, dynamic>> getMealRegistrations(
      {String? date, String? mealSessionId}) async {
    try {
      final params = <String, String>{};
      if (date != null) params['date'] = date;
      if (mealSessionId != null) params['mealSessionId'] = mealSessionId;
      final query = params.isNotEmpty
          ? '?${params.entries.map((e) => '${e.key}=${Uri.encodeComponent(e.value)}').join('&')}'
          : '';
      final response = await http.get(
          Uri.parse('$baseUrl/api/meals/registrations$query'),
          headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> createMealRegistration(
      Map<String, dynamic> data) async {
    try {
      final response = await http.post(
          Uri.parse('$baseUrl/api/meals/registrations'),
          headers: _headers,
          body: jsonEncode(data));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> deleteMealRegistration(String id) async {
    try {
      final response = await http.delete(
          Uri.parse('$baseUrl/api/meals/registrations/$id'),
          headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  // ==================== FIELD CHECK-IN / CHECK-IN ĐIỂM BÁN ====================

  // --- Field Locations (Điểm bán khách hàng) ---

  Future<Map<String, dynamic>> getFieldLocations(
      {String? search, String? category}) async {
    try {
      final params = <String, String>{};
      if (search != null && search.isNotEmpty) params['search'] = search;
      if (category != null && category.isNotEmpty) {
        params['category'] = category;
      }
      final query = params.isNotEmpty
          ? '?${params.entries.map((e) => '${e.key}=${Uri.encodeComponent(e.value)}').join('&')}'
          : '';
      final response = await http.get(
          Uri.parse('$baseUrl/api/field-checkin/locations$query'),
          headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> registerFieldLocation(
      Map<String, dynamic> data) async {
    try {
      final response = await http.post(
          Uri.parse('$baseUrl/api/field-checkin/locations'),
          headers: _headers,
          body: jsonEncode(data));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> updateFieldLocation(
      String id, Map<String, dynamic> data) async {
    try {
      final response = await http.put(
          Uri.parse('$baseUrl/api/field-checkin/locations/$id'),
          headers: _headers,
          body: jsonEncode(data));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> deleteFieldLocation(String id) async {
    try {
      final response = await http.delete(
          Uri.parse('$baseUrl/api/field-checkin/locations/$id'),
          headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  // --- Assignments ---

  Future<Map<String, dynamic>> getFieldAssignments({String? employeeId}) async {
    try {
      final query = employeeId != null ? '?employeeId=$employeeId' : '';
      final response = await http.get(
          Uri.parse('$baseUrl/api/field-checkin/assignments$query'),
          headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> getMyFieldAssignments({int? dayOfWeek}) async {
    try {
      final query = dayOfWeek != null ? '?dayOfWeek=$dayOfWeek' : '';
      final response = await http.get(
          Uri.parse('$baseUrl/api/field-checkin/my-assignments$query'),
          headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> createFieldAssignment(
      Map<String, dynamic> data) async {
    try {
      final response = await http.post(
          Uri.parse('$baseUrl/api/field-checkin/assignments'),
          headers: _headers,
          body: jsonEncode(data));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> bulkFieldAssign(
      List<Map<String, dynamic>> items) async {
    try {
      final response = await http.post(
          Uri.parse('$baseUrl/api/field-checkin/assignments/bulk'),
          headers: _headers,
          body: jsonEncode({'items': items}));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> updateFieldAssignment(
      String id, Map<String, dynamic> data) async {
    try {
      final response = await http.put(
          Uri.parse('$baseUrl/api/field-checkin/assignments/$id'),
          headers: _headers,
          body: jsonEncode(data));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> deleteFieldAssignment(String id) async {
    try {
      final response = await http.delete(
          Uri.parse('$baseUrl/api/field-checkin/assignments/$id'),
          headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> fieldCheckIn(Map<String, dynamic> data) async {
    try {
      final response = await http.post(
          Uri.parse('$baseUrl/api/field-checkin/checkin'),
          headers: _headers,
          body: jsonEncode(data));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> fieldCheckOut(
      String visitId, Map<String, dynamic> data) async {
    try {
      final response = await http.post(
          Uri.parse('$baseUrl/api/field-checkin/checkout/$visitId'),
          headers: _headers,
          body: jsonEncode(data));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> getMyFieldVisits({
    DateTime? fromDate,
    DateTime? toDate,
    String? status,
  }) async {
    try {
      final params = <String, String>{};
      if (fromDate != null) params['fromDate'] = fromDate.toIso8601String();
      if (toDate != null) params['toDate'] = toDate.toIso8601String();
      if (status != null) params['status'] = status;
      final uri = Uri.parse('$baseUrl/api/field-checkin/my-visits')
          .replace(queryParameters: params.isEmpty ? null : params);
      final response = await http.get(uri, headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> getTodayFieldVisits() async {
    try {
      final response = await http.get(
          Uri.parse('$baseUrl/api/field-checkin/today'),
          headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> getFieldReports({
    String? employeeId,
    String? locationId,
    DateTime? fromDate,
    DateTime? toDate,
    String? status,
  }) async {
    try {
      final params = <String, String>{};
      if (employeeId != null) params['employeeId'] = employeeId;
      if (locationId != null) params['locationId'] = locationId;
      if (fromDate != null) params['fromDate'] = fromDate.toIso8601String();
      if (toDate != null) params['toDate'] = toDate.toIso8601String();
      if (status != null) params['status'] = status;
      final uri = Uri.parse('$baseUrl/api/field-checkin/reports')
          .replace(queryParameters: params.isEmpty ? null : params);
      final response = await http.get(uri, headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> reviewFieldVisit(
      String visitId, Map<String, dynamic> data) async {
    try {
      final response = await http.post(
          Uri.parse('$baseUrl/api/field-checkin/review/$visitId'),
          headers: _headers,
          body: jsonEncode(data));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> getFieldSummary({
    DateTime? fromDate,
    DateTime? toDate,
  }) async {
    try {
      final params = <String, String>{};
      if (fromDate != null) params['fromDate'] = fromDate.toIso8601String();
      if (toDate != null) params['toDate'] = toDate.toIso8601String();
      final uri = Uri.parse('$baseUrl/api/field-checkin/summary')
          .replace(queryParameters: params.isEmpty ? null : params);
      final response = await http.get(uri, headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  // ==================== JOURNEY TRACKING ====================

  Future<Map<String, dynamic>> startJourney() async {
    try {
      final response = await http.post(
          Uri.parse('$baseUrl/api/field-checkin/journey/start'),
          headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> trackJourneyPoints(
      List<Map<String, dynamic>> points) async {
    try {
      final response = await http.post(
          Uri.parse('$baseUrl/api/field-checkin/journey/track'),
          headers: _headers,
          body: jsonEncode({'points': points}));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> endJourney({String? note}) async {
    try {
      final response = await http.post(
          Uri.parse('$baseUrl/api/field-checkin/journey/end'),
          headers: _headers,
          body: jsonEncode({'note': note}));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> getTodayJourney() async {
    try {
      final response = await http.get(
          Uri.parse('$baseUrl/api/field-checkin/journey/today'),
          headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> getJourneyReports({
    String? employeeId,
    DateTime? fromDate,
    DateTime? toDate,
  }) async {
    try {
      final params = <String, String>{};
      if (employeeId != null) params['employeeId'] = employeeId;
      if (fromDate != null) params['fromDate'] = fromDate.toIso8601String();
      if (toDate != null) params['toDate'] = toDate.toIso8601String();
      final uri = Uri.parse('$baseUrl/api/field-checkin/journey/reports')
          .replace(queryParameters: params.isEmpty ? null : params);
      final response = await http.get(uri, headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> getMyJourneyHistory({
    DateTime? fromDate,
    DateTime? toDate,
  }) async {
    try {
      final params = <String, String>{};
      if (fromDate != null) params['fromDate'] = fromDate.toIso8601String();
      if (toDate != null) params['toDate'] = toDate.toIso8601String();
      final uri = Uri.parse('$baseUrl/api/field-checkin/journey/my-history')
          .replace(queryParameters: params.isEmpty ? null : params);
      final response = await http.get(uri, headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> getActiveJourneys() async {
    try {
      final response = await http.get(
          Uri.parse('$baseUrl/api/field-checkin/journey/active'),
          headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> getEmployeeLocations(
      {bool fieldStaffOnly = true}) async {
    try {
      final uri = Uri.parse('$baseUrl/api/field-checkin/employee-locations')
          .replace(
              queryParameters:
                  fieldStaffOnly ? {'fieldStaffOnly': 'true'} : null);
      final response = await http.get(uri, headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> reportLocation({
    required double latitude,
    required double longitude,
    double? accuracy,
  }) async {
    try {
      final response = await http.post(
          Uri.parse('$baseUrl/api/field-checkin/report-location'),
          headers: _headers,
          body: jsonEncode({
            'latitude': latitude,
            'longitude': longitude,
            if (accuracy != null) 'accuracy': accuracy,
          }));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> getJourneyDetail(String journeyId) async {
    try {
      final response = await http.get(
          Uri.parse('$baseUrl/api/field-checkin/journey/$journeyId'),
          headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> reviewJourney(String journeyId,
      {String? reviewNote}) async {
    try {
      final response = await http.post(
          Uri.parse('$baseUrl/api/field-checkin/journey/$journeyId/review'),
          headers: _headers,
          body: jsonEncode({'reviewNote': reviewNote}));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  // ============================================================
  // SuperAdmin Announcements (Phase 1)
  // ============================================================

  Future<Map<String, dynamic>> listSystemAnnouncements({
    int page = 1,
    int pageSize = 20,
    String? keyword,
    int? kind,
    int? status,
  }) async {
    try {
      final qp = <String, String>{
        'page': '$page',
        'pageSize': '$pageSize',
        if (keyword != null && keyword.isNotEmpty) 'keyword': keyword,
        if (kind != null) 'kind': '$kind',
        if (status != null) 'status': '$status',
      };
      final uri = Uri.parse('$baseUrl/api/system-admin/announcements')
          .replace(queryParameters: qp);
      final response = await http.get(uri, headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> createSystemAnnouncement(
      Map<String, dynamic> body) async {
    try {
      final response = await http.post(
          Uri.parse('$baseUrl/api/system-admin/announcements'),
          headers: _headers,
          body: jsonEncode(body));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> sendSystemAnnouncement(String id) async {
    try {
      final response = await http.post(
          Uri.parse('$baseUrl/api/system-admin/announcements/$id/send'),
          headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> resendFailedAnnouncement(String id) async {
    try {
      final response = await http.post(
          Uri.parse(
              '$baseUrl/api/system-admin/announcements/$id/resend-failed'),
          headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> cancelSystemAnnouncement(String id) async {
    try {
      final response = await http.post(
          Uri.parse('$baseUrl/api/system-admin/announcements/$id/cancel'),
          headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> deleteSystemAnnouncement(String id) async {
    try {
      final response = await http.delete(
          Uri.parse('$baseUrl/api/system-admin/announcements/$id'),
          headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> getAnnouncementStats(String id) async {
    try {
      final response = await http.get(
          Uri.parse('$baseUrl/api/system-admin/announcements/$id/stats'),
          headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> previewAnnouncementAudience(
      Map<String, dynamic> audience) async {
    try {
      final response = await http.post(
          Uri.parse('$baseUrl/api/system-admin/announcements/preview-audience'),
          headers: _headers,
          body: jsonEncode(audience));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> getActiveAnnouncements() async {
    try {
      final response = await http.get(
          Uri.parse('$baseUrl/api/announcements/active'),
          headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> markAnnouncementSeen(String id) async {
    try {
      final response = await http.post(
          Uri.parse('$baseUrl/api/announcements/$id/seen'),
          headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> markAnnouncementClicked(String id) async {
    try {
      final response = await http.post(
          Uri.parse('$baseUrl/api/announcements/$id/clicked'),
          headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> markAnnouncementAcked(String id) async {
    try {
      final response = await http.post(
          Uri.parse('$baseUrl/api/announcements/$id/ack'),
          headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> dismissAnnouncement(String id) async {
    try {
      final response = await http.post(
          Uri.parse('$baseUrl/api/announcements/$id/dismiss'),
          headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  // ============ Phase 2 — Maintenance Windows ============

  Future<Map<String, dynamic>> listMaintenanceWindows(
      {bool? activeOnly}) async {
    try {
      final qs = activeOnly == true ? '?activeOnly=true' : '';
      final response = await http.get(
          Uri.parse('$baseUrl/api/system-admin/maintenance$qs'),
          headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> createMaintenanceWindow(
      Map<String, dynamic> body) async {
    try {
      final response = await http.post(
          Uri.parse('$baseUrl/api/system-admin/maintenance'),
          headers: _headers,
          body: jsonEncode(body));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> activateMaintenanceWindow(String id) async {
    try {
      final response = await http.post(
          Uri.parse('$baseUrl/api/system-admin/maintenance/$id/activate'),
          headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> deactivateMaintenanceWindow(String id) async {
    try {
      final response = await http.post(
          Uri.parse('$baseUrl/api/system-admin/maintenance/$id/deactivate'),
          headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> deleteMaintenanceWindow(String id) async {
    try {
      final response = await http.delete(
          Uri.parse('$baseUrl/api/system-admin/maintenance/$id'),
          headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> getActiveMaintenance() async {
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/api/maintenance/active'), headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  // ============ Phase 3 — Marketing (Templates + Campaigns) ============

  Future<Map<String, dynamic>> listNotificationTemplates(
      {bool? activeOnly}) async {
    try {
      final qs = activeOnly == true ? '?activeOnly=true' : '';
      final response = await http.get(
          Uri.parse('$baseUrl/api/system-admin/marketing/templates$qs'),
          headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> createNotificationTemplate(
      Map<String, dynamic> body) async {
    try {
      final response = await http.post(
          Uri.parse('$baseUrl/api/system-admin/marketing/templates'),
          headers: _headers,
          body: jsonEncode(body));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> updateNotificationTemplate(
      String id, Map<String, dynamic> body) async {
    try {
      final response = await http.put(
          Uri.parse('$baseUrl/api/system-admin/marketing/templates/$id'),
          headers: _headers,
          body: jsonEncode(body));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> deleteNotificationTemplate(String id) async {
    try {
      final response = await http.delete(
          Uri.parse('$baseUrl/api/system-admin/marketing/templates/$id'),
          headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> listMarketingCampaigns(
      {int page = 1, int pageSize = 50}) async {
    try {
      final response = await http.get(
          Uri.parse(
              '$baseUrl/api/system-admin/marketing/campaigns?page=$page&pageSize=$pageSize'),
          headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> getMarketingCampaign(String id) async {
    try {
      final response = await http.get(
          Uri.parse('$baseUrl/api/system-admin/marketing/campaigns/$id'),
          headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> createMarketingCampaign(
      Map<String, dynamic> body) async {
    try {
      final response = await http.post(
          Uri.parse('$baseUrl/api/system-admin/marketing/campaigns'),
          headers: _headers,
          body: jsonEncode(body));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> launchMarketingCampaign(String id) async {
    try {
      final response = await http.post(
          Uri.parse('$baseUrl/api/system-admin/marketing/campaigns/$id/launch'),
          headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> cancelMarketingCampaign(String id) async {
    try {
      final response = await http.post(
          Uri.parse('$baseUrl/api/system-admin/marketing/campaigns/$id/cancel'),
          headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> deleteMarketingCampaign(String id) async {
    try {
      final response = await http.delete(
          Uri.parse('$baseUrl/api/system-admin/marketing/campaigns/$id'),
          headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  // ============================================================
  // App Pages: Terms / Privacy / Help
  // ============================================================

  Future<Map<String, dynamic>> getAppPage(String type) async {
    try {
      final response = await http.get(Uri.parse('$baseUrl/api/app-pages/$type'),
          headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> adminGetAllAppPages() async {
    try {
      final response = await http.get(
          Uri.parse('$baseUrl/api/system-admin/app-pages'),
          headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> adminUpsertAppPage(
      String type, Map<String, dynamic> body) async {
    try {
      final response = await http.put(
          Uri.parse('$baseUrl/api/system-admin/app-pages/$type'),
          headers: _headers,
          body: jsonEncode(body));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  // ============================================================
  // App Bug Reports
  // ============================================================

  Future<Map<String, dynamic>> submitAppBugReport(
      Map<String, dynamic> body) async {
    try {
      final response = await http.post(Uri.parse('$baseUrl/api/app-reports'),
          headers: _headers, body: jsonEncode(body));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> adminGetAppBugReports({
    String? status,
    String? type,
    int page = 1,
    int pageSize = 50,
  }) async {
    try {
      final qp = <String, String>{
        'page': '$page',
        'pageSize': '$pageSize',
        if (status != null && status.isNotEmpty) 'status': status,
        if (type != null && type.isNotEmpty) 'type': type,
      };
      final uri = Uri.parse('$baseUrl/api/system-admin/app-reports')
          .replace(queryParameters: qp);
      final response = await http.get(uri, headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> adminUpdateAppBugReport(
      String id, Map<String, dynamic> body) async {
    try {
      final response = await http.put(
          Uri.parse('$baseUrl/api/system-admin/app-reports/$id'),
          headers: _headers,
          body: jsonEncode(body));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> adminGetConsultationRequests({
    String? status,
    String? search,
    int page = 1,
    int pageSize = 50,
  }) async {
    try {
      final qp = <String, String>{
        'page': '$page',
        'pageSize': '$pageSize',
        if (status != null && status.isNotEmpty) 'status': status,
        if (search != null && search.isNotEmpty) 'search': search,
      };
      final uri = Uri.parse('$baseUrl/api/system-admin/consultation-requests')
          .replace(queryParameters: qp);
      final response = await http.get(uri, headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> adminUpdateConsultationRequest(
      String id, Map<String, dynamic> body) async {
    try {
      final response = await http.put(
          Uri.parse('$baseUrl/api/system-admin/consultation-requests/$id'),
          headers: _headers,
          body: jsonEncode(body));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> adminDeleteConsultationRequest(String id) async {
    try {
      final response = await http.delete(
        Uri.parse('$baseUrl/api/system-admin/consultation-requests/$id'),
        headers: _headers,
      );
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  // ── POS / Hàng hóa ──

  Future<Map<String, dynamic>> getPosProducts({
    String? search,
    String? categoryId,
    String? brandId,
    String? storageLocationId,
    String? supplierId,
    PosProductType? productType,
    bool? isDirectSale,
    PosStockFilter stockFilter = PosStockFilter.all,
    PosStockoutFilter stockoutFilter = PosStockoutFilter.all,
    PosProductSortBy sortBy = PosProductSortBy.createdAt,
    bool sortDesc = true,
    bool includeInactive = false,
    DateTime? createdFrom,
    DateTime? createdTo,
    int page = 1,
    int pageSize = 50,
  }) async {
    try {
      final q = <String, String>{
        'page': '$page',
        'pageSize': '$pageSize',
        'stockFilter': stockFilter.index.toString(),
        'stockoutFilter': stockoutFilter.index.toString(),
        'sortBy': sortBy.index.toString(),
        'sortDesc': sortDesc.toString(),
        'includeInactive': includeInactive.toString(),
        'categoryIncludeChildren': 'true',
      };
      if (search != null && search.trim().isNotEmpty) q['search'] = search.trim();
      if (categoryId != null && categoryId.isNotEmpty) q['categoryId'] = categoryId;
      if (brandId != null && brandId.isNotEmpty) q['brandId'] = brandId;
      if (storageLocationId != null && storageLocationId.isNotEmpty) {
        q['storageLocationId'] = storageLocationId;
      }
      if (supplierId != null && supplierId.isNotEmpty) q['supplierId'] = supplierId;
      if (productType != null) {
        q['productType'] = productType == PosProductType.service
            ? '1'
            : productType == PosProductType.combo
                ? '2'
                : '0';
      }
      if (isDirectSale != null) q['isDirectSale'] = isDirectSale.toString();
      if (createdFrom != null) {
        q['createdFrom'] = createdFrom.toUtc().toIso8601String();
      }
      if (createdTo != null) {
        q['createdTo'] = createdTo.toUtc().toIso8601String();
      }
      final uri = Uri.parse('$baseUrl/api/pos/products').replace(queryParameters: q);
      final response =
          await http.get(uri, headers: _headers).timeout(const Duration(seconds: 30));
      return _handleResponse(response);
    } catch (e) {
      debugPrint('Error getPosProducts: $e');
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> getPosProduct(String id) async {
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/api/pos/products/$id'), headers: _headers)
          .timeout(const Duration(seconds: 30));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> getPosToppingGroups() async {
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/api/pos/topping-groups'), headers: _headers)
          .timeout(const Duration(seconds: 30));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> createPosToppingGroup(
      Map<String, dynamic> body) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/api/pos/topping-groups'),
            headers: _headers,
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 30));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> updatePosToppingGroup(
      String id, Map<String, dynamic> body) async {
    try {
      final response = await http
          .put(
            Uri.parse('$baseUrl/api/pos/topping-groups/$id'),
            headers: _headers,
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 30));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> deletePosToppingGroup(String id) async {
    try {
      final response = await http
          .delete(
            Uri.parse('$baseUrl/api/pos/topping-groups/$id'),
            headers: _headers,
          )
          .timeout(const Duration(seconds: 30));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> createPosProduct(Map<String, dynamic> body) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/api/pos/products'),
            headers: _headers,
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 60));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> updatePosProduct(
      String id, Map<String, dynamic> body) async {
    try {
      final response = await http
          .put(
            Uri.parse('$baseUrl/api/pos/products/$id'),
            headers: _headers,
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 60));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  /// Upload ảnh sản phẩm POS trực tiếp (multipart → lưu ImageUrl).
  Future<Map<String, dynamic>> uploadPosProductImage(
    String productId,
    List<int> fileBytes,
    String fileName,
  ) async {
    try {
      final uri = Uri.parse('$baseUrl/api/pos/products/$productId/image');
      final request = http.MultipartRequest('POST', uri);
      if (_token != null) request.headers['Authorization'] = 'Bearer $_token';

      final ext = fileName.toLowerCase().split('.').last;
      final mimeTypes = {
        'jpg': 'image/jpeg',
        'jpeg': 'image/jpeg',
        'png': 'image/png',
        'gif': 'image/gif',
        'webp': 'image/webp',
      };
      final contentType = mimeTypes[ext] ?? 'image/jpeg';
      final mediaParts = contentType.split('/');

      request.files.add(http.MultipartFile.fromBytes(
        'file',
        fileBytes,
        filename: fileName.contains('.') ? fileName : '$fileName.jpg',
        contentType: MediaType(mediaParts[0], mediaParts[1]),
      ));
      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);
      final result = _handleResponse(response);
      if (result['isSuccess'] != true) {
        debugPrint(
          'uploadPosProductImage failed: status=${response.statusCode} body=${response.body.substring(0, response.body.length.clamp(0, 300))}',
        );
      }
      return result;
    } catch (e) {
      debugPrint('Error uploading POS product image: $e');
      return {'isSuccess': false, 'message': 'Lỗi tải ảnh: $e'};
    }
  }

  Future<Map<String, dynamic>> deletePosProduct(String id) async {
    try {
      final response = await http
          .delete(Uri.parse('$baseUrl/api/pos/products/$id'), headers: _headers)
          .timeout(const Duration(seconds: 30));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> copyPosProduct(String id) async {
    try {
      final response = await http
          .post(Uri.parse('$baseUrl/api/pos/products/$id/copy'), headers: _headers)
          .timeout(const Duration(seconds: 30));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> togglePosProductFavorite(
      String id, bool value) async {
    try {
      final uri = Uri.parse('$baseUrl/api/pos/products/$id/favorite')
          .replace(queryParameters: {'value': value.toString()});
      final response =
          await http.post(uri, headers: _headers).timeout(const Duration(seconds: 15));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> patchPosProductQuick(
    String id, {
    double? basePrice,
    double? onHandQty,
    double? costPrice,
  }) async {
    try {
      final body = <String, dynamic>{};
      if (basePrice != null) body['basePrice'] = basePrice;
      if (onHandQty != null) body['onHandQty'] = onHandQty;
      if (costPrice != null) body['costPrice'] = costPrice;
      final response = await http
          .patch(
            Uri.parse('$baseUrl/api/pos/products/$id/quick'),
            headers: _headers,
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 30));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> patchPosProductSellingStatus(
    String id, {
    required bool isDirectSale,
    bool? isActive,
  }) async {
    try {
      final body = <String, dynamic>{'isDirectSale': isDirectSale};
      if (isActive != null) body['isActive'] = isActive;
      final response = await http
          .patch(
            Uri.parse('$baseUrl/api/pos/products/$id/selling-status'),
            headers: _headers,
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 30));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> getPosProductVariants(String productId) async {
    try {
      final response = await http
          .get(
            Uri.parse('$baseUrl/api/pos/products/$productId/variants'),
            headers: _headers,
          )
          .timeout(const Duration(seconds: 30));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> createPosProductVariant(
      String productId, Map<String, dynamic> body) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/api/pos/products/$productId/variants'),
            headers: _headers,
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 30));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> updatePosProductVariant(
      String productId, String variantId, Map<String, dynamic> body) async {
    try {
      final response = await http
          .put(
            Uri.parse(
                '$baseUrl/api/pos/products/$productId/variants/$variantId'),
            headers: _headers,
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 30));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> deletePosProductVariant(
      String productId, String variantId) async {
    try {
      final response = await http
          .delete(
            Uri.parse(
                '$baseUrl/api/pos/products/$productId/variants/$variantId'),
            headers: _headers,
          )
          .timeout(const Duration(seconds: 30));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> patchPosProductVariantQuick(
    String productId,
    String variantId, {
    double? basePrice,
    double? onHandQty,
    double? costPrice,
  }) async {
    try {
      final body = <String, dynamic>{};
      if (basePrice != null) body['basePrice'] = basePrice;
      if (onHandQty != null) body['onHandQty'] = onHandQty;
      if (costPrice != null) body['costPrice'] = costPrice;
      final response = await http
          .patch(
            Uri.parse(
                '$baseUrl/api/pos/products/$productId/variants/$variantId/quick'),
            headers: _headers,
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 30));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> generatePosProductVariants(
    String productId, {
    required List<Map<String, dynamic>> attributes,
    List<Map<String, dynamic>>? units,
    double? defaultBasePrice,
    double? defaultCostPrice,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse(
                '$baseUrl/api/pos/products/$productId/variants/generate'),
            headers: _headers,
            body: jsonEncode({
              'attributes': attributes,
              if (units != null) 'units': units,
              if (defaultBasePrice != null) 'defaultBasePrice': defaultBasePrice,
              if (defaultCostPrice != null) 'defaultCostPrice': defaultCostPrice,
            }),
          )
          .timeout(const Duration(seconds: 60));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> syncPosProductVariants(
    String productId,
    List<Map<String, dynamic>> variants,
  ) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/api/pos/products/$productId/variants/sync'),
            headers: _headers,
            body: jsonEncode({'variants': variants}),
          )
          .timeout(const Duration(seconds: 60));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> getPosProductCategories() async {
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/api/pos/catalog/categories'), headers: _headers)
          .timeout(const Duration(seconds: 30));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> createPosProductCategory(String name,
      {String? parentId}) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/api/pos/catalog/categories'),
            headers: _headers,
            body: jsonEncode({'name': name, 'parentId': parentId, 'sortOrder': 0}),
          )
          .timeout(const Duration(seconds: 30));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> updatePosProductCategory(
    String id,
    String name, {
    String? parentId,
    int sortOrder = 0,
  }) async {
    try {
      final response = await http
          .put(
            Uri.parse('$baseUrl/api/pos/catalog/categories/$id'),
            headers: _headers,
            body: jsonEncode({
              'name': name,
              'parentId': parentId,
              'sortOrder': sortOrder,
            }),
          )
          .timeout(const Duration(seconds: 30));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> sortPosProductCategories(
      List<Map<String, dynamic>> items) async {
    try {
      final response = await http
          .put(
            Uri.parse('$baseUrl/api/pos/catalog/categories/sort'),
            headers: _headers,
            body: jsonEncode({'items': items}),
          )
          .timeout(const Duration(seconds: 30));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> sortPosProducts(
      List<Map<String, dynamic>> items) async {
    try {
      final response = await http
          .put(
            Uri.parse('$baseUrl/api/pos/products/sort'),
            headers: _headers,
            body: jsonEncode({'items': items}),
          )
          .timeout(const Duration(seconds: 30));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> deletePosProductCategory(String id) async {
    try {
      final response = await http
          .delete(
            Uri.parse('$baseUrl/api/pos/catalog/categories/$id'),
            headers: _headers,
          )
          .timeout(const Duration(seconds: 30));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> getPosProductBrands() async {
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/api/pos/catalog/brands'), headers: _headers)
          .timeout(const Duration(seconds: 30));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> createPosProductBrand(String name) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/api/pos/catalog/brands'),
            headers: _headers,
            body: jsonEncode({'name': name, 'sortOrder': 0}),
          )
          .timeout(const Duration(seconds: 30));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> updatePosProductBrand(String id, String name) async {
    try {
      final response = await http
          .put(
            Uri.parse('$baseUrl/api/pos/catalog/brands/$id'),
            headers: _headers,
            body: jsonEncode({'name': name, 'sortOrder': 0}),
          )
          .timeout(const Duration(seconds: 30));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> deletePosProductBrand(String id) async {
    try {
      final response = await http
          .delete(Uri.parse('$baseUrl/api/pos/catalog/brands/$id'), headers: _headers)
          .timeout(const Duration(seconds: 30));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> getPosStorageLocations() async {
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/api/pos/catalog/storage-locations'),
              headers: _headers)
          .timeout(const Duration(seconds: 30));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> createPosStorageLocation(String name) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/api/pos/catalog/storage-locations'),
            headers: _headers,
            body: jsonEncode({'name': name, 'sortOrder': 0}),
          )
          .timeout(const Duration(seconds: 30));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> updatePosStorageLocation(String id, String name) async {
    try {
      final response = await http
          .put(
            Uri.parse('$baseUrl/api/pos/catalog/storage-locations/$id'),
            headers: _headers,
            body: jsonEncode({'name': name, 'sortOrder': 0}),
          )
          .timeout(const Duration(seconds: 30));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> deletePosStorageLocation(String id) async {
    try {
      final response = await http
          .delete(
            Uri.parse('$baseUrl/api/pos/catalog/storage-locations/$id'),
            headers: _headers,
          )
          .timeout(const Duration(seconds: 30));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> exportPosProductsExcel({
    String? search,
    String? categoryId,
    String? supplierId,
  }) async {
    final q = <String, String>{};
    if (search != null && search.trim().isNotEmpty) q['search'] = search.trim();
    if (categoryId != null && categoryId.isNotEmpty) q['categoryId'] = categoryId;
    if (supplierId != null && supplierId.isNotEmpty) q['supplierId'] = supplierId;
    return _getExcelExport(
      Uri.parse('$baseUrl/api/pos/products/export/excel')
          .replace(queryParameters: q.isEmpty ? null : q),
    );
  }

  Future<Map<String, dynamic>> importPosProductsExcelFile(
      List<int> fileBytes, String fileName) async {
    try {
      final uri = Uri.parse('$baseUrl/api/pos/products/import/excel/file');
      final request = http.MultipartRequest('POST', uri);
      final authHeaders = _headers;
      if (authHeaders.containsKey('Authorization')) {
        request.headers['Authorization'] = authHeaders['Authorization']!;
      }
      request.files.add(http.MultipartFile.fromBytes('file', fileBytes, filename: fileName));
      final streamed = await request.send().timeout(const Duration(seconds: 180));
      final response = await http.Response.fromStream(streamed);
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> importPosBarcodeCatalogExcel(
      List<int> fileBytes, String fileName) async {
    try {
      final uri =
          Uri.parse('$baseUrl/api/pos/products/barcode-catalog/import/excel');
      final request = http.MultipartRequest('POST', uri);
      final authHeaders = _headers;
      if (authHeaders.containsKey('Authorization')) {
        request.headers['Authorization'] = authHeaders['Authorization']!;
      }
      request.files.add(http.MultipartFile.fromBytes('file', fileBytes, filename: fileName));
      final streamed = await request.send().timeout(const Duration(seconds: 180));
      final response = await http.Response.fromStream(streamed);
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> exportPosBarcodeCatalogTemplate() {
    return _getExcelExport(
      Uri.parse('$baseUrl/api/pos/products/barcode-catalog/template'),
    );
  }

  Future<Map<String, dynamic>> createPosProductQuick(
      Map<String, dynamic> body) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/api/pos/products/quick'),
            headers: _headers,
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 30));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> getPosSuppliers() async {
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/api/pos/catalog/suppliers'), headers: _headers)
          .timeout(const Duration(seconds: 30));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> createPosSupplier(String name) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/api/pos/catalog/suppliers'),
            headers: _headers,
            body: jsonEncode({'name': name, 'sortOrder': 0}),
          )
          .timeout(const Duration(seconds: 30));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> updatePosSupplier(String id, String name) async {
    try {
      final response = await http
          .put(
            Uri.parse('$baseUrl/api/pos/catalog/suppliers/$id'),
            headers: _headers,
            body: jsonEncode({'name': name, 'sortOrder': 0}),
          )
          .timeout(const Duration(seconds: 30));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> deletePosSupplier(String id) async {
    try {
      final response = await http
          .delete(Uri.parse('$baseUrl/api/pos/catalog/suppliers/$id'), headers: _headers)
          .timeout(const Duration(seconds: 30));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> getPosProductAttributes() async {
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/api/pos/catalog/attributes'), headers: _headers)
          .timeout(const Duration(seconds: 30));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> createPosProductAttribute(String name) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/api/pos/catalog/attributes'),
            headers: _headers,
            body: jsonEncode({'name': name, 'sortOrder': 0}),
          )
          .timeout(const Duration(seconds: 30));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> getPosProductUnits(String productId) async {
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/api/pos/products/$productId/units'),
              headers: _headers)
          .timeout(const Duration(seconds: 30));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> createPosProductUnit(
      String productId, Map<String, dynamic> body) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/api/pos/products/$productId/units'),
            headers: _headers,
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 30));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> updatePosProductUnit(
      String productId, String unitId, Map<String, dynamic> body) async {
    try {
      final response = await http
          .put(
            Uri.parse('$baseUrl/api/pos/products/$productId/units/$unitId'),
            headers: _headers,
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 30));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> deletePosProductUnit(
      String productId, String unitId) async {
    try {
      final response = await http
          .delete(
            Uri.parse('$baseUrl/api/pos/products/$productId/units/$unitId'),
            headers: _headers,
          )
          .timeout(const Duration(seconds: 30));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> getPosStockTransactions({
    String? productId,
    String? variantId,
    DateTime? from,
    DateTime? to,
    int page = 1,
    int pageSize = 50,
  }) async {
    try {
      final q = <String, String>{'page': '$page', 'pageSize': '$pageSize'};
      if (productId != null && productId.isNotEmpty) q['productId'] = productId;
      if (variantId != null && variantId.isNotEmpty) q['variantId'] = variantId;
      if (from != null) q['from'] = from.toIso8601String();
      if (to != null) q['to'] = to.toIso8601String();
      final uri =
          Uri.parse('$baseUrl/api/pos/stock').replace(queryParameters: q);
      final response =
          await http.get(uri, headers: _headers).timeout(const Duration(seconds: 30));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> exportPosStockTransactionsExcel({
    String? productId,
    String? variantId,
    DateTime? from,
    DateTime? to,
  }) async {
    final q = <String, String>{};
    if (productId != null && productId.isNotEmpty) q['productId'] = productId;
    if (variantId != null && variantId.isNotEmpty) q['variantId'] = variantId;
    if (from != null) q['from'] = from.toIso8601String();
    if (to != null) q['to'] = to.toIso8601String();
    return _getExcelExport(
      Uri.parse('$baseUrl/api/pos/stock/export/excel')
          .replace(queryParameters: q.isEmpty ? null : q),
    );
  }

  Future<Map<String, dynamic>> getPosStockReceipts({
    String? search,
    DateTime? from,
    DateTime? to,
    int page = 1,
    int pageSize = 50,
  }) async {
    try {
      final q = <String, String>{'page': '$page', 'pageSize': '$pageSize'};
      if (search != null && search.trim().isNotEmpty) q['search'] = search.trim();
      if (from != null) q['from'] = from.toIso8601String();
      if (to != null) q['to'] = to.toIso8601String();
      final uri = Uri.parse('$baseUrl/api/pos/stock/receipts')
          .replace(queryParameters: q);
      final response =
          await http.get(uri, headers: _headers).timeout(const Duration(seconds: 30));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> getPosStockReceipt(String id) async {
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/api/pos/stock/receipts/$id'), headers: _headers)
          .timeout(const Duration(seconds: 30));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> adjustPosStock(
      String productId, Map<String, dynamic> body) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/api/pos/stock/products/$productId/adjust'),
            headers: _headers,
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 30));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> getPosSellProducts({
    String? search,
    String? categoryId,
    bool categoryIncludeChildren = true,
    int page = 1,
    int pageSize = 500,
  }) async {
    try {
      final params = <String, String>{
        'page': page.clamp(1, 9999).toString(),
        'pageSize': pageSize.clamp(1, 500).toString(),
      };
      if (categoryIncludeChildren) {
        params['categoryIncludeChildren'] = 'true';
      }
      if (search != null && search.trim().isNotEmpty) {
        params['search'] = search.trim();
      }
      if (categoryId != null && categoryId.trim().isNotEmpty) {
        params['categoryId'] = categoryId.trim();
      }
      final uri = Uri.parse('$baseUrl/api/pos/sales/products')
          .replace(queryParameters: params);
      final response =
          await http.get(uri, headers: _headers).timeout(const Duration(seconds: 30));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> lookupPosSellItem(String code) async {
    try {
      final encoded = Uri.encodeComponent(code.trim());
      final response = await http
          .get(Uri.parse('$baseUrl/api/pos/sales/lookup?code=$encoded'),
              headers: _headers)
          .timeout(const Duration(seconds: 30));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> getPosEInvoiceSettings() async {
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/api/pos/einvoice/settings'), headers: _headers)
          .timeout(const Duration(seconds: 20));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> savePosEInvoiceSettings(
      Map<String, dynamic> body) async {
    try {
      final response = await http
          .put(
            Uri.parse('$baseUrl/api/pos/einvoice/settings'),
            headers: _headers,
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 30));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> testPosEInvoiceConnection() async {
    try {
      final response = await http
          .post(Uri.parse('$baseUrl/api/pos/einvoice/test'), headers: _headers)
          .timeout(const Duration(seconds: 30));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> issuePosEInvoice(
    String orderId, {
    Map<String, dynamic>? buyer,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/api/pos/einvoice/issue/$orderId'),
            headers: _headers,
            body: jsonEncode(buyer ?? {}),
          )
          .timeout(const Duration(seconds: 120));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> getPosEInvoiceSummary({
    DateTime? from,
    DateTime? to,
  }) async {
    try {
      final q = <String, String>{};
      if (from != null) q['from'] = from.toIso8601String();
      if (to != null) q['to'] = to.toIso8601String();
      final uri = Uri.parse('$baseUrl/api/pos/einvoice/summary')
          .replace(queryParameters: q.isEmpty ? null : q);
      final response =
          await http.get(uri, headers: _headers).timeout(const Duration(seconds: 30));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> createPosSale(Map<String, dynamic> body) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/api/pos/sales'),
            headers: _headers,
            body: jsonEncode(body),
          )
          .timeout(Duration(
            seconds: body['issueEInvoice'] == true || body['complete'] == true
                ? 120
                : 60,
          ));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> getPosSellSellers() async {
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/api/pos/sales/sellers'), headers: _headers)
          .timeout(const Duration(seconds: 30));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> getPosBankAccounts() async {
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/api/pos/sales/bank-accounts'), headers: _headers)
          .timeout(const Duration(seconds: 30));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> getPosPriceLists() async {
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/api/pos/price-lists'), headers: _headers)
          .timeout(const Duration(seconds: 30));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> createPosPriceList(Map<String, dynamic> body) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/api/pos/price-lists'),
            headers: _headers,
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 30));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> updatePosPriceList(
      String id, Map<String, dynamic> body) async {
    try {
      final response = await http
          .put(
            Uri.parse('$baseUrl/api/pos/price-lists/$id'),
            headers: _headers,
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 30));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> deletePosPriceList(String id) async {
    try {
      final response = await http
          .delete(Uri.parse('$baseUrl/api/pos/price-lists/$id'), headers: _headers)
          .timeout(const Duration(seconds: 30));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> getPosPriceListItems(String priceListId,
      {String? productId, String? search}) async {
    try {
      final q = <String, String>{};
      if (productId != null) q['productId'] = productId;
      if (search != null && search.isNotEmpty) q['search'] = search;
      final uri = Uri.parse('$baseUrl/api/pos/price-lists/$priceListId/items')
          .replace(queryParameters: q.isEmpty ? null : q);
      final response =
          await http.get(uri, headers: _headers).timeout(const Duration(seconds: 30));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> upsertPosPriceListItems(
      String priceListId, List<Map<String, dynamic>> items) async {
    try {
      final response = await http
          .put(
            Uri.parse('$baseUrl/api/pos/price-lists/$priceListId/items'),
            headers: _headers,
            body: jsonEncode({'items': items}),
          )
          .timeout(const Duration(seconds: 60));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> getPosPriceListResolvedPrices(String priceListId) async {
    try {
      final response = await http
          .get(
            Uri.parse('$baseUrl/api/pos/price-lists/$priceListId/resolved-prices'),
            headers: _headers,
          )
          .timeout(const Duration(seconds: 60));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> getPosProductByBarcode(String code) async {
    try {
      final encoded = Uri.encodeComponent(code.trim());
      final response = await http
          .get(Uri.parse('$baseUrl/api/pos/products/by-barcode/$encoded'),
              headers: _headers)
          .timeout(const Duration(seconds: 30));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> getPosComboLines(String comboProductId) async {
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/api/pos/products/$comboProductId/combo-lines'),
              headers: _headers)
          .timeout(const Duration(seconds: 30));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> savePosComboLines(
      String comboProductId, List<Map<String, dynamic>> lines) async {
    try {
      final response = await http
          .put(
            Uri.parse('$baseUrl/api/pos/products/$comboProductId/combo-lines'),
            headers: _headers,
            body: jsonEncode({'lines': lines}),
          )
          .timeout(const Duration(seconds: 30));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> createPosStockReceipt(
      Map<String, dynamic> body) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/api/pos/stock/receipts'),
            headers: _headers,
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 60));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> getPosSalesReportSummary({
    DateTime? from,
    DateTime? to,
  }) async {
    try {
      final q = <String, String>{};
      if (from != null) q['from'] = from.toIso8601String();
      if (to != null) q['to'] = to.toIso8601String();
      final uri = Uri.parse('$baseUrl/api/pos/reports/sales/summary')
          .replace(queryParameters: q.isEmpty ? null : q);
      final response =
          await http.get(uri, headers: _headers).timeout(const Duration(seconds: 30));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> getPosGoodsReportSummary({
    DateTime? from,
    DateTime? to,
    int limit = 20,
    bool includeGoods = true,
    bool includeService = true,
    bool includeCombo = true,
    bool activeOnly = true,
    bool inactiveOnly = false,
    String? inventoryStatus,
  }) async {
    try {
      final q = <String, String>{
        'limit': '$limit',
        'includeGoods': includeGoods.toString(),
        'includeService': includeService.toString(),
        'includeCombo': includeCombo.toString(),
        'activeOnly': activeOnly.toString(),
        'inactiveOnly': inactiveOnly.toString(),
      };
      if (from != null) q['from'] = from.toIso8601String();
      if (to != null) q['to'] = to.toIso8601String();
      if (inventoryStatus != null && inventoryStatus.isNotEmpty) {
        q['inventoryStatus'] = inventoryStatus;
      }
      final uri = Uri.parse('$baseUrl/api/pos/reports/goods/summary')
          .replace(queryParameters: q);
      final response =
          await http.get(uri, headers: _headers).timeout(const Duration(seconds: 30));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> getPosBusinessAnalysis({
    DateTime? from,
    DateTime? to,
  }) async {
    try {
      final q = <String, String>{};
      if (from != null) q['from'] = from.toIso8601String();
      if (to != null) q['to'] = to.toIso8601String();
      final uri = Uri.parse('$baseUrl/api/pos/reports/analysis/overview')
          .replace(queryParameters: q.isEmpty ? null : q);
      final response =
          await http.get(uri, headers: _headers).timeout(const Duration(seconds: 30));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> getPosProfitByProduct({
    DateTime? from,
    DateTime? to,
    int limit = 100,
  }) async {
    try {
      final q = <String, String>{'limit': '$limit'};
      if (from != null) q['from'] = from.toIso8601String();
      if (to != null) q['to'] = to.toIso8601String();
      final uri = Uri.parse('$baseUrl/api/pos/reports/profit/by-product')
          .replace(queryParameters: q);
      final response =
          await http.get(uri, headers: _headers).timeout(const Duration(seconds: 45));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> getPosProfitByDimension({
    DateTime? from,
    DateTime? to,
    String groupBy = 'category',
  }) async {
    try {
      final q = <String, String>{'groupBy': groupBy};
      if (from != null) q['from'] = from.toIso8601String();
      if (to != null) q['to'] = to.toIso8601String();
      final uri = Uri.parse('$baseUrl/api/pos/reports/profit/by-dimension')
          .replace(queryParameters: q);
      final response =
          await http.get(uri, headers: _headers).timeout(const Duration(seconds: 45));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> getPosStockHealthReport({
    DateTime? from,
    DateTime? to,
    String mode = 'all',
    int idleDays = 30,
  }) async {
    try {
      final q = <String, String>{'mode': mode, 'idleDays': '$idleDays', 'limit': '100'};
      if (from != null) q['from'] = from.toIso8601String();
      if (to != null) q['to'] = to.toIso8601String();
      final uri = Uri.parse('$baseUrl/api/pos/reports/stock/health')
          .replace(queryParameters: q);
      final response =
          await http.get(uri, headers: _headers).timeout(const Duration(seconds: 45));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> getPosCustomerSalesReport({
    DateTime? from,
    DateTime? to,
    String? search,
  }) async {
    try {
      final q = <String, String>{};
      if (from != null) q['from'] = from.toIso8601String();
      if (to != null) q['to'] = to.toIso8601String();
      if (search != null && search.trim().isNotEmpty) q['search'] = search.trim();
      final uri = Uri.parse('$baseUrl/api/pos/reports/customers/sales')
          .replace(queryParameters: q.isEmpty ? null : q);
      final response =
          await http.get(uri, headers: _headers).timeout(const Duration(seconds: 45));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> getPosSupplierDebtReport({
    String? search,
    bool includeZeroDebt = false,
  }) async {
    try {
      final q = <String, String>{
        'includeZeroDebt': includeZeroDebt ? 'true' : 'false',
      };
      if (search != null && search.trim().isNotEmpty) q['search'] = search.trim();
      final uri = Uri.parse('$baseUrl/api/pos/reports/supplier-debt')
          .replace(queryParameters: q);
      final response =
          await http.get(uri, headers: _headers).timeout(const Duration(seconds: 60));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> getPosPurchasesReport({
    DateTime? from,
    DateTime? to,
  }) async {
    try {
      final q = <String, String>{};
      if (from != null) q['from'] = from.toIso8601String();
      if (to != null) q['to'] = to.toIso8601String();
      final uri = Uri.parse('$baseUrl/api/pos/reports/purchases/summary')
          .replace(queryParameters: q.isEmpty ? null : q);
      final response =
          await http.get(uri, headers: _headers).timeout(const Duration(seconds: 45));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> getPosReservationsReport({
    DateTime? from,
    DateTime? to,
    String? status,
  }) async {
    try {
      final q = <String, String>{};
      if (from != null) q['from'] = from.toIso8601String();
      if (to != null) q['to'] = to.toIso8601String();
      if (status != null && status.isNotEmpty) q['status'] = status;
      final uri = Uri.parse('$baseUrl/api/pos/reports/reservations/summary')
          .replace(queryParameters: q.isEmpty ? null : q);
      final response =
          await http.get(uri, headers: _headers).timeout(const Duration(seconds: 45));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> getPosEndOfDayReport({
    DateTime? from,
    DateTime? to,
    String? staffEmail,
    String? soldByEmployeeId,
    String filterBy = 'soldBy',
    bool includeProductDetail = true,
    bool includeTransactions = false,
  }) async {
    try {
      final q = <String, String>{
        'filterBy': filterBy,
        'includeProductDetail': includeProductDetail.toString(),
        'includeTransactions': includeTransactions.toString(),
      };
      if (from != null) q['from'] = from.toIso8601String();
      if (to != null) q['to'] = to.toIso8601String();
      if (staffEmail != null && staffEmail.isNotEmpty) q['staffEmail'] = staffEmail;
      if (soldByEmployeeId != null && soldByEmployeeId.isNotEmpty) {
        q['soldByEmployeeId'] = soldByEmployeeId;
      }
      final uri = Uri.parse('$baseUrl/api/pos/reports/end-of-day')
          .replace(queryParameters: q);
      final response =
          await http.get(uri, headers: _headers).timeout(const Duration(seconds: 45));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> getPosCashbookReport({
    DateTime? from,
    DateTime? to,
  }) async {
    try {
      final q = <String, String>{};
      if (from != null) q['from'] = from.toIso8601String();
      if (to != null) q['to'] = to.toIso8601String();
      final uri = Uri.parse('$baseUrl/api/pos/reports/cashbook/summary')
          .replace(queryParameters: q.isEmpty ? null : q);
      final response =
          await http.get(uri, headers: _headers).timeout(const Duration(seconds: 45));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> getPosExpenseReport({
    DateTime? from,
    DateTime? to,
  }) async {
    try {
      final q = <String, String>{};
      if (from != null) q['from'] = from.toIso8601String();
      if (to != null) q['to'] = to.toIso8601String();
      final uri = Uri.parse('$baseUrl/api/pos/reports/expenses/summary')
          .replace(queryParameters: q.isEmpty ? null : q);
      final response =
          await http.get(uri, headers: _headers).timeout(const Duration(seconds: 45));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> getPosVoucherReport({
    DateTime? from,
    DateTime? to,
  }) async {
    try {
      final q = <String, String>{};
      if (from != null) q['from'] = from.toIso8601String();
      if (to != null) q['to'] = to.toIso8601String();
      final uri = Uri.parse('$baseUrl/api/pos/reports/vouchers/summary')
          .replace(queryParameters: q.isEmpty ? null : q);
      final response =
          await http.get(uri, headers: _headers).timeout(const Duration(seconds: 45));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> getPosPnlReport({
    DateTime? from,
    DateTime? to,
  }) async {
    try {
      final q = <String, String>{};
      if (from != null) q['from'] = from.toIso8601String();
      if (to != null) q['to'] = to.toIso8601String();
      final uri = Uri.parse('$baseUrl/api/pos/reports/pnl/summary')
          .replace(queryParameters: q.isEmpty ? null : q);
      final response =
          await http.get(uri, headers: _headers).timeout(const Duration(seconds: 45));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> getPosEndOfDayStaff({
    DateTime? from,
    DateTime? to,
    String filterBy = 'soldBy',
  }) async {
    try {
      final q = <String, String>{'filterBy': filterBy};
      if (from != null) q['from'] = from.toIso8601String();
      if (to != null) q['to'] = to.toIso8601String();
      final uri = Uri.parse('$baseUrl/api/pos/reports/end-of-day/staff')
          .replace(queryParameters: q);
      final response =
          await http.get(uri, headers: _headers).timeout(const Duration(seconds: 30));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> exportPosSalesReportExcel({
    DateTime? from,
    DateTime? to,
  }) async {
    final q = <String, String>{};
    if (from != null) q['from'] = from.toIso8601String();
    if (to != null) q['to'] = to.toIso8601String();
    return _getExcelExport(
      Uri.parse('$baseUrl/api/pos/reports/sales/export/excel')
          .replace(queryParameters: q.isEmpty ? null : q),
    );
  }

  Future<Map<String, dynamic>> createPosStockIssue(
      Map<String, dynamic> body) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/api/pos/stock/issues'),
            headers: _headers,
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 60));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> getPosStockIssues({
    String? search,
    int page = 1,
    int pageSize = 50,
  }) async {
    try {
      final q = <String, String>{'page': '$page', 'pageSize': '$pageSize'};
      if (search != null && search.trim().isNotEmpty) q['search'] = search.trim();
      final uri = Uri.parse('$baseUrl/api/pos/stock/issues')
          .replace(queryParameters: q);
      final response =
          await http.get(uri, headers: _headers).timeout(const Duration(seconds: 30));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> getPosStockIssue(String id) async {
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/api/pos/stock/issues/$id'), headers: _headers)
          .timeout(const Duration(seconds: 30));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> createPosStockCount(
      Map<String, dynamic> body) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/api/pos/stock/counts'),
            headers: _headers,
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 120));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> updatePosStockCount(
      String id, Map<String, dynamic> body) async {
    try {
      final response = await http
          .put(
            Uri.parse('$baseUrl/api/pos/stock/counts/$id'),
            headers: _headers,
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 60));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> addPosStockCountLines(
      String id, List<Map<String, dynamic>> lines) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/api/pos/stock/counts/$id/lines/add'),
            headers: _headers,
            body: jsonEncode(lines),
          )
          .timeout(const Duration(seconds: 60));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> removePosStockCountLine(
      String countId, String lineId) async {
    try {
      final response = await http
          .delete(
            Uri.parse('$baseUrl/api/pos/stock/counts/$countId/lines/$lineId'),
            headers: _headers,
          )
          .timeout(const Duration(seconds: 30));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> copyPosStockCount(String id) async {
    try {
      final response = await http
          .post(Uri.parse('$baseUrl/api/pos/stock/counts/$id/copy'),
              headers: _headers)
          .timeout(const Duration(seconds: 60));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> getPosStockCounts({
    String? search,
    String? status,
    List<String>? statuses,
    String? createdBy,
    DateTime? from,
    DateTime? to,
    int page = 1,
    int pageSize = 50,
  }) async {
    try {
      final q = <String, String>{'page': '$page', 'pageSize': '$pageSize'};
      if (search != null && search.trim().isNotEmpty) q['search'] = search.trim();
      if (statuses != null && statuses.isNotEmpty) {
        q['statuses'] = statuses.join(',');
      } else if (status != null && status.isNotEmpty) {
        q['status'] = status;
      }
      if (createdBy != null && createdBy.trim().isNotEmpty) {
        q['createdBy'] = createdBy.trim();
      }
      if (from != null) q['from'] = from.toIso8601String();
      if (to != null) q['to'] = to.toIso8601String();
      final uri = Uri.parse('$baseUrl/api/pos/stock/counts')
          .replace(queryParameters: q);
      final response =
          await http.get(uri, headers: _headers).timeout(const Duration(seconds: 30));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> getPosStockCount(String id) async {
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/api/pos/stock/counts/$id'), headers: _headers)
          .timeout(const Duration(seconds: 30));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> updatePosStockCountLines(
      String id, List<Map<String, dynamic>> lines) async {
    try {
      final response = await http
          .put(
            Uri.parse('$baseUrl/api/pos/stock/counts/$id/lines'),
            headers: _headers,
            body: jsonEncode({'lines': lines}),
          )
          .timeout(const Duration(seconds: 60));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> completePosStockCount(String id) async {
    try {
      final response = await http
          .post(Uri.parse('$baseUrl/api/pos/stock/counts/$id/complete'),
              headers: _headers)
          .timeout(const Duration(seconds: 120));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> cancelPosStockCount(String id) async {
    try {
      final response = await http
          .post(Uri.parse('$baseUrl/api/pos/stock/counts/$id/cancel'),
              headers: _headers)
          .timeout(const Duration(seconds: 120));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> deletePosStockCount(String id) async {
    try {
      final response = await http
          .delete(Uri.parse('$baseUrl/api/pos/stock/counts/$id'),
              headers: _headers)
          .timeout(const Duration(seconds: 30));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> createPosStockIssueDoc(String kind,
      [Map<String, dynamic>? body]) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/api/pos/stock/$kind'),
            headers: _headers,
            body: jsonEncode(body ?? {}),
          )
          .timeout(const Duration(seconds: 60));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> getPosStockIssueDocs(
    String kind, {
    String? search,
    String? status,
    List<String>? statuses,
    String? createdBy,
    String? issuedBy,
    DateTime? from,
    DateTime? to,
    int page = 1,
    int pageSize = 50,
  }) async {
    try {
      final q = <String, String>{'page': '$page', 'pageSize': '$pageSize'};
      if (search != null && search.trim().isNotEmpty) q['search'] = search.trim();
      if (statuses != null && statuses.isNotEmpty) {
        q['statuses'] = statuses.join(',');
      } else if (status != null && status.isNotEmpty) {
        q['status'] = status;
      }
      if (createdBy != null && createdBy.trim().isNotEmpty) {
        q['createdBy'] = createdBy.trim();
      }
      if (issuedBy != null && issuedBy.trim().isNotEmpty) {
        q['issuedBy'] = issuedBy.trim();
      }
      if (from != null) q['from'] = from.toIso8601String();
      if (to != null) q['to'] = to.toIso8601String();
      final uri = Uri.parse('$baseUrl/api/pos/stock/$kind')
          .replace(queryParameters: q);
      final response =
          await http.get(uri, headers: _headers).timeout(const Duration(seconds: 30));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> getPosStockIssueDoc(String kind, String id) async {
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/api/pos/stock/$kind/$id'), headers: _headers)
          .timeout(const Duration(seconds: 30));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> updatePosStockIssueDoc(
      String kind, String id, Map<String, dynamic> body) async {
    try {
      final response = await http
          .put(
            Uri.parse('$baseUrl/api/pos/stock/$kind/$id'),
            headers: _headers,
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 60));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> addPosStockIssueDocLines(
      String kind, String id, List<Map<String, dynamic>> lines) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/api/pos/stock/$kind/$id/lines/add'),
            headers: _headers,
            body: jsonEncode(lines),
          )
          .timeout(const Duration(seconds: 60));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> removePosStockIssueDocLine(
      String kind, String issueId, String lineId) async {
    try {
      final response = await http
          .delete(
            Uri.parse('$baseUrl/api/pos/stock/$kind/$issueId/lines/$lineId'),
            headers: _headers,
          )
          .timeout(const Duration(seconds: 30));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> updatePosStockIssueDocLines(
      String kind, String id, List<Map<String, dynamic>> lines) async {
    try {
      final response = await http
          .put(
            Uri.parse('$baseUrl/api/pos/stock/$kind/$id/lines'),
            headers: _headers,
            body: jsonEncode({'lines': lines}),
          )
          .timeout(const Duration(seconds: 60));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> completePosStockIssueDoc(String kind, String id) async {
    try {
      final response = await http
          .post(Uri.parse('$baseUrl/api/pos/stock/$kind/$id/complete'),
              headers: _headers)
          .timeout(const Duration(seconds: 120));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> cancelPosStockIssueDoc(String kind, String id) async {
    try {
      final response = await http
          .post(Uri.parse('$baseUrl/api/pos/stock/$kind/$id/cancel'),
              headers: _headers)
          .timeout(const Duration(seconds: 120));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> deletePosStockIssueDoc(String kind, String id) async {
    try {
      final response = await http
          .delete(Uri.parse('$baseUrl/api/pos/stock/$kind/$id'),
              headers: _headers)
          .timeout(const Duration(seconds: 30));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> copyPosStockIssueDoc(String kind, String id) async {
    try {
      final response = await http
          .post(Uri.parse('$baseUrl/api/pos/stock/$kind/$id/copy'),
              headers: _headers)
          .timeout(const Duration(seconds: 60));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> getPosStockReportSummary() async {
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/api/pos/reports/stock/summary'),
              headers: _headers)
          .timeout(const Duration(seconds: 30));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> getPosStockReportProducts({
    String? search,
    String? filter,
    int page = 1,
    int pageSize = 50,
  }) async {
    try {
      final q = <String, String>{'page': '$page', 'pageSize': '$pageSize'};
      if (search != null && search.trim().isNotEmpty) q['search'] = search.trim();
      if (filter != null && filter.isNotEmpty) q['filter'] = filter;
      final uri = Uri.parse('$baseUrl/api/pos/reports/stock/products')
          .replace(queryParameters: q);
      final response =
          await http.get(uri, headers: _headers).timeout(const Duration(seconds: 30));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> getPosStockLotsExpiringSummary({int days = 30}) async {
    try {
      final uri = Uri.parse('$baseUrl/api/pos/stock/lots/expiring/summary')
          .replace(queryParameters: {'days': '$days'});
      final response =
          await http.get(uri, headers: _headers).timeout(const Duration(seconds: 20));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> getPosStockLotsByProduct(
    String productId, {
    String? variantId,
  }) async {
    try {
      final q = <String, String>{};
      if (variantId != null && variantId.isNotEmpty) q['variantId'] = variantId;
      final uri = Uri.parse('$baseUrl/api/pos/stock/lots/by-product/$productId')
          .replace(queryParameters: q.isEmpty ? null : q);
      final response =
          await http.get(uri, headers: _headers).timeout(const Duration(seconds: 15));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> getPosStockLotReportSummary() async {
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/api/pos/reports/stock/lots/summary'),
              headers: _headers)
          .timeout(const Duration(seconds: 30));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> getPosStockLotReport({
    String? search,
    String? filter,
    int page = 1,
    int pageSize = 50,
  }) async {
    try {
      final q = <String, String>{'page': '$page', 'pageSize': '$pageSize'};
      if (search != null && search.trim().isNotEmpty) q['search'] = search.trim();
      if (filter != null && filter.isNotEmpty) q['filter'] = filter;
      final uri = Uri.parse('$baseUrl/api/pos/reports/stock/lots')
          .replace(queryParameters: q);
      final response =
          await http.get(uri, headers: _headers).timeout(const Duration(seconds: 30));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> exportPosStockReportExcel({String? search}) async {
    final q = <String, String>{};
    if (search != null && search.trim().isNotEmpty) q['search'] = search.trim();
    return _getExcelExport(
      Uri.parse('$baseUrl/api/pos/reports/stock/export/excel')
          .replace(queryParameters: q.isEmpty ? null : q),
    );
  }

  // ── POS Purchase (KiotViet Mua hàng) ──

  Future<Map<String, dynamic>> getPosPurchaseReceipts({
    String? search,
    String? status,
    List<String>? statuses,
    String? supplierId,
    String? createdBy,
    String? importedBy,
    String? inputInvoiceNo,
    DateTime? from,
    DateTime? to,
    int page = 1,
    int pageSize = 50,
  }) async {
    try {
      final q = <String, String>{'page': '$page', 'pageSize': '$pageSize'};
      if (search != null && search.trim().isNotEmpty) q['search'] = search.trim();
      if (statuses != null && statuses.isNotEmpty) {
        q['statuses'] = statuses.join(',');
      } else if (status != null && status.isNotEmpty) {
        q['status'] = status;
      }
      if (supplierId != null && supplierId.isNotEmpty) q['supplierId'] = supplierId;
      if (createdBy != null && createdBy.trim().isNotEmpty) {
        q['createdBy'] = createdBy.trim();
      }
      if (importedBy != null && importedBy.trim().isNotEmpty) {
        q['importedBy'] = importedBy.trim();
      }
      if (inputInvoiceNo != null && inputInvoiceNo.trim().isNotEmpty) {
        q['inputInvoiceNo'] = inputInvoiceNo.trim();
      }
      if (from != null) q['from'] = from.toIso8601String();
      if (to != null) q['to'] = to.toIso8601String();
      final uri = Uri.parse('$baseUrl/api/pos/purchase/receipts')
          .replace(queryParameters: q);
      final response =
          await http.get(uri, headers: _headers).timeout(const Duration(seconds: 30));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> getPosPurchaseReceipt(String id) async {
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/api/pos/purchase/receipts/$id'), headers: _headers)
          .timeout(const Duration(seconds: 30));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> createPosPurchaseReceipt(Map<String, dynamic> body) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/api/pos/purchase/receipts'),
            headers: _headers,
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 60));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> updatePosPurchaseReceipt(
      String id, Map<String, dynamic> body) async {
    try {
      final response = await http
          .put(
            Uri.parse('$baseUrl/api/pos/purchase/receipts/$id'),
            headers: _headers,
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 60));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> completePosPurchaseReceipt(String id) async {
    try {
      final response = await http
          .post(Uri.parse('$baseUrl/api/pos/purchase/receipts/$id/complete'),
              headers: _headers)
          .timeout(const Duration(seconds: 60));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> copyPosPurchaseReceipt(String id) async {
    try {
      final response = await http
          .post(Uri.parse('$baseUrl/api/pos/purchase/receipts/$id/copy'),
              headers: _headers)
          .timeout(const Duration(seconds: 60));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> cancelPosPurchaseReceipt(String id) async {
    try {
      final response = await http
          .post(Uri.parse('$baseUrl/api/pos/purchase/receipts/$id/cancel'),
              headers: _headers)
          .timeout(const Duration(seconds: 120));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> deletePosPurchaseReceipt(String id) async {
    try {
      final response = await http
          .delete(Uri.parse('$baseUrl/api/pos/purchase/receipts/$id'),
              headers: _headers)
          .timeout(const Duration(seconds: 30));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> getPosPurchaseReceiptPayments(String id) async {
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/api/pos/purchase/receipts/$id/payments'),
              headers: _headers)
          .timeout(const Duration(seconds: 30));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> createPosPurchaseReceiptPayment(
    String id,
    Map<String, dynamic> body,
  ) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/api/pos/purchase/receipts/$id/payments'),
            headers: _headers,
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 30));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> getPosPurchaseReturns({
    String? search,
    String? status,
    List<String>? statuses,
    String? supplierId,
    String? createdBy,
    String? returnedBy,
    DateTime? from,
    DateTime? to,
    int page = 1,
    int pageSize = 50,
  }) async {
    try {
      final q = <String, String>{'page': '$page', 'pageSize': '$pageSize'};
      if (search != null && search.trim().isNotEmpty) q['search'] = search.trim();
      if (statuses != null && statuses.isNotEmpty) {
        q['statuses'] = statuses.join(',');
      } else if (status != null && status.isNotEmpty) {
        q['status'] = status;
      }
      if (supplierId != null && supplierId.isNotEmpty) q['supplierId'] = supplierId;
      if (createdBy != null && createdBy.trim().isNotEmpty) {
        q['createdBy'] = createdBy.trim();
      }
      if (returnedBy != null && returnedBy.trim().isNotEmpty) {
        q['returnedBy'] = returnedBy.trim();
      }
      if (from != null) q['from'] = from.toIso8601String();
      if (to != null) q['to'] = to.toIso8601String();
      final uri = Uri.parse('$baseUrl/api/pos/purchase/returns')
          .replace(queryParameters: q);
      final response =
          await http.get(uri, headers: _headers).timeout(const Duration(seconds: 30));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> getPosPurchaseReturn(String id) async {
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/api/pos/purchase/returns/$id'), headers: _headers)
          .timeout(const Duration(seconds: 30));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> getPosPurchaseReturnFromReceipt(String receiptId) async {
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/api/pos/purchase/returns/from-receipt/$receiptId'),
              headers: _headers)
          .timeout(const Duration(seconds: 30));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> createPosPurchaseReturn(Map<String, dynamic> body) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/api/pos/purchase/returns'),
            headers: _headers,
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 60));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> updatePosPurchaseReturn(
      String id, Map<String, dynamic> body) async {
    try {
      final response = await http
          .put(
            Uri.parse('$baseUrl/api/pos/purchase/returns/$id'),
            headers: _headers,
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 60));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> completePosPurchaseReturn(String id) async {
    try {
      final response = await http
          .post(Uri.parse('$baseUrl/api/pos/purchase/returns/$id/complete'),
              headers: _headers)
          .timeout(const Duration(seconds: 60));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> copyPosPurchaseReturn(String id) async {
    try {
      final response = await http
          .post(Uri.parse('$baseUrl/api/pos/purchase/returns/$id/copy'),
              headers: _headers)
          .timeout(const Duration(seconds: 60));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> cancelPosPurchaseReturn(String id) async {
    try {
      final response = await http
          .post(Uri.parse('$baseUrl/api/pos/purchase/returns/$id/cancel'),
              headers: _headers)
          .timeout(const Duration(seconds: 120));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> deletePosPurchaseReturn(String id) async {
    try {
      final response = await http
          .delete(Uri.parse('$baseUrl/api/pos/purchase/returns/$id'),
              headers: _headers)
          .timeout(const Duration(seconds: 30));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> getPosPurchaseSuppliers({
    String? search,
    String? groupId,
    double? debtFrom,
    double? debtTo,
    bool? activeOnly,
    int page = 1,
    int pageSize = 50,
  }) async {
    try {
      final q = <String, String>{'page': '$page', 'pageSize': '$pageSize'};
      if (search != null && search.trim().isNotEmpty) q['search'] = search.trim();
      if (groupId != null && groupId.isNotEmpty) q['groupId'] = groupId;
      if (debtFrom != null) q['debtFrom'] = '$debtFrom';
      if (debtTo != null) q['debtTo'] = '$debtTo';
      if (activeOnly != null) q['activeOnly'] = activeOnly ? 'true' : 'false';
      final uri = Uri.parse('$baseUrl/api/pos/purchase/suppliers')
          .replace(queryParameters: q);
      final response =
          await http.get(uri, headers: _headers).timeout(const Duration(seconds: 30));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> getPosPurchaseSupplier(String id) async {
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/api/pos/purchase/suppliers/$id'), headers: _headers)
          .timeout(const Duration(seconds: 30));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> createPosPurchaseSupplier(Map<String, dynamic> body) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/api/pos/purchase/suppliers'),
            headers: _headers,
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 30));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> updatePosPurchaseSupplier(
      String id, Map<String, dynamic> body) async {
    try {
      final response = await http
          .put(
            Uri.parse('$baseUrl/api/pos/purchase/suppliers/$id'),
            headers: _headers,
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 30));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> getPosPurchaseSupplierGroups() async {
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/api/pos/purchase/suppliers/groups'),
              headers: _headers)
          .timeout(const Duration(seconds: 30));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> createPosPurchaseSupplierGroup(String name) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/api/pos/purchase/suppliers/groups'),
            headers: _headers,
            body: jsonEncode({'name': name}),
          )
          .timeout(const Duration(seconds: 30));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> getPosPurchaseSupplierHistory(String id) async {
    try {
      final response = await http
          .get(
            Uri.parse('$baseUrl/api/pos/purchase/suppliers/$id/history'),
            headers: _headers,
          )
          .timeout(const Duration(seconds: 30));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> deactivatePosPurchaseSupplier(String id) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/api/pos/purchase/suppliers/$id/deactivate'),
            headers: _headers,
          )
          .timeout(const Duration(seconds: 30));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> activatePosPurchaseSupplier(String id) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/api/pos/purchase/suppliers/$id/activate'),
            headers: _headers,
          )
          .timeout(const Duration(seconds: 30));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> deletePosPurchaseSupplier(String id) async {
    try {
      final response = await http
          .delete(
            Uri.parse('$baseUrl/api/pos/purchase/suppliers/$id'),
            headers: _headers,
          )
          .timeout(const Duration(seconds: 30));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> getPosSale(
    String id, {
    String? deviceId,
    String? deviceName,
  }) async {
    try {
      final q = <String, String>{};
      if (deviceId != null && deviceId.isNotEmpty) q['deviceId'] = deviceId;
      if (deviceName != null && deviceName.isNotEmpty) {
        q['deviceName'] = deviceName;
      }
      final uri = Uri.parse('$baseUrl/api/pos/sales/$id').replace(
        queryParameters: q.isEmpty ? null : q,
      );
      final response =
          await http.get(uri, headers: _headers).timeout(const Duration(seconds: 30));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  /// Ghi nhận lần in — tăng PrintCount, trả daily context cho mẫu in.
  Future<Map<String, dynamic>> recordPosSalePrint(String id) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/api/pos/sales/$id/record-print'),
            headers: _headers,
          )
          .timeout(const Duration(seconds: 30));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> getPosSales({
    String? search,
    String? status,
    List<String>? statuses,
    String? paymentMethod,
    String? customerName,
    String? createdBy,
    String? soldBy,
    bool? isDelivery,
    String? deliveryStatus,
    String? customerId,
    DateTime? from,
    DateTime? to,
    int page = 1,
    int pageSize = 50,
  }) async {
    try {
      final q = <String, String>{'page': '$page', 'pageSize': '$pageSize'};
      if (search != null && search.trim().isNotEmpty) q['search'] = search.trim();
      if (statuses != null && statuses.isNotEmpty) {
        q['statuses'] = statuses.join(',');
      } else if (status != null && status.isNotEmpty) {
        q['status'] = status;
      }
      if (paymentMethod != null && paymentMethod.isNotEmpty) {
        q['paymentMethod'] = paymentMethod;
      }
      if (customerName != null && customerName.trim().isNotEmpty) {
        q['customerName'] = customerName.trim();
      }
      if (createdBy != null && createdBy.trim().isNotEmpty) {
        q['createdBy'] = createdBy.trim();
      }
      if (soldBy != null && soldBy.trim().isNotEmpty) {
        q['soldBy'] = soldBy.trim();
      }
      if (isDelivery != null) q['isDelivery'] = isDelivery.toString();
      if (deliveryStatus != null && deliveryStatus.trim().isNotEmpty) {
        q['deliveryStatus'] = deliveryStatus.trim();
      }
      if (customerId != null && customerId.isNotEmpty) q['customerId'] = customerId;
      if (from != null) q['from'] = from.toIso8601String();
      if (to != null) q['to'] = to.toIso8601String();
      final uri =
          Uri.parse('$baseUrl/api/pos/sales').replace(queryParameters: q);
      final response =
          await http.get(uri, headers: _headers).timeout(const Duration(seconds: 30));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> cancelPosSale(
    String id, {
    String? reason,
    String? detailNote,
    String? deviceName,
  }) async {
    try {
      final body = <String, dynamic>{
        if (reason != null && reason.isNotEmpty) 'reason': reason,
        if (detailNote != null && detailNote.isNotEmpty) 'detailNote': detailNote,
        if (deviceName != null && deviceName.isNotEmpty) 'deviceName': deviceName,
      };
      final response = await http
          .post(
            Uri.parse('$baseUrl/api/pos/sales/$id/cancel'),
            headers: _headers,
            body: body.isEmpty ? null : jsonEncode(body),
          )
          .timeout(const Duration(seconds: 60));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> deletePosSale(String id) async {
    try {
      final response = await http
          .delete(Uri.parse('$baseUrl/api/pos/sales/$id'), headers: _headers)
          .timeout(const Duration(seconds: 30));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> copyPosSale(String id) async {
    try {
      final response = await http
          .post(Uri.parse('$baseUrl/api/pos/sales/$id/copy'), headers: _headers)
          .timeout(const Duration(seconds: 60));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> getPosSalePayments(String id) async {
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/api/pos/sales/$id/payments'), headers: _headers)
          .timeout(const Duration(seconds: 30));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> getPosSaleReturns(String id) async {
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/api/pos/sales/$id/returns'), headers: _headers)
          .timeout(const Duration(seconds: 30));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> getPosSaleReturnHistory({
    String? search,
    int page = 1,
    int pageSize = 50,
  }) async {
    try {
      final q = <String, String>{'page': '$page', 'pageSize': '$pageSize'};
      if (search != null && search.trim().isNotEmpty) q['search'] = search.trim();
      final uri = Uri.parse('$baseUrl/api/pos/sales/return-history')
          .replace(queryParameters: q);
      final response =
          await http.get(uri, headers: _headers).timeout(const Duration(seconds: 30));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> returnPosSale(
      String id, Map<String, dynamic> body) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/api/pos/sales/$id/return'),
            headers: _headers,
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 60));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> cancelPosSaleReturn(
      String orderId, String returnNo) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/api/pos/sales/$orderId/returns/cancel'),
            headers: _headers,
            body: jsonEncode({'returnNo': returnNo}),
          )
          .timeout(const Duration(seconds: 60));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> updatePosSale(
      String id, Map<String, dynamic> body) async {
    try {
      final response = await http
          .put(
            Uri.parse('$baseUrl/api/pos/sales/$id'),
            headers: _headers,
            body: jsonEncode(body),
          )
          .timeout(Duration(
            seconds: body['issueEInvoice'] == true || body['complete'] == true
                ? 120
                : 60,
          ));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> completePosSale(String id) async {
    try {
      final response = await http
          .post(Uri.parse('$baseUrl/api/pos/sales/$id/complete'), headers: _headers)
          .timeout(const Duration(seconds: 120));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  /// Claim / renew / force-take khóa đơn tạm.
  Future<Map<String, dynamic>> lockPosSaleDraft(
    String id, {
    required String deviceId,
    required String deviceName,
    bool force = false,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/api/pos/sales/$id/lock'),
            headers: _headers,
            body: jsonEncode({
              'deviceId': deviceId,
              'deviceName': deviceName,
              'force': force,
            }),
          )
          .timeout(const Duration(seconds: 30));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> heartbeatPosSaleDraftLock(
    String id, {
    required String deviceId,
    required String deviceName,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/api/pos/sales/$id/lock/heartbeat'),
            headers: _headers,
            body: jsonEncode({
              'deviceId': deviceId,
              'deviceName': deviceName,
            }),
          )
          .timeout(const Duration(seconds: 20));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> unlockPosSaleDraft(
    String id, {
    required String deviceId,
    required String deviceName,
    Duration timeout = const Duration(seconds: 20),
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/api/pos/sales/$id/unlock'),
            headers: _headers,
            body: jsonEncode({
              'deviceId': deviceId,
              'deviceName': deviceName,
            }),
          )
          .timeout(timeout);
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  /// Slot hóa đơn động (mặc định 3, thêm/xóa được).
  /// [pruneEmpty]: chỉ bật lúc mở màn bán — thu gọn HĐ trống thừa (cũ 8 → 3).
  Future<Map<String, dynamic>> getPosInvoiceSlots({
    int count = 3,
    bool pruneEmpty = false,
    String? deviceId,
    String? deviceName,
  }) async {
    try {
      final q = <String, String>{'count': '$count'};
      if (pruneEmpty) q['pruneEmpty'] = 'true';
      if (deviceId != null && deviceId.isNotEmpty) q['deviceId'] = deviceId;
      if (deviceName != null && deviceName.isNotEmpty) {
        q['deviceName'] = deviceName;
      }
      final uri = Uri.parse('$baseUrl/api/pos/sales/invoice-slots')
          .replace(queryParameters: q);
      final response =
          await http.get(uri, headers: _headers).timeout(const Duration(seconds: 30));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> addPosInvoiceSlot({
    String? deviceId,
    String? deviceName,
  }) async {
    try {
      final q = <String, String>{};
      if (deviceId != null && deviceId.isNotEmpty) q['deviceId'] = deviceId;
      if (deviceName != null && deviceName.isNotEmpty) {
        q['deviceName'] = deviceName;
      }
      final uri = Uri.parse('$baseUrl/api/pos/sales/invoice-slots')
          .replace(queryParameters: q.isEmpty ? null : q);
      final response = await http
          .post(uri, headers: _headers)
          .timeout(const Duration(seconds: 30));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> removePosInvoiceSlot(
    int slot, {
    bool force = false,
    String? deviceId,
    String? deviceName,
  }) async {
    try {
      final q = <String, String>{'force': '$force'};
      if (deviceId != null && deviceId.isNotEmpty) q['deviceId'] = deviceId;
      if (deviceName != null && deviceName.isNotEmpty) {
        q['deviceName'] = deviceName;
      }
      final uri = Uri.parse('$baseUrl/api/pos/sales/invoice-slots/$slot')
          .replace(queryParameters: q);
      final response = await http
          .delete(uri, headers: _headers)
          .timeout(const Duration(seconds: 30));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> lookupPosWarranty({
    String? serial,
    String? phone,
    String? orderNo,
  }) async {
    try {
      final q = <String, String>{};
      if (serial != null && serial.trim().isNotEmpty) q['serial'] = serial.trim();
      if (phone != null && phone.trim().isNotEmpty) q['phone'] = phone.trim();
      if (orderNo != null && orderNo.trim().isNotEmpty) q['orderNo'] = orderNo.trim();
      final uri = Uri.parse('$baseUrl/api/pos/warranty/lookup').replace(queryParameters: q);
      final response = await http.get(uri, headers: _headers).timeout(const Duration(seconds: 30));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> getPosWarrantyExpiring({
    int days = 30,
    bool includeExpired = false,
  }) async {
    try {
      final uri = Uri.parse('$baseUrl/api/pos/warranty/expiring').replace(
        queryParameters: {
          'days': '$days',
          'includeExpired': includeExpired.toString(),
        },
      );
      final response = await http.get(uri, headers: _headers).timeout(const Duration(seconds: 30));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> exportPosSalesExcel({
    String? search,
    List<String>? statuses,
    String? paymentMethod,
    bool? isDelivery,
    DateTime? from,
    DateTime? to,
  }) async {
    final q = <String, String>{};
    if (search != null && search.trim().isNotEmpty) q['search'] = search.trim();
    if (statuses != null && statuses.isNotEmpty) q['statuses'] = statuses.join(',');
    if (paymentMethod != null && paymentMethod.isNotEmpty) {
      q['paymentMethod'] = paymentMethod;
    }
    if (isDelivery != null) q['isDelivery'] = isDelivery.toString();
    if (from != null) q['from'] = from.toIso8601String();
    if (to != null) q['to'] = to.toIso8601String();
    return _getExcelExport(
      Uri.parse('$baseUrl/api/pos/sales/export/excel')
          .replace(queryParameters: q.isEmpty ? null : q),
      timeout: const Duration(seconds: 90),
    );
  }

  Future<Map<String, dynamic>> getPosCustomers({
    String? search,
    double? debtFrom,
    double? debtTo,
    bool? hasDebt,
    int page = 1,
    int pageSize = 50,
  }) async {
    try {
      final q = <String, String>{'page': '$page', 'pageSize': '$pageSize'};
      if (search != null && search.trim().isNotEmpty) q['search'] = search.trim();
      if (debtFrom != null) q['debtFrom'] = '$debtFrom';
      if (debtTo != null) q['debtTo'] = '$debtTo';
      if (hasDebt == true) q['hasDebt'] = 'true';
      final uri = Uri.parse('$baseUrl/api/pos/customers')
          .replace(queryParameters: q);
      final response =
          await http.get(uri, headers: _headers).timeout(const Duration(seconds: 30));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> getPosCustomerPayments(String customerId) async {
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/api/pos/customers/$customerId/payments'),
              headers: _headers)
          .timeout(const Duration(seconds: 30));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> createPosCustomerPayment(
    String customerId,
    Map<String, dynamic> body,
  ) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/api/pos/customers/$customerId/payments'),
            headers: _headers,
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 30));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> getPosCustomerPointHistory(
    String customerId, {
    int page = 1,
    int pageSize = 50,
  }) async {
    try {
      final uri = Uri.parse('$baseUrl/api/pos/customers/$customerId/points')
          .replace(queryParameters: {'page': '$page', 'pageSize': '$pageSize'});
      final response =
          await http.get(uri, headers: _headers).timeout(const Duration(seconds: 30));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> getPosCustomerHistory(String customerId,
      {int take = 30}) async {
    try {
      final uri = Uri.parse('$baseUrl/api/pos/customers/$customerId/history')
          .replace(queryParameters: {'take': '$take'});
      final response =
          await http.get(uri, headers: _headers).timeout(const Duration(seconds: 30));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> getPosCustomerDebtReport({
    String? search,
    double? debtFrom,
    double? debtTo,
    bool includeZeroDebt = false,
  }) async {
    try {
      final q = <String, String>{'includeZeroDebt': includeZeroDebt ? 'true' : 'false'};
      if (search != null && search.trim().isNotEmpty) q['search'] = search.trim();
      if (debtFrom != null) q['debtFrom'] = '$debtFrom';
      if (debtTo != null) q['debtTo'] = '$debtTo';
      final uri = Uri.parse('$baseUrl/api/pos/reports/customer-debt')
          .replace(queryParameters: q);
      final response =
          await http.get(uri, headers: _headers).timeout(const Duration(seconds: 60));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> getPosVouchers({
    String? search,
    bool activeOnly = true,
    int page = 1,
    int pageSize = 50,
  }) async {
    try {
      final q = <String, String>{
        'page': '$page',
        'pageSize': '$pageSize',
        'activeOnly': activeOnly ? 'true' : 'false',
      };
      if (search != null && search.trim().isNotEmpty) q['search'] = search.trim();
      final uri = Uri.parse('$baseUrl/api/pos/vouchers').replace(queryParameters: q);
      final response =
          await http.get(uri, headers: _headers).timeout(const Duration(seconds: 30));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> validatePosVoucher({
    required String code,
    required double orderAmount,
    String? customerId,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/api/pos/vouchers/validate'),
            headers: _headers,
            body: jsonEncode({
              'code': code,
              'orderAmount': orderAmount,
              if (customerId != null && customerId.isNotEmpty) 'customerId': customerId,
            }),
          )
          .timeout(const Duration(seconds: 30));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> createPosVoucher(Map<String, dynamic> body) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/api/pos/vouchers'),
            headers: _headers,
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 30));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> updatePosVoucher(
      String id, Map<String, dynamic> body) async {
    try {
      final response = await http
          .put(
            Uri.parse('$baseUrl/api/pos/vouchers/$id'),
            headers: _headers,
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 30));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> deletePosVoucher(String id) async {
    try {
      final response = await http
          .delete(Uri.parse('$baseUrl/api/pos/vouchers/$id'), headers: _headers)
          .timeout(const Duration(seconds: 30));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> createPosCustomer(Map<String, dynamic> body) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/api/pos/customers'),
            headers: _headers,
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 30));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> updatePosCustomer(
      String id, Map<String, dynamic> body) async {
    try {
      final response = await http
          .put(
            Uri.parse('$baseUrl/api/pos/customers/$id'),
            headers: _headers,
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 30));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  // ── POS Print Templates ──

  Future<Map<String, dynamic>> getPosPrintTemplates({
    String? documentType,
    bool activeOnly = true,
  }) async {
    try {
      final q = <String, String>{'activeOnly': '$activeOnly'};
      if (documentType != null && documentType.isNotEmpty) {
        q['documentType'] = documentType;
      }
      final uri = Uri.parse('$baseUrl/api/pos/print-templates')
          .replace(queryParameters: q);
      final response =
          await http.get(uri, headers: _headers).timeout(const Duration(seconds: 30));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> getPosPrintTemplate(String id) async {
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/api/pos/print-templates/$id'), headers: _headers)
          .timeout(const Duration(seconds: 30));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> getPosPrintTemplatePresets({
    String documentType = 'SaleInvoice',
  }) async {
    try {
      final uri = Uri.parse('$baseUrl/api/pos/print-templates/presets')
          .replace(queryParameters: {'documentType': documentType});
      final response =
          await http.get(uri, headers: _headers).timeout(const Duration(seconds: 30));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> createPosPrintTemplate(Map<String, dynamic> body) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/api/pos/print-templates'),
            headers: _headers,
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 30));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> updatePosPrintTemplate(
      String id, Map<String, dynamic> body) async {
    try {
      final response = await http
          .put(
            Uri.parse('$baseUrl/api/pos/print-templates/$id'),
            headers: _headers,
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 30));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> deletePosPrintTemplate(String id) async {
    try {
      final response = await http
          .delete(Uri.parse('$baseUrl/api/pos/print-templates/$id'), headers: _headers)
          .timeout(const Duration(seconds: 30));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> seedPosPrintTemplates({
    String documentType = 'SaleInvoice',
  }) async {
    try {
      final uri = Uri.parse('$baseUrl/api/pos/print-templates/seed')
          .replace(queryParameters: {'documentType': documentType});
      final response = await http
          .post(uri, headers: _headers)
          .timeout(const Duration(seconds: 30));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  // ── POS Print Cloud (printers, routes, jobs, agents) ──

  Future<Map<String, dynamic>> getPosStorePrinters() async {
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/api/pos/printers'), headers: _headers)
          .timeout(const Duration(seconds: 30));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> getPosStorePrinter(String id) async {
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/api/pos/printers/$id'), headers: _headers)
          .timeout(const Duration(seconds: 30));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> createPosStorePrinter(
      Map<String, dynamic> body) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/api/pos/printers'),
            headers: _headers,
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 30));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> updatePosStorePrinter(
      String id, Map<String, dynamic> body) async {
    try {
      final response = await http
          .put(
            Uri.parse('$baseUrl/api/pos/printers/$id'),
            headers: _headers,
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 30));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> deletePosStorePrinter(String id) async {
    try {
      final response = await http
          .delete(Uri.parse('$baseUrl/api/pos/printers/$id'), headers: _headers)
          .timeout(const Duration(seconds: 30));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  /// Đồng bộ máy in nội bộ thiết bị → server (gán món dùng chung).
  Future<Map<String, dynamic>> upsertPosDeviceLocalPrinter(
      Map<String, dynamic> body) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/api/pos/printers/device-local'),
            headers: _headers,
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 30));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> reportPosPrinterHealth(
    String printerId, {
    required String status,
    String? errorMessage,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/api/pos/printers/$printerId/health'),
            headers: _headers,
            body: jsonEncode({
              'status': status,
              'errorMessage': errorMessage,
            }),
          )
          .timeout(const Duration(seconds: 15));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> getPosPrinterRoutes() async {
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/api/pos/printers/routes'), headers: _headers)
          .timeout(const Duration(seconds: 30));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> savePosPrinterRoutes(
      List<Map<String, dynamic>> routes) async {
    try {
      final response = await http
          .put(
            Uri.parse('$baseUrl/api/pos/printers/routes'),
            headers: _headers,
            body: jsonEncode({'routes': routes}),
          )
          .timeout(const Duration(seconds: 30));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> getPosProductPrinterMap() async {
    return _getProductPrinterApi('/map');
  }

  // «product-assignment» là API chính thức (PosPrintersController). API cũ
  // «product-printers» chỉ còn export/import Excel — KHÔNG có các route
  // summary/products/categories, luôn trả 404 hợp lệ. Trước đây khi base
  // chính bị lỗi mạng (timeout/DNS…) code nuốt exception rồi thử base cũ
  // → luôn ăn 404 và báo nhầm "API gán máy in không khả dụng (404)" dù
  // nguyên nhân thật là mất kết nối tạm thời. Giờ: lỗi mạng ở base chính →
  // trả lỗi kết nối rõ ràng ngay, không rơi xuống base cũ chắc chắn 404.
  Future<Map<String, dynamic>> _getProductPrinterApi(
    String suffix, {
    Map<String, String>? query,
  }) async {
    final primary = '$baseUrl/api/pos/printers/product-assignment';
    try {
      final uri = Uri.parse('$primary$suffix').replace(queryParameters: query);
      final response = await _retryOnUnauthorized(() => http
          .get(uri, headers: _headers)
          .timeout(const Duration(seconds: 45)));
      if (response.statusCode != 404) return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }

    try {
      final legacy = '$baseUrl/api/pos/product-printers';
      final uri = Uri.parse('$legacy$suffix').replace(queryParameters: query);
      final response = await _retryOnUnauthorized(() => http
          .get(uri, headers: _headers)
          .timeout(const Duration(seconds: 45)));
      if (response.statusCode != 404) return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
    return {'isSuccess': false, 'message': 'API gán máy in không khả dụng (404)'};
  }

  Future<Map<String, dynamic>> _mutateProductPrinterApi(
    String suffix,
    Future<http.Response> Function(Uri uri) request,
  ) async {
    final primary = '$baseUrl/api/pos/printers/product-assignment';
    try {
      final uri = Uri.parse('$primary$suffix');
      final response =
          await _retryOnUnauthorized(() => request(uri))
              .timeout(const Duration(seconds: 120));
      if (response.statusCode != 404) return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }

    try {
      final legacy = '$baseUrl/api/pos/product-printers';
      final uri = Uri.parse('$legacy$suffix');
      final response =
          await _retryOnUnauthorized(() => request(uri))
              .timeout(const Duration(seconds: 120));
      if (response.statusCode != 404) return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
    return {'isSuccess': false, 'message': 'API gán máy in không khả dụng (404)'};
  }

  Future<Map<String, dynamic>> getPosProductPrinterCategories() async {
    return _getProductPrinterApi('/categories');
  }

  Future<Map<String, dynamic>> getPosProductPrinterProducts({
    String? search,
    String? categoryId,
    bool unassignedOnly = false,
    bool forLabel = false,
    int page = 1,
    int pageSize = 50,
  }) async {
    final q = <String, String>{
      'page': '$page',
      'pageSize': '$pageSize',
      'unassignedOnly': '$unassignedOnly',
      'forLabel': '$forLabel',
    };
    if (search != null && search.trim().isNotEmpty) q['search'] = search.trim();
    if (categoryId != null && categoryId.isNotEmpty) q['categoryId'] = categoryId;
    return _getProductPrinterApi('/products', query: q);
  }

  Future<Map<String, dynamic>> setPosProductPrinterCategory(
      String id, String? printerId) async {
    return _mutateProductPrinterApi(
      '/categories/$id',
      (uri) => http.put(
        uri,
        headers: _headers,
        body: jsonEncode({'printerId': printerId}),
      ),
    );
  }

  Future<Map<String, dynamic>> applyPosProductPrinterCategory(
    String id, {
    bool includeChildCategories = true,
    bool overwriteExisting = false,
  }) async {
    return _mutateProductPrinterApi(
      '/categories/$id/apply',
      (uri) => http.post(
        uri,
        headers: _headers,
        body: jsonEncode({
          'includeChildCategories': includeChildCategories,
          'overwriteExisting': overwriteExisting,
        }),
      ),
    );
  }

  Future<Map<String, dynamic>> setPosProductPrinterProduct(
      String id, String? printerId) async {
    return _mutateProductPrinterApi(
      '/products/$id',
      (uri) => http.put(
        uri,
        headers: _headers,
        body: jsonEncode({'printerId': printerId}),
      ),
    );
  }

  Future<Map<String, dynamic>> getPosPrinterProductSummary() async {
    return _getProductPrinterApi('/printers/summary');
  }

  Future<Map<String, dynamic>> getPosPrinterProducts(
    String printerId, {
    bool assignedOnly = true,
    String? search,
    String? categoryId,
    bool? forLabel,
    int page = 1,
    int pageSize = 50,
  }) async {
    final q = <String, String>{
      'assignedOnly': '$assignedOnly',
      'page': '$page',
      'pageSize': '$pageSize',
      if (forLabel != null) 'forLabel': '$forLabel',
    };
    if (search != null && search.trim().isNotEmpty) q['search'] = search.trim();
    if (categoryId != null && categoryId.isNotEmpty) q['categoryId'] = categoryId;
    return _getProductPrinterApi('/printers/$printerId/products', query: q);
  }

  Future<Map<String, dynamic>> assignProductsToPosPrinter(
    String printerId, {
    List<String>? productIds,
    List<String>? categoryIds,
    bool allProducts = false,
    bool includeChildCategories = true,
    /// true = chuyển SP đang gán máy khác sang máy này.
    bool forceReassign = false,
    /// true = gán lane tem (không đụng gán phiếu bếp).
    bool? forLabel,
  }) async {
    return _mutateProductPrinterApi(
      '/printers/$printerId/assign',
      (uri) => http.post(
        uri,
        headers: _headers,
        body: jsonEncode({
          'productIds': productIds ?? [],
          'categoryIds': categoryIds ?? [],
          'allProducts': allProducts,
          'includeChildCategories': includeChildCategories,
          'forceReassign': forceReassign,
          'ForceReassign': forceReassign,
          if (forLabel != null) 'forLabel': forLabel,
          if (forLabel != null) 'ForLabel': forLabel,
        }),
      ),
    );
  }

  Future<Map<String, dynamic>> unassignProductsFromPosPrinter(
    String printerId, {
    List<String>? productIds,
    List<String>? categoryIds,
    bool allProducts = false,
    bool includeChildCategories = true,
  }) async {
    return _mutateProductPrinterApi(
      '/printers/$printerId/unassign',
      (uri) => http.post(
        uri,
        headers: _headers,
        body: jsonEncode({
          'productIds': productIds ?? [],
          'categoryIds': categoryIds ?? [],
          'allProducts': allProducts,
          'includeChildCategories': includeChildCategories,
        }),
      ),
    );
  }

  Future<Map<String, dynamic>> exportPosProductPrintersExcel() async {
    for (final url in [
      '$baseUrl/api/pos/printers/product-assignment/export/excel',
      '$baseUrl/api/pos/product-printers/export/excel',
    ]) {
      try {
        final response = await _retryOnUnauthorized(
          () => http
              .get(Uri.parse(url), headers: _binaryDownloadHeaders)
              .timeout(const Duration(seconds: 90)),
        );
        if (response.statusCode == 404) continue;
        final parsed = _parseExcelExportResponse(response);
        if (parsed['isSuccess'] == true || response.statusCode != 404) {
          return parsed;
        }
      } catch (e) {
        if (url.contains('product-printers')) return _connectionFailure(e);
      }
    }
    return {'isSuccess': false, 'message': 'Export Excel không khả dụng (404)'};
  }

  Future<Map<String, dynamic>> importPosProductPrintersExcelFile(
      List<int> fileBytes, String fileName) async {
    for (final base in [
      '$baseUrl/api/pos/printers/product-assignment/import/excel/file',
      '$baseUrl/api/pos/product-printers/import/excel/file',
    ]) {
      try {
        final request = http.MultipartRequest('POST', Uri.parse(base));
        final authHeaders = _headers;
        if (authHeaders.containsKey('Authorization')) {
          request.headers['Authorization'] = authHeaders['Authorization']!;
        }
        request.files.add(
            http.MultipartFile.fromBytes('file', fileBytes, filename: fileName));
        final streamed = await request.send().timeout(const Duration(seconds: 120));
        final response = await http.Response.fromStream(streamed);
        if (response.statusCode == 404) continue;
        return _handleResponse(response);
      } catch (e) {
        if (base.contains('product-printers')) return _connectionFailure(e);
      }
    }
    return {'isSuccess': false, 'message': 'Import Excel không khả dụng (404)'};
  }

  Future<Map<String, dynamic>> createPosPrintJob({
    required String documentType,
    required String payloadFormat,
    required String payload,
    int copies = 1,
    String? referenceNo,
    String? referenceId,
    String? printerId,
  }) async {
    try {
      final body = <String, dynamic>{
        'documentType': documentType,
        'payloadFormat': payloadFormat,
        'payload': payload,
        'copies': copies,
      };
      if (referenceNo != null && referenceNo.isNotEmpty) {
        body['referenceNo'] = referenceNo;
      }
      if (referenceId != null && referenceId.isNotEmpty) {
        body['referenceId'] = referenceId;
      }
      if (printerId != null && printerId.isNotEmpty) {
        body['printerId'] = printerId;
      }
      final response = await http
          .post(
            Uri.parse('$baseUrl/api/pos/print-jobs'),
            headers: _headers,
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 45));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> getPosPrintJob(String id) async {
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/api/pos/print-jobs/$id'), headers: _headers)
          .timeout(const Duration(seconds: 20));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> getPosPrintJobs({
    int limit = 30,
    String? status,
  }) async {
    try {
      final q = <String, String>{'limit': '$limit'};
      if (status != null && status.isNotEmpty) q['status'] = status;
      final uri = Uri.parse('$baseUrl/api/pos/print-jobs')
          .replace(queryParameters: q);
      final response =
          await http.get(uri, headers: _headers).timeout(const Duration(seconds: 30));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> getPosPrintAgents({
    bool onlineOnly = true,
    int staleSeconds = 180,
  }) async {
    try {
      final uri = Uri.parse('$baseUrl/api/pos/print-jobs/agents').replace(
        queryParameters: {
          'onlineOnly': '$onlineOnly',
          'staleSeconds': '$staleSeconds',
        },
      );
      final response =
          await http.get(uri, headers: _headers).timeout(const Duration(seconds: 20));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> registerPosPrintAgent({
    required String deviceId,
    String? deviceName,
    String? employeeName,
    required List<String> printerIds,
    String? appVersion,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/api/pos/print-jobs/agents/register'),
            headers: _headers,
            body: jsonEncode({
              'deviceId': deviceId,
              'deviceName': deviceName,
              'employeeName': employeeName,
              'printerIds': printerIds,
              'appVersion': appVersion,
            }),
          )
          .timeout(const Duration(seconds: 20));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> markPosPrintAgentOffline({
    required String deviceId,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/api/pos/print-jobs/agents/offline'),
            headers: _headers,
            body: jsonEncode({'deviceId': deviceId}),
          )
          .timeout(const Duration(seconds: 15));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> claimPosPrintJob(String agentId) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/api/pos/print-jobs/agents/$agentId/claim'),
            headers: _headers,
          )
          .timeout(const Duration(seconds: 25));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  /// Claim đúng 1 job (test cloud trên máy Agent).
  Future<Map<String, dynamic>> claimPosPrintJobById(
      String jobId, String agentId) async {
    try {
      final uri = Uri.parse('$baseUrl/api/pos/print-jobs/$jobId/claim')
          .replace(queryParameters: {'agentId': agentId});
      final response = await http
          .post(uri, headers: _headers)
          .timeout(const Duration(seconds: 25));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> markPosPrintJobPrinting(
      String jobId, String agentId) async {
    try {
      final uri = Uri.parse('$baseUrl/api/pos/print-jobs/$jobId/printing')
          .replace(queryParameters: {'agentId': agentId});
      final response = await http
          .post(uri, headers: _headers)
          .timeout(const Duration(seconds: 15));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> completePosPrintJob(
      String jobId, String agentId) async {
    try {
      final uri = Uri.parse('$baseUrl/api/pos/print-jobs/$jobId/complete')
          .replace(queryParameters: {'agentId': agentId});
      final response = await http
          .post(uri, headers: _headers)
          .timeout(const Duration(seconds: 15));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> failPosPrintJob(
    String jobId,
    String agentId, {
    required String errorCode,
    required String errorMessage,
  }) async {
    try {
      final qp = <String, String>{};
      if (agentId.trim().isNotEmpty) qp['agentId'] = agentId.trim();
      final uri = Uri.parse('$baseUrl/api/pos/print-jobs/$jobId/fail')
          .replace(queryParameters: qp.isEmpty ? null : qp);
      final response = await http
          .post(
            uri,
            headers: _headers,
            body: jsonEncode({
              'errorCode': errorCode,
              'errorMessage': errorMessage,
            }),
          )
          .timeout(const Duration(seconds: 15));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  /// Agent nhả job (USB không gắn…) → Queued lại cho máy Agent khác.
  Future<Map<String, dynamic>> releasePosPrintJob(
    String jobId,
    String agentId, {
    String errorCode = 'NOT_LOCAL',
    String errorMessage = 'Máy này không kết nối được cổng in',
  }) async {
    try {
      final uri = Uri.parse('$baseUrl/api/pos/print-jobs/$jobId/release')
          .replace(queryParameters: {'agentId': agentId});
      final response = await http
          .post(
            uri,
            headers: _headers,
            body: jsonEncode({
              'errorCode': errorCode,
              'errorMessage': errorMessage,
            }),
          )
          .timeout(const Duration(seconds: 15));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  // ── POS sell industry (profile / areas / rooms / sessions / gym) ──

  Future<Map<String, dynamic>> getPosSellSettings() async {
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/api/pos/sell-settings'), headers: _headers)
          .timeout(const Duration(seconds: 30));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  /// Đẩy state màn phụ lên server (máy khác mở link ?v=).
  Future<Map<String, dynamic>> putPosCustomerDisplayState({
    required String stateJson,
    required String viewerCode,
  }) async {
    try {
      final response = await http
          .put(
            Uri.parse('$baseUrl/api/pos/customer-display/state'),
            headers: _headers,
            body: jsonEncode({
              'stateJson': stateJson,
              'viewerCode': viewerCode,
            }),
          )
          .timeout(const Duration(seconds: 15));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  /// Máy khác — đọc state công khai theo mã xem (không cần login).
  Future<Map<String, dynamic>> getPosCustomerDisplayPublicState(
      String viewerCode) async {
    try {
      final uri = Uri.parse('$baseUrl/api/pos/customer-display/public-state')
          .replace(queryParameters: {'code': viewerCode});
      final response = await http
          .get(uri, headers: {'Content-Type': 'application/json'})
          .timeout(const Duration(seconds: 15));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> updatePosSellSettings(Map<String, dynamic> body) async {
    try {
      final response = await http
          .put(
            Uri.parse('$baseUrl/api/pos/sell-settings'),
            headers: _headers,
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 30));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> getPosServiceAreas() async {
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/api/pos/service-areas'), headers: _headers)
          .timeout(const Duration(seconds: 30));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  /// Khu vực được gán cho tài khoản (manager). seeAll=true khi chưa gán.
  Future<Map<String, dynamic>> getPosUserServiceAreas(String userId) async {
    try {
      final response = await http
          .get(
            Uri.parse('$baseUrl/api/pos/users/$userId/service-areas'),
            headers: _headers,
          )
          .timeout(const Duration(seconds: 30));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  /// Gán khu vực cho tài khoản. [areaIds] rỗng = xem tất cả khu.
  Future<Map<String, dynamic>> setPosUserServiceAreas(
    String userId,
    List<String> areaIds,
  ) async {
    try {
      final response = await http
          .put(
            Uri.parse('$baseUrl/api/pos/users/$userId/service-areas'),
            headers: _headers,
            body: jsonEncode({'areaIds': areaIds}),
          )
          .timeout(const Duration(seconds: 30));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> getMyPosServiceAreas() async {
    try {
      final response = await http
          .get(
            Uri.parse('$baseUrl/api/pos/my-service-areas'),
            headers: _headers,
          )
          .timeout(const Duration(seconds: 20));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> createPosServiceArea(Map<String, dynamic> body) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/api/pos/service-areas'),
            headers: _headers,
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 30));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> updatePosServiceArea(String id, Map<String, dynamic> body) async {
    try {
      final response = await http
          .put(
            Uri.parse('$baseUrl/api/pos/service-areas/$id'),
            headers: _headers,
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 30));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> sortPosServiceAreas(
      List<Map<String, dynamic>> items) async {
    try {
      final response = await http
          .put(
            Uri.parse('$baseUrl/api/pos/service-areas/sort'),
            headers: _headers,
            body: jsonEncode({'items': items}),
          )
          .timeout(const Duration(seconds: 30));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> deletePosServiceArea(String id) async {
    try {
      final response = await http
          .delete(Uri.parse('$baseUrl/api/pos/service-areas/$id'), headers: _headers)
          .timeout(const Duration(seconds: 30));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  /// [heal]: false khi poll silent — bỏ ghi DB orphan; true lúc mở sơ đồ / thao tác.
  Future<Map<String, dynamic>> getPosServiceResources({
    String? areaId,
    bool heal = true,
  }) async {
    try {
      final q = <String, String>{};
      if (areaId != null && areaId.isNotEmpty) q['areaId'] = areaId;
      if (!heal) q['heal'] = 'false';
      final uri = Uri.parse('$baseUrl/api/pos/service-resources')
          .replace(queryParameters: q.isEmpty ? null : q);
      final response =
          await http.get(uri, headers: _headers).timeout(const Duration(seconds: 30));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> createPosServiceResource(Map<String, dynamic> body) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/api/pos/service-resources'),
            headers: _headers,
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 30));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> updatePosServiceResource(String id, Map<String, dynamic> body) async {
    try {
      final response = await http
          .put(
            Uri.parse('$baseUrl/api/pos/service-resources/$id'),
            headers: _headers,
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 30));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> deletePosServiceResource(String id) async {
    try {
      final response = await http
          .delete(Uri.parse('$baseUrl/api/pos/service-resources/$id'), headers: _headers)
          .timeout(const Duration(seconds: 30));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> openPosResourceSession(Map<String, dynamic> body) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/api/pos/resource-sessions/open'),
            headers: _headers,
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 30));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> closePosResourceSession(String id) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/api/pos/resource-sessions/$id/close'),
            headers: _headers,
          )
          .timeout(const Duration(seconds: 30));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  /// Trả bàn về trống — đóng mọi phiên Open/Paused + xóa draft trống.
  Future<Map<String, dynamic>> freePosServiceResource(String resourceId) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/api/pos/service-resources/$resourceId/free'),
            headers: _headers,
          )
          .timeout(const Duration(seconds: 30));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> pausePosResourceSession(String id) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/api/pos/resource-sessions/$id/pause'),
            headers: _headers,
          )
          .timeout(const Duration(seconds: 30));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> resumePosResourceSession(String id) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/api/pos/resource-sessions/$id/resume'),
            headers: _headers,
          )
          .timeout(const Duration(seconds: 30));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> transferPosResourceSession(
      String id, String targetResourceId) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/api/pos/resource-sessions/$id/transfer'),
            headers: _headers,
            body: jsonEncode({'targetResourceId': targetResourceId}),
          )
          .timeout(const Duration(seconds: 30));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  /// Chuyển bàn theo resourceId nguồn (ổn định hơn sessionId).
  Future<Map<String, dynamic>> transferPosResource(
      String fromResourceId, String targetResourceId) async {
    try {
      final response = await http
          .post(
            Uri.parse(
                '$baseUrl/api/pos/service-resources/$fromResourceId/transfer'),
            headers: _headers,
            body: jsonEncode({'targetResourceId': targetResourceId}),
          )
          .timeout(const Duration(seconds: 30));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> splitPosResourceSession(
    String id, {
    required String targetResourceId,
    required List<String> lineIds,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/api/pos/resource-sessions/$id/split'),
            headers: _headers,
            body: jsonEncode({
              'targetResourceId': targetResourceId,
              'lineIds': lineIds,
            }),
          )
          .timeout(const Duration(seconds: 30));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> getPosCashierShiftCurrent() async {
    try {
      final response = await http
          .get(
            Uri.parse('$baseUrl/api/pos/cashier-shifts/current'),
            headers: _headers,
          )
          .timeout(const Duration(seconds: 20));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> openPosCashierShift({
    required double openingCash,
    String? note,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/api/pos/cashier-shifts/open'),
            headers: _headers,
            body: jsonEncode({
              'openingCash': openingCash,
              if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
            }),
          )
          .timeout(const Duration(seconds: 20));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> closePosCashierShift(
    String id, {
    required double countedCash,
    String? note,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/api/pos/cashier-shifts/$id/close'),
            headers: _headers,
            body: jsonEncode({
              'countedCash': countedCash,
              if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
            }),
          )
          .timeout(const Duration(seconds: 20));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> getPosQrOrderTables() async {
    try {
      final response = await http
          .get(
            Uri.parse('$baseUrl/api/pos/qr-order/tables'),
            headers: _headers,
          )
          .timeout(const Duration(seconds: 20));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> rotatePosQrOrderToken(String tableId) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/api/pos/qr-order/tables/$tableId/rotate-token'),
            headers: _headers,
          )
          .timeout(const Duration(seconds: 20));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> getPosKdsStations() async {
    try {
      final response = await http
          .get(
            Uri.parse('$baseUrl/api/pos/kds/stations'),
            headers: _headers,
          )
          .timeout(const Duration(seconds: 20));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> getPosKdsTickets({String? printerId}) async {
    try {
      final uri = Uri.parse('$baseUrl/api/pos/kds/tickets').replace(
        queryParameters: {
          if (printerId != null && printerId.isNotEmpty) 'printerId': printerId,
        },
      );
      final response = await http
          .get(uri, headers: _headers)
          .timeout(const Duration(seconds: 20));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> setPosKdsLinePrep(
      String lineId, String status) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/api/pos/kds/lines/$lineId/prep'),
            headers: _headers,
            body: jsonEncode({'status': status}),
          )
          .timeout(const Duration(seconds: 20));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> setPosKdsLinesPrep(
      List<String> lineIds, String status) async {
    try {
      final ids = lineIds.where((e) => e.trim().isNotEmpty).toList();
      if (ids.isEmpty) {
        return {'isSuccess': false, 'message': 'Chưa chọn món'};
      }
      final response = await http
          .post(
            Uri.parse('$baseUrl/api/pos/kds/lines/prep-batch'),
            headers: _headers,
            body: jsonEncode({'ids': ids, 'status': status}),
          )
          .timeout(const Duration(seconds: 30));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> bumpPosKdsTicket(String orderId) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/api/pos/kds/tickets/$orderId/bump'),
            headers: _headers,
          )
          .timeout(const Duration(seconds: 20));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> recallPosKdsTicket(String orderId) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/api/pos/kds/tickets/$orderId/recall'),
            headers: _headers,
          )
          .timeout(const Duration(seconds: 20));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> splitPosBill(
    String sessionId, {
    required List<Map<String, dynamic>> items,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/api/pos/resource-sessions/$sessionId/split-bill'),
            headers: _headers,
            body: jsonEncode({'items': items}),
          )
          .timeout(const Duration(seconds: 30));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> mergePosResourceSession(
      String id, String sourceSessionId) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/api/pos/resource-sessions/$id/merge'),
            headers: _headers,
            body: jsonEncode({'sourceSessionId': sourceSessionId}),
          )
          .timeout(const Duration(seconds: 30));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> setPosResourceSessionGuests(
      String id, int guestCount) async {
    try {
      final response = await http
          .put(
            Uri.parse('$baseUrl/api/pos/resource-sessions/$id/guests'),
            headers: _headers,
            body: jsonEncode({'guestCount': guestCount}),
          )
          .timeout(const Duration(seconds: 30));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> requestPosResourceBill(
    String id, {
    bool requested = true,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse(
                '$baseUrl/api/pos/resource-sessions/$id/request-bill?requested=$requested'),
            headers: _headers,
          )
          .timeout(const Duration(seconds: 30));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  /// Đánh dấu tạm tính theo bàn (phiên Open đang sống).
  Future<Map<String, dynamic>> requestPosResourceBillByResource(
    String resourceId, {
    bool requested = true,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse(
                '$baseUrl/api/pos/service-resources/$resourceId/request-bill?requested=$requested'),
            headers: _headers,
          )
          .timeout(const Duration(seconds: 30));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> markPosResourceCleaned(String id) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/api/pos/service-resources/$id/clean'),
            headers: _headers,
          )
          .timeout(const Duration(seconds: 30));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> createPosKitchenVoids(
      Map<String, dynamic> body) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/api/pos/kitchen-voids'),
            headers: _headers,
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 30));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> getPosKitchenVoids({
    DateTime? from,
    DateTime? to,
    bool? afterBillOnly,
    bool? beforeBillOnly,
    String? resourceId,
    String? resourceName,
    String? voidedBy,
    int take = 200,
  }) async {
    try {
      final q = <String, String>{'take': '$take'};
      if (from != null) q['from'] = from.toUtc().toIso8601String();
      if (to != null) q['to'] = to.toUtc().toIso8601String();
      if (afterBillOnly == true) q['afterBillOnly'] = 'true';
      if (beforeBillOnly == true) q['beforeBillOnly'] = 'true';
      if (resourceId != null && resourceId.isNotEmpty) {
        q['resourceId'] = resourceId;
      }
      if (resourceName != null && resourceName.isNotEmpty) {
        q['resourceName'] = resourceName;
      }
      if (voidedBy != null && voidedBy.isNotEmpty) q['voidedBy'] = voidedBy;
      final uri = Uri.parse('$baseUrl/api/pos/kitchen-voids')
          .replace(queryParameters: q);
      final response =
          await http.get(uri, headers: _headers).timeout(const Duration(seconds: 30));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> getPosCancelReturnAudits({
    DateTime? from,
    DateTime? to,
    String? actionType,
    bool? afterBillOnly,
    bool? beforeBillOnly,
    String? actor,
    String? search,
    int take = 300,
  }) async {
    try {
      final q = <String, String>{'take': '$take'};
      if (from != null) q['from'] = from.toUtc().toIso8601String();
      if (to != null) q['to'] = to.toUtc().toIso8601String();
      if (actionType != null && actionType.isNotEmpty) {
        q['actionType'] = actionType;
      }
      if (afterBillOnly == true) q['afterBillOnly'] = 'true';
      if (beforeBillOnly == true) q['beforeBillOnly'] = 'true';
      if (actor != null && actor.isNotEmpty) q['actor'] = actor;
      if (search != null && search.isNotEmpty) q['search'] = search;
      final uri = Uri.parse('$baseUrl/api/pos/cancel-return-audits')
          .replace(queryParameters: q);
      final response =
          await http.get(uri, headers: _headers).timeout(const Duration(seconds: 30));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> kitchenSendPosResourceSession(
    String id, {
    List<String>? lineIds,
    String? deviceId,
    String? deviceName,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/api/pos/resource-sessions/$id/kitchen-send'),
            headers: _headers,
            body: jsonEncode({
              if (lineIds != null) 'lineIds': lineIds,
              if (deviceId != null && deviceId.isNotEmpty) 'deviceId': deviceId,
              if (deviceName != null && deviceName.isNotEmpty)
                'deviceName': deviceName,
            }),
          )
          .timeout(const Duration(seconds: 30));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> savePosResourceLayout(
      List<Map<String, dynamic>> items) async {
    try {
      final response = await http
          .put(
            Uri.parse('$baseUrl/api/pos/service-resources/layout'),
            headers: _headers,
            body: jsonEncode({'items': items}),
          )
          .timeout(const Duration(seconds: 30));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> getPosOpenResourceSessions() async {
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/api/pos/resource-sessions/open'), headers: _headers)
          .timeout(const Duration(seconds: 30));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> createPosResourceReservation(
      Map<String, dynamic> body) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/api/pos/resource-reservations'),
            headers: _headers,
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 30));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> getPosResourceReservations({
    String? resourceId,
    DateTime? day,
    bool includeClosed = false,
  }) async {
    try {
      final q = <String, String>{};
      if (resourceId != null && resourceId.isNotEmpty) {
        q['resourceId'] = resourceId;
      }
      if (day != null) q['day'] = day.toUtc().toIso8601String();
      if (includeClosed) q['includeClosed'] = 'true';
      final uri = Uri.parse('$baseUrl/api/pos/resource-reservations')
          .replace(queryParameters: q.isEmpty ? null : q);
      final response =
          await http.get(uri, headers: _headers).timeout(const Duration(seconds: 30));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> collectPosResourceReservationDeposit(
    String id,
    Map<String, dynamic> body,
  ) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/api/pos/resource-reservations/$id/deposit'),
            headers: _headers,
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 30));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> cancelPosResourceReservation(
    String id, {
    bool forfeitDeposit = true,
    bool refundDeposit = false,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/api/pos/resource-reservations/$id/cancel'),
            headers: _headers,
            body: jsonEncode({
              'forfeitDeposit': forfeitDeposit,
              'refundDeposit': refundDeposit,
            }),
          )
          .timeout(const Duration(seconds: 30));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> seatPosResourceReservation(String id) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/api/pos/resource-reservations/$id/seat'),
            headers: _headers,
          )
          .timeout(const Duration(seconds: 30));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> expirePosResourceReservationNoShows() async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/api/pos/resource-reservations/expire-noshow'),
            headers: _headers,
          )
          .timeout(const Duration(seconds: 30));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> getPosReservationPipeline({
    DateTime? from,
    DateTime? to,
  }) async {
    try {
      final q = <String, String>{};
      if (from != null) q['from'] = from.toUtc().toIso8601String();
      if (to != null) q['to'] = to.toUtc().toIso8601String();
      final uri = Uri.parse('$baseUrl/api/pos/resource-reservations/pipeline')
          .replace(queryParameters: q.isEmpty ? null : q);
      final response =
          await http.get(uri, headers: _headers).timeout(const Duration(seconds: 30));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> getPosReservationAvailability({
    DateTime? from,
    DateTime? to,
    String? kind,
  }) async {
    try {
      final q = <String, String>{};
      if (from != null) q['from'] = from.toUtc().toIso8601String();
      if (to != null) q['to'] = to.toUtc().toIso8601String();
      if (kind != null && kind.isNotEmpty) q['kind'] = kind;
      final uri =
          Uri.parse('$baseUrl/api/pos/resource-reservations/availability')
              .replace(queryParameters: q.isEmpty ? null : q);
      final response =
          await http.get(uri, headers: _headers).timeout(const Duration(seconds: 30));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> getPosSessionBalances({String? customerId}) async {
    try {
      final q = <String, String>{};
      if (customerId != null && customerId.isNotEmpty) q['customerId'] = customerId;
      final uri = Uri.parse('$baseUrl/api/pos/session-balances')
          .replace(queryParameters: q.isEmpty ? null : q);
      final response =
          await http.get(uri, headers: _headers).timeout(const Duration(seconds: 30));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }

  Future<Map<String, dynamic>> redeemPosSessionBalance(Map<String, dynamic> body) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/api/pos/session-balances/redeem'),
            headers: _headers,
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 30));
      return _handleResponse(response);
    } catch (e) {
      return _connectionFailure(e);
    }
  }
}

