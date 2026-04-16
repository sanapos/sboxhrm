import 'package:flutter/services.dart';

class NotificationSound {
  static final NotificationSound _instance = NotificationSound._internal();
  factory NotificationSound() => _instance;
  NotificationSound._internal();

  void play() {
    // Phát âm thanh hệ thống + rung nhẹ trên Android/iOS
    SystemSound.play(SystemSoundType.alert);
    HapticFeedback.mediumImpact();
  }
}
