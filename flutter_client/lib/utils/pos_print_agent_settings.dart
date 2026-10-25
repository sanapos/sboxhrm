import 'package:shared_preferences/shared_preferences.dart';

/// Cài đặt Print Agent trên thiết bị này (điện thoại giữ kết nối BT máy in).
class PosPrintAgentSettings {
  const PosPrintAgentSettings({
    this.enabled = false,
    this.assignedPrinterIds = const [],
    this.deviceId,
    this.accountLabel,
  });

  final bool enabled;
  final List<String> assignedPrinterIds;
  final String? deviceId;

  /// Tên NV / email đăng nhập — gửi kèm heartbeat để máy khác thấy ai đang giữ Agent.
  final String? accountLabel;

  static const _kEnabled = 'pos_print_agent_enabled';
  static const _kPrinterIds = 'pos_print_agent_printer_ids';
  static const _kDeviceId = 'pos_print_device_id';
  static const _kAccountLabel = 'pos_print_agent_account_label';
  static const _kStoreId = 'pos_print_agent_store_id';

  /// Cửa hàng đang đăng nhập — app gán ngay khi biết storeId. Agent bật ở cửa hàng
  /// này không chạy khi máy đăng nhập cửa hàng khác (chip máy in là GUID của hàng cũ).
  static String? activeStoreId;
  static const _kMigrationKey = 'pos_print_agent_migration';
  // Bump to force one-time reset of enabled/printerIds/deviceId — Android
  // Auto Backup có thể phục hồi cấu hình Agent cũ (bật + gán máy in của
  // thiết bị khác) sau khi gỡ cài đặt lại app, khiến máy gửi (A7) vô tình
  // trở thành Agent "ma" tranh nhận job in của máy thật (A6).
  static const _kMigrationValue = 'reset_v1';

  static Future<PosPrintAgentSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    final migrated = prefs.getString(_kMigrationKey) == _kMigrationValue;
    if (!migrated) {
      await prefs.setBool(_kEnabled, false);
      await prefs.remove(_kPrinterIds);
      await prefs.remove(_kDeviceId);
      await prefs.setString(_kMigrationKey, _kMigrationValue);
    }
    final ids = prefs.getStringList(_kPrinterIds) ?? [];
    final owner = prefs.getString(_kStoreId);
    final active = activeStoreId;
    if (active != null && active.isNotEmpty) {
      if (owner == null || owner.isEmpty) {
        // Bản cũ chưa lưu cửa hàng: gắn với cửa hàng đang đăng nhập.
        await prefs.setString(_kStoreId, active);
      } else if (owner.toLowerCase() != active.toLowerCase()) {
        return PosPrintAgentSettings(
          deviceId: prefs.getString(_kDeviceId),
          accountLabel: prefs.getString(_kAccountLabel),
        );
      }
    }
    return PosPrintAgentSettings(
      enabled: prefs.getBool(_kEnabled) ?? false,
      assignedPrinterIds: ids,
      deviceId: prefs.getString(_kDeviceId),
      accountLabel: prefs.getString(_kAccountLabel),
    );
  }

  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kEnabled, enabled);
    await prefs.setStringList(_kPrinterIds, assignedPrinterIds);
    final active = activeStoreId;
    if (active != null && active.isNotEmpty) {
      await prefs.setString(_kStoreId, active);
    }
    if (deviceId != null && deviceId!.isNotEmpty) {
      await prefs.setString(_kDeviceId, deviceId!);
    }
    final label = accountLabel?.trim() ?? '';
    if (label.isEmpty) {
      await prefs.remove(_kAccountLabel);
    } else {
      await prefs.setString(_kAccountLabel, label);
    }
  }

  PosPrintAgentSettings copyWith({
    bool? enabled,
    List<String>? assignedPrinterIds,
    String? deviceId,
    String? accountLabel,
  }) =>
      PosPrintAgentSettings(
        enabled: enabled ?? this.enabled,
        assignedPrinterIds: assignedPrinterIds ?? this.assignedPrinterIds,
        deviceId: deviceId ?? this.deviceId,
        accountLabel: accountLabel ?? this.accountLabel,
      );
}
