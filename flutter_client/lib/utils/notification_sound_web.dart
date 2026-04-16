import 'package:flutter/foundation.dart';
import 'package:web/web.dart' as web;

/// Phát âm thanh thông báo sử dụng Web Audio API
/// Chỉ hoạt động trên web, bỏ qua trên các nền tảng khác
class NotificationSound {
  static final NotificationSound _instance = NotificationSound._internal();
  factory NotificationSound() => _instance;
  NotificationSound._internal();

  /// Phát âm thanh "ding-dong" ngắn cho thông báo mới
  void play() {
    if (!kIsWeb) return;
    try {
      final ctx = web.AudioContext();
      final now = ctx.currentTime;

      // Beep 1 - tần số thấp hơn
      final osc1 = ctx.createOscillator();
      final gain1 = ctx.createGain();
      osc1.type = 'sine';
      osc1.frequency.value = 830;
      gain1.gain.setValueAtTime(0.15, now);
      gain1.gain.exponentialRampToValueAtTime(0.01, now + 0.12);
      osc1.connect(gain1);
      gain1.connect(ctx.destination);
      osc1.start(now);
      osc1.stop(now + 0.12);

      // Beep 2 - tần số cao hơn (tạo hiệu ứng "ding-dong")
      final osc2 = ctx.createOscillator();
      final gain2 = ctx.createGain();
      osc2.type = 'sine';
      osc2.frequency.value = 1050;
      gain2.gain.setValueAtTime(0.15, now + 0.14);
      gain2.gain.exponentialRampToValueAtTime(0.01, now + 0.28);
      osc2.connect(gain2);
      gain2.connect(ctx.destination);
      osc2.start(now + 0.14);
      osc2.stop(now + 0.28);
    } catch (e) {
      debugPrint('Notification sound error: $e');
    }
  }
}
