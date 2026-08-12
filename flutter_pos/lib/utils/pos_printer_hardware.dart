import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';

/// Bridge native: Bluetooth đã ghép + chẩn đoán USB host.
class PosPrinterHardware {
  PosPrinterHardware._();
  static const _ch = MethodChannel('com.sboxhrm/printer_hardware');

  static bool get isSupported => !kIsWeb && Platform.isAndroid;

  static Future<Map<String, dynamic>> bluetoothDiagnostics() async {
    if (!isSupported) return const {};
    try {
      final raw = await _ch.invokeMethod<Map>('bluetoothDiagnostics');
      return Map<String, dynamic>.from(raw ?? const {});
    } catch (e) {
      debugPrint('bluetoothDiagnostics: $e');
      return const {};
    }
  }

  static Future<Map<String, dynamic>> usbDiagnostics() async {
    if (!isSupported) return const {};
    try {
      final raw = await _ch.invokeMethod<Map>('usbDiagnostics');
      return Map<String, dynamic>.from(raw ?? const {});
    } catch (e) {
      debugPrint('usbDiagnostics: $e');
      return const {};
    }
  }

  static Future<List<Map<String, String>>> listBondedBluetoothNative() async {
    if (!isSupported) return const [];
    try {
      final raw = await _ch.invokeMethod<List>('listBondedBluetooth');
      if (raw == null) return const [];
      return raw.whereType<Map>().map((e) {
        return {
          'name': e['name']?.toString() ?? 'Bluetooth',
          'address': e['address']?.toString() ?? '',
        };
      }).where((e) => e['address']!.isNotEmpty).toList();
    } catch (e) {
      debugPrint('listBondedBluetoothNative: $e');
      return const [];
    }
  }

  static Future<bool> requestEnableBluetooth() async {
    if (!isSupported) return false;
    try {
      return await _ch.invokeMethod<bool>('requestEnableBluetooth') == true;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> openBluetoothSettings() async {
    if (!isSupported) return false;
    try {
      return await _ch.invokeMethod<bool>('openBluetoothSettings') == true;
    } catch (_) {
      return false;
    }
  }

  /// Xin quyền cần thiết rồi lấy danh sách máy BT đã ghép (native + plugin).
  static Future<({List<Map<String, String>> devices, String? hint})>
      listBluetoothForPicker() async {
    if (kIsWeb) {
      return (devices: <Map<String, String>>[], hint: 'Web không hỗ trợ Bluetooth');
    }

    // Android 12+: Nearby devices. Android 6–11: Location (một số ROM cần để đọc bonded).
    try {
      await [
        Permission.bluetooth,
        Permission.bluetoothConnect,
        Permission.bluetoothScan,
        Permission.locationWhenInUse,
      ].request();
    } catch (e) {
      debugPrint('BT permission request: $e');
    }

    final diag = await bluetoothDiagnostics();
    final enabled = diag['enabled'] == true ||
        await PrintBluetoothThermal.bluetoothEnabled;

    if (!enabled) {
      await requestEnableBluetooth();
      return (
        devices: <Map<String, String>>[],
        hint:
            'Bluetooth đang tắt. Bật Bluetooth, ghép máy in trong Cài đặt, rồi bấm làm mới.',
      );
    }

    final byAddr = <String, Map<String, String>>{};
    void addAll(List<Map<String, String>> list) {
      for (final d in list) {
        final a = (d['address'] ?? '').trim().toUpperCase();
        if (a.isEmpty) continue;
        byAddr.putIfAbsent(a, () => {
              'name': d['name'] ?? 'Bluetooth',
              'address': d['address'] ?? a,
            });
      }
    }

    addAll(await listBondedBluetoothNative());
    try {
      final paired = await PrintBluetoothThermal.pairedBluetooths
          .timeout(const Duration(seconds: 5), onTimeout: () => []);
      addAll(
        paired
            .map((d) => {'name': d.name, 'address': d.macAdress})
            .toList(),
      );
    } catch (e) {
      debugPrint('pairedBluetooths: $e');
    }

    final devices = byAddr.values.toList()
      ..sort((a, b) => (a['name'] ?? '').compareTo(b['name'] ?? ''));

    if (devices.isEmpty) {
      return (
        devices: devices,
        hint:
            'Chưa có máy in Bluetooth đã ghép. Vào Cài đặt Bluetooth → Ghép máy in (PIN thường 0000/1234) → quay lại bấm làm mới. Hoặc nhập MAC thủ công.',
      );
    }
    return (devices: devices, hint: null);
  }
}
