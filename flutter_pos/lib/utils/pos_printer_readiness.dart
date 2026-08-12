import 'dart:io' show Socket;

import 'package:flutter/foundation.dart';

import 'pos_local_printers_store.dart';
import 'pos_printer_transport.dart';
import 'pos_thermal_printer_settings.dart';
import 'pos_usb_printer.dart';

/// Trạng thái kết nối máy in trên thiết bị hiện tại.
enum PosPrinterLinkStatus {
  /// USB gắn / Sunmi OK / LAN mở được / BT có địa chỉ.
  ready,
  /// Đã cấu hình nhưng không thấy cổng / không ping được.
  lost,
  /// Máy tắt trong app, hoặc chưa đủ thông tin để kiểm.
  unknown,
}

/// Quét cổng nội bộ (USB/LAN/BT/Sunmi) — dùng chung màn Agent + Máy in nội bộ.
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

  static String _normUsbRef(String? raw) => (raw ?? '').trim().toLowerCase();

  /// Cùng logic Online (exclusive) — dùng khi in để không lệch trạng thái UI.
  static Future<PosUsbDevice?> resolveUsbForPrint(String? savedRaw) async {
    final raw = (savedRaw ?? '').trim();
    if (raw.isEmpty || kIsWeb) return null;
    final list = await listUsbDevices();
    if (list.isEmpty) return null;

    final locals = await PosLocalPrintersStore.instance.loadAll();
    final usbProfiles = locals
        .where((p) =>
            p.enabled &&
            p.connectionType == PosThermalConnectionType.usb &&
            (p.usbDeviceName ?? '').trim().isNotEmpty)
        .map((p) => (id: p.id, savedRaw: p.usbDeviceName))
        .toList();

    final want = _normUsbRef(raw);
    final hasProfile =
        usbProfiles.any((p) => _normUsbRef(p.savedRaw) == want);
    final profiles = hasProfile
        ? usbProfiles
        : <({String id, String? savedRaw})>[
            ...usbProfiles,
            (id: '__print__', savedRaw: raw),
          ];

    final matched = PosUsbPrinter.matchProfilesExclusive(profiles, list);
    String? profileId;
    PosUsbDevice? device;
    for (final p in profiles) {
      if (_normUsbRef(p.savedRaw) != want) continue;
      device = matched[p.id];
      profileId = p.id == '__print__' ? null : p.id;
      break;
    }
    if (device == null) return null;

    // Cập nhật deviceName sau rematch (cắm lại cổng) — lần in sau khớp ngay.
    if (profileId != null) {
      final p = locals.where((x) => x.id == profileId).firstOrNull;
      if (p != null) {
        final nextRef = device.savedRef;
        if (nextRef != (p.usbDeviceName ?? '').trim()) {
          try {
            await PosLocalPrintersStore.instance.upsert(
              p.copyWith(usbDeviceName: nextRef),
              syncServer: false,
            );
          } catch (_) {}
        }
      }
    }
    return device;
  }

  static Future<PosPrinterLinkStatus> probeLocal(
    PosLocalPrinterProfile p, {
    List<PosUsbDevice>? usbList,
    PosUsbDevice? matchedUsb,
    bool useMatchedUsbOnly = false,
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
      matchedUsb: matchedUsb,
      useMatchedUsbOnly: useMatchedUsbOnly,
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
    PosUsbDevice? matchedUsb,
    bool useMatchedUsbOnly = false,
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
        final name = (usbDeviceName ?? '').trim();
        if (name.isEmpty) return false;
        if (usbList.isEmpty) return false;
        PosUsbDevice? matched;
        if (useMatchedUsbOnly) {
          matched = matchedUsb;
        } else if (matchedUsb != null) {
          matched = matchedUsb;
        } else {
          // Cùng exclusive matching với màn Online / lúc in.
          matched = await resolveUsbForPrint(name);
          matched ??= PosUsbPrinter.matchInList(usbList, name);
        }
        if (matched == null) return false;
        if (!matched.hasPermission) return false;
        return PosUsbPrinter.probeDevice(
          stableId: matched.stableId,
          deviceName: matched.deviceName,
          vendorId: matched.vendorId,
          productId: matched.productId,
          serialNumber: matched.serialNumber,
        );
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
        PosPrinterLinkStatus.ready => 'Sẵn sàng',
        PosPrinterLinkStatus.lost => 'Mất kết nối',
        PosPrinterLinkStatus.unknown => 'Chưa kiểm',
      };
}
