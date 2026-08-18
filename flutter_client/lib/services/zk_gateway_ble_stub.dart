import 'zk_gateway_ble.dart';

class _UnsupportedBle implements ZkGatewayBle {
  @override
  bool get isSupported => false;

  @override
  Future<void> ensureReady() async {
    throw UnsupportedError('BLE không hỗ trợ trên nền tảng này');
  }

  @override
  Stream<List<ZkBleDevice>> scan({Duration timeout = const Duration(seconds: 12)}) =>
      const Stream.empty();

  @override
  Future<void> stopScan() async {}

  @override
  Future<void> connect(String deviceId) async {
    throw UnsupportedError('BLE không hỗ trợ trên nền tảng này');
  }

  @override
  Future<void> disconnect() async {}

  @override
  Future<Map<String, dynamic>> readInfo() async => {};

  @override
  Future<ZkBleProvStatus> readStatus() async =>
      const ZkBleProvStatus(state: 'idle');

  @override
  Stream<ZkBleProvStatus> statusNotifications() => const Stream.empty();

  @override
  Future<void> writeConfig(Map<String, dynamic> payload) async {
    throw UnsupportedError('BLE không hỗ trợ trên nền tảng này');
  }

  @override
  Future<void> dispose() async {}
}

ZkGatewayBle createZkGatewayBle() => _UnsupportedBle();
