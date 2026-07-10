import 'package:flutter/foundation.dart';

import '../models/mobile_quick_actions_config.dart';
import '../services/api_service.dart';

class MobileQuickActionsPrefs {
  MobileQuickActionsPrefs._();

  static final ValueNotifier<int> revision = ValueNotifier(0);

  static MobileQuickActionsLayout? _cache;

  static MobileQuickActionsLayout get layout =>
      _cache ?? MobileQuickActionsLayout.defaults();

  static void clearCache() => _cache = null;

  static void _notify() => revision.value++;

  static Future<MobileQuickActionsLayout> load() async {
    try {
      final res =
          await ApiService().getAppSetting(MobileQuickActionsLayout.storageKey);
      if (res['isSuccess'] == true && res['data'] is Map) {
        final value = (res['data'] as Map)['value']?.toString();
        final parsed = MobileQuickActionsLayout.parseValue(value);
        if (parsed.modules.isNotEmpty) {
          _cache = parsed;
          return _cache!;
        }
      }
    } catch (_) {}
    _cache = MobileQuickActionsLayout.defaults();
    return _cache!;
  }

  static Future<bool> save(MobileQuickActionsLayout layout) async {
    try {
      final res = await ApiService().upsertAppSetting(
        key: MobileQuickActionsLayout.storageKey,
        value: layout.toStorageValue(),
        description: 'Lưới truy cập nhanh tab Thêm (mobile)',
        group: 'ui',
        dataType: 'json',
      );
      if (res['isSuccess'] == true) {
        _cache = layout;
        _notify();
        return true;
      }
    } catch (_) {}
    return false;
  }

  static Future<MobileQuickActionsLayout> reset() async {
    final d = MobileQuickActionsLayout.defaults();
    await save(d);
    return d;
  }
}
