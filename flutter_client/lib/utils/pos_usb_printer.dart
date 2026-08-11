import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Một cổng / thiết bị USB máy in (Android UsbManager).
class PosUsbDevice {
  const PosUsbDevice({
    required this.deviceName,
    required this.vendorId,
    required this.productId,
    required this.deviceId,
    required this.stableId,
    required this.displayName,
    this.serialNumber,
    this.productName,
    this.manufacturerName,
    this.deviceClass,
    this.hasPermission = false,
  });

  final String deviceName;
  final int vendorId;
  final int productId;
  final int deviceId;
  final String stableId;
  final String displayName;
  final String? serialNumber;
  final String? productName;
  final String? manufacturerName;
  final int? deviceClass;
  final bool hasPermission;

  factory PosUsbDevice.fromMap(Map<dynamic, dynamic> m) {
    return PosUsbDevice(
      deviceName: m['deviceName']?.toString() ?? '',
      vendorId: (m['vendorId'] as num?)?.toInt() ?? 0,
      productId: (m['productId'] as num?)?.toInt() ?? 0,
      deviceId: (m['deviceId'] as num?)?.toInt() ?? 0,
      stableId: m['stableId']?.toString() ?? '',
      displayName: m['displayName']?.toString() ?? 'USB',
      serialNumber: m['serialNumber']?.toString(),
      productName: m['productName']?.toString(),
      manufacturerName: m['manufacturerName']?.toString(),
      deviceClass: (m['deviceClass'] as num?)?.toInt(),
      hasPermission: m['hasPermission'] == true,
    );
  }

  Map<String, dynamic> toIdentityArgs() => {
        'stableId': stableId,
        'deviceName': deviceName,
        'vendorId': vendorId,
        'productId': productId,
        if (serialNumber != null && serialNumber!.isNotEmpty)
          'serialNumber': serialNumber,
      };
}

/// Bridge USB ESC/POS — liệt kê cổng, xin quyền, ghi bytes (mỗi máy khóa riêng).
class PosUsbPrinter {
  PosUsbPrinter._();
  static const _ch = MethodChannel('com.sboxhrm/usb_printer');

  static bool get isSupported => !kIsWeb;

  static Future<List<PosUsbDevice>> listDevices() async {
    if (!isSupported) return const [];
    try {
      final raw = await _ch.invokeMethod<List<dynamic>>('listDevices');
      if (raw == null) return const [];
      return raw
          .whereType<Map>()
          .map((e) => PosUsbDevice.fromMap(e))
          .where((d) => d.deviceName.isNotEmpty)
          .toList();
    } catch (e) {
      debugPrint('PosUsbPrinter.listDevices: $e');
      return const [];
    }
  }

  static Future<bool> requestPermission(PosUsbDevice device) async {
    if (!isSupported) return false;
    try {
      final ok = await _ch.invokeMethod<bool>(
        'requestPermission',
        device.toIdentityArgs(),
      );
      return ok == true;
    } catch (e) {
      debugPrint('PosUsbPrinter.requestPermission: $e');
      return false;
    }
  }

  /// Ghi ESC/POS tới máy đã chọn. Mở→ghi→đóng theo stableId (không đá máy khác).
  static Future<bool> writeBytes({
    required List<int> bytes,
    String? stableId,
    String? deviceName,
    int? vendorId,
    int? productId,
    String? serialNumber,
  }) async {
    if (!isSupported || bytes.isEmpty) return false;
    try {
      final ok = await _ch.invokeMethod<bool>('writeBytes', {
        'bytes': Uint8List.fromList(bytes),
        if (stableId != null && stableId.isNotEmpty) 'stableId': stableId,
        if (deviceName != null && deviceName.isNotEmpty) 'deviceName': deviceName,
        if (vendorId != null) 'vendorId': vendorId,
        if (productId != null) 'productId': productId,
        if (serialNumber != null && serialNumber.isNotEmpty)
          'serialNumber': serialNumber,
      });
      return ok == true;
    } catch (e) {
      debugPrint('PosUsbPrinter.writeBytes: $e');
      return false;
    }
  }

  /// Tìm lại máy đã lưu (VID/PID/serial) trong danh sách hiện tại.
  static Future<PosUsbDevice?> resolveSaved({
    String? stableId,
    String? deviceName,
    int? vendorId,
    int? productId,
    String? serialNumber,
  }) async {
    final list = await listDevices();
    if (list.isEmpty) return null;
    final sid = (stableId ?? '').trim();
    if (sid.isNotEmpty) {
      final hit = list.where((d) => d.stableId == sid).firstOrNull;
      if (hit != null) return hit;
      // Fallback: vid:pid khi serial đổi / chưa có quyền đọc SN
      final parts = sid.split(':');
      if (parts.length >= 2) {
        final vid = int.tryParse(parts[0]);
        final pid = int.tryParse(parts[1]);
        if (vid != null && pid != null) {
          final sn = parts.length > 2 ? parts.sublist(2).join(':') : '';
          final byVidPid = list.where((d) =>
              d.vendorId == vid &&
              d.productId == pid &&
              (sn.isEmpty || (d.serialNumber ?? '') == sn));
          if (byVidPid.isNotEmpty) return byVidPid.first;
        }
      }
    }
    final dn = (deviceName ?? '').trim();
    if (dn.isNotEmpty) {
      final hit = list.where((d) => d.deviceName == dn).firstOrNull;
      if (hit != null) return hit;
    }
    if (vendorId != null && productId != null) {
      final sn = (serialNumber ?? '').trim();
      final hits = list.where((d) =>
          d.vendorId == vendorId &&
          d.productId == productId &&
          (sn.isEmpty || (d.serialNumber ?? '') == sn));
      if (hits.isNotEmpty) return hits.first;
    }
    return null;
  }
}
