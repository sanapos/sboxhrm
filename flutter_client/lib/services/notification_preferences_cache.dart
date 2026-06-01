import 'package:flutter/foundation.dart';
import '../utils/notification_category_utils.dart';
import 'api_service.dart';

/// In-memory cache of per-user notification category preferences (from API).
class NotificationPreferencesCache {
  NotificationPreferencesCache._();
  static final NotificationPreferencesCache instance =
      NotificationPreferencesCache._();

  final Map<String, bool> _byCode = {};
  bool _loaded = false;
  Future<void>? _loading;

  bool get isLoaded => _loaded;

  Future<void> ensureLoaded([ApiService? api]) async {
    if (_loaded) return;
    if (_loading != null) {
      await _loading;
      return;
    }
    _loading = refresh(api ?? ApiService());
    try {
      await _loading;
    } finally {
      _loading = null;
    }
  }

  Future<void> refresh(ApiService api) async {
    _byCode.clear();
    try {
      final result = await api.getNotificationPreferences();
      if (result['isSuccess'] == true && result['data'] is List) {
        for (final raw in result['data'] as List) {
          final map = Map<String, dynamic>.from(raw as Map);
          final code = NotificationCategoryUtils.normalizeCategory(
            map['categoryCode'] as String?,
          );
          if (code == null || code.isEmpty) continue;
          _byCode[code] = map['isEnabled'] as bool? ?? true;
        }
      }
    } catch (e) {
      debugPrint('NotificationPreferencesCache.refresh failed: $e');
    }
    _loaded = true;
  }

  void applyFromPreferenceList(List<Map<String, dynamic>> prefs) {
    for (final p in prefs) {
      final code = NotificationCategoryUtils.normalizeCategory(
        p['categoryCode'] as String?,
      );
      if (code == null || code.isEmpty) continue;
      _byCode[code] = p['isEnabled'] as bool? ?? true;
    }
    _loaded = true;
  }

  void clear() {
    _byCode.clear();
    _loaded = false;
  }

  bool isCategoryEnabled({
    String? categoryCode,
    String? relatedEntityType,
  }) {
    final code = NotificationCategoryUtils.resolveCategory(
      categoryCode: categoryCode,
      relatedEntityType: relatedEntityType,
    );
    return _byCode[code] ?? true;
  }
}
