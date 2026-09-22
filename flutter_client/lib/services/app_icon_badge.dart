import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Số trên icon app (iOS). Android không dùng badge này.
class AppIconBadge {
  AppIconBadge._();

  static const _channel = MethodChannel('sbox/app_badge');

  static Future<void> set(int count) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.iOS) return;
    final n = count < 0 ? 0 : count;
    try {
      await _channel.invokeMethod<void>('set', n);
    } catch (e) {
      debugPrint('AppIconBadge.set failed: $e');
    }
  }
}
