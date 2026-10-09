import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

import 'api_service.dart';

/// API Công việc đa ngành: thiết lập theo ngành, Google Drive, biểu mẫu, ảnh, check-in GPS,
/// phiếu hoàn thành, bảng điều khiển, khoán. Dùng token của [ApiService].
class WorkApi {
  WorkApi([ApiService? api]) : _api = api ?? ApiService();

  final ApiService _api;

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        ...?_api.imageAuthHeaders,
      };

  Uri _u(String path, [Map<String, String>? q]) =>
      Uri.parse('${ApiService.baseUrl}$path').replace(queryParameters: q == null || q.isEmpty ? null : q);

  Map<String, dynamic> _parse(http.Response r) {
    try {
      final d = jsonDecode(utf8.decode(r.bodyBytes));
      if (d is Map<String, dynamic>) {
        if (r.statusCode >= 400 && d['isSuccess'] == null) {
          return {'isSuccess': false, 'message': d['message'] ?? d['detail'] ?? 'Lỗi ${r.statusCode}'};
        }
        return d;
      }
      return {'isSuccess': r.statusCode < 400, 'data': d};
    } catch (_) {
      return {
        'isSuccess': false,
        'message': r.statusCode == 401 ? 'Phiên đăng nhập hết hạn — đăng nhập lại' : 'Lỗi máy chủ (${r.statusCode})',
      };
    }
  }

  Future<Map<String, dynamic>> _send(String method, String path, {Object? body, Map<String, String>? query}) async {
    Future<http.Response> go() {
      final uri = _u(path, query);
      final b = body == null ? null : jsonEncode(body);
      return switch (method) {
        'GET' => http.get(uri, headers: _headers),
        'POST' => http.post(uri, headers: _headers, body: b),
        'PUT' => http.put(uri, headers: _headers, body: b),
        'PATCH' => http.patch(uri, headers: _headers, body: b),
        _ => http.delete(uri, headers: _headers),
      }.timeout(const Duration(seconds: 60));
    }

    try {
      var r = await go();
      if (r.statusCode == 401) {
        // Làm mới phiên qua ApiService (tự refresh token) rồi thử lại một lần.
        await _api.getMyEmployee();
        r = await go();
      }
      return _parse(r);
    } catch (e) {
      return {'isSuccess': false, 'message': 'Không kết nối được máy chủ'};
    }
  }

  // ─── Thiết lập ───
  Future<Map<String, dynamic>> workspace() => _send('GET', '/api/tasks/workspace');
  Future<Map<String, dynamic>> updateWorkspace({String? industryKey, String? photoStorage, int? checkInRadiusM}) =>
      _send('PUT', '/api/tasks/workspace', body: {
        if (industryKey != null) 'industryKey': industryKey,
        if (photoStorage != null) 'photoStorage': photoStorage,
        if (checkInRadiusM != null) 'checkInRadiusM': checkInRadiusM,
      });
  Future<Map<String, dynamic>> onboard(String industryKey, {bool enableRecurring = true, List<String>? assigneeIds}) =>
      _send('POST', '/api/tasks/workspace/onboard', body: {
        'industryKey': industryKey,
        'enableRecurring': enableRecurring,
        if (assigneeIds != null && assigneeIds.isNotEmpty) 'recurringAssigneeIds': assigneeIds,
      });
  Future<Map<String, dynamic>> driveConnectUrl() => _send('GET', '/api/tasks/drive/connect-url');
  Future<Map<String, dynamic>> driveDisconnect() => _send('POST', '/api/tasks/drive/disconnect');
  Future<Map<String, dynamic>> driveTest() => _send('POST', '/api/tasks/drive/test');

  // ─── Biểu mẫu / hiện trường ───
  Future<Map<String, dynamic>> saveForm(String taskId, Map<String, String?> values) =>
      _send('PUT', '/api/tasks/$taskId/form', body: {'values': values});
  Future<Map<String, dynamic>> checkIn(String taskId, {double? lat, double? lng, String? note}) =>
      _send('POST', '/api/tasks/$taskId/check-in', body: {'latitude': lat, 'longitude': lng, 'note': note});
  Future<Map<String, dynamic>> checkOut(String taskId, {double? lat, double? lng, String? note}) =>
      _send('POST', '/api/tasks/$taskId/check-out', body: {'latitude': lat, 'longitude': lng, 'note': note});
  Future<Map<String, dynamic>> timeLogs(String taskId) => _send('GET', '/api/tasks/$taskId/time-logs');

  // ─── Ảnh / chữ ký / file ───
  Future<Map<String, dynamic>> media(String taskId) => _send('GET', '/api/tasks/$taskId/media');
  Future<Map<String, dynamic>> deleteMedia(String taskId, String mediaId) =>
      _send('DELETE', '/api/tasks/$taskId/media/$mediaId');

  /// Tải ảnh / chữ ký / file lên nơi lưu của cửa hàng (máy chủ hoặc Google Drive).
  Future<Map<String, dynamic>> uploadMedia(
    String taskId,
    List<int> bytes,
    String fileName, {
    String category = 'report',
    String? checklistItemId,
    String? fieldKey,
    String? caption,
    double? lat,
    double? lng,
  }) async {
    try {
      final req = http.MultipartRequest('POST', _u('/api/tasks/$taskId/media'));
      req.headers.addAll({...?_api.imageAuthHeaders});
      req.fields['category'] = category;
      if (checklistItemId != null) req.fields['checklistItemId'] = checklistItemId;
      if (fieldKey != null) req.fields['fieldKey'] = fieldKey;
      if (caption != null && caption.isNotEmpty) req.fields['caption'] = caption;
      if (lat != null && lng != null) {
        req.fields['latitude'] = '$lat';
        req.fields['longitude'] = '$lng';
      }
      final ext = fileName.toLowerCase().split('.').last;
      final mime = switch (ext) {
        'png' => MediaType('image', 'png'),
        'webp' => MediaType('image', 'webp'),
        'heic' => MediaType('image', 'heic'),
        'pdf' => MediaType('application', 'pdf'),
        'mp4' => MediaType('video', 'mp4'),
        _ => MediaType('image', 'jpeg'),
      };
      req.files.add(http.MultipartFile.fromBytes('file', bytes, filename: fileName, contentType: mime));
      final r = await http.Response.fromStream(await req.send().timeout(const Duration(seconds: 120)));
      return _parse(r);
    } catch (e) {
      return {'isSuccess': false, 'message': 'Không tải được file lên'};
    }
  }

  // ─── Báo cáo / thống kê ───
  Future<Map<String, dynamic>> reportHtml(String taskId) => _send('GET', '/api/tasks/$taskId/report');
  String reportPdfUrl(String taskId) => '${ApiService.baseUrl}/api/tasks/$taskId/report.pdf';
  Future<List<int>?> reportPdf(String taskId) async {
    try {
      final r = await http.get(_u('/api/tasks/$taskId/report.pdf'), headers: {...?_api.imageAuthHeaders})
          .timeout(const Duration(seconds: 120));
      return r.statusCode == 200 ? r.bodyBytes : null;
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, dynamic>> dashboard({DateTime? from, DateTime? to, String? projectId}) =>
      _send('GET', '/api/tasks/dashboard', query: {
        if (from != null) 'from': from.toIso8601String(),
        if (to != null) 'to': to.toIso8601String(),
        if (projectId != null) 'projectId': projectId,
      });
  Future<Map<String, dynamic>> pieceRates({int? month, int? year}) => _send('GET', '/api/tasks/piece-rates', query: {
        if (month != null) 'month': '$month',
        if (year != null) 'year': '$year',
      });

  // ─── Liên kết ───
  Future<Map<String, dynamic>> fromQuote(String quoteId, {String? industryKey, String? ownerEmployeeId}) =>
      _send('POST', '/api/tasks/from-quote/$quoteId', body: {
        if (industryKey != null) 'industryKey': industryKey,
        if (ownerEmployeeId != null) 'ownerEmployeeId': ownerEmployeeId,
      });
  Future<Map<String, dynamic>> byCustomer(String customerId) => _send('GET', '/api/tasks/by-customer/$customerId');
  Future<Map<String, dynamic>> byRelated(String type, String id) => _send('GET', '/api/tasks/by-related/$type/$id');

  /// Tạo việc nhanh (giao một dòng). [templateId] → lấy biểu mẫu / checklist / khoán của mẫu.
  Future<Map<String, dynamic>> quickCreate({
    required String title,
    String? assigneeId,
    DateTime? dueDate,
    String? templateId,
    String? projectId,
    String? customerName,
    String? customerPhone,
    String? location,
  }) =>
      _send('POST', '/api/tasks', body: {
        'title': title,
        if (assigneeId != null) 'assigneeId': assigneeId,
        if (dueDate != null) 'dueDate': dueDate.toIso8601String(),
        if (templateId != null) 'templateId': templateId,
        if (projectId != null) 'projectId': projectId,
        if (customerName != null && customerName.isNotEmpty) 'customerName': customerName,
        if (customerPhone != null && customerPhone.isNotEmpty) 'customerPhone': customerPhone,
        if (location != null && location.isNotEmpty) 'location': location,
        'requireAcceptance': false,
      });
}
