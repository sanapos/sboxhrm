import 'dart:async';
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

  /// Lưu cả stableId + deviceName — phân biệt nhiều máy cùng VID/PID trên Sunmi.
  String get savedRef => '$stableId|$deviceName';
}

/// Tham chiếu máy USB đã lưu (`stableId` hoặc `stableId|deviceName`).
class PosUsbSavedRef {
  const PosUsbSavedRef({this.stableId, this.deviceName});

  final String? stableId;
  final String? deviceName;

  bool get isEmpty =>
      (stableId == null || stableId!.isEmpty) &&
      (deviceName == null || deviceName!.isEmpty);

  static PosUsbSavedRef parse(String? raw) {
    final s = (raw ?? '').trim();
    if (s.isEmpty) return const PosUsbSavedRef();
    if (s.contains('|')) {
      final i = s.indexOf('|');
      final left = s.substring(0, i).trim();
      final right = s.substring(i + 1).trim();
      return PosUsbSavedRef(
        stableId: left.isEmpty ? null : left,
        deviceName: right.isEmpty ? null : right,
      );
    }
    if (RegExp(r'^\d+:\d+:').hasMatch(s)) {
      return PosUsbSavedRef(stableId: s);
    }
    // Path kiểu /dev/bus/usb/... hoặc tên cũ.
    return PosUsbSavedRef(deviceName: s);
  }
}

/// Bridge USB ESC/POS — liệt kê cổng, xin quyền, ghi bytes (mỗi máy khóa riêng).
class PosUsbPrinter {
  PosUsbPrinter._();
  static const _ch = MethodChannel('com.sboxhrm/usb_printer');
  static const _events = EventChannel('com.sboxhrm/usb_printer_events');

  static bool get isSupported => !kIsWeb;

  static Stream<Map<String, dynamic>>? _eventStream;

  /// attached / detached — làm mới online/offline từng máy khi nhiều USB.
  static Stream<Map<String, dynamic>> get deviceEvents {
    _eventStream ??= _events
        .receiveBroadcastStream()
        .map((e) => Map<String, dynamic>.from(e as Map))
        .handleError((_) {});
    return _eventStream!;
  }

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

  /// Open+claim (không ghi lệnh) — xác nhận đúng cổng còn mở được.
  static Future<bool> probeDevice({
    String? stableId,
    String? deviceName,
    int? vendorId,
    int? productId,
    String? serialNumber,
  }) async {
    if (!isSupported) return false;
    try {
      final ok = await _ch.invokeMethod<bool>('probeDevice', {
        if (stableId != null && stableId.isNotEmpty) 'stableId': stableId,
        if (deviceName != null && deviceName.isNotEmpty) 'deviceName': deviceName,
        if (vendorId != null) 'vendorId': vendorId,
        if (productId != null) 'productId': productId,
        if (serialNumber != null && serialNumber.isNotEmpty)
          'serialNumber': serialNumber,
      }).timeout(const Duration(seconds: 2), onTimeout: () => false);
      return ok == true;
    } catch (e) {
      debugPrint('PosUsbPrinter.probeDevice: $e');
      return false;
    }
  }

  /// Khớp đúng 1 máy trong list — không lấy nhầm máy cùng VID/PID còn lại trên bus.
  ///
  /// Không bao giờ gán «chỉ còn 1 máy VID/PID» cho profile — lỗi 1 máy bật → 2 profile Online.
  static PosUsbDevice? matchInList(
    List<PosUsbDevice> list,
    String? savedRaw,
  ) {
    if (list.isEmpty) return null;
    final ref = PosUsbSavedRef.parse(savedRaw);
    if (ref.isEmpty) return null;

    final dn = (ref.deviceName ?? '').trim();
    if (dn.isNotEmpty) {
      final byName = list.where((d) => d.deviceName == dn).firstOrNull;
      if (byName != null) return byName;
    }

    final sid = (ref.stableId ?? '').trim();
    if (sid.isEmpty) return null;

    final parts = sid.split(':');
    if (parts.length < 2) return null;
    final vid = int.tryParse(parts[0]);
    final pid = int.tryParse(parts[1]);
    if (vid == null || pid == null) return null;
    final sn = parts.length > 2 ? parts.sublist(2).join(':') : '';

    // Chỉ nhận stableId khi SN đủ để phân biệt (hoặc đúng 1 thiết bị trùng full stableId
    // và SN không rỗng). stableId dạng vid:pid: (SN trống) không đủ khi multi-USB.
    if (sn.isEmpty) return null;

    final bySn = list
        .where((d) =>
            d.vendorId == vid &&
            d.productId == pid &&
            (d.serialNumber ?? '') == sn)
        .toList();
    if (bySn.length == 1) return bySn.first;
    return null;
  }

