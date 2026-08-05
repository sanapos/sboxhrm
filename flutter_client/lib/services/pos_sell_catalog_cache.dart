import 'dart:convert';

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
  });

  final List<PosProduct> items;
  final DateTime cachedAt;
  final DateTime? catalogVersion;

  bool get isFresh =>
      DateTime.now().difference(cachedAt) < PosSellCatalogCache.ttl;
}

/// Cache catalog bán hàng theo storeId — hiển thị ngay, sync nền sau TTL.
class PosSellCatalogCache {
  PosSellCatalogCache._();
  static final PosSellCatalogCache instance = PosSellCatalogCache._();

  static const ttl = Duration(minutes: 20);
  static const _metaPrefix = 'pos_sell_catalog_v1_';
  String? _lastStoreId;

  Future<PosSellCatalogSnapshot?> read(String storeId) async {
    if (storeId.isEmpty) return null;
    try {
      final prefs = await SharedPreferences.getInstance();
      final metaKey = '$_metaPrefix$storeId';
      final cachedAtMs = prefs.getInt('${metaKey}_at');
      if (cachedAtMs == null) return null;

      final raw = await cache_io.readCatalogJson(storeId);
      if (raw == null || raw.isEmpty) return null;

      final root = jsonDecode(raw) as Map<String, dynamic>;
      final rawItems = root['items'] as List? ?? [];
      final items = <PosProduct>[];
      for (final e in rawItems) {
        if (e is! Map) continue;
        try {
          items.add(PosProduct.fromJson(Map<String, dynamic>.from(e)));
        } catch (_) {}
      }
      if (items.isEmpty) return null;

      final versionRaw = root['catalogVersion'];
      DateTime? catalogVersion;
      if (versionRaw != null) {
        catalogVersion = DateTime.tryParse(versionRaw.toString());
      }
      return PosSellCatalogSnapshot(
        items: items,
        cachedAt: DateTime.fromMillisecondsSinceEpoch(cachedAtMs),
        catalogVersion: catalogVersion,
      );
    } catch (_) {
      return null;
    }
  }

  Future<bool> shouldSync(String storeId) async {
    final snap = await read(storeId);
    if (snap == null) return true;
    return !snap.isFresh;
  }

  Future<void> write(
    String storeId, {
    required List<PosProduct> items,
    DateTime? catalogVersion,
  }) async {
    if (storeId.isEmpty) return;
    _lastStoreId = storeId;
    try {
      final payload = jsonEncode({
        'catalogVersion': catalogVersion?.toUtc().toIso8601String(),
        'items': items.map((p) => p.toSellCacheJson()).toList(),
      });
      await cache_io.writeCatalogJson(storeId, payload);

      final prefs = await SharedPreferences.getInstance();
      final metaKey = '$_metaPrefix$storeId';
      await prefs.setInt('${metaKey}_at', DateTime.now().millisecondsSinceEpoch);
      if (catalogVersion != null) {
        await prefs.setString(
          '${metaKey}_ver',
          catalogVersion.toUtc().toIso8601String(),
        );
      }
    } catch (_) {
      // Cache thất bại không được chặn UI catalog.
    }
  }

  Future<void> invalidate(String storeId) async {
    if (storeId.isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final metaKey = '$_metaPrefix$storeId';
      await prefs.remove('${metaKey}_at');
      await prefs.remove('${metaKey}_ver');
      await cache_io.deleteCatalogJson(storeId);
      if (_lastStoreId == storeId) _lastStoreId = null;
    } catch (_) {}
  }

  Future<void> invalidateLast() async {
    if (_lastStoreId != null && _lastStoreId!.isNotEmpty) {
      await invalidate(_lastStoreId!);
    }
  }
}
