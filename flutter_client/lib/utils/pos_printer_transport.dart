import 'dart:io' show Platform, Socket;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';
import 'package:sunmi_printer_plus/sunmi_printer_plus.dart';

import 'pos_thermal_printer_service.dart';
import 'pos_thermal_printer_settings.dart';

/// Gửi byte thô tới máy in qua Bluetooth / LAN / Sunmi.
class PosPrinterTransport {
  static Future<bool> send({
    required PosThermalConnectionType connectionType,
    String? bluetoothAddress,
    String? lanHost,
    int lanPort = 9100,
    required List<int> bytes,
    int sunmiFeedLines = 0,
  }) async {
    if (kIsWeb) return false;
    switch (connectionType) {
      case PosThermalConnectionType.lan:
        return _sendLan(lanHost, lanPort, bytes);
      case PosThermalConnectionType.sunmi:
        return _sendSunmi(bytes, sunmiFeedLines);
      case PosThermalConnectionType.bluetooth:
        return _sendBluetooth(bluetoothAddress, bytes);
      case PosThermalConnectionType.usb:
        if (await PosThermalPrinterService.isSunmiDevice()) {
          return _sendSunmi(bytes, sunmiFeedLines);
        }
        return _sendLan(lanHost, lanPort, bytes);
    }
  }

  static Future<bool> _sendLan(String? host, int port, List<int> bytes) async {
    final h = host?.trim();
    if (h == null || h.isEmpty) return false;
    try {
      final socket = await Socket.connect(h, port, timeout: const Duration(seconds: 8));
      socket.add(bytes);
      await socket.flush();
      await Future<void>.delayed(const Duration(milliseconds: 200));
      await socket.close();
      return true;
    } catch (e) {
      debugPrint('LAN print failed: $e');
      return false;
    }
  }

  static Future<bool> _sendSunmi(List<int> bytes, int feedLines) async {
    if (!await PosThermalPrinterService.isSunmiDevice()) return false;
    try {
      await SunmiPrinter.bindingPrinter();
      await SunmiPrinter.printRawData(Uint8List.fromList(bytes));
      if (feedLines > 0) await SunmiPrinter.lineWrap(feedLines);
      return true;
    } catch (e) {
      debugPrint('Sunmi print failed: $e');
      return false;
    }
  }

  static Future<bool> _sendBluetooth(String? addr, List<int> bytes) async {
    final address = addr?.trim();
    if (address == null || address.isEmpty) return false;
    try {
      final connected = await PrintBluetoothThermal.connect(macPrinterAddress: address);
      if (connected != true) return false;
      final ok = await PrintBluetoothThermal.writeBytes(bytes);
      await Future<void>.delayed(const Duration(milliseconds: 400));
      return ok == true;
    } catch (e) {
      debugPrint('Bluetooth print failed: $e');
      return false;
    }
  }
}
