import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Lắng nghe máy quét mã cứng Sunmi (broadcast `ACTION_DATA_CODE_RECEIVED`).
///
/// Nhanh hơn camera trên V2s — cần bật chế độ Broadcast / Keyboard trong
/// Cài đặt → Máy quét mã vạch của thiết bị.
class PosSunmiScanner {
  PosSunmiScanner._();

  static const _event = EventChannel('com.sboxhrm/sunmi_scanner');
  static Stream<String>? _cached;

  static Stream<String> get barcodes {
    if (kIsWeb) return const Stream.empty();
    return _cached ??= _event
        .receiveBroadcastStream()
        .map((e) => e?.toString().trim() ?? '')
        .where((s) => s.isNotEmpty)
        .asBroadcastStream();
  }
}
