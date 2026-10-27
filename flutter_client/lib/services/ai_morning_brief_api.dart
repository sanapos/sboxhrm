import 'dart:convert';

import 'package:http/http.dart' as http;

import 'api_service.dart';
import 'shared_http_client.dart';

/// API «Bản tin sáng tự động» (Thiết lập SBOX › Trợ lý AI): thiết lập, xem thử, lịch sử. Dùng token của [ApiService].
class AiMorningBriefApi {
  AiMorningBriefApi([ApiService? api]) : _api = api ?? ApiService();

  final ApiService _api;

  static const _base = '/api/ai/morning-brief';

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        ...?_api.imageAuthHeaders,
      };

  Uri _u(String path, [Map<String, String>? q]) =>
      Uri.parse('${ApiService.baseUrl}$_base$path').replace(queryParameters: q == null || q.isEmpty ? null : q);

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

  Future<Map<String, dynamic>> _send(String method, String path,
      {Object? body, Map<String, String>? query, Duration timeout = const Duration(seconds: 30)}) async {
    Future<http.Response> go() {
      final uri = _u(path, query);
      final b = body == null ? null : jsonEncode(body);
      return switch (method) {
        'POST' => sharedHttpClient.post(uri, headers: _headers, body: b),
        'PUT' => sharedHttpClient.put(uri, headers: _headers, body: b),
        _ => sharedHttpClient.get(uri, headers: _headers),
      }.timeout(timeout);
    }

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

  /// { enabled, sendTime "HH:mm", recipients [...], sections [...], canEdit, moduleAllowed, updatedAt }
  Future<Map<String, dynamic>> getSettings() => _send('GET', '/settings');

  Future<Map<String, dynamic>> saveSettings({
    required bool enabled,
    required String sendTime,
    required List<String> recipients,
    required List<String> sections,
  }) =>
      _send('PUT', '/settings', body: {
        'enabled': enabled,
        'sendTime': sendTime,
        'recipients': recipients,
        'sections': sections,
      });

  /// Bản tin hôm nay của chính mình (không gửi) — có thể gọi AI nên chờ lâu hơn.
  Future<Map<String, dynamic>> preview() => _send('POST', '/preview', timeout: const Duration(seconds: 90));

  Future<Map<String, dynamic>> history({int take = 14}) => _send('GET', '/history', query: {'take': '$take'});
}
