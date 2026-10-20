import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Số trên icon app (iOS). Android không dùng badge này.
class AppIconBadge {
  AppIconBadge._();

  static const _channel = MethodChannel('sbox/app_badge');

  /// Chặn trên badge icon iOS: số lớn (vd hàng nghìn do thông báo tồn đọng)
  /// hiển thị xấu và vô nghĩa trên home screen. Danh sách trong app vẫn giữ số thật.
  static const int _maxBadge = 99;

  static Future<void> set(int count) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.iOS) return;
    final n = count < 0 ? 0 : (count > _maxBadge ? _maxBadge : count);
    try {
      await _channel.invokeMethod<void>('set', n);
    } catch (e) {
      debugPrint('AppIconBadge.set failed: $e');
    }
  }
}
