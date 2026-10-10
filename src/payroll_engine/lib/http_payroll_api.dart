/// Nguồn dữ liệu bảng lương chạy trên máy chủ: gọi đúng các API mà app gọi (cùng đường dẫn,
/// tham số, cách đọc phản hồi như `ApiService`) bằng token của người đang xem.
///
/// Chỉ dùng cho chương trình dòng lệnh (dart:io) — app web / di động không import file này.
library;

import 'dart:convert';
import 'dart:io';

import 'payroll_api.dart';

Map<String, String> _page(int page, int pageSize) => {
      'pageNumber': page.toString(),
      'pageSize': pageSize.toString(),
      'page': page.toString(),
    };

String _ymd(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

String _alDate(DateTime x) =>
    '${x.year}-${x.month.toString().padLeft(2, '0')}-${x.day.toString().padLeft(2, '0')}';

class HttpPayrollApi implements PayrollApi {
  HttpPayrollApi({
    required String baseUrl,
    required this.token,
    this.branchHeader,
    this.timeout = const Duration(seconds: 60),
  })
      : baseUrl = baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;

  final String baseUrl;
  final String token;

  /// Chi nhánh đang thao tác của người xem (header X-Branch-Id như app gửi) — để thấy đúng dữ liệu như app.
  final String? branchHeader;
  final Duration timeout;
  final HttpClient _client = HttpClient()..connectionTimeout = const Duration(seconds: 10);

  /// Số lần gọi API (theo dõi hiệu năng).
  int requestCount = 0;

  void close() => _client.close(force: true);

  Uri _uri(String path, [Map<String, String>? query]) =>
      Uri.parse('$baseUrl$path').replace(queryParameters: query == null || query.isEmpty ? null : query);

  Future<({int status, String body})> _send(String method, Uri uri, {Object? body}) async {
    requestCount++;
    final req = await _client.openUrl(method, uri).timeout(timeout);
    req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
    req.headers.set(HttpHeaders.acceptHeader, 'application/json');
    final branch = branchHeader;
    if (branch != null && branch.isNotEmpty) req.headers.set('X-Branch-Id', branch);
    if (body != null) {
      req.headers.contentType = ContentType.json;
      req.add(utf8.encode(jsonEncode(body)));
    }
    final res = await req.close().timeout(timeout);
    final bytes = await res.fold<List<int>>(<int>[], (a, b) => a..addAll(b)).timeout(timeout);
    return (status: res.statusCode, body: utf8.decode(bytes, allowMalformed: true));
  }

  /// Như `ApiService._normalizeResponseMap`.
  static Map<String, dynamic> _normalize(Map<String, dynamic> source) {
    final result = Map<String, dynamic>.from(source);
    if (result['isSuccess'] == null && result['IsSuccess'] != null) result['isSuccess'] = result['IsSuccess'];
    if (result['data'] == null && result['Data'] != null) result['data'] = result['Data'];
    final errors = result['errors'] ?? result['Errors'];
    if ((result['message'] == null || result['message'].toString().isEmpty) && errors is List && errors.isNotEmpty) {
      result['message'] = errors.map((e) => e.toString()).join('; ');
    }
    return result;
  }

  /// Như `ApiService._handleResponse`.
  static Map<String, dynamic> _handle(({int status, String body}) r) {
    final ok = r.status >= 200 && r.status < 300;
    if (r.body.isEmpty) {
      return ok ? {'isSuccess': true} : {'isSuccess': false, 'message': 'Lỗi: ${r.status}', 'statusCode': r.status};
    }
    final dynamic data;
    try {
      data = json.decode(r.body);
    } catch (_) {
      return {'isSuccess': false, 'message': 'Phản hồi không hợp lệ (${r.status})', 'statusCode': r.status};
    }
    if (ok) {
      if (data is Map<String, dynamic>) return _normalize(data);
      return {'isSuccess': true, 'data': data};
    }
    var message = 'Lỗi không xác định';
    if (data is Map<String, dynamic>) {
      final n = _normalize(data);
      if (n['message'] != null) {
        message = n['message'].toString();
      } else if (n['title'] != null) {
        message = (n['detail'] ?? n['title']).toString();
      }
    }
    final out = <String, dynamic>{'isSuccess': false, 'message': message, 'statusCode': r.status};
    if (data is Map<String, dynamic>) {
      final n = _normalize(data);
      if (n['data'] != null) out['data'] = n['data'];
    }
    return out;
  }

  static Map<String, dynamic> _failure(Object e) => {'isSuccess': false, 'message': '$e'};

  Future<Map<String, dynamic>> _get(String path, [Map<String, String>? query]) async {
    try {
      return _handle(await _send('GET', _uri(path, query)));
    } catch (e) {
      return _failure(e);
    }
  }

  Map<String, dynamic>? _parseProfile(Map<String, dynamic> result) {
    if (result['isSuccess'] != true) return null;
    final data = result['data'];
    if (data is Map<String, dynamic> && data.isNotEmpty) return data;
    return null;
  }

  @override
  Future<Map<String, dynamic>> getAppSetting(String key) => _get('/api/settings/app/$key');

  @override
  Future<List<dynamic>> getEmployees({
    int? page,
    int? pageSize,
    String? branchId,
    bool includeChildBranches = true,
    bool excludeResigned = false,
  }) async {
    final size = pageSize ?? 500;
    Future<List<dynamic>> one(int p) async {
      try {
        final params = _page(p, size);
        if (branchId != null) {
          params['branchId'] = branchId;
          params['includeChildBranches'] = includeChildBranches.toString();
        }
        if (excludeResigned) params['excludeResigned'] = 'true';
        final data = _handle(await _send('GET', _uri('/api/employees', params)));
        if (data['isSuccess'] == true) {
          final d = data['data'];
          if (d is List) return d;
          if (d is Map && d['items'] != null) return d['items'] as List<dynamic>;
        }
      } catch (_) {}
      return [];
    }

    if (page != null) return one(page);
    final all = <dynamic>[];
    for (var p = 1; p <= 50; p++) {
      final items = await one(p);
      if (items.isEmpty) break;
      all.addAll(items);
      if (items.length < size) break;
    }
    return all;
  }

  @override
  Future<List<dynamic>> getEmployeeSalaryProfiles() async {
    try {
      return (await _get('/api/benefits/employees'))['data'] ?? [];
    } catch (_) {
      return [];
    }
  }

  @override
  Future<Map<String, dynamic>?> getEmployeeSalaryProfile(String employeeId) async {
    try {
      final profile = _parseProfile(await _get('/api/benefits/employees/$employeeId'));
      if (profile != null) return profile;
      final me = await getMyEmployeeSalaryProfile();
      if (me == null) return null;
      final meEmpId = me['employeeId']?.toString() ?? '';
      if (meEmpId.isEmpty || meEmpId.toLowerCase() == employeeId.toLowerCase()) return me;
      return null;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<Map<String, dynamic>?> getMyEmployeeSalaryProfile() async {
    try {
      return _parseProfile(await _get('/api/benefits/me'));
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, dynamic>> _dataMap(String path) async {
    try {
      final r = await _get(path);
      final d = r['data'];
      return d is Map<String, dynamic> ? d : <String, dynamic>{};
    } catch (_) {
      return {};
    }
  }

  @override
  Future<Map<String, dynamic>> getInsuranceSettings() => _dataMap('/api/settings/insurance');

  @override
  Future<Map<String, dynamic>> getSalarySettings() => _dataMap('/api/settings/salary');

  @override
  Future<Map<String, dynamic>> getTaxSettings() => _dataMap('/api/settings/tax');

  @override
  Future<List<dynamic>> getEmployeeTaxDeductions() async {
    final data = (await _get('/api/settings/tax/employee-deductions'))['data'] ?? [];
    return data is List ? data : [];
  }

  @override
  Future<Map<String, dynamic>> getTransactions({
    DateTime? fromDate,
    DateTime? toDate,
    String? type,
    int page = 1,
    int pageSize = 100,
  }) =>
      _get('/api/Transactions', {
        'page': '$page',
        'pageSize': '$pageSize',
        if (fromDate != null) 'fromDate': fromDate.toIso8601String(),
        if (toDate != null) 'toDate': toDate.toIso8601String(),
        if (type != null) 'type': type,
      });

  @override
  Future<Map<String, dynamic>> getAdvanceRequests({
    int page = 1,
    int pageSize = 50,
    String? employeeUserId,
    int? status,
    DateTime? fromDate,
    DateTime? toDate,
  }) =>
      _get('/api/AdvanceRequests', {
        'page': '$page',
        'pageSize': '$pageSize',
        if (employeeUserId != null) 'employeeUserId': employeeUserId,
        if (status != null) 'status': '$status',
        if (fromDate != null) 'fromDate': fromDate.toIso8601String(),
        if (toDate != null) 'toDate': toDate.toIso8601String(),
      });

  @override
  Future<List<dynamic>> getShifts() async {
    final data = await _get('/api/shifts/templates');
    if (data['isSuccess'] == true && data['data'] != null) return data['data'] as List<dynamic>;
    return [];
  }

  @override
  Future<List<dynamic>> getAllowanceSettings() async {
    try {
      final dynamic result = await _get('/api/allowances', {'pageSize': '1000'});
      return result['data']?['items'] ?? result['data'] ?? [];
    } catch (_) {
      return [];
    }
  }

  @override
  Future<List<dynamic>> getHolidaySettings(int year) async {
    try {
      final r = await _get('/api/settings/holidays', year > 0 ? {'year': '$year'} : null);
      return r['data'] ?? [];
    } catch (_) {
      return [];
    }
  }

  @override
  Future<Map<String, dynamic>> getWorkSchedules({
    int page = 1,
    int pageSize = 50,
    String? employeeUserId,
    String? employeeId,
    String? shiftId,
    DateTime? fromDate,
    DateTime? toDate,
    bool? isDayOff,
  }) {
    final empId = employeeUserId ?? employeeId;
    return _get('/api/workschedules', {
      'page': '$page',
      'pageSize': '$pageSize',
      if (empId != null) 'employeeUserId': empId,
      if (shiftId != null) 'shiftId': shiftId,
      if (fromDate != null) 'fromDate': fromDate.toIso8601String(),
      if (toDate != null) 'toDate': toDate.toIso8601String(),
      if (isDayOff != null) 'isDayOff': '$isDayOff',
    });
  }

  @override
  Future<Map<String, dynamic>> getMyWorkSchedules({DateTime? fromDate, DateTime? toDate, int pageSize = 50}) =>
      _get('/api/workschedules/my', {
        'pageSize': '$pageSize',
        if (fromDate != null) 'fromDate': fromDate.toIso8601String(),
        if (toDate != null) 'toDate': toDate.toIso8601String(),
      });

  @override
  Future<Map<String, dynamic>> getPenaltyTickets({
    int page = 1,
    int pageSize = 20,
    String? employeeId,
    String? status,
    String? type,
    DateTime? fromDate,
    DateTime? toDate,
  }) =>
      _get('/api/PenaltyTickets', {
        'page': '$page',
        'pageSize': '$pageSize',
        if (employeeId != null) 'employeeId': employeeId,
        if (status != null) 'status': status,
        if (type != null) 'type': type,
        if (fromDate != null) 'fromDate': fromDate.toIso8601String(),
        if (toDate != null) 'toDate': toDate.toIso8601String(),
      });

  @override
  Future<Map<String, dynamic>> getHrFinPayrollAdjustments(DateTime from, DateTime to) =>
      _get('/api/hr-finance/payroll-adjustments', {'from': _ymd(from), 'to': _ymd(to)});

  @override
  Future<Map<String, dynamic>> getShiftSalaryLevels() => _get('/api/shift-salary-levels');

  @override
  Future<Map<String, dynamic>> getCommissionSettings() async {
    try {
      final result = await _get('/api/settings/app/commission_settings');
      if (result['isSuccess'] == true && result['data'] != null) {
        final value = (result['data'] as Map)['value'];
        if (value != null && value is String) return json.decode(value) as Map<String, dynamic>;
      }
      return {};
    } catch (_) {
      return {};
    }
  }

  @override
  Future<Map<String, dynamic>> getKpiPeriods() => _get('/api/kpi/periods');

  @override
  Future<Map<String, dynamic>> getKpiEmployeeTargets({String? periodId}) =>
      _get('/api/kpi/employee-targets', periodId == null ? null : {'periodId': periodId});

  @override
  Future<Map<String, dynamic>> getProductionSummary({
    required DateTime fromDate,
    required DateTime toDate,
    String? employeeId,
    String? productGroupId,
  }) =>
      _get('/api/production/summary', {
        'fromDate': fromDate.toIso8601String(),
        'toDate': toDate.toIso8601String(),
        if (employeeId != null) 'employeeId': employeeId,
        if (productGroupId != null) 'productGroupId': productGroupId,
      });

  @override
  Future<Map<String, dynamic>> getKpiSalaryForPayroll({required DateTime from, required DateTime to}) =>
      _get('/api/kpi/salary/for-payroll', {'from': _ymd(from), 'to': _ymd(to)});

  @override
  Future<Map<String, dynamic>> getSalaryTimeline(DateTime from, DateTime to) =>
      _get('/api/benefits/timeline', {'from': _alDate(from), 'to': _alDate(to)});

  @override
  Future<Map<String, dynamic>> getAnnualLeavePayouts(DateTime from, DateTime to) =>
      _get('/api/annual-leave/payouts', {'from': _alDate(from), 'to': _alDate(to)});

  @override
  Future<Map<String, dynamic>> getMobileAttendanceHistory({
    String? employeeId,
    DateTime? fromDate,
    DateTime? toDate,
    String? status,
    String? punchTypes,
    int? pageSize,
  }) =>
      _get('/api/mobile-attendance/history', {
        if (employeeId != null) 'employeeId': employeeId,
        if (fromDate != null) 'fromDate': fromDate.toIso8601String(),
        if (toDate != null) 'toDate': toDate.toIso8601String(),
        if (status != null) 'status': status,
        if (punchTypes != null && punchTypes.trim().isNotEmpty) 'punchTypes': punchTypes.trim(),
        if (pageSize != null && pageSize > 0) 'pageSize': '$pageSize',
      });

  @override
  Future<List<dynamic>> getDevices({bool storeOnly = false}) async {
    try {
      final data = await _get('/api/devices', storeOnly ? {'storeOnly': 'true'} : null);
      if (data['isSuccess'] == true) return data['data'] ?? [];
    } catch (_) {}
    return [];
  }

  static int _toInt(Object? v, int d) => v is int ? v : (v is num ? v.toInt() : int.tryParse('$v') ?? d);

  @override
  Future<Map<String, dynamic>> getAttendances({
    List<String>? deviceIds,
    DateTime? fromDate,
    DateTime? toDate,
    int page = 1,
    int pageSize = 20,
  }) async {
    try {
      final body = <String, dynamic>{
        'deviceIds': deviceIds ?? [],
        'fromDate': (fromDate ?? DateTime.now().subtract(const Duration(days: 7))).toIso8601String(),
        'toDate': (toDate ?? DateTime.now()).toIso8601String(),
      };
      final data = _handle(await _send('POST', _uri('/api/attendances/devices', _page(page, pageSize)), body: body));
      if (data['isSuccess'] == true) {
        final responseData = data['data'];
        final map = responseData is Map ? responseData : null;
        return {
          'items': map != null ? (map['items'] ?? map['Items'] ?? []) : (responseData ?? []),
          'totalCount': _toInt(map != null ? (map['totalCount'] ?? map['TotalCount']) : null, 0),
          'pageNumber': _toInt(map != null ? (map['pageNumber'] ?? map['PageNumber']) : null, page),
          'pageSize': _toInt(map != null ? (map['pageSize'] ?? map['PageSize']) : null, pageSize),
        };
      }
    } catch (_) {}
    return {'items': [], 'totalCount': 0, 'pageNumber': 1, 'pageSize': 20};
  }

  @override
  Future<Map<String, dynamic>> getAllLeaves({
    int? page,
    int? pageSize,
    String? status,
    String? fromDate,
    String? toDate,
    String? employeeId,
  }) {
    final params = <String, String>{};
    if (page != null) {
      params.addAll(_page(page, pageSize ?? 20));
    } else if (pageSize != null) {
      params['pageSize'] = '$pageSize';
    }
    if (status != null) params['status'] = status;
    if (fromDate != null) params['fromDate'] = fromDate;
    if (toDate != null) params['toDate'] = toDate;
    if (employeeId != null) params['employeeId'] = employeeId;
    return _get('/api/Leaves', params);
  }
}
