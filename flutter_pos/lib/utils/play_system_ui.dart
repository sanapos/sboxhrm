import 'package:flutter/services.dart';

import '../theme/sbox_tokens.dart';

/// Overlay styles without status/nav bar colors (Android 15 Play scan).
const kPlayOverlayOnLightBg = SystemUiOverlayStyle(
  statusBarIconBrightness: Brightness.light,
  statusBarBrightness: Brightness.dark,
  systemNavigationBarIconBrightness: Brightness.light,
  systemStatusBarContrastEnforced: false,
  systemNavigationBarContrastEnforced: false,
);

const kPlayOverlayOnDarkBg = SboxColors.posApp ? _posOverlay : _darkOverlay;

const _darkOverlay = SystemUiOverlayStyle(
  statusBarIconBrightness: Brightness.light,
  statusBarBrightness: Brightness.dark,
  systemNavigationBarIconBrightness: Brightness.light,
  systemStatusBarContrastEnforced: false,
  systemNavigationBarContrastEnforced: false,
);

/// SBOX POS (giống bản Android 7): thanh trạng thái cùng màu nền trang, icon tối.
/// Thanh điều hướng giữ nền đen: Android 6 (T1) không đổi được icon điều hướng sang tối.
const _posOverlay = SystemUiOverlayStyle(
  statusBarColor: SboxColors.chrome,
  statusBarIconBrightness: Brightness.dark,
  statusBarBrightness: Brightness.light,
  systemNavigationBarColor: Color(0xFF000000),
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
