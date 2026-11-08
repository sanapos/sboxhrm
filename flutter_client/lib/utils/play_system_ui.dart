import 'package:flutter/services.dart';

/// SBOX BOSS liền một nền nhạt từ trên xuống dưới: icon hệ thống tối. App khác nền đen, icon sáng.
const _bossLightBars = String.fromEnvironment('SBOX_APP') == 'boss';
const _barIcons = _bossLightBars ? Brightness.dark : Brightness.light;
const _barIosHint = _bossLightBars ? Brightness.light : Brightness.dark;

/// Overlay styles without status/nav bar colors.
/// Those colors map to deprecated Window.setStatusBarColor /
/// setNavigationBarColor on Android 15 (Play Console quality scan).
const kPlayOverlayOnLightBg = SystemUiOverlayStyle(
  statusBarIconBrightness: _barIcons,
  statusBarBrightness: _barIosHint,
  systemNavigationBarIconBrightness: _barIcons,
  systemStatusBarContrastEnforced: false,
  systemNavigationBarContrastEnforced: false,
);

const kPlayOverlayOnDarkBg = SystemUiOverlayStyle(
  statusBarIconBrightness: _barIcons,
  statusBarBrightness: _barIosHint,
  systemNavigationBarIconBrightness: _barIcons,
  systemStatusBarContrastEnforced: false,
  systemNavigationBarContrastEnforced: false,
);

/// Ẩn status/nav (POS phóng toàn màn). Dùng [manual] overlays rỗng —
/// [SystemUiMode.immersiveSticky] cũng ẩn nhưng khi thoát [edgeToEdge]
/// không gỡ IMMERSIVE_STICKY (phải vuốt mới hiện thanh).
Future<void> hideSystemBarsForImmersive() {
  return SystemChrome.setEnabledSystemUIMode(
    SystemUiMode.manual,
    overlays: const [],
  );
}

/// Hiện lại status/nav rồi trở về edge-to-edge.
/// Chỉ [edgeToEdge] không xóa FULLSCREEN / IMMERSIVE_STICKY.
Future<void> restoreSystemBarsEdgeToEdge() async {
  await SystemChrome.setEnabledSystemUIMode(
    SystemUiMode.manual,
    overlays: SystemUiOverlay.values,
  );
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(kPlayOverlayOnDarkBg);
}
