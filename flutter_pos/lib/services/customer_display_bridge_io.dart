import 'dart:async';

import 'package:flutter/services.dart';

/// Android/iOS: MethodChannel + Activity/Presentation màn phụ (DisplayManager).
class CustomerDisplayPlatformBridge {
  static const _method = MethodChannel('com.sboxhrm/customer_display');
  static const _events = EventChannel('com.sboxhrm/customer_display_events');
  static Stream<String>? _cached;

  /// true chỉ khi thiết bị có display phụ (không tính màn chính).
  static Future<bool> hasSecondaryDisplay() async {
    try {
      final ok = await _method.invokeMethod<bool>('hasSecondaryDisplay');
      return ok == true;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> openSecondary({
    String route = '/customer-display',
    String mode = 't1Native',
  }) async {
    try {
      // window: Kotlin trả true mà không mở màn local.
      if (mode == 'window') {
        final ok = await _method.invokeMethod<bool>('show', {
          'route': route,
          'mode': mode,
        });
        return ok == true;
      }
      final has = await hasSecondaryDisplay();
      if (!has) return false;
      final ok = await _method.invokeMethod<bool>('show', {
        'route': route,
        'mode': mode,
      });
      return ok == true;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> closeSecondary() async {
    try {
      final ok = await _method.invokeMethod<bool>('hide');
      return ok == true;
    } catch (_) {
      return false;
    }
  }

  static Future<List<Map<String, dynamic>>> listDisplays() async {
    try {
      final raw = await _method.invokeMethod<List<dynamic>>('listDisplays');
      if (raw == null) return const [];
      return raw
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  static Future<void> publishNative(String json) async {
    try {
      await _method.invokeMethod('publish', {'json': json});
    } catch (_) {}
  }

  static Future<String?> readNative() async {
    try {
      return await _method.invokeMethod<String>('read');
    } catch (_) {
      return null;
    }
  }

  static Stream<String>? nativeStateStream() {
    _cached ??= _events
        .receiveBroadcastStream()
        .map((e) => e?.toString() ?? '')
        .where((e) => e.isNotEmpty);
    return _cached;
  }
}
