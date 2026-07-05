import 'package:flutter_cache_manager/flutter_cache_manager.dart';

/// Disk cache ảnh SP POS — key theo productId + etag (updatedAt / imageUrl).
class PosProductImageCacheManager {
  PosProductImageCacheManager._();
  static final PosProductImageCacheManager instance =
      PosProductImageCacheManager._();

  static const _cacheName = 'posProductImageCache';

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
  }) {
    final etag = updatedAt?.millisecondsSinceEpoch ??
        (imageUrl != null ? imageUrl.hashCode : 0);
    final id = productId?.trim();
    if (id != null && id.isNotEmpty) return '${id}_$etag';
    return 'url_${imageUrl ?? 'none'}_$etag';
  }
}
