import 'dart:js_interop';

import 'package:web/web.dart' as web;

bool get posBrowserFullscreenActive =>
    web.document.fullscreenElement != null;

/// Bật/tắt fullscreen trình duyệt. Trả về true nếu đang fullscreen sau thao tác.
Future<bool> togglePosBrowserFullscreen() async {
  try {
    if (posBrowserFullscreenActive) {
      await web.document.exitFullscreen().toDart;
      return false;
    }
    final el = web.document.documentElement;
    if (el == null) return false;
    await el.requestFullscreen().toDart;
    return true;
  } catch (_) {
    return posBrowserFullscreenActive;
  }
}
