import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/pos_product.dart';

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

  Future<File> _fileFor(String storeId) async {
    final dir = await getApplicationSupportDirectory();
    final safe = storeId.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
    return File('${dir.path}/pos_sell_catalog_$safe.json');
  }

  Future<PosSellCatalogSnapshot?> read(String storeId) async {
    if (storeId.isEmpty) return null;
    final prefs = await SharedPreferences.getInstance();
    final metaKey = '$_metaPrefix$storeId';
    final cachedAtMs = prefs.getInt('${metaKey}_at');
    if (cachedAtMs == null) return null;

    final file = await _fileFor(storeId);
    if (!await file.exists()) return null;

    try {
      final root = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      final rawItems = root['items'] as List? ?? [];
      final items = rawItems
          .map((e) => PosProduct.fromJson(e as Map<String, dynamic>))
          .toList();
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
    final file = await _fileFor(storeId);
    await file.parent.create(recursive: true);
    final payload = jsonEncode({
      'catalogVersion': catalogVersion?.toUtc().toIso8601String(),
      'items': items.map((p) => p.toSellCacheJson()).toList(),
    });
    await file.writeAsString(payload, flush: true);

    final prefs = await SharedPreferences.getInstance();
    final metaKey = '$_metaPrefix$storeId';
    await prefs.setInt('${metaKey}_at', DateTime.now().millisecondsSinceEpoch);
    if (catalogVersion != null) {
      await prefs.setString(
        '${metaKey}_ver',
        catalogVersion.toUtc().toIso8601String(),
      );
    }
  }

  Future<void> invalidate(String storeId) async {
    if (storeId.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final metaKey = '$_metaPrefix$storeId';
    await prefs.remove('${metaKey}_at');
    await prefs.remove('${metaKey}_ver');
    final file = await _fileFor(storeId);
    if (await file.exists()) {
      await file.delete();
    }
    if (_lastStoreId == storeId) _lastStoreId = null;
  }

  Future<void> invalidateLast() async {
    if (_lastStoreId != null && _lastStoreId!.isNotEmpty) {
      await invalidate(_lastStoreId!);
    }
  }
}
