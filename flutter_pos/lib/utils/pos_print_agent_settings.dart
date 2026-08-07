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

  static Future<PosPrintAgentSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    final ids = prefs.getStringList(_kPrinterIds) ?? [];
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
