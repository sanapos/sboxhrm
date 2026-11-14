import 'dart:convert';

import 'package:http/http.dart' as http;

import 'api_service.dart';
import 'shared_http_client.dart';

/// API «Token AI đã dùng» (Thiết lập SBOX › Trợ lý AI): tổng token theo ngày / tính năng / model.
/// Dùng token đăng nhập của [ApiService].
class AiTokenUsageApi {
  AiTokenUsageApi([ApiService? api]) : _api = api ?? ApiService();

  final ApiService _api;

  static const _base = '/api/ai/usage';

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        ...?_api.imageAuthHeaders,
      };

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

  /// Báo cáo token của cửa hàng trong [days] ngày gần nhất (tính theo ngày giờ Việt Nam).
  /// Trả { from, to, totals {...}, byDay [...], byFeature [...], byModel [...] }.
  Future<Map<String, dynamic>> report({int days = 30}) async {
    final to = DateTime.now();
    final from = to.subtract(Duration(days: days - 1));
    String d(DateTime x) =>
        '${x.year}-${x.month.toString().padLeft(2, '0')}-${x.day.toString().padLeft(2, '0')}';
    final uri = Uri.parse('${ApiService.baseUrl}$_base')
        .replace(queryParameters: {'from': d(from), 'to': d(to)});

    Future<http.Response> go() =>
        sharedHttpClient.get(uri, headers: _headers).timeout(const Duration(seconds: 30));

    try {
      var r = await go();
      if (r.statusCode == 401) {
        // Làm mới phiên qua ApiService (tự refresh token) rồi thử lại một lần.
        await _api.getMyEmployee();
        r = await go();
      }
      return _parse(r);
    } catch (_) {
      return {'isSuccess': false, 'message': 'Không kết nối được máy chủ'};
    }
  }
}
