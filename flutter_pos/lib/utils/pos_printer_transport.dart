import 'dart:io' show Platform, Socket;

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';
import 'package:sbox_pos/shims/sunmi_api_shim.dart';

import 'pos_thermal_printer_settings.dart';
import 'pos_thermal_bitmap.dart';
import 'pos_printer_peripheral.dart';
import 'pos_usb_printer.dart';

/// Gửi byte thô tới máy in qua Bluetooth / LAN / USB / Sunmi.
class PosPrinterTransport {
  static const _btChunkSize = 512;
  static const _btChunkSizeLarge = 256;
  static const _btLargePayloadBytes = 8 * 1024;
  static const _btChunkDelay = Duration(milliseconds: 40);
  static const _btChunkDelayLarge = Duration(milliseconds: 70);
  static const _btSettleDelay = Duration(milliseconds: 600);

  static Future<bool> isSunmiDevice() async {
    if (kIsWeb || !Platform.isAndroid) return false;
    try {
      final info = await DeviceInfoPlugin().androidInfo;
      final brand = info.brand.toLowerCase();
      final man = info.manufacturer.toLowerCase();
      if (brand.contains('sunmi') || man.contains('sunmi')) return true;
    } catch (_) {}
    // Fallback: SDK đã bind được máy in nội bộ (OEM rebrand).
    try {
      final status = await SunmiConfig.getStatus();
      return status != null && status.trim().isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  /// Handheld (V2s/V2/V1…) in trong máy — không có dao cắt, chỉ xé tay.
  static Future<bool> sunmiHasAutoCutter() async {
    if (kIsWeb || !Platform.isAndroid) return false;
    try {
      final info = await DeviceInfoPlugin().androidInfo;
      final m =
          '${info.model} ${info.device} ${info.product}'.toLowerCase();
      if (m.contains('v2s') ||
          m.contains('v2_') ||
          m.contains('v1s') ||
          RegExp(r'\bv1\b').hasMatch(m) ||
          m.contains('p2mini') ||
          m.contains('l2s') ||
          m.contains('l2k')) {
        return false;
      }
      if (m.contains('t1') ||
          m.contains('t2') ||
          m.contains('nt3') ||
          m.contains('d2')) {
        return true;
      }
    } catch (_) {}
    return false;
  }

  /// Đẩy giấy đúng số dòng đã chỉnh. 0 = không đẩy thêm.
  /// Máy không dao cắt: không gọi cutPaper (trên V2s lệnh cắt nuốt feed).
  static Future<void> finishSunmiSlip({required int feedLines}) async {
    final n = feedLines.clamp(0, 40);
    final hasCutter = await sunmiHasAutoCutter();
    // V2s (không dao): KHÔNG đẩy giấy ở đây. Lệnh feed gửi rời sau raster bị
    // firmware nuốt ⇒ giấy kẹt đầu in. Feed được nhồi hàng trắng vào GS v 0
    // (xem _printImageLines / _sendSunmi). Chỉ máy có dao mới đẩy + cắt tại đây.
    if (!hasCutter) return;
    if (n > 0) {
      try {
        await SunmiPrinter.lineWrap(n);
      } catch (e) {
        debugPrint('Sunmi lineWrap: $e');
      }
    }
    try {
      await SunmiPrinter.cutPaper();
    } catch (e) {
      debugPrint('Sunmi cutPaper: $e');
    }
  }

  /// Feed n dòng: nhồi hàng trắng vào GS v 0 (LF sau raster bị V2s bỏ qua).
  static List<int> _escFeedBytes(List<int> payload, int n, {int paperDots = 384}) {
    return PosThermalBitmapEncoder.appendHandheldFeed(
      payload,
      n,
      paperDots: paperDots,
    );
  }

  /// Chuẩn hóa brand Sunmi khi cổng đã chọn là Sunmi.
  /// Không ghi đè USB / Bluetooth / LAN đã cấu hình trên thiết bị Sunmi.
  static Future<PosThermalPrinterSettings> prepareLocalSettings(
    PosThermalPrinterSettings settings,
  ) async {
    if (settings.connectionType == PosThermalConnectionType.sunmi) {
      return settings.copyWith(printerBrand: PosThermalPrinterBrand.sunmi);
    }
    return settings;
  }

  static Future<bool> send({
    required PosThermalConnectionType connectionType,
    String? bluetoothAddress,
    String? lanHost,
    int lanPort = 9100,
    String? usbDeviceName,
    String? usbStableId,
    int? usbVendorId,
    int? usbProductId,
    String? usbSerial,
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
        return _sendUsb(
          bytes: bytes,
          usbDeviceName: usbDeviceName,
          usbStableId: usbStableId,
          usbVendorId: usbVendorId,
          usbProductId: usbProductId,
          usbSerial: usbSerial,
          sunmiFeedLines: sunmiFeedLines,
        );
    }
  }

  /// USB OTG: mở→ghi→đóng theo máy (stableId). Nhiều máy USB không dùng chung 1 kết nối.
  static Future<bool> _sendUsb({
    required List<int> bytes,
    String? usbDeviceName,
    String? usbStableId,
    int? usbVendorId,
    int? usbProductId,
    String? usbSerial,
    int sunmiFeedLines = 0,
  }) async {
    final name = (usbDeviceName ?? '').trim();
    var stable = (usbStableId ?? '').trim();
    if (stable.isEmpty && RegExp(r'^\d+:\d+:').hasMatch(name) && !name.contains('|')) {
      stable = name;
    }

    // Ưu tiên savedRaw (stableId|deviceName) — tránh lấy nhầm máy cùng VID/PID.
    final resolved = await PosUsbPrinter.resolveSaved(
      savedRaw: name.isNotEmpty ? name : null,
      stableId: stable.isEmpty ? null : stable,
      deviceName: name.contains('|')
          ? null
          : (name.isEmpty || stable == name ? null : name),
      vendorId: usbVendorId,
      productId: usbProductId,
      serialNumber: usbSerial,
    );

    if (resolved != null) {
      if (!resolved.hasPermission) {
        final granted = await PosUsbPrinter.requestPermission(resolved);
        if (!granted) {
          debugPrint('USB print: user denied permission ${resolved.displayName}');
          return false;
        }
      }
      final ok = await PosUsbPrinter.writeBytes(
        bytes: bytes,
        stableId: resolved.stableId,
        deviceName: resolved.deviceName,
        vendorId: resolved.vendorId,
        productId: resolved.productId,
        serialNumber: resolved.serialNumber,
      ).timeout(
        const Duration(seconds: 25),
        onTimeout: () {
          debugPrint('USB print timeout 25s on ${resolved.displayName}');
          return false;
        },
      );
      if (ok) return true;
      debugPrint('USB print failed on ${resolved.displayName}');
      return false;
    }

    final list = await PosUsbPrinter.listDevices();
    if (list.isEmpty) {
      debugPrint('USB print failed: không có thiết bị USB');
      return false;
    }
    // Đã cấu hình máy cụ thể nhưng không thấy → fail (không gửi nhầm máy còn lại).
    final hadTarget = stable.isNotEmpty ||
        name.isNotEmpty ||
        usbVendorId != null ||
        usbProductId != null;
    if (hadTarget) {
      debugPrint(
        'USB print failed: không tìm thấy máy đã cấu hình '
        '(stable=$stable name=$name) — list=${list.length}',
      );
      return false;
    }
    if (list.length == 1) {
      final only = list.first;
      if (!only.hasPermission) {
        final granted = await PosUsbPrinter.requestPermission(only);
        if (!granted) return false;
      }
      return PosUsbPrinter.writeBytes(
        bytes: bytes,
        stableId: only.stableId,
        deviceName: only.deviceName,
        vendorId: only.vendorId,
        productId: only.productId,
        serialNumber: only.serialNumber,
      ).timeout(
        const Duration(seconds: 25),
        onTimeout: () {
          debugPrint('USB print timeout 25s (single device)');
          return false;
        },
      );
    }
    debugPrint(
      'USB print failed: có ${list.length} máy USB — chọn cổng trong Thiết lập máy in',
    );
    return false;
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

  /// Bỏ lệnh cắt GS V + feed thừa cuối payload — tránh giấy trắng dài khi
  /// Sunmi còn lineWrap/cutPaper sau printEscPos.
  /// Beep (ESC B) / mở két (ESC p) đứng sau cắt nên phải bỏ qua, không break.
  static List<int> stripTrailingCut(List<int> bytes) {
    final out = List<int>.from(bytes);
    final kept = <int>[];
    var guard = 0;
    while (out.length >= 2 && guard++ < 96) {
      final n = out.length;
      if (n >= 3 && out[n - 3] == 0x1D && out[n - 2] == 0x56) {
        out.removeRange(n - 3, n);
        continue;
      }
      if (n >= 4 && out[n - 4] == 0x1D && out[n - 3] == 0x56) {
        out.removeRange(n - 4, n);
        continue;
      }
      if (n >= 3 && out[n - 3] == 0x1B && out[n - 2] == 0x64) {
        out.removeRange(n - 3, n);
        continue;
      }
      if (n >= 4 && out[n - 4] == 0x1B && out[n - 3] == 0x42) {
        kept.insertAll(0, out.sublist(n - 4));
        out.removeRange(n - 4, n);
        continue;
      }
      if (n >= 5 && out[n - 5] == 0x1B && out[n - 4] == 0x70) {
        kept.insertAll(0, out.sublist(n - 5));
        out.removeRange(n - 5, n);
        continue;
      }
      if (out[n - 1] == 0x0A || out[n - 1] == 0x0D) {
        out.removeLast();
        continue;
      }
      break;
    }
    out.addAll(kept);
    return out;
  }

  static Future<bool> ensureSunmiBound() async {
    try {
      final ok = await SunmiPrinterPlus().rebindPrinter();
      if (ok) return true;
    } catch (e) {
      debugPrint('Sunmi rebindPrinter: $e');
    }
    try {
      final status = await SunmiConfig.getStatus();
      return sunmiStatusLooksOk(status);
    } catch (e) {
      debugPrint('Sunmi getStatus: $e');
      return false;
    }
  }

  /// `printEscPos` thường trả `"ok"`; null / fail / error → không tin.
  static bool sunmiEscPosResultOk(String? result) {
    if (result == null) return false;
    final s = result.trim().toLowerCase();
    if (s.isEmpty) return false;
    if (s.contains('fail') ||
        s.contains('error') ||
        s.contains('exception') ||
        s.contains('null')) {
      return false;
    }
    return true;
  }

  /// PrinterX status (READY / OUT_OF_PAPER / COVER_OPEN / …).
  static bool sunmiStatusLooksOk(String? status) {
    if (status == null) return false;
    final s = status.trim().toLowerCase();
    if (s.isEmpty || s == 'null') return false;
    const bad = [
      'out_of_paper',
      'outofpaper',
      'no_paper',
      'nopaper',
      'open_the_lid',
      'cover_open',
      'coveropen',
      'lid_open',
      'error',
      'exception',
      'abnormal',
      'offline',
      'no_printer',
      'noprinter',
      'overheat',
      'overheating',
      'unknown',
    ];
    for (final b in bad) {
      if (s.contains(b)) return false;
    }
    return true;
  }

  /// Đọc trạng thái sau khi gửi lệnh in (hết giấy / nắp mở → fail).
  static Future<bool> verifySunmiAfterPrint() async {
    try {
      final status = await SunmiConfig.getStatus();
      debugPrint('Sunmi post-print status: $status');
      return sunmiStatusLooksOk(status);
    } catch (e) {
      debugPrint('Sunmi post-print getStatus: $e');
      return false;
    }
  }

  static Future<bool> _sendSunmi(List<int> bytes, int feedLines) async {
    if (!await isSunmiDevice()) {
      debugPrint('Sunmi print skipped: not a Sunmi device');
      return false;
    }
    try {
      final bound = await ensureSunmiBound();
      if (!bound) {
        debugPrint('Sunmi print failed: printer not bound');
        return false;
      }

      // Shim map printEscPos → printRawData (sunmi_printer_plus 2.x AIDL).
      // Strip GS V — cắt bằng cutPaper sau khi đẩy giấy.
      final payload = stripTrailingCut(bytes);
      final feed = feedLines.clamp(0, 40);
      final hasCutter = await sunmiHasAutoCutter();

      // Máy KHÔNG dao (V2s): nhồi hàng trắng vào CÙNG GS v 0. LF / lineWrap
      // gửi rời (và cả LF nối sau raster) bị firmware nuốt ⇒ số dòng không đổi.
      final toSend = (!hasCutter && feed > 0)
          ? _escFeedBytes(payload, feed)
          : payload;
      final result = await SunmiPrinter.printEscPos(toSend);
      debugPrint('Sunmi printEscPos result: $result');
      if (!sunmiEscPosResultOk(result)) {
        debugPrint('Sunmi printEscPos rejected: $result');
        return false;
      }

      // Máy có dao: đẩy giấy + cắt (feed rời chạy ổn trên dòng máy có dao).
      // Máy không dao: feed đã nằm trong payload ở trên, không gọi lại.
      if (hasCutter) {
        await finishSunmiSlip(feedLines: feed);
      }
      // Bổ sung API mở két nếu payload có ESC p (strip không xóa lệnh này).
      final drawerSig = PosPrinterPeripheral.openDrawerEscPos();
      final tail = bytes.length > 24 ? bytes.sublist(bytes.length - 24) : bytes;
      var openDrawer = false;
      for (var i = 0; i <= tail.length - drawerSig.length; i++) {
        var match = true;
        for (var j = 0; j < drawerSig.length; j++) {
          if (tail[i + j] != drawerSig[j]) {
            match = false;
            break;
          }
        }
        if (match) {
          openDrawer = true;
          break;
        }
      }
      if (openDrawer) {
        try {
          await SunmiDrawer.openDrawer();
        } catch (e) {
          debugPrint('SunmiDrawer after ESC print: $e');
        }
      }
      return verifySunmiAfterPrint();
    } catch (e) {
      debugPrint('Sunmi print failed: $e');
      return false;
    }
  }

  static Future<bool> _sendBluetooth(String? addr, List<int> bytes) async {
    final address = addr?.trim();
    if (address == null || address.isEmpty) return false;
    var ok = await _sendBluetoothOnce(address, bytes);
    if (ok) return true;
    // Một lần reconnect — giảm mất bill do drop BT tạm thời.
    debugPrint('Bluetooth print retry after reconnect…');
    try {
      await PrintBluetoothThermal.disconnect;
    } catch (_) {}
    await Future<void>.delayed(const Duration(milliseconds: 400));
    return _sendBluetoothOnce(address, bytes);
  }

  static Future<bool> _sendBluetoothOnce(String address, List<int> bytes) async {
    try {
      final connected =
          await PrintBluetoothThermal.connect(macPrinterAddress: address);
      if (connected != true) return false;

      // Gửi theo chunk — ghi một cục lớn (ảnh GS v 0) dễ tràn buffer BT,
      // lần 2 thường in font/ký tự rác. Payload lớn → chunk nhỏ hơn + delay dài hơn.
      final large = bytes.length >= _btLargePayloadBytes;
      final chunk = large ? _btChunkSizeLarge : _btChunkSize;
      final delay = large ? _btChunkDelayLarge : _btChunkDelay;
      for (var i = 0; i < bytes.length; i += chunk) {
        final end = i + chunk < bytes.length ? i + chunk : bytes.length;
        final ok =
            await PrintBluetoothThermal.writeBytes(bytes.sublist(i, end));
        if (ok != true) {
          try {
            await PrintBluetoothThermal.disconnect;
          } catch (_) {}
          return false;
        }
        if (end < bytes.length) {
          await Future<void>.delayed(delay);
        }
      }

      await Future<void>.delayed(_btSettleDelay);
      try {
        await PrintBluetoothThermal.disconnect;
      } catch (_) {}
      return true;
    } catch (e) {
      debugPrint('Bluetooth print failed: $e');
      try {
        await PrintBluetoothThermal.disconnect;
      } catch (_) {}
      return false;
    }
  }
}
