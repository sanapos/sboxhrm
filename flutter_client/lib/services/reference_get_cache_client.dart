import 'dart:async';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

/// Cache ngắn hạn cho GET dữ liệu tham chiếu (phòng ban, chi nhánh, ca mẫu, thiết lập…).
///
/// Mỗi lần chuyển chức năng, màn mới tải lại cùng các danh mục này → chờ mạng + spinner.
/// Lớp này trả ngay bản đã tải trong [ttl] và gộp các GET trùng đang bay (khởi động app
/// nhiều màn cùng hỏi chi nhánh). Bất kỳ lệnh ghi nào (POST/PUT/PATCH/DELETE) xoá toàn bộ
/// cache → sau khi sửa trên máy này luôn thấy dữ liệu mới.
///
/// Chỉ cache đường dẫn trong [cacheablePaths] (khớp nguyên đường dẫn, không phân biệt hoa
/// thường) hoặc bắt đầu bằng [cacheablePrefixes]; khóa cache gồm URL + header (token,
/// chi nhánh) nên đổi tài khoản / cửa hàng không dùng nhầm dữ liệu.
class ReferenceGetCacheClient extends http.BaseClient {
  ReferenceGetCacheClient(
    this._inner, {
    this.ttl = const Duration(seconds: 45),
    Set<String>? cacheablePaths,
    List<String>? cacheablePrefixes,
    DateTime Function()? clock,
  })  : cacheablePaths = cacheablePaths ?? defaultCacheablePaths,
        cacheablePrefixes = cacheablePrefixes ?? defaultCacheablePrefixes,
        _clock = clock ?? DateTime.now;

  static const Set<String> defaultCacheablePaths = {
    '/api/benefits',
    '/api/departments',
    '/api/branches',
    '/api/shift-salary-levels',
    '/api/shifts/templates',
    '/api/settings/holidays',
    '/api/pos/sell-settings',
    '/api/pos/catalog/categories',
    '/api/pos/print-templates',
  };

  static const List<String> defaultCacheablePrefixes = [
    '/api/settings/app/',
  ];

  final http.Client _inner;
  final Duration ttl;
  final Set<String> cacheablePaths;
  final List<String> cacheablePrefixes;
  final DateTime Function() _clock;

  final Map<String, _CachedResponse> _cache = {};
  final Map<String, Future<_CachedResponse>> _inFlight = {};

  /// Tăng mỗi lần xoá cache: GET đang bay trước lệnh ghi không được ghi đè cache cũ vào.
  int _generation = 0;

  bool isCacheable(Uri url) {
    final path = url.path.toLowerCase();
    if (cacheablePaths.contains(path)) return true;
    for (final p in cacheablePrefixes) {
      if (path.startsWith(p)) return true;
    }
    return false;
  }

  void clear() {
    _generation++;
    _cache.clear();
    _inFlight.clear();
  }

  String _keyFor(http.BaseRequest request) {
    final h = request.headers.entries
        .map((e) => '${e.key.toLowerCase()}=${e.value}')
        .toList()
      ..sort();
    return '${request.url}|${h.join('&')}';
  }

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (request.method.toUpperCase() != 'GET') {
      clear();
      try {
        return await _inner.send(request);
      } finally {
        // Phản hồi của lệnh ghi có thể về sau một GET vừa cache → xoá lần nữa.
        clear();
      }
    }
    if (!isCacheable(request.url)) return _inner.send(request);

    final key = _keyFor(request);
    final hit = _cache[key];
    if (hit != null && _clock().difference(hit.at) < ttl) {
      return hit.toStreamed(request);
    }

    final pending = _inFlight[key];
    if (pending != null) return (await pending).toStreamed(request);

    final gen = _generation;
    final future = () async {
      final res = await _inner.send(request);
      final bytes = await res.stream.toBytes();
      return _CachedResponse(
        statusCode: res.statusCode,
        headers: res.headers,
        reasonPhrase: res.reasonPhrase,
        bytes: bytes,
        at: _clock(),
      );
    }();
    _inFlight[key] = future;
    try {
      final fresh = await future;
      if (gen == _generation && fresh.statusCode == 200) {
        _cache[key] = fresh;
      }
      return fresh.toStreamed(request);
    } finally {
      if (identical(_inFlight[key], future)) _inFlight.remove(key);
    }
  }

  @override
  void close() => _inner.close();
}

class _CachedResponse {
  _CachedResponse({
    required this.statusCode,
    required this.headers,
    required this.reasonPhrase,
    required this.bytes,
    required this.at,
  });

  final int statusCode;
  final Map<String, String> headers;
  final String? reasonPhrase;
  final Uint8List bytes;
  final DateTime at;

  http.StreamedResponse toStreamed(http.BaseRequest request) =>
      http.StreamedResponse(
        Stream<List<int>>.value(bytes),
        statusCode,
        contentLength: bytes.length,
        request: request,
        headers: headers,
        reasonPhrase: reasonPhrase,
      );
}
