import 'dart:convert';

import 'package:http/http.dart' as http;

import 'api_service.dart';
import 'shared_http_client.dart';

/// API «Zalo bot» của cửa hàng (Thiết lập SBOX › Zalo bot) và liên kết Zalo của chính mình (Cài đặt).
class ZaloBotApi {
  ZaloBotApi([ApiService? api]) : _api = api ?? ApiService();

  final ApiService _api;

  static const _base = '/api/zalo-bot';

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        ...?_api.imageAuthHeaders,
      };

  Uri _u(String path) => Uri.parse('${ApiService.baseUrl}$_base$path');

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
        'message': switch (r.statusCode) {
          401 => 'Phiên đăng nhập hết hạn — đăng nhập lại',
          403 => 'Tài khoản không có quyền',
          _ => 'Lỗi máy chủ (${r.statusCode})',
        },
      };
    }
  }

  Future<Map<String, dynamic>> _send(String method, String path, {Object? body}) async {
    Future<http.Response> go() {
      final uri = _u(path);
      final b = body == null ? null : jsonEncode(body);
      return switch (method) {
        'POST' => sharedHttpClient.post(uri, headers: _headers, body: b),
        'PUT' => sharedHttpClient.put(uri, headers: _headers, body: b),
        'DELETE' => sharedHttpClient.delete(uri, headers: _headers),
        _ => sharedHttpClient.get(uri, headers: _headers),
      }.timeout(const Duration(seconds: 30));
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

  /// { enabled, hasToken, botName, botLink, webhookOk, webhookUrl, categories [...], hideMoney, lastError,
  ///   linkedCount, allCategories [{code,label}], updatedAt }
  Future<Map<String, dynamic>> getSettings() => _send('GET', '/settings');

  /// [botToken] trống = giữ token cũ.
  Future<Map<String, dynamic>> saveSettings({
    required bool enabled,
    String? botToken,
    String? botLink,
    required List<String> categories,
    required bool hideMoney,
  }) =>
      _send('PUT', '/settings', body: {
        'enabled': enabled,
        if (botToken != null && botToken.trim().isNotEmpty) 'botToken': botToken.trim(),
        'botLink': botLink,
        'categories': categories,
        'hideMoney': hideMoney,
      });

  Future<Map<String, dynamic>> registerWebhook() => _send('POST', '/settings/webhook');

  Future<Map<String, dynamic>> sendTest() => _send('POST', '/settings/test');

  /// [{ userId, name, userName, role, linked, zaloName, linkedAt }]
  Future<Map<String, dynamic>> getLinks() => _send('GET', '/links');

  Future<Map<String, dynamic>> unlinkUser(String userId) => _send('DELETE', '/links/$userId');

  /// { available, linked, zaloName, linkedAt, botName, botLink }
  Future<Map<String, dynamic>> getMyLink() => _send('GET', '/me');

  /// { code, expiresAt, botName, botLink }
  Future<Map<String, dynamic>> createMyCode() => _send('POST', '/me/code');

  Future<Map<String, dynamic>> unlinkMe() => _send('DELETE', '/me');
}