  /// Gán cổng USB cho nhiều profile — mỗi deviceName chỉ thuộc 1 máy.
  /// Tránh: tắt 1 máy / còn 1 máy → cả 2 profile cùng báo Online.
  static Map<String, PosUsbDevice?> matchProfilesExclusive(
    List<({String id, String? savedRaw})> profiles,
    List<PosUsbDevice> list,
  ) {
    final out = <String, PosUsbDevice?>{
      for (final p in profiles) p.id: null,
    };
    if (list.isEmpty || profiles.isEmpty) return out;

    final used = <String>{};

    // Pass 1: đúng deviceName đã lưu (ổn định khi máy còn cắm).
    for (final p in profiles) {
      final ref = PosUsbSavedRef.parse(p.savedRaw);
      final dn = (ref.deviceName ?? '').trim();
      if (dn.isEmpty) continue;
      final hit = list.where((d) => d.deviceName == dn).firstOrNull;
      if (hit == null || used.contains(hit.deviceName)) continue;
      out[p.id] = hit;
      used.add(hit.deviceName);
    }

    // Pass 2: đúng serial (phân biệt cùng model).
    for (final p in profiles) {
      if (out[p.id] != null) continue;
      final ref = PosUsbSavedRef.parse(p.savedRaw);
      final sid = (ref.stableId ?? '').trim();
      if (sid.isEmpty) continue;
      final parts = sid.split(':');
      if (parts.length < 2) continue;
      final vid = int.tryParse(parts[0]);
      final pid = int.tryParse(parts[1]);
      final sn = parts.length > 2 ? parts.sublist(2).join(':') : '';
      if (vid == null || pid == null || sn.isEmpty) continue;
      final hits = list
          .where((d) =>
              !used.contains(d.deviceName) &&
              d.vendorId == vid &&
              d.productId == pid &&
              (d.serialNumber ?? '') == sn)
          .toList();
      if (hits.length != 1) continue;
      out[p.id] = hits.first;
      used.add(hits.first.deviceName);
    }

    // Pass 3: chỉ khi còn đúng 1 profile chưa gán + 1 device cùng VID/PID chưa dùng
    // (1 máy cấu hình / cắm lại). Không gán khi ≥2 profile tranh 1 device.
    final pending = profiles.where((p) => out[p.id] == null).toList();
    final byVp = <String, List<({String id, String? savedRaw})>>{};
    for (final p in pending) {
      final ref = PosUsbSavedRef.parse(p.savedRaw);
      final sid = (ref.stableId ?? '').trim();
      final parts = sid.split(':');
      if (parts.length < 2) continue;
      final vid = int.tryParse(parts[0]);
      final pid = int.tryParse(parts[1]);
      if (vid == null || pid == null) continue;
      final key = '$vid:$pid';
      (byVp[key] ??= []).add(p);
    }
    for (final entry in byVp.entries) {
      final vpParts = entry.key.split(':');
      final vid = int.parse(vpParts[0]);
      final pid = int.parse(vpParts[1]);
      final unused = list
          .where((d) =>
              !used.contains(d.deviceName) &&
              d.vendorId == vid &&
              d.productId == pid)
          .toList();
      if (entry.value.length == 1 && unused.length == 1) {
        final p = entry.value.first;
        out[p.id] = unused.first;
        used.add(unused.first.deviceName);
      }
    }

    return out;
  }

  /// Tìm lại máy đã lưu (VID/PID/serial + deviceName) trong danh sách hiện tại.
  static Future<PosUsbDevice?> resolveSaved({
    String? stableId,
    String? deviceName,
    int? vendorId,
    int? productId,
    String? serialNumber,
    String? savedRaw,
  }) async {
    final list = await listDevices();
    if (list.isEmpty) return null;

    if ((savedRaw ?? '').trim().isNotEmpty) {
      return matchInList(list, savedRaw);
    }

    final composite = [
      if ((stableId ?? '').trim().isNotEmpty) stableId!.trim(),
      if ((deviceName ?? '').trim().isNotEmpty) deviceName!.trim(),
    ].join('|');
    if (composite.isNotEmpty) {
      final hit = matchInList(
        list,
        composite.contains('|') ? composite : (stableId ?? deviceName),
      );
      if (hit != null) return hit;
    }

    // Chỉ khớp VID/PID khi có serial — không đoán khi multi-USB cùng model.
    if (vendorId != null && productId != null) {
      final sn = (serialNumber ?? '').trim();
      if (sn.isEmpty) return null;
      final hits = list
          .where((d) =>
              d.vendorId == vendorId &&
              d.productId == productId &&
              (d.serialNumber ?? '') == sn)
          .toList();
      return hits.length == 1 ? hits.first : null;
    }
    return null;
  }
}
