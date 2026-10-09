import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/pos_product.dart';

// Conditional File I/O — tránh import dart:io trên web (làm crash/spinner forever).
import 'pos_sell_catalog_cache_io.dart'
    if (dart.library.html) 'pos_sell_catalog_cache_web.dart' as cache_io;

class PosSellCatalogSnapshot {
  const PosSellCatalogSnapshot({
    required this.items,
    required this.cachedAt,
    this.catalogVersion,
    this.complete = false,
    this.syncedAt,
    this.fullSyncedAt,
  });

  final List<PosProduct> items;
  final DateTime cachedAt;
  final DateTime? catalogVersion;

  /// Đã có ĐỦ danh mục (đồng bộ hết các trang) — mới được tìm / lọc trên máy và
  /// đồng bộ phần thay đổi. Bản cũ (chỉ trang 1) = false → tải lại đủ.
  final bool complete;

  /// Mốc giờ server của lần đồng bộ gần nhất — gửi lại làm updatedSince.
  final DateTime? syncedAt;

  /// Lần tải lại toàn bộ gần nhất (đơn vị tính / topping / combo đổi không cập nhật
  /// updatedAt của món → tải lại toàn bộ định kỳ cho chắc).
  final DateTime? fullSyncedAt;

  bool get isFresh =>
      DateTime.now().difference(cachedAt) < PosSellCatalogCache.ttl;
}

/// Payload isolate: decode JSON → danh sách map + version.
class _CatalogDecodeResult {
  const _CatalogDecodeResult({
    required this.itemMaps,
    this.catalogVersionIso,
    this.complete = false,
    this.syncedAtIso,
    this.fullSyncedAtIso,
  });

  final List<Map<String, dynamic>> itemMaps;
  final String? catalogVersionIso;
  final bool complete;
  final String? syncedAtIso;
  final String? fullSyncedAtIso;
}

_CatalogDecodeResult _decodeCatalogIsolate(String raw) {
  final root = jsonDecode(raw);
  if (root is! Map) {
    return const _CatalogDecodeResult(itemMaps: []);
  }
  final rawItems = root['items'] as List? ?? [];
  final itemMaps = <Map<String, dynamic>>[];
  for (final e in rawItems) {
    if (e is Map) itemMaps.add(Map<String, dynamic>.from(e));
  }
  final versionRaw = root['catalogVersion'];
  return _CatalogDecodeResult(
    itemMaps: itemMaps,
    catalogVersionIso: versionRaw?.toString(),
    complete: root['complete'] == true,
    syncedAtIso: root['syncedAt']?.toString(),
    fullSyncedAtIso: root['fullSyncedAt']?.toString(),
  );
}

String _encodeCatalogIsolate(Map<String, dynamic> root) => jsonEncode(root);

/// Giữ 1 dòng / productId — cache từng bị ghép trùng khi iOS gọi loadMore page 1.
List<PosProduct> uniquePosProductsById(Iterable<PosProduct> items) {
  final seen = <String>{};
  final out = <PosProduct>[];
  for (final p in items) {
    final id = p.id.trim().toLowerCase();
    if (id.isEmpty || !seen.add(id)) continue;
    out.add(p);
  }
  return out;
}

/// Cache catalog bán hàng theo storeId — hiển thị ngay, sync nền sau TTL.
class PosSellCatalogCache {
  PosSellCatalogCache._();
  static final PosSellCatalogCache instance = PosSellCatalogCache._();

  /// Sau mốc này hỏi server phần thay đổi (nhẹ: thường vài món). Danh mục vẫn hiện ngay.
  static const ttl = Duration(minutes: 2);

  /// Tải lại toàn bộ định kỳ.
  static const fullSyncEvery = Duration(hours: 6);
  static const _metaPrefix = 'pos_sell_catalog_v1_';
  static const _diskDebounce = Duration(milliseconds: 700);

  String? _lastStoreId;
  String? _memoryStoreId;
  PosSellCatalogSnapshot? _memory;
  Timer? _diskWriteTimer;
  int _diskWriteGen = 0;

  /// Store gần nhất đã đọc/ghi cache — dùng patch tồn khi lưới bán chưa mount.
  String? get lastStoreId => _lastStoreId;

  /// Decode sẵn catalog lúc đang xem sơ đồ — lần mở lưới không jsonDecode lại.
  Future<void> warmup(String storeId) async {
    await read(storeId);
  }

  Future<PosSellCatalogSnapshot?> read(String storeId) async {
    if (storeId.isEmpty) return null;
    if (_memory != null && _memoryStoreId == storeId) {
      final unique = uniquePosProductsById(_memory!.items);
      if (unique.length != _memory!.items.length) {
        _memory = _copy(_memory!, items: unique);
        _scheduleDiskWrite(storeId);
      }
      return _memory;
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      final metaKey = '$_metaPrefix$storeId';
      final cachedAtMs = prefs.getInt('${metaKey}_at');
      if (cachedAtMs == null) return null;

      final raw = await cache_io.readCatalogJson(storeId);
      if (raw == null || raw.isEmpty) return null;

      final decoded = await compute(_decodeCatalogIsolate, raw);
      final items = <PosProduct>[];
      for (final e in decoded.itemMaps) {
        try {
          items.add(PosProduct.fromJson(e));
        } catch (_) {}
      }
      if (items.isEmpty) return null;
      final unique = uniquePosProductsById(items);

      DateTime? catalogVersion;
      if (decoded.catalogVersionIso != null) {
        catalogVersion = DateTime.tryParse(decoded.catalogVersionIso!);
      }
      _lastStoreId = storeId;
      _memoryStoreId = storeId;
      _memory = PosSellCatalogSnapshot(
        items: unique,
        cachedAt: DateTime.fromMillisecondsSinceEpoch(cachedAtMs),
        catalogVersion: catalogVersion,
        complete: decoded.complete,
        syncedAt: decoded.syncedAtIso == null ? null : DateTime.tryParse(decoded.syncedAtIso!),
        fullSyncedAt:
            decoded.fullSyncedAtIso == null ? null : DateTime.tryParse(decoded.fullSyncedAtIso!),
      );
      if (unique.length != items.length) {
        _scheduleDiskWrite(storeId);
      }
      return _memory;
    } catch (_) {
      return null;
    }
  }

