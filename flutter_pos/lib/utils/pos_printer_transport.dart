import 'dart:io' show Platform, Socket;

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';
import 'package:sbox_pos/shims/sunmi_api_shim.dart';

import 'pos_thermal_printer_settings.dart';
import 'pos_printer_peripheral.dart';

/// Gửi byte thô tới máy in qua Bluetooth / LAN / Sunmi.
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

  /// Ép cổng Sunmi nội bộ khi chạy trên thiết bị Sunmi.
  static Future<PosThermalPrinterSettings> prepareLocalSettings(
    PosThermalPrinterSettings settings,
  ) async {
    if (await isSunmiDevice()) {
      return settings.copyWith(
        connectionType: PosThermalConnectionType.sunmi,
        printerBrand: PosThermalPrinterBrand.sunmi,
      );
    }
    return settings;
  }

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
        // USB OTG ESC/POS chưa có driver — chỉ hợp lệ trên Sunmi (máy in nội bộ).
        // Không giả gửi LAN khi thiếu IP (tránh "in lỗi font" do không in được).
        if (await isSunmiDevice()) {
          return _sendSunmi(bytes, sunmiFeedLines);
        }
        final host = lanHost?.trim();
        if (host != null && host.isNotEmpty) {
          debugPrint(
            'USB print: không có OTG — chuyển LAN $host:$lanPort',
          );
          return _sendLan(lanHost, lanPort, bytes);
        }
        debugPrint(
          'USB print failed: chưa hỗ trợ USB OTG. Dùng Bluetooth, LAN hoặc Sunmi.',
        );
        return false;
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

  /// Bỏ lệnh cắt GS V + feed thừa cuối payload — tránh giấy trắng dài khi
  /// Sunmi còn lineWrap/cutPaper sau printEscPos.
  static List<int> stripTrailingCut(List<int> bytes) {
    final out = List<int>.from(bytes);
    var guard = 0;
    while (out.length >= 2 && guard++ < 64) {
      final n = out.length;
      // GS V m [n] — cắt
      if (n >= 3 && out[n - 3] == 0x1D && out[n - 2] == 0x56) {
        out.removeRange(n - 3, n);
        continue;
      }
      if (n >= 4 && out[n - 4] == 0x1D && out[n - 3] == 0x56) {
        out.removeRange(n - 4, n);
        continue;
      }
      // ESC d n — feed n dòng
      if (n >= 3 && out[n - 3] == 0x1B && out[n - 2] == 0x64) {
        out.removeRange(n - 3, n);
        continue;
      }
      // LF / CR thừa
      if (out[n - 1] == 0x0A || out[n - 1] == 0x0D) {
        out.removeLast();
        continue;
      }
      break;
    }
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
      'cover_open',
      'coveropen',
      'lid_open',
      'error',
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

      // sunmi_printer_plus ≥4.x: printRawData/bindingPrinter là no-op.
      // Phải dùng printEscPos. Strip GS V — cắt bằng cutPaper sau khi đẩy giấy.
      final payload = stripTrailingCut(bytes);
      final result = await SunmiPrinter.printEscPos(payload);
      debugPrint('Sunmi printEscPos result: $result');
      if (!sunmiEscPosResultOk(result)) {
        debugPrint('Sunmi printEscPos rejected: $result');
        return false;
      }

      // ESC/POS đã có nội dung — chỉ đẩy nhẹ để xé (không +3 dòng trống như trước).
      // Native Sunmi tự feed trong PosSunmiNativePrint; đường này chỉ fallback.
      final feed = feedLines.clamp(0, 6);
      if (feed > 0) {
        await SunmiPrinter.lineWrap(feed);
      }
      try {
        await SunmiPrinter.cutPaper();
      } catch (e) {
        debugPrint('Sunmi cutPaper: $e');
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
