import 'package:flutter/foundation.dart';

import 'play_system_ui.dart';
import 'pos_browser_fullscreen.dart';
import 'system_ui_inset_mode.dart';

/// Chế độ «Toàn màn hình» dùng chung cho cả app (HRM, POS bán hàng, KDS).
///
/// - Android / iOS: ẩn thanh trạng thái + thanh điều hướng.
/// - Web: xin trình duyệt fullscreen; trình duyệt từ chối (iPhone Safari…) vẫn ẩn khung app.
/// - Windows / macOS: chỉ ẩn khung app (sidebar, thanh trên).
///
/// [MainLayout] đọc [active] để ẩn khung chính; [mediaQueryWithSystemPadding] bỏ chừa thanh hệ thống.
class AppFullscreen {
  AppFullscreen._();

  static ValueListenable<bool> get active => SystemUiInsetMode.immersive;

  static bool get isActive => SystemUiInsetMode.immersive.value;

  static bool _webListening = false;

  static void _ensureWebListener() {
    if (!kIsWeb || _webListening) return;
    _webListening = true;
    // Esc / F11 của trình duyệt thoát fullscreen mà app không nhận phím → đồng bộ lại.
    listenPosBrowserFullscreenChange((browserActive) {
      if (!browserActive && SystemUiInsetMode.immersive.value) {
        SystemUiInsetMode.immersive.value = false;
      }
    });
  }

  static Future<bool> toggle() => set(!isActive);

  static Future<void> exit() async {
    if (isActive) await set(false);
  }

  static Future<bool> set(bool on) async {
    if (kIsWeb) {
      _ensureWebListener();
      if (on != posBrowserFullscreenActive) {
        await togglePosBrowserFullscreen();
      }
      SystemUiInsetMode.immersive.value = on;
      return on;
    }
    SystemUiInsetMode.immersive.value = on;
    if (!_phone) return on;
    try {
      if (on) {
        await hideSystemBarsForImmersive();
      } else {
        await restoreSystemBarsEdgeToEdge();
      }
    } catch (_) {
      // Máy không hỗ trợ ẩn thanh hệ thống: vẫn giữ chế độ ẩn khung app.
    }
    return on;
  }

  static bool get _phone =>
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;
}
