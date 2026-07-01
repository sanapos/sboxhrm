import '../models/settings_hub_sidebar_config.dart';
import '../services/api_service.dart';
import '../utils/settings_hub_catalog.dart';

/// Tải / lưu cấu hình sidebar Thiết lập HRM (theo cửa hàng qua AppSettings).
class SettingsHubSidebarPrefs {
  SettingsHubSidebarPrefs._();

  static SettingsHubSidebarConfig? _cache;

  static SettingsHubSidebarConfig? get cached => _cache;

  static void setCache(SettingsHubSidebarConfig? config) {
    _cache = config;
  }

  static Future<SettingsHubSidebarConfig> load() async {
    if (_cache != null) return _cache!;
    try {
      final res =
          await ApiService().getAppSetting(SettingsHubSidebarConfig.storageKey);
      if (res['isSuccess'] == true && res['data'] is Map) {
        final data = res['data'] as Map;
        final value = data['value']?.toString();
        final parsed = SettingsHubSidebarConfig.parseValue(value);
        if (parsed.order.isNotEmpty) {
          _cache = parsed;
          return parsed;
        }
      }
    } catch (_) {}
    final defaults =
        SettingsHubSidebarConfig.defaults(SettingsHubCatalog.defaultOrder);
    _cache = defaults;
    return defaults;
  }

  static Future<bool> save(SettingsHubSidebarConfig config) async {
    try {
      final res = await ApiService().upsertAppSetting(
        key: SettingsHubSidebarConfig.storageKey,
        value: config.toStorageValue(),
        description: 'Thứ tự và hiển thị module sidebar Thiết lập HRM',
        group: 'ui',
        dataType: 'json',
      );
      if (res['isSuccess'] == true) {
        _cache = config;
        return true;
      }
    } catch (_) {}
    return false;
  }

  static Future<SettingsHubSidebarConfig> reset() async {
    final defaults =
        SettingsHubSidebarConfig.defaults(SettingsHubCatalog.defaultOrder);
    await save(defaults);
    return defaults;
  }
}
