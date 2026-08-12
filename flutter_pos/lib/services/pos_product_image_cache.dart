import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:http/http.dart' as http;

import 'api_service.dart';

/// Disk + helper load ảnh SP POS — key theo productId / path + etag (updatedAt).
class PosProductImageCacheManager {
  PosProductImageCacheManager._();
  static final PosProductImageCacheManager instance =
      PosProductImageCacheManager._();

  static const _cacheName = 'posProductImageCache';
  /// Sunmi / máy yếu: giữ ít ảnh full-bytes trong RAM.
  static const _maxMemoryEntries = 96;
  /// Giới hạn HTTP ảnh song song toàn app.
  static const _maxConcurrentHttp = 3;

  static final Map<String, Uint8List> _memory = {};
  static int _httpInFlight = 0;
  static final List<Completer<void>> _httpWaiters = [];

  late final CacheManager manager = CacheManager(
    Config(
      _cacheName,
      stalePeriod: const Duration(days: 30),
      maxNrOfCacheObjects: 800,
    ),
  );

  static String cacheKey({
    String? productId,
    DateTime? updatedAt,
    String? imageUrl,
    String? path,
    int cacheEpoch = 0,
  }) {
    final etag = updatedAt?.millisecondsSinceEpoch ?? cacheEpoch;
    final id = productId?.trim();
    if (id != null && id.isNotEmpty) return 'pid_${id}_$etag';
    final p = (path ?? imageUrl ?? 'none').trim();
    return 'path_${p.hashCode}_$etag';
  }

  Uint8List? memoryGet(String key) => _memory[key];

  void memoryPut(String key, Uint8List bytes) {
    if (bytes.isEmpty) return;
    while (_memory.length >= _maxMemoryEntries) {
      final first = _memory.keys.first;
      _memory.remove(first);
    }
    _memory[key] = bytes;
  }

  Future<void> removeKey(String key) async {
    _memory.remove(key);
    if (!kIsWeb) {
      try {
        await manager.removeFile(key);
      } catch (_) {}
    }
  }

  Future<void> _acquireHttpSlot() async {
    while (_httpInFlight >= _maxConcurrentHttp) {
      final c = Completer<void>();
      _httpWaiters.add(c);
      await c.future;
    }
    _httpInFlight++;
  }

  void _releaseHttpSlot() {
    if (_httpInFlight > 0) _httpInFlight--;
    if (_httpWaiters.isNotEmpty) {
      _httpWaiters.removeAt(0).complete();
    }
  }

  /// Tải bytes: memory → disk (Android) → HTTP auth. Ghi lại memory (+ disk nếu !web).
  Future<Uint8List?> loadBytes({
    required String url,
    required String key,
    Map<String, String>? headers,
    int cacheEpoch = 0,
  }) async {
    final mem = memoryGet(key);
    if (mem != null && mem.isNotEmpty) return mem;

    if (!kIsWeb) {
      try {
        final cached = await manager.getFileFromCache(key);
        if (cached != null && await cached.file.exists()) {
          final bytes = await cached.file.readAsBytes();
          if (bytes.isNotEmpty) {
            memoryPut(key, bytes);
            return bytes;
          }
        }
      } catch (_) {}
    }

    await _acquireHttpSlot();
    try {
      final uri = kIsWeb
          ? Uri.parse(url).replace(
              queryParameters: {
                ...Uri.parse(url).queryParameters,
                '_': cacheEpoch.toString(),
              },
            )
          : Uri.parse(url);
      final response = await http
          .get(uri, headers: headers ?? const {})
          .timeout(const Duration(seconds: 20));
      if (response.statusCode != 200 || response.bodyBytes.isEmpty) {
        return null;
      }
      final bytes = response.bodyBytes;
      memoryPut(key, bytes);
      if (!kIsWeb) {
        try {
          await manager.putFile(
            url,
            bytes,
            key: key,
            maxAge: const Duration(days: 30),
          );
        } catch (_) {}
      }
      return bytes;
    } catch (_) {
      return null;
    } finally {
      _releaseHttpSlot();
    }
  }

  /// Prefetch không chặn UI — dùng cho lưới thực đơn.
  Future<void> prefetchProduct({
    required ApiService api,
    required String productId,
    String? imageUrl,
    DateTime? updatedAt,
  }) async {
    final paths = <String>[
      if ((imageUrl ?? '').trim().isNotEmpty) imageUrl!.trim(),
      ApiService.posProductImagePath(productId),
    ];
    final epoch = updatedAt?.millisecondsSinceEpoch ?? 0;
    final headers = <String, String>{...?api.imageAuthHeaders};
    for (final path in paths) {
      final url = api.getFileUrl(path);
      if (url.isEmpty) continue;
      final key = cacheKey(
        productId: productId,
        updatedAt: updatedAt,
        path: path,
        cacheEpoch: epoch,
      );
      if (memoryGet(key) != null) return;
      final bytes = await loadBytes(
        url: url,
        key: key,
        headers: headers,
        cacheEpoch: epoch,
      );
      if (bytes != null && bytes.isNotEmpty) return;
    }
  }
}
