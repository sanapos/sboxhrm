import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';

import 'zk_gateway_ble.dart';

class _IoZkGatewayBle implements ZkGatewayBle {
  BluetoothDevice? _device;
  BluetoothCharacteristic? _configChr;
  BluetoothCharacteristic? _statusChr;
  BluetoothCharacteristic? _infoChr;
  StreamSubscription<List<ScanResult>>? _scanSub;

  @override
  bool get isSupported {
    if (kIsWeb) return false;
    return defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS;
  }

  @override
  Future<void> ensureReady() async {
    if (!isSupported) {
      throw const ZkBleException('Thiết bị này không hỗ trợ Bluetooth LE');
    }
    final adapter = await FlutterBluePlus.isSupported;
    if (!adapter) {
      throw const ZkBleException('Máy không có Bluetooth LE');
    }

    if (defaultTargetPlatform == TargetPlatform.android) {
      final scan = await Permission.bluetoothScan.request();
      final connect = await Permission.bluetoothConnect.request();
      if (!scan.isGranted || !connect.isGranted) {
        // Android cũ: BLE scan cần location.
        final loc = await Permission.locationWhenInUse.request();
        if (!loc.isGranted && (!scan.isGranted || !connect.isGranted)) {
          throw const ZkBleException(
            'Cần quyền Bluetooth (và Vị trí trên Android cũ) để dò gateway',
          );
        }
      }
    }

    if (FlutterBluePlus.adapterStateNow != BluetoothAdapterState.on) {
      try {
        await FlutterBluePlus.turnOn();
      } catch (_) {}
      await FlutterBluePlus.adapterState
          .where((s) => s == BluetoothAdapterState.on)
          .first
          .timeout(
            const Duration(seconds: 8),
            onTimeout: () => BluetoothAdapterState.off,
          );
      if (FlutterBluePlus.adapterStateNow != BluetoothAdapterState.on) {
        throw const ZkBleException('Hãy bật Bluetooth rồi thử lại');
      }
    }
  }

  @override
  Stream<List<ZkBleDevice>> scan({
    Duration timeout = const Duration(seconds: 12),
  }) {
    final controller = StreamController<List<ZkBleDevice>>();
    () async {
      try {
        await ensureReady();
        await stopScan();
        final byId = <String, ZkBleDevice>{};

        _scanSub = FlutterBluePlus.scanResults.listen((results) {
          for (final r in results) {
            final name = r.advertisementData.advName.isNotEmpty
                ? r.advertisementData.advName
                : r.device.platformName;
            final hasSvc = r.advertisementData.serviceUuids.any(
              (u) => u.str.toLowerCase() == ZkBleUuids.service.toLowerCase(),
            );
            if (!_isSboxGatewayName(name) && !hasSvc) continue;
            final label = name.isNotEmpty ? name : 'SBOX-Gateway';
            byId[r.device.remoteId.str] = ZkBleDevice(
              id: r.device.remoteId.str,
              name: label,
              rssi: r.rssi,
            );
          }
          if (!controller.isClosed) {
            final list = byId.values.toList()
              ..sort((a, b) => b.rssi.compareTo(a.rssi));
            controller.add(List<ZkBleDevice>.from(list));
          }
        });

        await FlutterBluePlus.startScan(
          timeout: timeout,
          androidUsesFineLocation: true,
        );
        await Future<void>.delayed(timeout + const Duration(milliseconds: 400));
      } catch (e, st) {
        controller.addError(e, st);
      } finally {
        await stopScan();
        if (!controller.isClosed) await controller.close();
      }
    }();
    return controller.stream;
  }

  @override
  Future<void> stopScan() async {
    await _scanSub?.cancel();
    _scanSub = null;
    try {
      await FlutterBluePlus.stopScan();
    } catch (_) {}
  }

  @override
  Future<void> connect(String deviceId) async {
    await stopScan();
    await disconnect();
    final device = BluetoothDevice.fromId(deviceId);
    await device.connect(timeout: const Duration(seconds: 15), autoConnect: false);
    _device = device;

    final services = await device.discoverServices();
    BluetoothService? svc;
    for (final s in services) {
      if (s.uuid.str.toLowerCase() == ZkBleUuids.service.toLowerCase()) {
        svc = s;
        break;
      }
    }
    if (svc == null) {
      await disconnect();
      throw const ZkBleException(
        'Thiết bị BLE không phải gateway SBOX (thiếu service)',
      );
    }

    for (final c in svc.characteristics) {
      final id = c.uuid.str.toLowerCase();
      if (id == ZkBleUuids.config.toLowerCase()) _configChr = c;
      if (id == ZkBleUuids.status.toLowerCase()) _statusChr = c;
      if (id == ZkBleUuids.info.toLowerCase()) _infoChr = c;
    }
    if (_configChr == null || _statusChr == null) {
      await disconnect();
      throw const ZkBleException('Gateway BLE thiếu characteristic cấu hình');
    }

    try {
      await _device!.requestMtu(247);
    } catch (_) {}

    if (_statusChr!.properties.notify) {
      await _statusChr!.setNotifyValue(true);
    }
  }

  @override
  Future<void> disconnect() async {
    final d = _device;
    _device = null;
    _configChr = null;
    _statusChr = null;
    _infoChr = null;
    if (d != null) {
      try {
        await d.disconnect();
      } catch (_) {}
    }
  }

  @override
  Future<Map<String, dynamic>> readInfo() async {
    final chr = _infoChr;
    if (chr == null) return {};
    final raw = await chr.read();
    return _decodeJsonMap(raw);
  }

  @override
  Future<ZkBleProvStatus> readStatus() async {
    final chr = _statusChr;
    if (chr == null) return const ZkBleProvStatus(state: 'idle');
    final raw = await chr.read();
    return ZkBleProvStatus.fromJson(_decodeJsonMap(raw));
  }

  @override
  Stream<ZkBleProvStatus> statusNotifications() {
    final chr = _statusChr;
    if (chr == null) return const Stream.empty();
    return chr.onValueReceived.map((raw) {
      try {
        return ZkBleProvStatus.fromJson(_decodeJsonMap(raw));
      } catch (_) {
        return const ZkBleProvStatus(state: 'idle');
      }
    });
  }

  @override
  Future<void> writeConfig(Map<String, dynamic> payload) async {
    final chr = _configChr;
    if (chr == null) {
      throw const ZkBleException('Chưa kết nối gateway BLE');
    }
    final bytes = utf8.encode(jsonEncode(payload));
    if (bytes.length > 480) {
      throw const ZkBleException('Cấu hình quá dài');
    }
    await chr.write(bytes, withoutResponse: false, allowLongWrite: true);
  }

  @override
  Future<void> dispose() async {
    await stopScan();
    await disconnect();
  }

  bool _isSboxGatewayName(String name) {
    final n = name.trim();
    return n.startsWith('SBOX-Gateway-') || n.startsWith('SBOX-GW-');
  }

  Map<String, dynamic> _decodeJsonMap(List<int> raw) {
    final text = utf8.decode(raw, allowMalformed: true).trim();
    if (text.isEmpty) return {};
    final decoded = jsonDecode(text);
    if (decoded is Map) {
      return decoded.cast<String, dynamic>();
    }
    return {};
  }
}

ZkGatewayBle createZkGatewayBle() => _IoZkGatewayBle();
