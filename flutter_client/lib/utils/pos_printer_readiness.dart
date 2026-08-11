import 'dart:io' show Socket;

import 'package:flutter/foundation.dart';

import 'pos_local_printers_store.dart';
import 'pos_printer_transport.dart';
import 'pos_thermal_printer_settings.dart';
import 'pos_usb_printer.dart';

/// Tráº¡ng thÃ¡i káº¿t ná»‘i mÃ¡y in trÃªn thiáº¿t bá»‹ hiá»‡n táº¡i.
enum PosPrinterLinkStatus {
  /// USB gáº¯n / Sunmi OK / LAN má»Ÿ Ä‘Æ°á»£c / BT cÃ³ Ä‘á»‹a chá»‰.
  ready,
  /// ÄÃ£ cáº¥u hÃ¬nh nhÆ°ng khÃ´ng tháº¥y cá»•ng / khÃ´ng ping Ä‘Æ°á»£c.
  lost,
  /// MÃ¡y táº¯t trong app, hoáº·c chÆ°a Ä‘á»§ thÃ´ng tin Ä‘á»ƒ kiá»ƒm.
  unknown,
}

/// QuÃ©t cá»•ng ná»™i bá»™ (USB/LAN/BT/Sunmi) â€” dÃ¹ng chung mÃ n Agent + MÃ¡y in ná»™i bá»™.
class PosPrinterReadiness {
  PosPrinterReadiness._();

  static Future<List<PosUsbDevice>> listUsbDevices() async {
    if (kIsWeb || !PosUsbPrinter.isSupported) return const [];
    try {
      return await PosUsbPrinter.listDevices();
    } catch (_) {
      return const [];
    }
  }

  static Future<PosPrinterLinkStatus> probeLocal(
    PosLocalPrinterProfile p, {
    List<PosUsbDevice>? usbList,
  }) async {
    if (!p.enabled) return PosPrinterLinkStatus.unknown;
    if (kIsWeb) return PosPrinterLinkStatus.unknown;
    final list = usbList ?? await listUsbDevices();
    final ok = await probePort(
      connectionType: p.connectionType,
      usbDeviceName: p.usbDeviceName,
      lanHost: p.lanHost,
      lanPort: p.lanPort,
      bluetoothAddress: p.bluetoothAddress,
      usbList: list,
    );
    return ok ? PosPrinterLinkStatus.ready : PosPrinterLinkStatus.lost;
  }

  static Future<bool> probePort({
    required PosThermalConnectionType connectionType,
    String? usbDeviceName,
    String? lanHost,
    int lanPort = 9100,
    String? bluetoothAddress,
    required List<PosUsbDevice> usbList,
  }) async {
    switch (connectionType) {
      case PosThermalConnectionType.sunmi:
        if (!await PosPrinterTransport.isSunmiDevice()) return false;
        try {
          return await PosPrinterTransport.ensureSunmiBound();
        } catch (_) {
          return true;
        }
      case PosThermalConnectionType.usb:
        if (usbList.isEmpty) return false;
        final name = (usbDeviceName ?? '').trim();
        if (name.isEmpty) {
          return usbList.any((d) => d.hasPermission) || usbList.length == 1;
        }
        final resolved = await PosUsbPrinter.resolveSaved(
          stableId: RegExp(r'^\d+:\d+:').hasMatch(name) ? name : null,
          deviceName: RegExp(r'^\d+:\d+:').hasMatch(name) ? null : name,
        );
        if (resolved != null) return true;
        return usbList.any((d) =>
            d.stableId == name ||
            d.deviceName == name ||
            d.displayName.contains(name));
      case PosThermalConnectionType.lan:
        final host = (lanHost ?? '').trim();
        if (host.isEmpty) return false;
        try {
          final socket = await Socket.connect(
            host,
            lanPort <= 0 ? 9100 : lanPort,
            timeout: const Duration(milliseconds: 800),
          );
          await socket.close();
          return true;
        } catch (_) {
          return false;
        }
      case PosThermalConnectionType.bluetooth:
        return (bluetoothAddress ?? '').trim().isNotEmpty;
    }
  }

  static String labelVi(PosPrinterLinkStatus s) => switch (s) {
        PosPrinterLinkStatus.ready => 'Sáºµn sÃ ng',
        PosPrinterLinkStatus.lost => 'Máº¥t káº¿t ná»‘i',
        PosPrinterLinkStatus.unknown => 'ChÆ°a kiá»ƒm',
      };
}
