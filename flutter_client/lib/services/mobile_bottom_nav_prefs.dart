import 'package:flutter/foundation.dart';

import '../models/mobile_bottom_nav_config.dart';
import '../services/api_service.dart';

/// Tải / lưu bố cục thanh điều hướng mobile (theo cửa hàng — AppSettings).
class MobileBottomNavPrefs {
  MobileBottomNavPrefs._();

  static final ValueNotifier<int> revision = ValueNotifier(0);

  static MobileBottomNavLayout? _mainCache;
  static MobileBottomNavLayout? _posCache;

  static MobileBottomNavLayout get mainLayout =>
      _mainCache ?? MobileBottomNavLayout.mainDefaults();

  static MobileBottomNavLayout get posLayout =>
      _posCache ?? MobileBottomNavLayout.posDefaults();

  static void clearCache() {
    _mainCache = null;
    _posCache = null;
  }

  static void _notify() => revision.value++;

  static Future<void> loadAll() async {
    await Future.wait([loadMain(), loadPos()]);
  }

  static Future<MobileBottomNavLayout> loadMain() async {
    final parsed = await _loadKey(MobileBottomNavLayout.storageKeyMain);
    _mainCache = parsed.slots.isEmpty
        ? MobileBottomNavLayout.mainDefaults()
        : parsed;
    return _mainCache!;
  }

  static Future<MobileBottomNavLayout> loadPos() async {
    final parsed = await _loadKey(MobileBottomNavLayout.storageKeyPos);
    _posCache = parsed.slots.isEmpty
        ? MobileBottomNavLayout.posDefaults()
        : parsed;
    return _posCache!;
  }

  static Future<MobileBottomNavLayout> _loadKey(String key) async {
    try {
      final res = await ApiService().getAppSetting(key);
      if (res['isSuccess'] == true && res['data'] is Map) {
        final value = (res['data'] as Map)['value']?.toString();
        final parsed = MobileBottomNavLayout.parseValue(value);
        if (parsed.slots.isNotEmpty) return parsed;
      }
    } catch (_) {}
    return const MobileBottomNavLayout(slots: []);
  }

  static Future<bool> saveMain(MobileBottomNavLayout layout) async =>
      _save(MobileBottomNavLayout.storageKeyMain, layout, isMain: true);

  static Future<bool> savePos(MobileBottomNavLayout layout) async =>
      _save(MobileBottomNavLayout.storageKeyPos, layout, isMain: false);

  static Future<bool> _save(
    String key,
    MobileBottomNavLayout layout, {
    required bool isMain,
  }) async {
    try {
      final res = await ApiService().upsertAppSetting(
        key: key,
        value: layout.toStorageValue(),
        description: isMain
            ? 'Bố cục thanh điều hướng mobile (app)'
            : 'Bố cục thanh điều hướng mobile (POS)',
        group: 'ui',
        dataType: 'json',
      );
      if (res['isSuccess'] == true) {
        if (isMain) {
          _mainCache = layout;
        } else {
          _posCache = layout;
        }
        _notify();
        return true;
      }
    } catch (_) {}
    return false;
  }

  static Future<MobileBottomNavLayout> resetMain() async {
    final d = MobileBottomNavLayout.mainDefaults();
    await saveMain(d);
    return d;
  }

  static Future<MobileBottomNavLayout> resetPos() async {
    final d = MobileBottomNavLayout.posDefaults();
    await savePos(d);
    return d;
  }
}
