import 'package:shared_preferences/shared_preferences.dart';

import 'mobile_device_id.dart';

/// Cache cờ ảnh hiện trường (cửa hàng + từng thiết bị) khi server chưa đồng bộ.
class DeviceSitePhotoPrefs {
  static const _storeKey = 'mobile_site_photo_store_enabled';
  static const _devicePrefix = 'mobile_site_photo_device_';

  static Future<void> setStoreEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_storeKey, enabled);
  }

  static Future<bool> getStoreEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_storeKey) ?? false;
  }

  static Future<void> setDeviceEnabled(String deviceId, bool enabled) async {
    final id = deviceId.trim();
    if (id.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('$_devicePrefix$id', enabled);
  }

  static Future<bool> getDeviceEnabled(String deviceId) async {
    final id = deviceId.trim();
    if (id.isEmpty) return false;
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('$_devicePrefix$id') ?? false;
  }

  /// Ghi cờ cho cả mã máy trên server và mã máy đang cầm (tránh lệch id).
  static Future<void> setDeviceEnabledForRecord(
    String serverDeviceId,
    bool enabled,
  ) async {
    await setDeviceEnabled(serverDeviceId, enabled);
    if (enabled) await setStoreEnabled(true);
    try {
      final currentId = await MobileDeviceId.resolve();
      if (currentId.trim().isNotEmpty &&
          currentId.trim() != serverDeviceId.trim()) {
        await setDeviceEnabled(currentId, enabled);
      }
    } catch (_) {}
  }

  /// Đồng bộ prefs khi UI đang hiển thị BẬT (tránh API server trả TẮT).
  static Future<void> syncFromUiState({
    required bool storeEnabled,
    String? deviceId,
    bool deviceEnabled = false,
  }) async {
    await setStoreEnabled(storeEnabled);
    if (deviceId != null &&
        deviceId.trim().isNotEmpty &&
        deviceEnabled) {
      await setDeviceEnabledForRecord(deviceId, true);
    }
  }

  static Future<String> resolveHardwareId(String? hardwareDeviceId) async {
    final h = hardwareDeviceId?.trim() ?? '';
    if (h.isNotEmpty) return h;
    try {
      return await MobileDeviceId.resolve();
    } catch (_) {
      return '';
    }
  }

  static Future<bool> isDeviceEnabledOnPhone(String? hardwareDeviceId) async {
    final id = await resolveHardwareId(hardwareDeviceId);
    if (id.isEmpty) return false;
    return getDeviceEnabled(id);
  }

  /// Quyết định mở camera sau chấm — ưu tiên prefs trên máy.
  static Future<bool> shouldCaptureAfterPunch({
    bool serverStoreFlag = false,
    bool serverDeviceFlag = false,
    String? hardwareDeviceId,
  }) async {
    if (await isDeviceEnabledOnPhone(hardwareDeviceId)) return true;
    // Bật cấp cửa hàng (prefs hoặc server) → chụp cho mọi thiết bị, không cần bật từng máy.
    if (await getStoreEnabled() || serverStoreFlag) return true;
    if (serverDeviceFlag) return true;
    return false;
  }
}
