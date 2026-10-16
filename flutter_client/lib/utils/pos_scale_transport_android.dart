import 'dart:async';

import 'package:flutter/services.dart';

import 'pos_scale_reader.dart';
import 'pos_scale_transport.dart';

/// Cân qua cáp USB-Serial trên Android (UsbSerialScale.kt — CH340, PL2303, CP210x, FTDI, CDC-ACM).
/// Lần đầu mở, Android hỏi «Cho phép SBOX dùng thiết bị USB?».
class PosScaleAndroidUsbTransport implements PosScaleTransport {
  static const _ch = MethodChannel('com.sboxhrm/usb_scale');
  static const _events = EventChannel('com.sboxhrm/usb_scale_data');
  StreamSubscription<dynamic>? _sub;

  @override
  bool get supported => true;
  @override
  bool get isWeb => false;
  @override
  String get kind => 'android';
  @override
  String get unsupportedReason => 'Máy này không hỗ trợ USB host — dùng mã vạch cân.';

  /// «vid:pid · chip · tên» — phần trước « · » là khóa mở cân.
  @override
  Future<List<String>> listPorts() async {
    try {
      final list = await _ch.invokeListMethod<Map<dynamic, dynamic>>('listPorts') ?? const [];
      return [for (final m in list) '${m['name'] ?? m['key']}'];
    } catch (_) {
      return const [];
    }
  }

  @override
  Future<({int? vendorId, int? productId})?> requestPort() async => null;

  @override
  Future<void> open(PosScaleDeviceSettings s, void Function(List<int> bytes) onData, void Function(String error) onError) async {
    await close();
    // Nghe trước khi mở để không lỡ khung đầu.
    _sub = _events.receiveBroadcastStream().listen((e) {
      if (e is Uint8List) {
        onData(e);
      } else if (e is Map && e['error'] != null) {
        onError('${e['error']}');
      }
    }, onError: (Object e) => onError('$e'));
    try {
      await _ch.invokeMethod<bool>('open', {
        'key': s.port.split(' · ').first.trim(),
        'baud': s.baudRate,
        'dataBits': s.dataBits,
        'parity': s.parity,
        'stopBits': s.stopBits,
      });
    } on PlatformException catch (e) {
      await close();
      throw Exception(e.message ?? 'Không mở được cân USB');
    }
  }

  @override
  Future<void> write(List<int> bytes) async {
    try {
      await _ch.invokeMethod<bool>('write', {'bytes': Uint8List.fromList(bytes)});
    } catch (_) {}
  }

  @override
  Future<void> close() async {
    await _sub?.cancel();
    _sub = null;
    try {
      await _ch.invokeMethod<bool>('close');
    } catch (_) {}
  }
}
