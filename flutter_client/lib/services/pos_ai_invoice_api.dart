import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

import 'api_service.dart';
import 'shared_http_client.dart';

/// API «Chụp hóa đơn NCC → phiếu nhập»: AI đọc ảnh hóa đơn, tạo phiếu nhập; kèm tra hàng / NCC cho màn xem trước.
/// Dùng token của [ApiService].
class PosAiInvoiceApi {
  PosAiInvoiceApi([ApiService? api]) : _api = api ?? ApiService();

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
        'message': r.statusCode == 401
            ? 'Phiên đăng nhập hết hạn — đăng nhập lại'
            : r.statusCode == 413
                ? 'Ảnh quá lớn — chụp lại hoặc bớt ảnh'
                : 'Lỗi máy chủ (${r.statusCode})',
      };
    }
  }

  /// Gửi lại một lần sau khi làm mới phiên (401).
  Future<Map<String, dynamic>> _withRetry(Future<http.Response> Function() go) async {
    try {
      var r = await go();
      if (r.statusCode == 401) {
        await _api.getMyEmployee();
        r = await go();
      }
      return _parse(r);
    } catch (e) {
      return {'isSuccess': false, 'message': 'Không kết nối được máy chủ'};
    }
  }

  /// AI đọc 1–4 ảnh hóa đơn (đã nén JPEG) → NCC, số / ngày, dòng hàng đã đối chiếu, tổng, cảnh báo.
  Future<Map<String, dynamic>> scan(List<({List<int> bytes, String name, bool heic})> images) =>
      _withRetry(() async {
        final request = http.MultipartRequest('POST', _u('/api/pos/ai/purchase-invoice/scan'));
        request.headers.addAll({...?_api.imageAuthHeaders});
        for (final img in images) {
          request.files.add(http.MultipartFile.fromBytes('files', img.bytes,
              filename: img.name,
              contentType: img.heic ? MediaType('image', 'heic') : MediaType('image', 'jpeg')));
        }
        // Máy chủ chờ AI tối đa ~150 s.
        final streamed = await request.send().timeout(const Duration(seconds: 200));
        return http.Response.fromStream(streamed);
      });

  /// Tạo phiếu nhập (tạm / hoàn thành) từ dữ liệu đã duyệt; nhớ ánh xạ tên hóa đơn → hàng.
  Future<Map<String, dynamic>> confirm(Map<String, dynamic> body) => _withRetry(() => sharedHttpClient
      .post(_u('/api/pos/ai/purchase-invoice/confirm'), headers: _headers, body: jsonEncode(body))
      .timeout(const Duration(seconds: 90)));

  /// Tìm hàng (tên / mã / mã vạch) cho ô chọn hàng của từng dòng.
  Future<List<Map<String, dynamic>>> searchProducts(String q) async {
    final res = await _withRetry(() => sharedHttpClient
        .get(_u('/api/pos/products', {'search': q.trim(), 'pageSize': '30'}), headers: _headers)
        .timeout(const Duration(seconds: 30)));
    return _items(res);
  }

  /// Danh sách NCC để chọn / đổi NCC của hóa đơn.
  Future<List<Map<String, dynamic>>> suppliers() async {
    final res = await _withRetry(() => sharedHttpClient
        .get(_u('/api/pos/purchase/suppliers', {'page': '1', 'pageSize': '200'}), headers: _headers)
        .timeout(const Duration(seconds: 30)));
    return _items(res);
  }

  static List<Map<String, dynamic>> _items(Map<String, dynamic> res) {
    if (res['isSuccess'] != true) return const [];
    final d = res['data'];
    final list = d is Map ? (d['items'] as List?) ?? const [] : (d is List ? d : const []);
    return [for (final e in list) if (e is Map) Map<String, dynamic>.from(e)];
  }
}
