import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart' show MediaType;
import 'package:shared_preferences/shared_preferences.dart';
import 'api_config.dart';

class ApiService {
  static final String baseUrl = getApiBaseUrl();
  static const String _tokenKey = 'access_token';
  static const String _refreshTokenKey = 'refresh_token';
  static const Duration _defaultTimeout = Duration(seconds: 8);

  String? _token;

  // Singleton pattern
  static final ApiService _instance = ApiService._internal();
  factory ApiService() => _instance;
  ApiService._internal();

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
      } else {
        debugPrint('❌ ApiService: Token refresh failed');
      }
    }
    return response;
  }

  // ==================== AUTH ====================
  Future<Map<String, dynamic>> login(
      String storeCode, String email, String password) async {
    try {
      debugPrint(
          '🔐 Login attempt: $storeCode / $email to $baseUrl/api/auth/login');
      final response = await http
          .post(
            Uri.parse('$baseUrl/api/auth/login'),
            headers: {'Content-Type': 'application/json'},
            body: json.encode({
              'storeCode': storeCode,
              'userName': email,
              'password': password,
            }),
          )
          .timeout(const Duration(seconds: 10));
      debugPrint('📥 Login response status: ${response.statusCode}');
      debugPrint('📥 Login response body: ${response.body}');
      return _handleResponse(response);
    } catch (e) {
      debugPrint('❌ Login error: $e');
      return {
        'isSuccess': false,
        'message': 'Không thể kết nối đến server: $e',
      };
    }
  }

  Future<Map<String, dynamic>> adminLogin(String email, String password) async {
    try {
      debugPrint(
          '🔐 AdminLogin attempt: $email to $baseUrl/api/auth/admin-login');
      final response = await http
          .post(
            Uri.parse('$baseUrl/api/auth/AdminLogin'),
            headers: {'Content-Type': 'application/json'},
            body: json.encode({'userName': email, 'password': password}),
          )
          .timeout(const Duration(seconds: 10));
      debugPrint('📥 AdminLogin response status: ${response.statusCode}');
      debugPrint('📥 AdminLogin response body: ${response.body}');
      return _handleResponse(response);
    } catch (e) {
      debugPrint('❌ AdminLogin error: $e');
      return {
        'isSuccess': false,
        'message': 'Không thể kết nối đến server: $e'
      };
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
      return {
        'isSuccess': false,
        'message': 'Không thể kết nối đến server: $e'
      };
    }
  }

  // Đăng ký cửa hàng mới
  Future<Map<String, dynamic>> register(
      String storeName, String email, String password,
      {String? phoneNumber, String? storeCode}) async {
    try {
      debugPrint('📝 Register attempt: $storeName - $email');
      final body = {
        'storeName': storeName,
        'email': email,
        'password': password,
      };
      if (phoneNumber != null && phoneNumber.isNotEmpty) {
        body['phoneNumber'] = phoneNumber;
      }
      if (storeCode != null && storeCode.isNotEmpty) {
        body['storeCode'] = storeCode;
      }
      final response = await http
          .post(
            Uri.parse('$baseUrl/api/auth/register'),
            headers: {'Content-Type': 'application/json'},
            body: json.encode(body),
          )
          .timeout(const Duration(seconds: 10));
      debugPrint('📥 Register response status: ${response.statusCode}');
      debugPrint('📥 Register response body: ${response.body}');
      return _handleResponse(response);
    } catch (e) {
      debugPrint('❌ Register error: $e');
      return {
        'isSuccess': false,
        'message': 'Không thể kết nối đến server: $e',
      };
    }
  }

  /// Cài đặt dữ liệu mẫu cho cửa hàng mới đăng ký
  Future<Map<String, dynamic>> seedSampleData(String storeCode) async {
    try {
      debugPrint('🌱 Seeding sample data for store: $storeCode');
      final response = await http
          .post(
            Uri.parse('$baseUrl/api/sampledata/seed/$storeCode'),
            headers: {'Content-Type': 'application/json'},
          )
          .timeout(const Duration(seconds: 30));
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
      String errorMsg;
      if (e.toString().contains('TimeoutException')) {
        errorMsg = 'Server không phản hồi. Vui lòng thử lại.';
      } else if (e.toString().contains('SocketException')) {
        errorMsg = 'Không thể kết nối server. Vui lòng kiểm tra kết nối mạng.';
      } else {
        errorMsg = 'Lỗi kết nối server: $e';
      }
      return {'success': false, 'message': errorMsg};
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
      return {'success': false, 'message': 'Lỗi kết nối server: $e'};
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
      String errorMsg;
      if (e.toString().contains('TimeoutException') ||
          e.toString().contains('SocketException')) {
        errorMsg = 'Không thể kết nối server. Vui lòng kiểm tra kết nối mạng.';
      } else {
        errorMsg = 'Lỗi kết nối server: $e';
      }
      return {
        'serialNumber': serialNumber,
        'exists': false,
        'isAvailable': false,
        'isClaimed': false,
        'error': true,
        'message': errorMsg,
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
      String errorMsg;
      if (e.toString().contains('TimeoutException')) {
        errorMsg = 'Server không phản hồi. Vui lòng thử lại.';
      } else if (e.toString().contains('SocketException')) {
        errorMsg = 'Không thể kết nối server. Vui lòng kiểm tra kết nối mạng.';
      } else {
        errorMsg = 'Lỗi kết nối server: $e';
      }
      return {
        'success': false,
        'message': errorMsg,
      };
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
      return {
        'success': false,
        'message': 'Lỗi kết nối server: $e',
      };
    }
  }

  // ==================== EMPLOYEES ====================
  Future<List<dynamic>> getEmployees({int? pageSize}) async {
    try {
      final params = <String, String>{};
      if (pageSize != null) params['pageSize'] = pageSize.toString();
      final uri = Uri.parse('$baseUrl/api/employees')
          .replace(queryParameters: params.isNotEmpty ? params : null);
      final response = await http
          .get(
            uri,
            headers: _headers,
          )
          .timeout(const Duration(seconds: 10));
      final data = _handleResponse(response);
      if (data['isSuccess'] == true) {
        // API returns PagedResult: {items, totalCount, pageNumber, pageSize}
        final responseData = data['data'];
        if (responseData is List) {
          return responseData;
        } else if (responseData is Map && responseData['items'] != null) {
          return responseData['items'] as List<dynamic>;
        }
        return [];
      }
    } catch (e) {
      debugPrint('Error getting employees: $e');
    }
    return [];
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

  Future<bool> createEmployee(Map<String, dynamic> employeeData) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/api/employees'),
            headers: _headers,
            body: json.encode(employeeData),
          )
          .timeout(const Duration(seconds: 10));
      final data = _handleResponse(response);
      return data['isSuccess'] == true;
    } catch (e) {
      debugPrint('Error creating employee: $e');
      return false;
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

  Future<bool> deleteEmployee(String employeeId) async {
    try {
      final response = await http
          .delete(
            Uri.parse('$baseUrl/api/employees/$employeeId'),
            headers: _headers,
          )
          .timeout(const Duration(seconds: 10));
      final data = _handleResponse(response);
      return data['isSuccess'] == true;
    } catch (e) {
      debugPrint('Error deleting employee: $e');
      return false;
    }
  }

  /// Export employees as Excel — returns raw bytes
  Future<Map<String, dynamic>> exportEmployeesExcel() async {
    try {
      final response = await http
          .get(
            Uri.parse('$baseUrl/api/employees/export/excel'),
            headers: _headers,
          )
          .timeout(const Duration(seconds: 30));
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return {'isSuccess': true, 'data': response.bodyBytes.toList()};
      }
      return {
        'isSuccess': false,
        'message': 'Export thất bại: ${response.statusCode}'
      };
    } catch (e) {
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
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
      final queryParams = <String, String>{
        'page': page.toString(),
        'pageSize': pageSize.toString(),
      };

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
          .timeout(const Duration(seconds: 15)));

      debugPrint('📥 Attendance response status: ${response.statusCode}');
      final data = _handleResponse(response);

      if (data['isSuccess'] == true) {
        final responseData = data['data'];
        return {
          'items': responseData is Map ? (responseData['items'] ?? []) : (responseData ?? []),
          'totalCount': _toInt(responseData is Map ? responseData['totalCount'] : null, 0),
          'pageNumber': _toInt(responseData is Map ? responseData['pageNumber'] : null, page),
          'pageSize': _toInt(responseData is Map ? responseData['pageSize'] : null, pageSize),
        };
      }
      debugPrint('❌ Attendance response error: ${data['message']}');
    } catch (e) {
      debugPrint('Error getting attendances: $e');
    }
    return {'items': [], 'totalCount': 0, 'pageNumber': 1, 'pageSize': 20};
  }

  /// Create manual attendance record
  Future<bool> createManualAttendance({
    required String employeeId,
    required DateTime punchTime,
    String? deviceId,
    String? note,
  }) async {
    try {
      debugPrint('📤 Creating manual attendance for employee: $employeeId');

      final body = {
        'employeeId': employeeId,
        'punchTime': punchTime.toIso8601String(),
        'deviceId': deviceId,
        'verifyType': 100, // Manual verification type
        'note': note ?? 'Chấm công thủ công',
        'isManual': true,
      };

      final response = await http
          .post(
            Uri.parse('$baseUrl/api/attendances/manual'),
            headers: _headers,
            body: json.encode(body),
          )
          .timeout(const Duration(seconds: 15));

      debugPrint('📥 Manual attendance response: ${response.statusCode}');
      debugPrint('📥 Manual attendance body: ${response.body}');
      final data = _handleResponse(response);
      debugPrint('📥 Manual attendance parsed: isSuccess=${data['isSuccess']}');
      return data['isSuccess'] == true;
    } catch (e) {
      debugPrint('❌ Error creating manual attendance: $e');
      return false;
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

  /// Delete an attendance record
  Future<bool> deleteAttendance(String id) async {
    try {
      debugPrint('📤 Deleting attendance: $id');

      final response = await _retryOnUnauthorized(() => http
          .delete(
            Uri.parse('$baseUrl/api/attendances/$id'),
            headers: _headers,
          )
          .timeout(const Duration(seconds: 15)));

      debugPrint('📥 Delete attendance response: ${response.statusCode}');
      if (response.statusCode == 204) return true;
      final data = _handleResponse(response);
      return data['isSuccess'] == true;
    } catch (e) {
      debugPrint('❌ Error deleting attendance: $e');
      return false;
    }
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
  Future<Map<String, dynamic>> getEmployeeDashboard({String period = 'week'}) async {
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
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
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
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
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
        return {'isSuccess': false, 'message': 'Thiết bị đang offline. Vui lòng kiểm tra kết nối mạng của máy chấm công.'};
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
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
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
              'command': 'ENROLL_FP PIN=$pin\tFID=$fingerIndex',
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
        return {'isSuccess': false, 'message': 'Thiết bị đang offline. Vui lòng kiểm tra kết nối mạng của máy chấm công.'};
      }
      debugPrint(
          '📤 Enrolling fingerprint for PIN=$pin, FID=$fingerIndex on device $deviceId');
      final response = await http
          .post(
            Uri.parse('$baseUrl/api/devices/$deviceId/commands'),
            headers: _headers,
            body: json.encode({
              'commandType': 9, // EnrollFingerprint
              'command': 'ENROLL_FP PIN=$pin\tFID=$fingerIndex',
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
      final command = fingerIndex != null && fingerIndex >= 0
          ? 'DATA DELETE FINGERTMP PIN=$pin\tFID=$fingerIndex'
          : 'DATA DELETE FINGERTMP PIN=$pin';
      debugPrint('📤 Deleting fingerprint: $command on device $deviceId');
      final response = await http
          .post(
            Uri.parse('$baseUrl/api/devices/$deviceId/commands'),
            headers: _headers,
            body: json.encode({
              'commandType': 10, // DeleteFingerprint
              'command': command,
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

  // Đăng ký khuôn mặt - trả về response đầy đủ để lấy commandId
  Future<Map<String, dynamic>?> enrollFaceWithResponse(
      String deviceId, String pin) async {
    debugPrint(
      '⚠️ Remote face enrollment disabled for device $deviceId, PIN=$pin because ENROLL_FP opens fingerprint enrollment on FACE devices.',
    );
    return {
      'isSuccess': false,
      'message':
          'Thiết bị này hiện không hỗ trợ mở đăng ký khuôn mặt từ xa qua ADMS. Hãy đăng ký trực tiếp trên máy rồi dùng đồng bộ sinh trắc học.',
      'data': null,
    };
  }

  // Xóa khuôn mặt - gửi lệnh DATA DELETE FINGERTMP PIN=xxx FID=50
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
              'command': 'DATA DELETE FINGERTMP PIN=$pin\tFID=50',
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
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
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
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
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
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
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
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
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
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
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
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
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
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
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
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
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
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
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
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
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
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
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
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
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
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
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
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
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
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
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
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
    }
  }

  // ==================== SCHEDULE NOTIFICATIONS & STAFFING QUOTAS ====================

  // Gửi nhắc nhở đăng ký lịch làm việc
  Future<Map<String, dynamic>> sendScheduleReminder(Map<String, dynamic> data) async {
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
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
    }
  }

  // Yêu cầu bổ sung nhân viên cho ca
  Future<Map<String, dynamic>> requestShiftCoverage(Map<String, dynamic> data) async {
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
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
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
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
    }
  }

  // Tạo/cập nhật định mức nhân sự
  Future<Map<String, dynamic>> upsertStaffingQuota(Map<String, dynamic> data) async {
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
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
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
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
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
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
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
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
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
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
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
      if (result['isSuccess'] == true) {
        return result['data'];
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
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
    }
  }

  // ==================== STORE MODULES ====================

  /// Lấy danh sách module được phép của cửa hàng hiện tại
  Future<List<String>> getMyModules() async {
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
    } catch (e) {
      debugPrint('Error getting my modules: $e');
    }
    return [];
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
          .post(
            Uri.parse('$baseUrl/api/settings/salary'),
            headers: _headers,
            body: json.encode(settings),
          )
          .timeout(const Duration(seconds: 10));
      return _handleResponse(response);
    } catch (e) {
      debugPrint('Error saving salary settings: $e');
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
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
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
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
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
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
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
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
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
    }
  }

  // Holiday Settings
  Future<List<dynamic>> getHolidaySettings(int year) async {
    try {
      final response = await http
          .get(
            Uri.parse('$baseUrl/api/settings/holidays?year=$year'),
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
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
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
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
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
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
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
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
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
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
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
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
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
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
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
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
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
          : Uri.parse('$baseUrl/api/permission-management/by-role?roleName=$roleName');
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
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
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
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
    }
  }

  /// Lấy quyền hiệu lực của user hiện tại (role + department, merged)
  Future<List<Map<String, dynamic>>> getMyEffectivePermissions() async {
    try {
      final response = await _retryOnUnauthorized(() => http
          .get(
            Uri.parse('$baseUrl/api/permission-management/my-permissions'),
            headers: _headers,
          )
          .timeout(const Duration(seconds: 15)));
      final result = _handleResponse(response);
      if (result['data'] != null && result['data'] is List) {
        return List<Map<String, dynamic>>.from(
            (result['data'] as List).map((e) => Map<String, dynamic>.from(e)));
      }
      return [];
    } catch (e) {
      debugPrint('Error getting effective permissions: $e');
      return [];
    }
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
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
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
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
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
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
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
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
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
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
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
          'totalCount': _toInt(responseData is Map ? responseData['totalCount'] : null, 0),
          'pageNumber': _toInt(responseData is Map ? responseData['pageNumber'] : null, page),
          'pageSize': _toInt(responseData is Map ? responseData['pageSize'] : null, pageSize),
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
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
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
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
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
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
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
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
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
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
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
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
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
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
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
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
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
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
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
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
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
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
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
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
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
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
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
      };
      if (wifiBssid != null) body['wifiBssid'] = wifiBssid;

      final response = await http
          .post(
            Uri.parse('$baseUrl/api/mobile-attendance/register-device'),
            headers: _headers,
            body: json.encode(body),
          )
          .timeout(const Duration(seconds: 30));
      return _handleResponse(response);
    } catch (e) {
      debugPrint('Error registering mobile device: $e');
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
    }
  }

  /// Kiểm tra trạng thái thiết bị của nhân viên hiện tại
  Future<Map<String, dynamic>> getMyDeviceStatus({String? employeeId}) async {
    try {
      final uri = employeeId != null
          ? '$baseUrl/api/mobile-attendance/my-device?employeeId=$employeeId'
          : '$baseUrl/api/mobile-attendance/my-device';
      final response = await http
          .get(
            Uri.parse(uri),
            headers: _headers,
          )
          .timeout(const Duration(seconds: 10));
      return _handleResponse(response);
    } catch (e) {
      debugPrint('Error getting device status: $e');
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
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
            Uri.parse('$baseUrl/api/mobile-attendance/approve-device/$deviceId'),
            headers: _headers,
            body: json.encode(body),
          )
          .timeout(const Duration(seconds: 10));
      return _handleResponse(response);
    } catch (e) {
      debugPrint('Error approving device: $e');
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
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
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
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
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
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
        'punchTime': DateTime.now().toIso8601String(),
      };
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
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
    }
  }

  /// Lấy lịch sử chấm công mobile
  Future<Map<String, dynamic>> getMobileAttendanceHistory({
    String? employeeId,
    DateTime? fromDate,
    DateTime? toDate,
    String? status,
  }) async {
    try {
      final queryParams = <String, String>{};
      if (employeeId != null) queryParams['employeeId'] = employeeId;
      if (fromDate != null) {
        queryParams['fromDate'] = fromDate.toIso8601String();
      }
      if (toDate != null) queryParams['toDate'] = toDate.toIso8601String();
      if (status != null) queryParams['status'] = status;

      final uri = Uri.parse('$baseUrl/api/mobile-attendance/history').replace(
          queryParameters: queryParams.isNotEmpty ? queryParams : null);

      final response = await http
          .get(uri, headers: _headers)
          .timeout(const Duration(seconds: 10));
      return _handleResponse(response);
    } catch (e) {
      debugPrint('Error getting mobile attendance history: $e');
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
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
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
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
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
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
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
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
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
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
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
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
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
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
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
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
      final response = await http.get(uri, headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      debugPrint('Error getting advance requests: $e');
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
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
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
    }
  }

  // Duyệt hoặc từ chối yêu cầu ứng lương
  Future<Map<String, dynamic>> approveAdvanceRequest({
    required String requestId,
    required bool isApproved,
    String? rejectionReason,
  }) async {
    try {
      final body = {
        'requestId': requestId,
        'isApproved': isApproved,
        'rejectionReason': rejectionReason,
      };
      final response = await http.post(
        Uri.parse('$baseUrl/api/AdvanceRequests/$requestId/approve'),
        headers: _headers,
        body: json.encode(body),
      );
      return _handleResponse(response);
    } catch (e) {
      debugPrint('Error approving advance request: $e');
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
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
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
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
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
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
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
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
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
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
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
    }
  }

  Future<Map<String, dynamic>> createAsset({
    required String assetCode,
    required String name,
    String? description,
    String? serialNumber,
    String? model,
    String? brand,
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
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
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
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
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
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
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
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
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
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
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
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
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
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
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
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
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
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
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
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
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
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
    }
  }

  Future<Map<String, dynamic>> confirmAssetTransfer(String transferId, {String? notes}) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/Assets/transfers/$transferId/confirm'),
        headers: _headers,
        body: json.encode({'transferId': transferId, if (notes != null) 'notes': notes}),
      );
      return _handleResponse(response);
    } catch (e) {
      debugPrint('Error confirming asset transfer: $e');
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
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
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
    }
  }

  Future<Map<String, dynamic>> createAssetInventory({
    required String name,
    String? description,
    DateTime? startDate,
    DateTime? endDate,
    String? responsibleUserId,
    String? notes,
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

      final response = await http.post(
        Uri.parse('$baseUrl/api/Assets/inventories'),
        headers: _headers,
        body: json.encode(body),
      );
      return _handleResponse(response);
    } catch (e) {
      debugPrint('Error creating asset inventory: $e');
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
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
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
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
      final response = await http.get(uri, headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      debugPrint('Error getting transactions: $e');
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
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
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
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
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
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
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
    }
  }

  Future<Map<String, dynamic>> updateTransactionStatus(
      String id, String status) async {
    try {
      final response = await http.put(
        Uri.parse('$baseUrl/api/Transactions/$id/status'),
        headers: _headers,
        body: json.encode({'status': status}),
      );
      return _handleResponse(response);
    } catch (e) {
      debugPrint('Error updating transaction status: $e');
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
    }
  }

  Future<Map<String, dynamic>> bulkApproveTransactions(List<String> ids) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/Transactions/bulk-approve'),
        headers: _headers,
        body: json.encode({'ids': ids}),
      );
      return _handleResponse(response);
    } catch (e) {
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
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
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
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
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
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
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
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
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
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
      if (sortDescending != null) params['sortDescending'] = sortDescending.toString();

      final uri = Uri.parse('$baseUrl/api/communications')
          .replace(queryParameters: params);
      final response = await http.get(uri, headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      debugPrint('Error getting communications: $e');
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
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
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
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
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
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
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
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
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
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
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
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
      int? pageSize,
      String? searchTerm,
      bool? isActive}) async {
    try {
      final params = <String, String>{};
      if (pageNumber != null) params['pageNumber'] = pageNumber.toString();
      if (pageSize != null) params['pageSize'] = pageSize.toString();
      if (searchTerm != null) params['searchTerm'] = searchTerm;
      if (isActive != null) params['isActive'] = isActive.toString();
      final uri = Uri.parse('$baseUrl/api/Departments')
          .replace(queryParameters: params.isNotEmpty ? params : null);
      final response = await http.get(uri, headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
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
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
    }
  }

  Future<Map<String, dynamic>> getDepartmentsForSelect() async {
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/api/Departments/select'), headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
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
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
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
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
    }
  }

  Future<Map<String, dynamic>> deleteDepartment(String id) async {
    try {
      final response = await http
          .delete(Uri.parse('$baseUrl/api/Departments/$id'), headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
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
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
    }
  }

  Future<Map<String, dynamic>> getBranchTree() async {
    try {
      final response = await http.get(Uri.parse('$baseUrl/api/branches/tree'),
          headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
    }
  }

  Future<Map<String, dynamic>> getBranchStats() async {
    try {
      final response = await http.get(Uri.parse('$baseUrl/api/branches/stats'),
          headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
    }
  }

  Future<Map<String, dynamic>> getBranchesForSelect() async {
    try {
      final response = await http.get(Uri.parse('$baseUrl/api/branches/select'),
          headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
    }
  }

  Future<Map<String, dynamic>> createBranch(Map<String, dynamic> data) async {
    try {
      final response = await http.post(Uri.parse('$baseUrl/api/branches'),
          headers: _headers, body: json.encode(data));
      return _handleResponse(response);
    } catch (e) {
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
    }
  }

  Future<Map<String, dynamic>> updateBranch(
      String id, Map<String, dynamic> data) async {
    try {
      final response = await http.put(Uri.parse('$baseUrl/api/branches/$id'),
          headers: _headers, body: json.encode(data));
      return _handleResponse(response);
    } catch (e) {
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
    }
  }

  Future<Map<String, dynamic>> toggleBranchActive(String id) async {
    try {
      final response = await http.put(
          Uri.parse('$baseUrl/api/branches/$id/toggle-active'),
          headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
    }
  }

  Future<Map<String, dynamic>> deleteBranch(String id) async {
    try {
      final response = await http.delete(Uri.parse('$baseUrl/api/branches/$id'),
          headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
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
      if (page != null) params['pageNumber'] = page.toString();
      if (pageSize != null) params['pageSize'] = pageSize.toString();
      if (status != null) params['status'] = status;
      if (fromDate != null) params['fromDate'] = fromDate;
      if (toDate != null) params['toDate'] = toDate;
      final uri = Uri.parse('$baseUrl/api/Leaves/my-leaves')
          .replace(queryParameters: params.isNotEmpty ? params : null);
      final response = await http.get(uri, headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
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
      if (page != null) params['pageNumber'] = page.toString();
      if (pageSize != null) params['pageSize'] = pageSize.toString();
      if (status != null) params['status'] = status;
      if (fromDate != null) params['fromDate'] = fromDate;
      if (toDate != null) params['toDate'] = toDate;
      if (employeeId != null) params['employeeId'] = employeeId;
      final uri = Uri.parse('$baseUrl/api/Leaves')
          .replace(queryParameters: params.isNotEmpty ? params : null);
      final response = await http.get(uri, headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
    }
  }

  Future<Map<String, dynamic>> getPendingLeaves(
      {int? page, int? pageSize}) async {
    try {
      final params = <String, String>{};
      if (page != null) params['pageNumber'] = page.toString();
      if (pageSize != null) params['pageSize'] = pageSize.toString();
      final uri = Uri.parse('$baseUrl/api/Leaves/pending')
          .replace(queryParameters: params.isNotEmpty ? params : null);
      final response = await http.get(uri, headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
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
      String? employeeId}) async {
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
      };
      final response = await http.post(Uri.parse('$baseUrl/api/Leaves'),
          headers: _headers, body: json.encode(data));
      return _handleResponse(response);
    } catch (e) {
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
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
      String? employeeId}) async {
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
      };
      final response = await http.put(Uri.parse('$baseUrl/api/Leaves/$leaveId'),
          headers: _headers, body: json.encode(data));
      return _handleResponse(response);
    } catch (e) {
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
    }
  }

  Future<Map<String, dynamic>> cancelLeave(String id) async {
    try {
      final response = await http.delete(Uri.parse('$baseUrl/api/Leaves/$id'),
          headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
    }
  }

  Future<Map<String, dynamic>> approveLeave(String id) async {
    try {
      final response = await http.post(
          Uri.parse('$baseUrl/api/Leaves/$id/approve'),
          headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
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
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
    }
  }

  Future<Map<String, dynamic>> undoLeaveApproval(String id) async {
    try {
      final response = await http.post(
          Uri.parse('$baseUrl/api/Leaves/$id/undo-approve'),
          headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
    }
  }

  Future<Map<String, dynamic>> forceDeleteLeave(String id) async {
    try {
      final response = await http.delete(
          Uri.parse('$baseUrl/api/Leaves/$id/force'),
          headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
    }
  }

  // ==================== ATTENDANCE CORRECTIONS ====================
  Future<Map<String, dynamic>> getMyAttendanceCorrections(
      {int? page, int? pageSize, dynamic status}) async {
    try {
      final params = <String, String>{};
      if (page != null) params['pageNumber'] = page.toString();
      if (pageSize != null) params['pageSize'] = pageSize.toString();
      if (status != null) params['status'] = status.toString();
      final uri = Uri.parse('$baseUrl/api/AttendanceCorrections/my')
          .replace(queryParameters: params.isNotEmpty ? params : null);
      final response = await http.get(uri, headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
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
      if (page != null) params['pageNumber'] = page.toString();
      if (pageSize != null) params['pageSize'] = pageSize.toString();
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
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
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
              ? oldDate.toIso8601String()
              : oldDate.toString(),
        if (oldTime != null) 'oldTime': oldTime,
        if (newDate != null)
          'newDate': newDate is DateTime
              ? newDate.toIso8601String()
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
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
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
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
    }
  }

  Future<Map<String, dynamic>> undoAttendanceCorrectionApproval(
      String id) async {
    try {
      final response = await http.post(
          Uri.parse('$baseUrl/api/AttendanceCorrections/$id/undo-approve'),
          headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
    }
  }

  Future<Map<String, dynamic>> deleteAttendanceCorrection(String id) async {
    try {
      final response = await http.delete(
          Uri.parse('$baseUrl/api/AttendanceCorrections/$id'),
          headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
    }
  }

  Future<Map<String, dynamic>> getAttendanceCorrectionById(String id) async {
    try {
      final response = await http.get(
          Uri.parse('$baseUrl/api/AttendanceCorrections/$id'),
          headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
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
      if (p != null) params['pageNumber'] = p.toString();
      if (pageSize != null) params['pageSize'] = pageSize.toString();
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
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
    }
  }

  Future<Map<String, dynamic>> createCashTransaction(
      Map<String, dynamic> data) async {
    try {
      final response = await _post(Uri.parse('$baseUrl/api/CashTransactions'),
          body: json.encode(data));
      return _handleResponse(response);
    } catch (e) {
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
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
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
    }
  }

  Future<Map<String, dynamic>> deleteCashTransaction(String id) async {
    try {
      final response =
          await _delete(Uri.parse('$baseUrl/api/CashTransactions/$id'));
      return _handleResponse(response);
    } catch (e) {
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
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
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
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
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
    }
  }

  // ==================== TRANSACTION CATEGORIES ====================
  Future<Map<String, dynamic>> getTransactionCategories() async {
    try {
      final response =
          await _get(Uri.parse('$baseUrl/api/TransactionCategories'));
      return _handleResponse(response);
    } catch (e) {
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
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
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
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
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
    }
  }

  Future<Map<String, dynamic>> initDefaultTransactionCategories() async {
    try {
      final response = await _post(
          Uri.parse('$baseUrl/api/TransactionCategories/init-default'));
      return _handleResponse(response);
    } catch (e) {
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
    }
  }

  // ==================== BANK ACCOUNTS ====================
  Future<Map<String, dynamic>> getBankAccounts() async {
    try {
      final response = await _get(Uri.parse('$baseUrl/api/BankAccounts'));
      return _handleResponse(response);
    } catch (e) {
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
    }
  }

  Future<Map<String, dynamic>> createBankAccount(
      Map<String, dynamic> data) async {
    try {
      final response = await _post(Uri.parse('$baseUrl/api/BankAccounts'),
          body: json.encode(data));
      return _handleResponse(response);
    } catch (e) {
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
    }
  }

  Future<Map<String, dynamic>> updateBankAccount(
      String id, Map<String, dynamic> data) async {
    try {
      final response = await _put(Uri.parse('$baseUrl/api/BankAccounts/$id'),
          body: json.encode(data));
      return _handleResponse(response);
    } catch (e) {
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
    }
  }

  Future<Map<String, dynamic>> setDefaultBankAccount(String id) async {
    try {
      final response =
          await _put(Uri.parse('$baseUrl/api/BankAccounts/$id/set-default'));
      return _handleResponse(response);
    } catch (e) {
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
    }
  }

  Future<Map<String, dynamic>> deleteBankAccount(String id) async {
    try {
      final response =
          await _delete(Uri.parse('$baseUrl/api/BankAccounts/$id'));
      return _handleResponse(response);
    } catch (e) {
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
    }
  }

  Future<Map<String, dynamic>> getVietQRBanks() async {
    try {
      final response =
          await _get(Uri.parse('$baseUrl/api/BankAccounts/vietqr-banks'));
      return _handleResponse(response);
    } catch (e) {
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
    }
  }

  // ==================== ORGCHART ====================
  Future<Map<String, dynamic>> getOrgChartTree() async {
    try {
      final response = await http.get(Uri.parse('$baseUrl/api/orgchart/tree'),
          headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
    }
  }

  Future<Map<String, dynamic>> getOrgChartStats() async {
    try {
      final response = await http.get(Uri.parse('$baseUrl/api/orgchart/stats'),
          headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
    }
  }

  Future<Map<String, dynamic>> getOrgPositions() async {
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/api/orgchart/positions'), headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
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
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
    }
  }

  Future<Map<String, dynamic>> deleteOrgPosition(String id) async {
    try {
      final response = await http.delete(
          Uri.parse('$baseUrl/api/orgchart/positions/$id'),
          headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
    }
  }

  Future<Map<String, dynamic>> getOrgAssignments() async {
    try {
      final response = await http.get(
          Uri.parse('$baseUrl/api/orgchart/assignments'),
          headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
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
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
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
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
    }
  }

  Future<Map<String, dynamic>> deleteOrgAssignment(String id) async {
    try {
      final response = await http.delete(
          Uri.parse('$baseUrl/api/orgchart/assignments/$id'),
          headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
    }
  }

  Future<Map<String, dynamic>> getApprovalFlows() async {
    try {
      final response = await http.get(
          Uri.parse('$baseUrl/api/orgchart/approval-flows'),
          headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
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
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
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
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
    }
  }

  Future<Map<String, dynamic>> deleteApprovalFlow(String id) async {
    try {
      final response = await http.delete(
          Uri.parse('$baseUrl/api/orgchart/approval-flows/$id'),
          headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
    }
  }

  Future<Map<String, dynamic>> getUnassignedEmployees() async {
    try {
      final response = await http.get(
          Uri.parse('$baseUrl/api/orgchart/unassigned-employees'),
          headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
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
      dynamic toDate}) async {
    try {
      final params = <String, String>{};
      if (page != null) params['page'] = page.toString();
      if (pageSize != null) params['pageSize'] = pageSize.toString();
      if (status != null) params['status'] = status.toString();
      if (priority != null) params['priority'] = priority.toString();
      if (assigneeId != null) params['assigneeId'] = assigneeId;
      if (search != null) params['search'] = search;
      if (taskType != null) params['taskType'] = taskType.toString();
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
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
    }
  }

  Future<Map<String, dynamic>> getTaskById(String id) async {
    try {
      final response = await http.get(Uri.parse('$baseUrl/api/Tasks/$id'),
          headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
    }
  }

  Future<Map<String, dynamic>> getMyTasks({
    int? page,
    int? pageSize,
    dynamic status,
    dynamic priority,
  }) async {
    try {
      final params = <String, String>{};
      if (page != null) params['page'] = page.toString();
      if (pageSize != null) params['pageSize'] = pageSize.toString();
      if (status != null) params['status'] = status.toString();
      if (priority != null) params['priority'] = priority.toString();
      final uri = Uri.parse('$baseUrl/api/Tasks/my')
          .replace(queryParameters: params.isNotEmpty ? params : null);
      final response = await http.get(uri, headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
    }
  }

  Future<Map<String, dynamic>> createTask(
      {String? title,
      String? description,
      dynamic taskType,
      dynamic priority,
      String? assigneeId,
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
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
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
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
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
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
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
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
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
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
    }
  }

  Future<Map<String, dynamic>> deleteTask(String id) async {
    try {
      final response = await http.delete(
          Uri.parse('$baseUrl/api/Tasks/$id'),
          headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
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
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
    }
  }

  Future<Map<String, dynamic>> getTaskKanbanBoard(
      {String? assigneeId, dynamic priority}) async {
    try {
      final params = <String, String>{};
      if (assigneeId != null) params['assigneeId'] = assigneeId;
      if (priority != null) params['priority'] = priority.toString();
      final uri = Uri.parse('$baseUrl/api/Tasks/kanban')
          .replace(queryParameters: params.isNotEmpty ? params : null);
      final response = await http.get(uri, headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
    }
  }

  Future<Map<String, dynamic>> getTaskStatistics(
      {String? assigneeId,
      dynamic priority,
      dynamic fromDate,
      dynamic toDate}) async {
    try {
      final params = <String, String>{};
      if (assigneeId != null) params['assigneeId'] = assigneeId;
      if (priority != null) params['priority'] = priority.toString();
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
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
    }
  }

  Future<Map<String, dynamic>> getTaskHistory(String taskId) async {
    try {
      final response = await http.get(
          Uri.parse('$baseUrl/api/Tasks/$taskId/history'),
          headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
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
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
    }
  }

  Future<Map<String, dynamic>> updateTask(
      String id, Map<String, dynamic> data) async {
    try {
      final response = await http.put(Uri.parse('$baseUrl/api/Tasks/$id/full'),
          headers: _headers, body: json.encode(data));
      return _handleResponse(response);
    } catch (e) {
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
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
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
    }
  }

  Future<Map<String, dynamic>> getTaskReminders(String taskId) async {
    try {
      final response = await http.get(
          Uri.parse('$baseUrl/api/Tasks/$taskId/reminders'),
          headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
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
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
    }
  }

  Future<Map<String, dynamic>> getTaskEvaluations(String taskId) async {
    try {
      final response = await http.get(
          Uri.parse('$baseUrl/api/Tasks/$taskId/evaluations'),
          headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
    }
  }

  // ==================== REPORTS ====================
  Future<Map<String, dynamic>> getDailyAttendanceReport(
      {dynamic date, String? departmentId}) async {
    try {
      final params = <String, String>{};
      if (date != null) {
        params['date'] = date is DateTime
            ? date.toIso8601String().split('T').first
            : date.toString();
      }
      if (departmentId != null) params['departmentId'] = departmentId;
      final uri = Uri.parse('$baseUrl/api/Reports/attendance/daily')
          .replace(queryParameters: params.isNotEmpty ? params : null);
      final response = await http.get(uri, headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
    }
  }

  Future<Map<String, dynamic>> getMonthlyAttendanceReport(
      {int? month, int? year, String? departmentId}) async {
    try {
      final params = <String, String>{};
      if (month != null) params['month'] = month.toString();
      if (year != null) params['year'] = year.toString();
      if (departmentId != null) params['departmentId'] = departmentId;
      final uri = Uri.parse('$baseUrl/api/Reports/attendance/monthly')
          .replace(queryParameters: params.isNotEmpty ? params : null);
      final response = await http.get(uri, headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
    }
  }

  Future<Map<String, dynamic>> getLateEarlyReport(
      {dynamic fromDate,
      dynamic toDate,
      String? departmentId,
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
      if (departmentId != null) params['departmentId'] = departmentId;
      final uri = Uri.parse('$baseUrl/api/Reports/late-early')
          .replace(queryParameters: params.isNotEmpty ? params : null);
      final response = await http.get(uri, headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
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
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
    }
  }

  Future<Map<String, dynamic>> exportDailyReport(
      {dynamic date, String? departmentId}) async {
    try {
      final params = <String, String>{};
      if (date != null) {
        params['date'] = date is DateTime
            ? date.toIso8601String().split('T').first
            : date.toString();
      }
      if (departmentId != null) params['departmentId'] = departmentId;
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
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
    }
  }

  Future<Map<String, dynamic>> exportMonthlyReport(
      {int? month, int? year, String? departmentId}) async {
    try {
      final params = <String, String>{};
      if (month != null) params['month'] = month.toString();
      if (year != null) params['year'] = year.toString();
      if (departmentId != null) params['departmentId'] = departmentId;
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
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
    }
  }

  Future<Map<String, dynamic>> exportLateEarlyReport(
      {dynamic fromDate,
      dynamic toDate,
      String? departmentId,
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
      if (departmentId != null) params['departmentId'] = departmentId;
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
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
    }
  }

  Future<Map<String, dynamic>> exportDailyReportExcel(
      {dynamic date, String? departmentId}) async {
    try {
      final params = <String, String>{};
      if (date != null) {
        params['date'] = date is DateTime
            ? date.toIso8601String().split('T').first
            : date.toString();
      }
      if (departmentId != null) params['departmentId'] = departmentId;
      final uri = Uri.parse('$baseUrl/api/Reports/export/excel/daily')
          .replace(queryParameters: params.isNotEmpty ? params : null);
      final response = await http.get(uri, headers: _headers);
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return {'isSuccess': true, 'data': response.bodyBytes.toList()};
      }
      return {
        'isSuccess': false,
        'message': 'Export failed: ${response.statusCode}'
      };
    } catch (e) {
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
    }
  }

  Future<Map<String, dynamic>> exportMonthlyReportExcel(
      {int? month, int? year, String? departmentId}) async {
    try {
      final params = <String, String>{};
      if (month != null) params['month'] = month.toString();
      if (year != null) params['year'] = year.toString();
      if (departmentId != null) params['departmentId'] = departmentId;
      final uri = Uri.parse('$baseUrl/api/Reports/export/excel/monthly')
          .replace(queryParameters: params.isNotEmpty ? params : null);
      final response = await http.get(uri, headers: _headers);
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return {'isSuccess': true, 'data': response.bodyBytes.toList()};
      }
      return {
        'isSuccess': false,
        'message': 'Export failed: ${response.statusCode}'
      };
    } catch (e) {
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
    }
  }

  Future<Map<String, dynamic>> exportLateEarlyReportExcel(
      {dynamic fromDate,
      dynamic toDate,
      String? departmentId,
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
      if (departmentId != null) params['departmentId'] = departmentId;
      final uri = Uri.parse('$baseUrl/api/Reports/export/excel/late-early')
          .replace(queryParameters: params.isNotEmpty ? params : null);
      final response = await http.get(uri, headers: _headers);
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return {'isSuccess': true, 'data': response.bodyBytes.toList()};
      }
      return {
        'isSuccess': false,
        'message': 'Export failed: ${response.statusCode}'
      };
    } catch (e) {
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
    }
  }

  Future<Map<String, dynamic>> exportDepartmentSummaryExcel(
      {int? year, int? month}) async {
    try {
      final params = <String, String>{};
      if (year != null) params['year'] = year.toString();
      if (month != null) params['month'] = month.toString();
      final uri = Uri.parse('$baseUrl/api/Reports/export/excel/department')
          .replace(queryParameters: params.isNotEmpty ? params : null);
      final response = await http.get(uri, headers: _headers);
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return {'isSuccess': true, 'data': response.bodyBytes.toList()};
      }
      return {
        'isSuccess': false,
        'message': 'Export failed: ${response.statusCode}'
      };
    } catch (e) {
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
    }
  }

  Future<Map<String, dynamic>> getOvertimeReport(
      {dynamic startDate, dynamic endDate, String? department, int? minOvertimeMinutes}) async {
    try {
      final params = <String, String>{};
      if (startDate != null) {
        params['startDate'] = startDate is DateTime ? startDate.toIso8601String() : startDate.toString();
      }
      if (endDate != null) {
        params['endDate'] = endDate is DateTime ? endDate.toIso8601String() : endDate.toString();
      }
      if (department != null) params['department'] = department;
      if (minOvertimeMinutes != null) params['minOvertimeMinutes'] = minOvertimeMinutes.toString();
      final uri = Uri.parse('$baseUrl/api/Reports/overtime')
          .replace(queryParameters: params.isNotEmpty ? params : null);
      final response = await http.get(uri, headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
    }
  }

  Future<Map<String, dynamic>> exportOvertimeReportExcel(
      {dynamic startDate, dynamic endDate}) async {
    try {
      final params = <String, String>{};
      if (startDate != null) {
        params['startDate'] = startDate is DateTime ? startDate.toIso8601String() : startDate.toString();
      }
      if (endDate != null) {
        params['endDate'] = endDate is DateTime ? endDate.toIso8601String() : endDate.toString();
      }
      final uri = Uri.parse('$baseUrl/api/Reports/export/excel/overtime')
          .replace(queryParameters: params.isNotEmpty ? params : null);
      final response = await http.get(uri, headers: _headers);
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return {'isSuccess': true, 'data': response.bodyBytes.toList()};
      }
      return {'isSuccess': false, 'message': 'Export failed: ${response.statusCode}'};
    } catch (e) {
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
    }
  }

  Future<Map<String, dynamic>> getLeaveReport(
      {dynamic startDate, dynamic endDate, String? department}) async {
    try {
      final params = <String, String>{};
      if (startDate != null) {
        params['startDate'] = startDate is DateTime ? startDate.toIso8601String() : startDate.toString();
      }
      if (endDate != null) {
        params['endDate'] = endDate is DateTime ? endDate.toIso8601String() : endDate.toString();
      }
      if (department != null) params['department'] = department;
      final uri = Uri.parse('$baseUrl/api/Reports/leave-summary')
          .replace(queryParameters: params.isNotEmpty ? params : null);
      final response = await http.get(uri, headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
    }
  }

  Future<Map<String, dynamic>> exportLeaveReportExcel(
      {dynamic startDate, dynamic endDate}) async {
    try {
      final params = <String, String>{};
      if (startDate != null) {
        params['startDate'] = startDate is DateTime ? startDate.toIso8601String() : startDate.toString();
      }
      if (endDate != null) {
        params['endDate'] = endDate is DateTime ? endDate.toIso8601String() : endDate.toString();
      }
      final uri = Uri.parse('$baseUrl/api/Reports/export/excel/leave-summary')
          .replace(queryParameters: params.isNotEmpty ? params : null);
      final response = await http.get(uri, headers: _headers);
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return {'isSuccess': true, 'data': response.bodyBytes.toList()};
      }
      return {'isSuccess': false, 'message': 'Export failed: ${response.statusCode}'};
    } catch (e) {
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
    }
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
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
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
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
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
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
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
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
    }
  }

  Future<Map<String, dynamic>> getDepartmentStats() async {
    try {
      final response = await http.get(
          Uri.parse('$baseUrl/api/Dashboard/department-stats'),
          headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
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
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
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
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
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
      if (page != null) params['pageNumber'] = page.toString();
      if (pageSize != null) params['pageSize'] = pageSize.toString();
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
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
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
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
    }
  }

  Future<Map<String, dynamic>> toggleStoreStatus(String id) async {
    try {
      final response = await http.post(
          Uri.parse('$baseUrl/api/system-admin/stores/$id/toggle-status'),
          headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
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
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
    }
  }

  Future<Map<String, dynamic>> unlockStore(String id) async {
    try {
      final response = await http.post(
          Uri.parse('$baseUrl/api/system-admin/stores/$id/unlock'),
          headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
    }
  }

  Future<Map<String, dynamic>> updateStore(String id,
      {String? name,
      String? description,
      String? address,
      String? phone}) async {
    try {
      final data = <String, dynamic>{
        if (name != null) 'name': name,
        if (description != null) 'description': description,
        if (address != null) 'address': address,
        if (phone != null) 'phone': phone,
      };
      final response = await http.put(
          Uri.parse('$baseUrl/api/system-admin/stores/$id'),
          headers: _headers,
          body: json.encode(data));
      return _handleResponse(response);
    } catch (e) {
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
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
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
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
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
    }
  }

  Future<Map<String, dynamic>> deleteAllStoreData(String id) async {
    try {
      final response = await http.delete(
          Uri.parse('$baseUrl/api/system-admin/stores/$id/data?confirmDelete=true'),
          headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
    }
  }

  Future<Map<String, dynamic>> deleteStore(String id) async {
    try {
      final response = await http.delete(
          Uri.parse('$baseUrl/api/system-admin/stores/$id?confirmDelete=true'),
          headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
    }
  }

  // ==================== SERVICE PACKAGES ====================

  Future<Map<String, dynamic>> getAvailableModules() async {
    try {
      final response = await http.get(
          Uri.parse('$baseUrl/api/system-admin/service-packages/available-modules'),
          headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
    }
  }

  Future<Map<String, dynamic>> getServicePackages() async {
    try {
      final response = await http.get(
          Uri.parse('$baseUrl/api/system-admin/service-packages'),
          headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
    }
  }

  Future<Map<String, dynamic>> createServicePackage(Map<String, dynamic> data) async {
    try {
      final response = await http.post(
          Uri.parse('$baseUrl/api/system-admin/service-packages'),
          headers: _headers,
          body: json.encode(data));
      return _handleResponse(response);
    } catch (e) {
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
    }
  }

  Future<Map<String, dynamic>> updateServicePackage(String id, Map<String, dynamic> data) async {
    try {
      final response = await http.put(
          Uri.parse('$baseUrl/api/system-admin/service-packages/$id'),
          headers: _headers,
          body: json.encode(data));
      return _handleResponse(response);
    } catch (e) {
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
    }
  }

  Future<Map<String, dynamic>> deleteServicePackage(String id) async {
    try {
      final response = await http.delete(
          Uri.parse('$baseUrl/api/system-admin/service-packages/$id'),
          headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
    }
  }

  Future<Map<String, dynamic>> assignPackageToStore(String storeId, String packageId) async {
    try {
      final response = await http.post(
          Uri.parse('$baseUrl/api/system-admin/stores/$storeId/assign-package/$packageId'),
          headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
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
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
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
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
    }
  }

  Future<Map<String, dynamic>> createKeyPromotion(Map<String, dynamic> data) async {
    try {
      final response = await http.post(
          Uri.parse('$baseUrl/api/system-admin/key-promotions'),
          headers: _headers,
          body: json.encode(data));
      return _handleResponse(response);
    } catch (e) {
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
    }
  }

  Future<Map<String, dynamic>> updateKeyPromotion(String id, Map<String, dynamic> data) async {
    try {
      final response = await http.put(
          Uri.parse('$baseUrl/api/system-admin/key-promotions/$id'),
          headers: _headers,
          body: json.encode(data));
      return _handleResponse(response);
    } catch (e) {
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
    }
  }

  Future<Map<String, dynamic>> deleteKeyPromotion(String id) async {
    try {
      final response = await http.delete(
          Uri.parse('$baseUrl/api/system-admin/key-promotions/$id'),
          headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
    }
  }

  Future<Map<String, dynamic>> bulkActivateLicenses(String storeId, List<String> licenseKeys) async {
    try {
      final response = await http.post(
          Uri.parse('$baseUrl/api/system-admin/stores/$storeId/activate-bulk'),
          headers: _headers,
          body: json.encode({'licenseKeys': licenseKeys}));
      return _handleResponse(response);
    } catch (e) {
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
    }
  }

  Future<Map<String, dynamic>> previewBulkActivation(String storeId, List<String> licenseKeys) async {
    try {
      final response = await http.post(
          Uri.parse('$baseUrl/api/system-admin/stores/$storeId/activate-bulk-preview'),
          headers: _headers,
          body: json.encode({'licenseKeys': licenseKeys}));
      return _handleResponse(response);
    } catch (e) {
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
    }
  }

  Future<Map<String, dynamic>> getSystemUsers(
      {int? page,
      int? pageSize,
      String? search,
      String? storeId,
      String? role}) async {
    try {
      final params = <String, String>{};
      if (page != null) params['pageNumber'] = page.toString();
      if (pageSize != null) params['pageSize'] = pageSize.toString();
      if (search != null) params['search'] = search;
      if (storeId != null) params['storeId'] = storeId;
      if (role != null) params['role'] = role;
      final uri = Uri.parse('$baseUrl/api/system-admin/users')
          .replace(queryParameters: params.isNotEmpty ? params : null);
      final response = await http.get(uri, headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
    }
  }

  Future<Map<String, dynamic>> getSystemAdminUsers(
      {int? page,
      int? pageSize,
      String? search,
      String? storeId,
      String? role}) async {
    return getSystemUsers(
        page: page,
        pageSize: pageSize,
        search: search,
        storeId: storeId,
        role: role);
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
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
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
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
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
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
    }
  }

  Future<Map<String, dynamic>> deleteSystemUser(String userId) async {
    try {
      final response = await http.delete(
          Uri.parse('$baseUrl/api/system-admin/users/$userId'),
          headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
    }
  }

  Future<Map<String, dynamic>> getSystemDevices(
      {int? page,
      int? pageSize,
      bool? isOnline,
      bool? isClaimed,
      String? search,
      String? storeId}) async {
    try {
      final params = <String, String>{};
      if (page != null) params['pageNumber'] = page.toString();
      if (pageSize != null) params['pageSize'] = pageSize.toString();
      if (isOnline != null) params['isOnline'] = isOnline.toString();
      if (isClaimed != null) params['isClaimed'] = isClaimed.toString();
      if (search != null) params['search'] = search;
      if (storeId != null) params['storeId'] = storeId;
      final uri = Uri.parse('$baseUrl/api/system-admin/devices')
          .replace(queryParameters: params.isNotEmpty ? params : null);
      final response = await http.get(uri, headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
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
        return {'isSuccess': false, 'message': 'Thiết bị đang offline. Vui lòng kiểm tra kết nối mạng của máy chấm công.'};
      }
      final data = <String, dynamic>{'commandType': commandType};
      if (command != null) data['command'] = command;
      final response = await _retryOnUnauthorized(() => http.post(
          Uri.parse('$baseUrl/api/devices/$deviceId/commands'),
          headers: _headers,
          body: json.encode(data)));
      return _handleResponse(response);
    } catch (e) {
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
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
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
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
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
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
      if (page != null) params['pageNumber'] = page.toString();
      if (pageSize != null) params['pageSize'] = pageSize.toString();
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
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
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
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
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
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
    }
  }

  Future<Map<String, dynamic>> revokeLicenseKey(String id) async {
    try {
      final response = await http.delete(
          Uri.parse('$baseUrl/api/system-admin/licenses/$id'),
          headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
    }
  }

  Future<Map<String, dynamic>> deleteLicenseKeyPermanent(String id) async {
    try {
      final response = await http.delete(
          Uri.parse('$baseUrl/api/system-admin/licenses/$id/permanent'),
          headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
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
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
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
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
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
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
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
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
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
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
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
      if (page != null) params['pageNumber'] = page.toString();
      if (pageSize != null) params['pageSize'] = pageSize.toString();
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
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
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
      int? tokenValidDays}) async {
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
      };
      final response = await http.post(
          Uri.parse('$baseUrl/api/system-admin/agents'),
          headers: _headers,
          body: json.encode(data));
      return _handleResponse(response);
    } catch (e) {
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
    }
  }

  Future<Map<String, dynamic>> updateAgent(
      {String? id,
      String? name,
      String? phone,
      String? address,
      String? description,
      int? maxStores,
      bool? isActive}) async {
    try {
      final data = <String, dynamic>{
        if (name != null) 'name': name,
        if (phone != null) 'phone': phone,
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
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
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
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
    }
  }

  // ==================== APP SETTINGS ====================
  Future<Map<String, dynamic>> getAppSetting(String key) async {
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/api/settings/app/$key'), headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
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
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
    }
  }

  Future<Map<String, dynamic>> getAllAppSettings() async {
    try {
      final response = await http.get(
          Uri.parse('$baseUrl/api/system-admin/settings'),
          headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
    }
  }

  Future<Map<String, dynamic>> initializeAppSettings() async {
    try {
      final response = await http.post(
          Uri.parse('$baseUrl/api/system-admin/settings/initialize'),
          headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
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
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
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
      if (page != null) params['pageNumber'] = page.toString();
      if (pageSize != null) params['pageSize'] = pageSize.toString();
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
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
    }
  }

  Future<Map<String, dynamic>> getAuditStats() async {
    try {
      final response = await http.get(
          Uri.parse('$baseUrl/api/system-admin/audit-logs/stats'),
          headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
    }
  }

  Future<Map<String, dynamic>> getSystemHealth() async {
    try {
      final response = await http.get(
          Uri.parse('$baseUrl/api/system-admin/system-health'),
          headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
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
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
    }
  }

  Future<Map<String, dynamic>> backupDatabase() async {
    try {
      final response = await http.post(
          Uri.parse('$baseUrl/api/system-admin/database/backup'),
          headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
    }
  }

  Future<Map<String, dynamic>> backupStoreData(String storeId) async {
    try {
      final response = await http.post(
          Uri.parse('$baseUrl/api/system-admin/database/backup/store/$storeId'),
          headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
    }
  }

  Future<Map<String, dynamic>> getBackupFiles() async {
    try {
      final response = await http.get(
          Uri.parse('$baseUrl/api/system-admin/database/backups'),
          headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
    }
  }

  Future<Map<String, dynamic>> deleteBackupFile(String fileName) async {
    try {
      final response = await http.delete(
          Uri.parse('$baseUrl/api/system-admin/database/backups/$fileName'),
          headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
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
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
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
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
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
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
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
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
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
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
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
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
    }
  }

  Future<Map<String, dynamic>> getGeminiConfig() async {
    try {
      final response = await http.get(
          Uri.parse('$baseUrl/api/communications/ai/config'),
          headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
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
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
    }
  }

  Future<Map<String, dynamic>> testGeminiConnection() async {
    try {
      final response = await http.post(
          Uri.parse('$baseUrl/api/communications/ai/test'),
          headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
    }
  }

  Future<Map<String, dynamic>> getDeepSeekConfig() async {
    try {
      final response = await http.get(
          Uri.parse('$baseUrl/api/communications/ai/deepseek/config'),
          headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
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
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
    }
  }

  Future<Map<String, dynamic>> testDeepSeekConnection() async {
    try {
      final response = await http.post(
          Uri.parse('$baseUrl/api/communications/ai/deepseek/test'),
          headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
    }
  }

  // ==================== GOOGLE DRIVE ====================
  Future<Map<String, dynamic>> getGoogleDriveConfig() async {
    try {
      final response = await http.get(
          Uri.parse('$baseUrl/api/Storage/google-drive/config'),
          headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
    }
  }

  Future<Map<String, dynamic>> updateGoogleDriveConfig(
      Map<String, dynamic> data) async {
    try {
      final response = await http.post(
          Uri.parse('$baseUrl/api/Storage/google-drive/config'),
          headers: _headers,
          body: json.encode(data));
      return _handleResponse(response);
    } catch (e) {
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
    }
  }

  Future<Map<String, dynamic>> testGoogleDriveConnection() async {
    try {
      final response = await http.post(
          Uri.parse('$baseUrl/api/Storage/google-drive/test'),
          headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
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
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
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
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
    }
  }

  Future<Map<String, dynamic>> verifyOtp(String storeCode, String email,
      String otp, String newPassword, String confirmPassword) async {
    try {
      final response =
          await http.post(Uri.parse('$baseUrl/api/Auth/VerifyOtp'),
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
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
    }
  }

  // ==================== DEVICE ATTENDANCE ====================
  Future<Map<String, dynamic>> deleteAttendancesByDevice(
      {required String deviceId, DateTime? fromDate, DateTime? toDate}) async {
    try {
      if (!await isDeviceOnline(deviceId)) {
        return {'isSuccess': false, 'message': 'Thiết bị đang offline. Vui lòng kiểm tra kết nối mạng của máy chấm công.'};
      }
      final params = <String, String>{};
      if (fromDate != null) params['fromDate'] = fromDate.toIso8601String();
      if (toDate != null) params['toDate'] = toDate.toIso8601String();
      final uri = Uri.parse('$baseUrl/api/Attendances/devices/$deviceId')
          .replace(queryParameters: params.isNotEmpty ? params : null);
      final response = await http.delete(uri, headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
    }
  }

  Future<Map<String, dynamic>> syncAttendances(String deviceId,
      {DateTime? fromTime, DateTime? toTime}) async {
    try {
      if (!await isDeviceOnline(deviceId)) {
        return {'isSuccess': false, 'message': 'Thiết bị đang offline. Vui lòng kiểm tra kết nối mạng của máy chấm công.'};
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
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
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
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
    }
  }

  Future<Map<String, dynamic>> getCommunicationDetail(String id) async {
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/api/communications/$id'), headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      debugPrint('Error getting communication detail: $e');
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
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
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
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
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
    }
  }

  Future<Map<String, dynamic>> getCommunicationComments(String id) async {
    try {
      final response = await http.get(
          Uri.parse('$baseUrl/api/communications/$id/comments'),
          headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
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
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
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
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
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
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
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
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
    }
  }

  String getFileUrl(String path) {
    if (path.startsWith('http')) return path;
    final cleanPath = path.startsWith('/') ? path.substring(1) : path;
    return '$baseUrl/$cleanPath';
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
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
    }
  }

  // ==================== KPI ====================
  Future<Map<String, dynamic>> getKpiConfigs() async {
    try {
      final response = await http.get(Uri.parse('$baseUrl/api/kpi/configs'),
          headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
    }
  }

  Future<Map<String, dynamic>> createKpiConfig(
      Map<String, dynamic> data) async {
    try {
      final response = await http.post(Uri.parse('$baseUrl/api/kpi/configs'),
          headers: _headers, body: json.encode(data));
      return _handleResponse(response);
    } catch (e) {
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
    }
  }

  Future<Map<String, dynamic>> updateKpiConfig(
      String id, Map<String, dynamic> data) async {
    try {
      final response = await http.put(Uri.parse('$baseUrl/api/kpi/configs/$id'),
          headers: _headers, body: json.encode(data));
      return _handleResponse(response);
    } catch (e) {
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
    }
  }

  Future<Map<String, dynamic>> deleteKpiConfig(String id) async {
    try {
      final response = await http
          .delete(Uri.parse('$baseUrl/api/kpi/configs/$id'), headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
    }
  }

  Future<Map<String, dynamic>> getKpiPeriods() async {
    try {
      final response = await http.get(Uri.parse('$baseUrl/api/kpi/periods'),
          headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
    }
  }

  Future<Map<String, dynamic>> createKpiPeriod(
      Map<String, dynamic> data) async {
    try {
      final response = await http.post(Uri.parse('$baseUrl/api/kpi/periods'),
          headers: _headers, body: json.encode(data));
      return _handleResponse(response);
    } catch (e) {
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
    }
  }

  Future<Map<String, dynamic>> updateKpiPeriod(
      String id, Map<String, dynamic> data) async {
    try {
      final response = await http.put(Uri.parse('$baseUrl/api/kpi/periods/$id'),
          headers: _headers, body: json.encode(data));
      return _handleResponse(response);
    } catch (e) {
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
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
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
    }
  }

  Future<Map<String, dynamic>> deleteKpiPeriod(String id) async {
    try {
      final response = await http
          .delete(Uri.parse('$baseUrl/api/kpi/periods/$id'), headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
    }
  }

  Future<Map<String, dynamic>> getKpiBonusRules() async {
    try {
      final response = await http.get(Uri.parse('$baseUrl/api/kpi/bonus-rules'),
          headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
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
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
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
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
    }
  }

  Future<Map<String, dynamic>> saveKpiResults(Map<String, dynamic> data) async {
    try {
      final response = await http.post(Uri.parse('$baseUrl/api/kpi/results'),
          headers: _headers, body: json.encode(data));
      return _handleResponse(response);
    } catch (e) {
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
    }
  }

  Future<Map<String, dynamic>> getKpiDashboard() async {
    try {
      final response = await http.get(Uri.parse('$baseUrl/api/kpi/dashboard'),
          headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
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
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
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
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
    }
  }

  Future<Map<String, dynamic>> deleteKpiEmployeeTarget(String id) async {
    try {
      final response = await http.delete(
          Uri.parse('$baseUrl/api/kpi/employee-targets/$id'),
          headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
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
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
    }
  }

  Future<Map<String, dynamic>> getKpiSalaries(String periodId) async {
    try {
      final uri = Uri.parse('$baseUrl/api/kpi/salary')
          .replace(queryParameters: {'periodId': periodId});
      final response = await http.get(uri, headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
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
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
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
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
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
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
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
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
    }
  }

  Future<Map<String, dynamic>> syncKpiActualsFromGSheet(String periodId) async {
    try {
      final response = await http.post(
          Uri.parse('$baseUrl/api/kpi/sync-actuals/$periodId'),
          headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
    }
  }

  Future<Map<String, dynamic>> getGSheetCredentialsStatus() async {
    try {
      final response = await http.get(
          Uri.parse('$baseUrl/api/kpi/gsheet-config/credentials-status'),
          headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
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
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
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
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
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
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
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
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
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
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
    }
  }

  // ==================== OVERTIMES ====================
  Future<Map<String, dynamic>> getOvertimes(
      {String? status, DateTime? fromDate, DateTime? toDate}) async {
    try {
      final params = <String, String>{};
      if (status != null) params['status'] = status;
      if (fromDate != null) params['fromDate'] = fromDate.toIso8601String();
      if (toDate != null) params['toDate'] = toDate.toIso8601String();
      final uri = Uri.parse('$baseUrl/api/overtimes')
          .replace(queryParameters: params.isNotEmpty ? params : null);
      final response = await http.get(uri, headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
    }
  }

  Future<Map<String, dynamic>> getMyOvertimes() async {
    try {
      final response = await http.get(
          Uri.parse('$baseUrl/api/overtimes/my-overtimes'),
          headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
    }
  }

  Future<Map<String, dynamic>> createOvertime(Map<String, dynamic> data) async {
    try {
      final response = await http.post(Uri.parse('$baseUrl/api/overtimes'),
          headers: _headers, body: json.encode(data));
      return _handleResponse(response);
    } catch (e) {
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
    }
  }

  Future<Map<String, dynamic>> updateOvertime(
      String id, Map<String, dynamic> data) async {
    try {
      final response = await http.put(Uri.parse('$baseUrl/api/overtimes/$id'),
          headers: _headers, body: json.encode(data));
      return _handleResponse(response);
    } catch (e) {
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
    }
  }

  Future<Map<String, dynamic>> cancelOvertime(String id) async {
    try {
      final response = await http
          .delete(Uri.parse('$baseUrl/api/overtimes/$id'), headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
    }
  }

  Future<Map<String, dynamic>> getPendingOvertimes() async {
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/api/overtimes/pending'), headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
    }
  }

  Future<Map<String, dynamic>> approveOvertime(String id) async {
    try {
      final response = await http.post(
          Uri.parse('$baseUrl/api/overtimes/$id/approve'),
          headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
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
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
    }
  }

  Future<Map<String, dynamic>> completeOvertime(String id) async {
    try {
      final response = await http.post(
          Uri.parse('$baseUrl/api/overtimes/$id/complete'),
          headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
    }
  }

  Future<Map<String, dynamic>> getOvertimeStatistics() async {
    try {
      final response = await http.get(
          Uri.parse('$baseUrl/api/overtimes/statistics'),
          headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
    }
  }

  // ==================== PAYSLIPS ====================
  Future<Map<String, dynamic>> generatePayslip(
      Map<String, dynamic> data) async {
    try {
      final response = await http.post(
          Uri.parse('$baseUrl/api/payslips/generate'),
          headers: _headers,
          body: json.encode(data));
      return _handleResponse(response);
    } catch (e) {
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
    }
  }

  Future<Map<String, dynamic>> getEmployeePayslips(
      String employeeUserId) async {
    try {
      final response = await http.get(
          Uri.parse('$baseUrl/api/payslips/employee/$employeeUserId'),
          headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
    }
  }

  Future<Map<String, dynamic>> getMyPayslips() async {
    try {
      final response = await http.get(
          Uri.parse('$baseUrl/api/payslips/my-payslips'),
          headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
    }
  }

  Future<Map<String, dynamic>> getPayslipById(String id) async {
    try {
      final response = await http.get(Uri.parse('$baseUrl/api/payslips/$id'),
          headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
    }
  }

  // ==================== SHIFT SWAPS ====================
  Future<Map<String, dynamic>> getShiftSwaps() async {
    try {
      final response = await http.get(Uri.parse('$baseUrl/api/shiftswaps'),
          headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
    }
  }

  Future<Map<String, dynamic>> getShiftSwapsPendingForMe() async {
    try {
      final response = await http.get(
          Uri.parse('$baseUrl/api/shiftswaps/pending-for-me'),
          headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
    }
  }

  Future<Map<String, dynamic>> getShiftSwapsPendingApproval() async {
    try {
      final response = await http.get(
          Uri.parse('$baseUrl/api/shiftswaps/pending-approval'),
          headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
    }
  }

  Future<Map<String, dynamic>> createShiftSwap(
      Map<String, dynamic> data) async {
    try {
      final response = await http.post(Uri.parse('$baseUrl/api/shiftswaps'),
          headers: _headers, body: json.encode(data));
      return _handleResponse(response);
    } catch (e) {
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
    }
  }

  Future<Map<String, dynamic>> respondToShiftSwap(
      String id, Map<String, dynamic> data) async {
    try {
      final response = await http.post(
          Uri.parse('$baseUrl/api/shiftswaps/$id/respond'),
          headers: _headers,
          body: json.encode(data));
      return _handleResponse(response);
    } catch (e) {
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
    }
  }

  Future<Map<String, dynamic>> approveShiftSwap(String id) async {
    try {
      final response = await http.post(
          Uri.parse('$baseUrl/api/shiftswaps/$id/approve'),
          headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
    }
  }

  Future<Map<String, dynamic>> cancelShiftSwap(String id) async {
    try {
      final response = await http
          .delete(Uri.parse('$baseUrl/api/shiftswaps/$id'), headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
    }
  }

  // ==================== SHIFTS (Registration/Approval) ====================
  Future<Map<String, dynamic>> getMyShifts() async {
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/api/shifts/my-shifts'), headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
    }
  }

  Future<Map<String, dynamic>> createShiftRegistration(
      Map<String, dynamic> data) async {
    try {
      final response = await http.post(Uri.parse('$baseUrl/api/shifts'),
          headers: _headers, body: json.encode(data));
      return _handleResponse(response);
    } catch (e) {
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
    }
  }

  Future<Map<String, dynamic>> deleteShiftRegistration(String id) async {
    try {
      final response = await http.delete(Uri.parse('$baseUrl/api/shifts/$id'),
          headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
    }
  }

  Future<Map<String, dynamic>> getPendingShifts() async {
    try {
      final response = await http.get(Uri.parse('$baseUrl/api/shifts/pending'),
          headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
    }
  }

  Future<Map<String, dynamic>> getManagedShifts() async {
    try {
      final response = await http.get(Uri.parse('$baseUrl/api/shifts/managed'),
          headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
    }
  }

  Future<Map<String, dynamic>> approveShift(String id) async {
    try {
      final response = await http.post(
          Uri.parse('$baseUrl/api/shifts/$id/approve'),
          headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
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
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
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
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
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
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
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
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
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
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
    }
  }

  Future<Map<String, dynamic>> deleteShiftSalaryLevel(String id) async {
    try {
      final response = await http.delete(
          Uri.parse('$baseUrl/api/shift-salary-levels/$id'),
          headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
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
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
    }
  }

  Future<Map<String, dynamic>> getBiometricSummary(String deviceId) async {
    try {
      final response = await http.get(
          Uri.parse('$baseUrl/api/biometrics/device/$deviceId/summary'),
          headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
    }
  }

  Future<Map<String, dynamic>> syncBiometrics(String deviceId) async {
    try {
      if (!await isDeviceOnline(deviceId)) {
        return {'isSuccess': false, 'message': 'Thiết bị đang offline. Vui lòng kiểm tra kết nối mạng của máy chấm công.'};
      }
      final response = await http.post(
          Uri.parse('$baseUrl/api/biometrics/device/$deviceId/sync'),
          headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
    }
  }

  Future<Map<String, dynamic>> cancelBiometricSync(String deviceId) async {
    try {
      final response = await http.post(
          Uri.parse('$baseUrl/api/biometrics/device/$deviceId/cancel-sync'),
          headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
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
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
    }
  }

  // ==================== GEOFENCES ====================
  Future<Map<String, dynamic>> getGeofences() async {
    try {
      final response = await http.get(Uri.parse('$baseUrl/api/geofences'),
          headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
    }
  }

  Future<Map<String, dynamic>> createGeofence(Map<String, dynamic> data) async {
    try {
      final response = await http.post(Uri.parse('$baseUrl/api/geofences'),
          headers: _headers, body: json.encode(data));
      return _handleResponse(response);
    } catch (e) {
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
    }
  }

  Future<Map<String, dynamic>> updateGeofence(
      String id, Map<String, dynamic> data) async {
    try {
      final response = await http.put(Uri.parse('$baseUrl/api/geofences/$id'),
          headers: _headers, body: json.encode(data));
      return _handleResponse(response);
    } catch (e) {
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
    }
  }

  Future<Map<String, dynamic>> deleteGeofence(String id) async {
    try {
      final response = await http
          .delete(Uri.parse('$baseUrl/api/geofences/$id'), headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
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
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
    }
  }

  // ==================== HR DOCUMENTS ====================
  Future<Map<String, dynamic>> getHrDocuments(
      {String? employeeId, String? type}) async {
    try {
      final params = <String, String>{};
      if (employeeId != null) params['employeeId'] = employeeId;
      if (type != null) params['type'] = type;
      final uri = Uri.parse('$baseUrl/api/hr-documents')
          .replace(queryParameters: params.isNotEmpty ? params : null);
      final response = await http.get(uri, headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
    }
  }

  Future<Map<String, dynamic>> getExpiringDocuments() async {
    try {
      final response = await http.get(
          Uri.parse('$baseUrl/api/hr-documents/expiring'),
          headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
    }
  }

  Future<Map<String, dynamic>> createHrDocument(
      Map<String, dynamic> data) async {
    try {
      final response = await http.post(Uri.parse('$baseUrl/api/hr-documents'),
          headers: _headers, body: json.encode(data));
      return _handleResponse(response);
    } catch (e) {
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
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
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
    }
  }

  Future<Map<String, dynamic>> deleteHrDocument(String id) async {
    try {
      final response = await http.delete(
          Uri.parse('$baseUrl/api/hr-documents/$id'),
          headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
    }
  }

  // ==================== USER MANAGEMENT ====================
  Future<Map<String, dynamic>> getUsers() async {
    try {
      final response =
          await http.get(Uri.parse('$baseUrl/api/users'), headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
    }
  }

  Future<Map<String, dynamic>> getUserById(String userId) async {
    try {
      final response = await http.get(Uri.parse('$baseUrl/api/users/$userId'),
          headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
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
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
    }
  }

  Future<Map<String, dynamic>> getAvailableRoles() async {
    try {
      final response = await _retryOnUnauthorized(() => http.get(
          Uri.parse('$baseUrl/api/users/available-roles'),
          headers: _headers));
      return _handleResponse(response);
    } catch (e) {
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
    }
  }

  Future<Map<String, dynamic>> lockUser(String userId) async {
    try {
      final response = await _retryOnUnauthorized(() => http.post(
          Uri.parse('$baseUrl/api/users/$userId/lock'),
          headers: _headers));
      return _handleResponse(response);
    } catch (e) {
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
    }
  }

  Future<Map<String, dynamic>> unlockUser(String userId) async {
    try {
      final response = await _retryOnUnauthorized(() => http.post(
          Uri.parse('$baseUrl/api/users/$userId/unlock'),
          headers: _headers));
      return _handleResponse(response);
    } catch (e) {
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
    }
  }

  Future<Map<String, dynamic>> resetUserPassword(String userId, {String? newPassword}) async {
    try {
      final response = await _retryOnUnauthorized(() => http.post(
          Uri.parse('$baseUrl/api/users/$userId/reset-password'),
          headers: _headers,
          body: json.encode({'newPassword': newPassword ?? ''})));
      return _handleResponse(response);
    } catch (e) {
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
    }
  }

  Future<Map<String, dynamic>> updateUser(
      String userId, Map<String, dynamic> data) async {
    try {
      final response = await _retryOnUnauthorized(() => http.put(Uri.parse('$baseUrl/api/users/$userId'),
          headers: _headers, body: json.encode(data)));
      return _handleResponse(response);
    } catch (e) {
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
    }
  }

  Future<Map<String, dynamic>> deleteUser(String userId) async {
    try {
      final response = await _retryOnUnauthorized(() => http
          .delete(Uri.parse('$baseUrl/api/users/$userId'), headers: _headers));
      return _handleResponse(response);
    } catch (e) {
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
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
      // Handle empty body (e.g. 204 No Content)
      if (response.body.isEmpty) {
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
      final data = json.decode(response.body);
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return data is Map<String, dynamic>
            ? data
            : {'isSuccess': true, 'data': data};
      } else {
        // Extract error message from various API response formats
        String errorMessage = 'Lỗi không xác định';
        if (data is Map<String, dynamic>) {
          if (data['message'] != null) {
            errorMessage = data['message'];
          } else if (data['title'] != null) {
            // ASP.NET ProblemDetails format - prefer detail over title (title is often just exception type name)
            errorMessage = data['detail'] ?? data['title'];
            if (data['errors'] is Map) {
              final errors = (data['errors'] as Map)
                  .values
                  .expand((v) => v is List ? v : [v])
                  .join(', ');
              if (errors.isNotEmpty) errorMessage = errors;
            }
          }
        }
        return {
          'isSuccess': false,
          'message': errorMessage,
          'statusCode': response.statusCode,
        };
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
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
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
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
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
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
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
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
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
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
    }
  }

  /// Thống kê phiếu phạt
  Future<Map<String, dynamic>> getPenaltyTicketStats(
      {int? month, int? year}) async {
    try {
      var queryParams = '';
      if (month != null) queryParams += 'month=$month&';
      if (year != null) queryParams += 'year=$year';

      final response = await http
          .get(
            Uri.parse('$baseUrl/api/PenaltyTickets/stats?$queryParams'),
            headers: _headers,
          )
          .timeout(const Duration(seconds: 10));
      return _handleResponse(response);
    } catch (e) {
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
    }
  }

  /// Tạo phiếu phạt thủ công
  Future<Map<String, dynamic>> createPenaltyTicket(Map<String, dynamic> data) async {
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
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
    }
  }

  /// Sửa phiếu phạt
  Future<Map<String, dynamic>> updatePenaltyTicket(String id, Map<String, dynamic> data) async {
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
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
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
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
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
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
    }
  }

  // ══════════ AGENT PORTAL ══════════

  Future<Map<String, dynamic>> getAgentProfile() async {
    try {
      final response = await http.get(
          Uri.parse('$baseUrl/api/agent/profile'),
          headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
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
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
    }
  }

  // ==================== PRODUCTION / PIECE-RATE SALARY ====================

  // ── Product Groups ──
  Future<Map<String, dynamic>> getProductGroups() async {
    try {
      final response = await http.get(
          Uri.parse('$baseUrl/api/production/groups'), headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
    }
  }

  Future<Map<String, dynamic>> createProductGroup(Map<String, dynamic> data) async {
    try {
      final response = await http.post(
          Uri.parse('$baseUrl/api/production/groups'),
          headers: _headers, body: json.encode(data));
      return _handleResponse(response);
    } catch (e) {
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
    }
  }

  Future<Map<String, dynamic>> updateProductGroup(String id, Map<String, dynamic> data) async {
    try {
      final response = await http.put(
          Uri.parse('$baseUrl/api/production/groups/$id'),
          headers: _headers, body: json.encode(data));
      return _handleResponse(response);
    } catch (e) {
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
    }
  }

  Future<Map<String, dynamic>> deleteProductGroup(String id) async {
    try {
      final response = await http.delete(
          Uri.parse('$baseUrl/api/production/groups/$id'), headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
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
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
    }
  }

  Future<Map<String, dynamic>> createProductItem(Map<String, dynamic> data) async {
    try {
      final response = await http.post(
          Uri.parse('$baseUrl/api/production/items'),
          headers: _headers, body: json.encode(data));
      return _handleResponse(response);
    } catch (e) {
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
    }
  }

  Future<Map<String, dynamic>> updateProductItem(String id, Map<String, dynamic> data) async {
    try {
      final response = await http.put(
          Uri.parse('$baseUrl/api/production/items/$id'),
          headers: _headers, body: json.encode(data));
      return _handleResponse(response);
    } catch (e) {
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
    }
  }

  Future<Map<String, dynamic>> deleteProductItem(String id) async {
    try {
      final response = await http.delete(
          Uri.parse('$baseUrl/api/production/items/$id'), headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
    }
  }

  // ── Production Entries ──
  Future<Map<String, dynamic>> getProductionEntries({
    DateTime? fromDate, DateTime? toDate,
    String? employeeId, String? productGroupId, String? productItemId,
    int page = 1, int pageSize = 50,
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
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
    }
  }

  Future<Map<String, dynamic>> createProductionEntry(Map<String, dynamic> data) async {
    try {
      final response = await http.post(
          Uri.parse('$baseUrl/api/production/entries'),
          headers: _headers, body: json.encode(data));
      return _handleResponse(response);
    } catch (e) {
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
    }
  }

  Future<Map<String, dynamic>> createProductionEntryBatch(List<Map<String, dynamic>> entries) async {
    try {
      final response = await http.post(
          Uri.parse('$baseUrl/api/production/entries/batch'),
          headers: _headers, body: json.encode({'entries': entries}));
      return _handleResponse(response);
    } catch (e) {
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
    }
  }

  Future<Map<String, dynamic>> updateProductionEntry(String id, Map<String, dynamic> data) async {
    try {
      final response = await http.put(
          Uri.parse('$baseUrl/api/production/entries/$id'),
          headers: _headers, body: json.encode(data));
      return _handleResponse(response);
    } catch (e) {
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
    }
  }

  Future<Map<String, dynamic>> deleteProductionEntry(String id) async {
    try {
      final response = await http.delete(
          Uri.parse('$baseUrl/api/production/entries/$id'), headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
    }
  }

  // ── Production Summary ──
  Future<Map<String, dynamic>> getProductionSummary({
    required DateTime fromDate, required DateTime toDate,
    String? employeeId, String? productGroupId,
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
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
    }
  }

  // ── Production Import ──

  Future<Map<String, dynamic>> importProductionFromExcel(Map<String, dynamic> data) async {
    try {
      final response = await http.post(
          Uri.parse('$baseUrl/api/production/import'),
          headers: _headers, body: json.encode(data));
      return _handleResponse(response);
    } catch (e) {
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
    }
  }

  Future<Map<String, dynamic>> testProductionGSheetConnection(Map<String, dynamic> data) async {
    try {
      final response = await http.post(
          Uri.parse('$baseUrl/api/production/gsheet/test-connection'),
          headers: _headers, body: json.encode(data));
      return _handleResponse(response);
    } catch (e) {
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
    }
  }

  Future<Map<String, dynamic>> getProductionGSheetNames(Map<String, dynamic> data) async {
    try {
      final response = await http.post(
          Uri.parse('$baseUrl/api/production/gsheet/sheet-names'),
          headers: _headers, body: json.encode(data));
      return _handleResponse(response);
    } catch (e) {
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
    }
  }

  Future<Map<String, dynamic>> syncProductionFromGSheet(Map<String, dynamic> data) async {
    try {
      final response = await http.post(
          Uri.parse('$baseUrl/api/production/gsheet/sync'),
          headers: _headers, body: json.encode(data));
      return _handleResponse(response);
    } catch (e) {
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
    }
  }

  Future<Map<String, dynamic>> syncProductionFromGSheetMulti(Map<String, dynamic> data) async {
    try {
      final response = await http.post(
          Uri.parse('$baseUrl/api/production/gsheet/sync-multi'),
          headers: _headers, body: json.encode(data));
      return _handleResponse(response);
    } catch (e) {
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
    }
  }

  // ══════════════════ FEEDBACK / Ý KIẾN ══════════════════

  Future<Map<String, dynamic>> getFeedbacks({
    String? status, String? category, int page = 1, int pageSize = 20,
  }) async {
    try {
      final params = <String, String>{
        'page': page.toString(), 'pageSize': pageSize.toString(),
      };
      if (status != null) params['status'] = status;
      if (category != null) params['category'] = category;
      final uri = Uri.parse('$baseUrl/api/feedback')
          .replace(queryParameters: params);
      final response = await http.get(uri, headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
    }
  }

  Future<Map<String, dynamic>> getMyFeedbacks() async {
    try {
      final response = await http.get(
          Uri.parse('$baseUrl/api/feedback/my'), headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
    }
  }

  Future<Map<String, dynamic>> createFeedback(Map<String, dynamic> data) async {
    try {
      final response = await http.post(
          Uri.parse('$baseUrl/api/feedback'),
          headers: _headers, body: json.encode(data));
      return _handleResponse(response);
    } catch (e) {
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
    }
  }

  Future<Map<String, dynamic>> respondFeedback(String id, Map<String, dynamic> data) async {
    try {
      final response = await http.put(
          Uri.parse('$baseUrl/api/feedback/$id/respond'),
          headers: _headers, body: json.encode(data));
      return _handleResponse(response);
    } catch (e) {
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
    }
  }

  Future<Map<String, dynamic>> deleteFeedback(String id) async {
    try {
      final response = await http.delete(
          Uri.parse('$baseUrl/api/feedback/$id'), headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
    }
  }

  Future<Map<String, dynamic>> getFeedbackManagers() async {
    try {
      final response = await http.get(
          Uri.parse('$baseUrl/api/feedback/managers'), headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
    }
  }

  // ==================== MEAL TRACKING ====================

  Future<Map<String, dynamic>> getMealSessions() async {
    try {
      final response = await http.get(
          Uri.parse('$baseUrl/api/meals/sessions'), headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
    }
  }

  Future<Map<String, dynamic>> createMealSession(Map<String, dynamic> data) async {
    try {
      final response = await http.post(
          Uri.parse('$baseUrl/api/meals/sessions'),
          headers: _headers,
          body: jsonEncode(data));
      return _handleResponse(response);
    } catch (e) {
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
    }
  }

  Future<Map<String, dynamic>> updateMealSession(String id, Map<String, dynamic> data) async {
    try {
      final response = await http.put(
          Uri.parse('$baseUrl/api/meals/sessions/$id'),
          headers: _headers,
          body: jsonEncode(data));
      return _handleResponse(response);
    } catch (e) {
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
    }
  }

  Future<Map<String, dynamic>> deleteMealSession(String id) async {
    try {
      final response = await http.delete(
          Uri.parse('$baseUrl/api/meals/sessions/$id'), headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
    }
  }

  Future<Map<String, dynamic>> getMealEstimate({String? date}) async {
    try {
      final queryParams = <String, String>{};
      if (date != null) queryParams['date'] = date;
      final uri = Uri.parse('$baseUrl/api/meals/estimate').replace(queryParameters: queryParams.isNotEmpty ? queryParams : null);
      final response = await http.get(uri, headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
    }
  }

  Future<Map<String, dynamic>> getMealRecords({
    String? date,
    String? mealSessionId,
    int page = 1,
    int pageSize = 20,
  }) async {
    try {
      final queryParams = <String, String>{
        'page': page.toString(),
        'pageSize': pageSize.toString(),
      };
      if (date != null) queryParams['date'] = date;
      if (mealSessionId != null) queryParams['mealSessionId'] = mealSessionId;
      final uri = Uri.parse('$baseUrl/api/meals/records').replace(queryParameters: queryParams);
      final response = await http.get(uri, headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
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
      if (employeeUserId != null) queryParams['employeeUserId'] = employeeUserId;
      final uri = Uri.parse('$baseUrl/api/meals/summary').replace(queryParameters: queryParams);
      final response = await http.get(uri, headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
    }
  }

  Future<Map<String, dynamic>> getMealMenu({String? date, String? mealSessionId}) async {
    try {
      final queryParams = <String, String>{};
      if (date != null) queryParams['date'] = date;
      if (mealSessionId != null) queryParams['mealSessionId'] = mealSessionId;
      final uri = Uri.parse('$baseUrl/api/meals/menu').replace(queryParameters: queryParams.isNotEmpty ? queryParams : null);
      final response = await http.get(uri, headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
    }
  }

  Future<Map<String, dynamic>> getWeeklyMealMenu({String? weekStartDate}) async {
    try {
      final queryParams = <String, String>{};
      if (weekStartDate != null) queryParams['weekStartDate'] = weekStartDate;
      final uri = Uri.parse('$baseUrl/api/meals/menu/weekly').replace(queryParameters: queryParams.isNotEmpty ? queryParams : null);
      final response = await http.get(uri, headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
    }
  }

  Future<Map<String, dynamic>> createMealMenu(Map<String, dynamic> data) async {
    try {
      final response = await http.post(
          Uri.parse('$baseUrl/api/meals/menu'),
          headers: _headers,
          body: jsonEncode(data));
      return _handleResponse(response);
    } catch (e) {
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
    }
  }

  Future<Map<String, dynamic>> updateMealMenu(String id, Map<String, dynamic> data) async {
    try {
      final response = await http.put(
          Uri.parse('$baseUrl/api/meals/menu/$id'),
          headers: _headers,
          body: jsonEncode(data));
      return _handleResponse(response);
    } catch (e) {
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
    }
  }

  // ── Meal Registration (đăng ký suất ăn) ──

  Future<Map<String, dynamic>> registerMeal(Map<String, dynamic> data) async {
    try {
      final response = await http.post(
          Uri.parse('$baseUrl/api/meals/register'),
          headers: _headers,
          body: jsonEncode(data));
      return _handleResponse(response);
    } catch (e) {
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
    }
  }

  Future<Map<String, dynamic>> batchRegisterMeal(List<Map<String, dynamic>> registrations) async {
    try {
      final response = await http.post(
          Uri.parse('$baseUrl/api/meals/register/batch'),
          headers: _headers,
          body: jsonEncode({'registrations': registrations}));
      return _handleResponse(response);
    } catch (e) {
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
    }
  }

  Future<Map<String, dynamic>> getMyMealRegistrations({DateTime? fromDate, DateTime? toDate}) async {
    try {
      final params = <String, String>{};
      if (fromDate != null) params['fromDate'] = fromDate.toIso8601String().split('T')[0];
      if (toDate != null) params['toDate'] = toDate.toIso8601String().split('T')[0];
      final query = params.isNotEmpty ? '?${params.entries.map((e) => '${e.key}=${e.value}').join('&')}' : '';
      final response = await http.get(
          Uri.parse('$baseUrl/api/meals/register/my$query'),
          headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
    }
  }

  Future<Map<String, dynamic>> getMealRegistrationSummary({String? date, String? mealSessionId}) async {
    try {
      final params = <String, String>{};
      if (date != null) params['date'] = date;
      if (mealSessionId != null) params['mealSessionId'] = mealSessionId;
      final query = params.isNotEmpty ? '?${params.entries.map((e) => '${e.key}=${e.value}').join('&')}' : '';
      final response = await http.get(
          Uri.parse('$baseUrl/api/meals/register/summary$query'),
          headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
    }
  }

  Future<Map<String, dynamic>> qrMealCheckIn({String? mealSessionId, String? qrCode}) async {
    try {
      final response = await http.post(
          Uri.parse('$baseUrl/api/meals/checkin/qr'),
          headers: _headers,
          body: jsonEncode({
            if (mealSessionId != null) 'mealSessionId': mealSessionId,
            if (qrCode != null) 'qrCode': qrCode,
          }));
      return _handleResponse(response);
    } catch (e) {
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
    }
  }

  // ==================== FIELD CHECK-IN / CHECK-IN ĐIỂM BÁN ====================

  // --- Field Locations (Điểm bán khách hàng) ---

  Future<Map<String, dynamic>> getFieldLocations({String? search, String? category}) async {
    try {
      final params = <String, String>{};
      if (search != null && search.isNotEmpty) params['search'] = search;
      if (category != null && category.isNotEmpty) params['category'] = category;
      final query = params.isNotEmpty
          ? '?${params.entries.map((e) => '${e.key}=${Uri.encodeComponent(e.value)}').join('&')}'
          : '';
      final response = await http.get(
          Uri.parse('$baseUrl/api/field-checkin/locations$query'),
          headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
    }
  }

  Future<Map<String, dynamic>> registerFieldLocation(Map<String, dynamic> data) async {
    try {
      final response = await http.post(
          Uri.parse('$baseUrl/api/field-checkin/locations'),
          headers: _headers,
          body: jsonEncode(data));
      return _handleResponse(response);
    } catch (e) {
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
    }
  }

  Future<Map<String, dynamic>> updateFieldLocation(String id, Map<String, dynamic> data) async {
    try {
      final response = await http.put(
          Uri.parse('$baseUrl/api/field-checkin/locations/$id'),
          headers: _headers,
          body: jsonEncode(data));
      return _handleResponse(response);
    } catch (e) {
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
    }
  }

  Future<Map<String, dynamic>> deleteFieldLocation(String id) async {
    try {
      final response = await http.delete(
          Uri.parse('$baseUrl/api/field-checkin/locations/$id'),
          headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
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
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
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
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
    }
  }

  Future<Map<String, dynamic>> createFieldAssignment(Map<String, dynamic> data) async {
    try {
      final response = await http.post(
          Uri.parse('$baseUrl/api/field-checkin/assignments'),
          headers: _headers,
          body: jsonEncode(data));
      return _handleResponse(response);
    } catch (e) {
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
    }
  }

  Future<Map<String, dynamic>> bulkFieldAssign(List<Map<String, dynamic>> items) async {
    try {
      final response = await http.post(
          Uri.parse('$baseUrl/api/field-checkin/assignments/bulk'),
          headers: _headers,
          body: jsonEncode({'items': items}));
      return _handleResponse(response);
    } catch (e) {
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
    }
  }

  Future<Map<String, dynamic>> updateFieldAssignment(String id, Map<String, dynamic> data) async {
    try {
      final response = await http.put(
          Uri.parse('$baseUrl/api/field-checkin/assignments/$id'),
          headers: _headers,
          body: jsonEncode(data));
      return _handleResponse(response);
    } catch (e) {
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
    }
  }

  Future<Map<String, dynamic>> deleteFieldAssignment(String id) async {
    try {
      final response = await http.delete(
          Uri.parse('$baseUrl/api/field-checkin/assignments/$id'),
          headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
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
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
    }
  }

  Future<Map<String, dynamic>> fieldCheckOut(String visitId, Map<String, dynamic> data) async {
    try {
      final response = await http.post(
          Uri.parse('$baseUrl/api/field-checkin/checkout/$visitId'),
          headers: _headers,
          body: jsonEncode(data));
      return _handleResponse(response);
    } catch (e) {
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
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
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
    }
  }

  Future<Map<String, dynamic>> getTodayFieldVisits() async {
    try {
      final response = await http.get(
          Uri.parse('$baseUrl/api/field-checkin/today'),
          headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
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
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
    }
  }

  Future<Map<String, dynamic>> reviewFieldVisit(String visitId, Map<String, dynamic> data) async {
    try {
      final response = await http.post(
          Uri.parse('$baseUrl/api/field-checkin/review/$visitId'),
          headers: _headers,
          body: jsonEncode(data));
      return _handleResponse(response);
    } catch (e) {
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
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
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
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
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
    }
  }

  Future<Map<String, dynamic>> trackJourneyPoints(List<Map<String, dynamic>> points) async {
    try {
      final response = await http.post(
          Uri.parse('$baseUrl/api/field-checkin/journey/track'),
          headers: _headers,
          body: jsonEncode({'points': points}));
      return _handleResponse(response);
    } catch (e) {
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
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
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
    }
  }

  Future<Map<String, dynamic>> getTodayJourney() async {
    try {
      final response = await http.get(
          Uri.parse('$baseUrl/api/field-checkin/journey/today'),
          headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
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
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
    }
  }

  Future<Map<String, dynamic>> getActiveJourneys() async {
    try {
      final response = await http.get(
          Uri.parse('$baseUrl/api/field-checkin/journey/active'),
          headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
    }
  }

  Future<Map<String, dynamic>> getEmployeeLocations() async {
    try {
      final response = await http.get(
          Uri.parse('$baseUrl/api/field-checkin/employee-locations'),
          headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
    }
  }

  Future<Map<String, dynamic>> getJourneyDetail(String journeyId) async {
    try {
      final response = await http.get(
          Uri.parse('$baseUrl/api/field-checkin/journey/$journeyId'),
          headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
    }
  }

  Future<Map<String, dynamic>> reviewJourney(String journeyId, {String? reviewNote}) async {
    try {
      final response = await http.post(
          Uri.parse('$baseUrl/api/field-checkin/journey/$journeyId/review'),
          headers: _headers,
          body: jsonEncode({'reviewNote': reviewNote}));
      return _handleResponse(response);
    } catch (e) {
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
    }
  }
}
