import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Chuông / ting KDS + phiếu bếp từ máy khác (cùng pref trên thiết bị).
class PosKdsAlert {
  PosKdsAlert._();

  static const voiceOnKey = 'pos_kds_voice_on';
  static const bellBeforeVoiceKey = 'pos_kds_bell_before_voice';
  static const printTingKey = 'pos_kds_print_ting';
  static const lateMinutesKey = 'pos_kds_late_minutes';
  static const defaultLateMinutes = 10;

  static DateTime? _lastBell;
  static DateTime? _lastTing;
  static int _ui = 0;

  /// `true` khi màn bếp đang mở — overlay khác lắng nghe để ẩn ngay.
  static final ValueNotifier<bool> uiOpen = ValueNotifier(false);

  static bool get isOpen => _ui > 0;

  static void enterUi() {
    _ui++;
    uiOpen.value = true;
  }

  static void leaveUi() {
    if (_ui > 0) _ui--;
    uiOpen.value = _ui > 0;
  }

  static Future<bool> bellBeforeVoice() async {
    final p = await SharedPreferences.getInstance();
    return p.getBool(bellBeforeVoiceKey) ?? true;
  }

  static Future<bool> printTingEnabled() async {
    final p = await SharedPreferences.getInstance();
    return p.getBool(printTingKey) ?? true;
  }

  /// Chuông trước khi đọc món mới.
  static Future<void> playBell() async {
    final now = DateTime.now();
    if (_lastBell != null &&
        now.difference(_lastBell!) < const Duration(milliseconds: 900)) {
      return;
    }
    _lastBell = now;
    try {
      await SystemSound.play(SystemSoundType.alert);
      await HapticFeedback.mediumImpact();
      await Future<void>.delayed(const Duration(milliseconds: 220));
      await SystemSound.play(SystemSoundType.alert);
    } catch (_) {}
  }

  /// Ting khi nhận phiếu in bếp từ thiết bị khác.
  static Future<void> playTing() async {
    final now = DateTime.now();
    if (_lastTing != null &&
        now.difference(_lastTing!) < const Duration(milliseconds: 700)) {
      return;
    }
    _lastTing = now;
    try {
      await SystemSound.play(SystemSoundType.alert);
      await HapticFeedback.lightImpact();
    } catch (_) {}
  }
}
