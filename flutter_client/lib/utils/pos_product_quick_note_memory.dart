import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Ghi chú nhanh học từ màn bán — theo cửa hàng + món, gợi ý lần mở sau.
class PosProductQuickNoteMemory {
  PosProductQuickNoteMemory._();

  static const _prefix = 'pos_learned_line_notes_v1_';

  static String _key(String storeId) => '$_prefix$storeId';

  static Future<List<String>> load(String storeId, String productId) async {
    if (storeId.isEmpty || productId.isEmpty) return const [];
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key(storeId));
      if (raw == null || raw.isEmpty) return const [];
      final map = jsonDecode(raw);
      if (map is! Map) return const [];
      final list = map[productId];
      if (list is! List) return const [];
      return list
          .map((e) => e.toString().trim())
          .where((s) => s.isNotEmpty)
          .toList();
    } catch (_) {
      return const [];
    }
  }

  static Future<void> remember(
    String storeId,
    String productId,
    String note, {
    int maxPerProduct = 20,
  }) async {
    final t = note.trim();
    if (storeId.isEmpty || productId.isEmpty || t.isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = _key(storeId);
      final raw = prefs.getString(key);
      Map<String, dynamic> map = {};
      if (raw != null && raw.isEmpty == false) {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          map = Map<String, dynamic>.from(decoded);
        }
      }
      final prev = <String>[];
      final existing = map[productId];
      if (existing is List) {
        for (final e in existing) {
          final s = e.toString().trim();
          if (s.isNotEmpty) prev.add(s);
        }
      }
      final next = <String>[t];
      for (final s in prev) {
        if (s.toLowerCase() == t.toLowerCase()) continue;
        next.add(s);
        if (next.length >= maxPerProduct) break;
      }
      map[productId] = next;
      await prefs.setString(key, jsonEncode(map));
    } catch (_) {}
  }

  static Future<void> forget(
    String storeId,
    String productId,
    String note,
  ) async {
    final t = note.trim();
    if (storeId.isEmpty || productId.isEmpty || t.isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = _key(storeId);
      final raw = prefs.getString(key);
      if (raw == null || raw.isEmpty) return;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return;
      final map = Map<String, dynamic>.from(decoded);
      final existing = map[productId];
      if (existing is! List) return;
      final next = existing
          .map((e) => e.toString().trim())
          .where((s) => s.isNotEmpty && s.toLowerCase() != t.toLowerCase())
          .toList();
      if (next.isEmpty) {
        map.remove(productId);
      } else {
        map[productId] = next;
      }
      await prefs.setString(key, jsonEncode(map));
    } catch (_) {}
  }
}
