import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Gán món → máy in **trên thiết bị này** (A7/A6 độc lập).
/// Không ghi đè map cửa hàng / Agent.
class PosDeviceProductPrinters {
  PosDeviceProductPrinters._();
  static final instance = PosDeviceProductPrinters._();

  static const _key = 'pos_device_product_printers_v1';

  Map<String, String> _slip = {};
  Map<String, String> _label = {};
  bool _loaded = false;

  Future<void> preload() async {
    if (_loaded) return;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw != null && raw.isNotEmpty) {
      try {
        final m = jsonDecode(raw);
        if (m is Map) {
          _slip = _asIdMap(m['slip']);
          _label = _asIdMap(m['label']);
        }
      } catch (e) {
        debugPrint('PosDeviceProductPrinters load: $e');
      }
    }
    _loaded = true;
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key,
      jsonEncode({'slip': _slip, 'label': _label}),
    );
  }

  static Map<String, String> _asIdMap(Object? raw) {
    if (raw is! Map) return {};
    final out = <String, String>{};
    raw.forEach((k, v) {
      final id = k.toString().trim();
      final pid = v?.toString().trim() ?? '';
      if (id.isNotEmpty && pid.isNotEmpty) out[id] = pid;
    });
    return out;
  }

  Map<String, String> _lane({required bool label}) => label ? _label : _slip;

  Future<String?> printerIdForProduct(
    String productId, {
    required bool label,
  }) async {
    await preload();
    final id = productId.trim();
    if (id.isEmpty) return null;
    final pid = _lane(label: label)[id]?.trim();
    return (pid == null || pid.isEmpty) ? null : pid;
  }

  Future<Set<String>> productIdsForPrinter(
    String printerId, {
    required bool label,
  }) async {
    await preload();
    final want = printerId.trim().toLowerCase();
    if (want.isEmpty) return {};
    return {
      for (final e in _lane(label: label).entries)
        if (e.value.trim().toLowerCase() == want) e.key,
    };
  }

  /// Toàn bộ map món → máy trên thiết bị này (phiếu hoặc tem).
  Future<Map<String, String>> laneSnapshot({required bool label}) async {
    await preload();
    return Map<String, String>.from(_lane(label: label));
  }

  Future<void> assignProducts({
    required String printerId,
    required Iterable<String> productIds,
    required bool label,
  }) async {
    await preload();
    final pid = printerId.trim();
    if (pid.isEmpty) return;
    final map = _lane(label: label);
    for (final raw in productIds) {
      final id = raw.trim();
      if (id.isEmpty || id == 'null') continue;
      map[id] = pid;
    }
    await _persist();
  }

  Future<void> unassignProducts({
    required Iterable<String> productIds,
    required bool label,
  }) async {
    await preload();
    final map = _lane(label: label);
    for (final raw in productIds) {
      map.remove(raw.trim());
    }
    await _persist();
  }
}
