import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'pos_scanner_config.dart';

/// Lắng nghe máy quét mã cứng / máy kiểm kho gửi broadcast: Sunmi (`ACTION_DATA_CODE_RECEIVED`),
/// Urovo, Newland, iData, Chainway, Seuic và action tự cài ([PosScannerConfig]).
/// Một broadcast chứa nhiều mã (đầu đọc RFID gửi lô EPC) được tách thành từng mã.
///
/// Nhanh hơn camera trên V2s — cần bật chế độ Broadcast / Keyboard trong
/// Cài đặt → Máy quét mã vạch của thiết bị.
class PosSunmiScanner {
  PosSunmiScanner._();

  static const _event = EventChannel('com.sboxhrm/sunmi_scanner');
  static Stream<String>? _cached;

  static Stream<String> get barcodes {
    if (kIsWeb) return const Stream.empty();
    if (_cached == null) {
      // Nạp action / extra riêng của máy kiểm kho (Zebra, Honeywell, RFID…) trước khi nghe.
      unawaited(PosScannerConfig.apply());
    }
    return _cached ??= _event
        .receiveBroadcastStream()
        .map((e) => e?.toString().trim() ?? '')
        .where((s) => s.isNotEmpty)
        .asBroadcastStream();
  }
}
