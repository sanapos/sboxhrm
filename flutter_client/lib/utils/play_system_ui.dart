import 'package:flutter/services.dart';

/// Overlay styles without status/nav bar colors.
/// Those colors map to deprecated Window.setStatusBarColor /
/// setNavigationBarColor on Android 15 (Play Console quality scan).
const kPlayOverlayOnLightBg = SystemUiOverlayStyle(
  statusBarIconBrightness: Brightness.light,
  statusBarBrightness: Brightness.dark,
  systemNavigationBarIconBrightness: Brightness.light,
  systemStatusBarContrastEnforced: false,
  systemNavigationBarContrastEnforced: false,
);

const kPlayOverlayOnDarkBg = SystemUiOverlayStyle(
  statusBarIconBrightness: Brightness.light,
  statusBarBrightness: Brightness.dark,
  systemNavigationBarIconBrightness: Brightness.light,
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