  Future<bool> shouldSync(String storeId) async {
    final snap = await read(storeId);
    if (snap == null) return true;
    return !snap.isFresh;
  }

  PosSellCatalogSnapshot _copy(
    PosSellCatalogSnapshot s, {
    List<PosProduct>? items,
    DateTime? cachedAt,
  }) =>
      PosSellCatalogSnapshot(
        items: items ?? s.items,
        cachedAt: cachedAt ?? s.cachedAt,
        catalogVersion: s.catalogVersion,
        complete: s.complete,
        syncedAt: s.syncedAt,
        fullSyncedAt: s.fullSyncedAt,
      );

  /// Cập nhật memory + ghi đĩa (debounce) — không chặn UI.
  /// [complete]/[syncedAt]/[fullSyncedAt] = null → giữ giá trị cũ (patch tồn không làm mất cờ).
  Future<void> write(
    String storeId, {
    required List<PosProduct> items,
    DateTime? catalogVersion,
    bool? complete,
    DateTime? syncedAt,
    DateTime? fullSyncedAt,
  }) async {
    if (storeId.isEmpty) return;
    final prev = _memoryStoreId == storeId ? _memory : null;
    _lastStoreId = storeId;
    _memoryStoreId = storeId;
    _memory = PosSellCatalogSnapshot(
      items: uniquePosProductsById(items),
      cachedAt: DateTime.now(),
      catalogVersion: catalogVersion ?? prev?.catalogVersion,
      complete: complete ?? prev?.complete ?? false,
      syncedAt: syncedAt ?? prev?.syncedAt,
      fullSyncedAt: fullSyncedAt ?? prev?.fullSyncedAt,
    );
    _scheduleDiskWrite(storeId);
  }

  /// Patch tồn theo productId — không map toàn bộ catalog khi không cần.
  void patchMemoryProducts(
    String storeId,
    Set<String> productIds,
    PosProduct Function(PosProduct product) patch,
  ) {
    if (storeId.isEmpty ||
        productIds.isEmpty ||
        _memory == null ||
        _memoryStoreId != storeId) {
      return;
    }
    final items = _memory!.items;
    var changed = false;
    final next = List<PosProduct>.from(items);
    for (var i = 0; i < next.length; i++) {
      if (!productIds.contains(next[i].id)) continue;
      next[i] = patch(next[i]);
      changed = true;
    }
    if (!changed) return;
    _memory = _copy(_memory!, items: next);
    _scheduleDiskWrite(storeId);
  }

  void _scheduleDiskWrite(String storeId) {
    _diskWriteTimer?.cancel();
    final gen = ++_diskWriteGen;
    _diskWriteTimer = Timer(_diskDebounce, () {
      unawaited(_flushDisk(storeId, gen));
    });
  }

  Future<void> _flushDisk(String storeId, int gen) async {
    if (gen != _diskWriteGen) return;
    final snap = _memory;
    if (snap == null || _memoryStoreId != storeId) return;
    try {
      final itemMaps = snap.items.map((p) => p.toSellCacheJson()).toList();
      final payload = await compute(_encodeCatalogIsolate, {
        'catalogVersion': snap.catalogVersion?.toUtc().toIso8601String(),
        'complete': snap.complete,
        'syncedAt': snap.syncedAt?.toUtc().toIso8601String(),
        'fullSyncedAt': snap.fullSyncedAt?.toUtc().toIso8601String(),
        'items': itemMaps,
      });
      if (gen != _diskWriteGen) return;
      await cache_io.writeCatalogJson(storeId, payload);

      final prefs = await SharedPreferences.getInstance();
      final metaKey = '$_metaPrefix$storeId';
      await prefs.setInt('${metaKey}_at', snap.cachedAt.millisecondsSinceEpoch);
      if (snap.catalogVersion != null) {
        await prefs.setString(
          '${metaKey}_ver',
          snap.catalogVersion!.toUtc().toIso8601String(),
        );
      }
    } catch (_) {
      // Cache thất bại không được chặn UI catalog.
    }
  }

  Future<void> invalidate(String storeId) async {
    if (storeId.isEmpty) return;
    try {
      _diskWriteTimer?.cancel();
      _diskWriteGen++;
      final prefs = await SharedPreferences.getInstance();
      final metaKey = '$_metaPrefix$storeId';
      await prefs.remove('${metaKey}_at');
      await prefs.remove('${metaKey}_ver');
      await cache_io.deleteCatalogJson(storeId);
      if (_lastStoreId == storeId) _lastStoreId = null;
      if (_memoryStoreId == storeId) {
        _memoryStoreId = null;
        _memory = null;
      }
    } catch (_) {}
  }

  Future<void> invalidateLast() async {
    if (_lastStoreId != null && _lastStoreId!.isNotEmpty) {
      await invalidate(_lastStoreId!);
    }
  }
}
