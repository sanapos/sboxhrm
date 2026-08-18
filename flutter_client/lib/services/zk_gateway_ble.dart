import '../models/zk_gateway.dart';

import 'zk_gateway_ble_stub.dart'
    if (dart.library.io) 'zk_gateway_ble_io.dart' as impl;

/// Kết quả dò BLE một gateway SBOX.
class ZkBleDevice {
  const ZkBleDevice({
    required this.id,
    required this.name,
    required this.rssi,
  });

  final String id;
  final String name;
  final int rssi;

  String get displayName => name.isNotEmpty ? name : 'SBOX Gateway';
}

/// Trạng thái sau khi gửi cấu hình qua BLE.
class ZkBleProvStatus {
  const ZkBleProvStatus({
    required this.state,
    this.ip = '',
    this.message = '',
    this.wifi = false,
    this.provisioned = false,
  });

  final String state;
  final String ip;
  final String message;
  final bool wifi;
  final bool provisioned;

  bool get isConnected => state == 'connected' && (wifi || ip.isNotEmpty);
  bool get isFailed => state == 'failed';
  bool get isBusy =>
      state == 'saving' || state == 'connecting' || state == 'busy';

  factory ZkBleProvStatus.fromJson(Map<String, dynamic> json) => ZkBleProvStatus(
        state: json['state']?.toString() ?? 'idle',
        ip: json['ip']?.toString() ?? '',
        message: json['msg']?.toString() ?? json['message']?.toString() ?? '',
        wifi: json['wifi'] == true,
        provisioned: json['provisioned'] == true,
      );
}

/// UUID GATT khớp firmware `ble_prov.c`.
abstract final class ZkBleUuids {
  static const service = 'a6b10001-0a7c-4b8e-9f21-5b0c90000001';
  static const config = 'a6b10001-0a7c-4b8e-9f21-5b0c90000002';
  static const status = 'a6b10001-0a7c-4b8e-9f21-5b0c90000003';
  static const info = 'a6b10001-0a7c-4b8e-9f21-5b0c90000004';
}

/// API cấu hình gateway qua Bluetooth LE.
abstract class ZkGatewayBle {
  bool get isSupported;

  Future<void> ensureReady();

  /// Quét thiết bị tên bắt đầu bằng `SBOX-Gateway-`.
  Stream<List<ZkBleDevice>> scan({
    Duration timeout = const Duration(seconds: 12),
  });

  Future<void> stopScan();

  Future<void> connect(String deviceId);

  Future<void> disconnect();

  Future<Map<String, dynamic>> readInfo();

  Future<ZkBleProvStatus> readStatus();

  Stream<ZkBleProvStatus> statusNotifications();

  /// Gửi JSON cấu hình (wifiSsid, wifiPass, deviceIp, ...).
  Future<void> writeConfig(Map<String, dynamic> payload);

  Future<void> dispose();
}

ZkGatewayBle createZkGatewayBle() => impl.createZkGatewayBle();

class ZkBleException implements Exception {
  const ZkBleException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Helper: dựng payload từ [ZkGatewayConfig] + mật khẩu WiFi.
Map<String, dynamic> zkBleConfigPayload(
  ZkGatewayConfig cfg, {
  required String wifiPass,
}) {
  return {
    'gwName': cfg.gwName,
    'wifiSsid': cfg.wifiSsid,
    'wifiPass': wifiPass,
    'deviceIp': cfg.deviceIp,
    'devicePort': cfg.devicePort,
    'commKey': cfg.commKey,
  };
}
