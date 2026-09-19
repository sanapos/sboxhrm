import 'package:flutter/services.dart';

class NotificationSound {
  static final NotificationSound _instance = NotificationSound._internal();
  factory NotificationSound() => _instance;
  NotificationSound._internal();

  DateTime? _lastPlay;

  void play() {
    final now = DateTime.now();
    if (_lastPlay != null &&
        now.difference(_lastPlay!) < const Duration(milliseconds: 800)) {
      return;
    }
    _lastPlay = now;
    SystemSound.play(SystemSoundType.click);
  }

  /// CK Tingee thành công — tiếng rõ hơn click toast.
  void playPaymentSuccess() {
    _lastPlay = DateTime.now();
    SystemSound.play(SystemSoundType.alert);
    Future<void>.delayed(const Duration(milliseconds: 180), () {
      SystemSound.play(SystemSoundType.click);
    });
  }

  static Future<void> playStatic([dynamic a, dynamic b, dynamic c]) async {
    NotificationSound().play();
  }
}
