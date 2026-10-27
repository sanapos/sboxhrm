import 'package:http/http.dart' as http;

/// Gặp 401 do access token vừa hết hạn → làm mới token rồi gửi lại request MỘT lần.
///
/// Hầu hết lệnh gọi API dùng [sharedHttpClient] trực tiếp (không qua `_retryOnUnauthorized`):
/// trước đây request đầu tiên sau khi token hết hạn trả lỗi «Phiên đăng nhập hết hạn» lên màn
/// (vd. tab Hợp đồng) dù token đã được làm mới ngay sau đó ở nền — bấm lại thì chạy.
class AuthRetryClient extends http.BaseClient {
  AuthRetryClient(this._inner);

  final http.Client _inner;

  /// Do [ApiService] gắn: làm mới token (gộp chung 1 lượt), trả token mới hoặc null nếu hỏng.
  static Future<String?> Function()? refreshAccessToken;

  /// Do [ApiService] gắn: access token hiện tại trong bộ nhớ.
  static String? Function()? currentAccessToken;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final auth = request.headers['Authorization'] ?? request.headers['authorization'];
    final refresh = refreshAccessToken;
    // Chỉ request có thể gửi lại nguyên vẹn (http.Request giữ body) và đang mang token.
    if (refresh == null ||
        request is! http.Request ||
        auth == null ||
        !auth.startsWith('Bearer ') ||
        request.url.path.toLowerCase().contains('/api/auth/')) {
      return _inner.send(request);
    }
    final body = request.bodyBytes;
    final res = await _inner.send(request);
    if (res.statusCode != 401) return res;

    // Request khác vừa làm mới xong trong lúc request này bay → dùng luôn token mới, khỏi làm mới lần 2.
    final current = currentAccessToken?.call();
    final token = current != null && 'Bearer $current' != auth ? current : await refresh();
    if (token == null || 'Bearer $token' == auth) return res;
    await res.stream.drain<void>();

    // headers của http.Request không phân biệt hoa thường → ghi đè thẳng «Authorization».
    final retry = http.Request(request.method, request.url)
      ..headers.addAll(request.headers)
      ..followRedirects = request.followRedirects
      ..maxRedirects = request.maxRedirects
      ..persistentConnection = request.persistentConnection
      ..bodyBytes = body;
    retry.headers['Authorization'] = 'Bearer $token';
    return _inner.send(retry);
  }

  @override
  void close() => _inner.close();
}
