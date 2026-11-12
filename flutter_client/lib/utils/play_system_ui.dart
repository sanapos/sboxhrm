import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// App SBOX POS, SBOX Nhân Viên: các thanh cùng màu nền trang sáng nên icon hệ thống phải tối.
/// SBOX HRM (không đặt SBOX_APP) cũng vậy: thanh hệ thống trắng như AppBar — xem [SboxColors.lightSystemBars].
/// SBOX BOSS liền một nền nhạt từ trên xuống dưới: icon hệ thống tối.
const _posApp = bool.fromEnvironment('SBOX_POS_STANDALONE') ||
    String.fromEnvironment('SBOX_APP') == 'staff' ||
    String.fromEnvironment('SBOX_APP') == '' ||
    String.fromEnvironment('SBOX_APP') == 'boss';

/// Giao diện tối (HRM bật chế độ tối): dải nền tối → icon hệ thống sáng.
const kPlayOverlayDarkTheme = SystemUiOverlayStyle(
  statusBarIconBrightness: Brightness.light,
  statusBarBrightness: Brightness.dark,
  systemNavigationBarIconBrightness: Brightness.light,
  systemStatusBarContrastEnforced: false,
  systemNavigationBarContrastEnforced: false,
);

/// Kiểu thanh hệ thống cho khung app theo giao diện sáng / tối.
SystemUiOverlayStyle playOverlayFor({required bool darkTheme}) =>
    darkTheme && !_alwaysLightChrome ? kPlayOverlayDarkTheme : kPlayOverlayOnDarkBg;

/// POS / Nhân Viên: luôn khung sáng (không theo chế độ tối).
const _alwaysLightChrome =
    bool.fromEnvironment('SBOX_POS_STANDALONE') || String.fromEnvironment('SBOX_APP') == 'staff';

/// Overlay styles without status/nav bar colors.
/// Those colors map to deprecated Window.setStatusBarColor /
/// setNavigationBarColor on Android 15 (Play Console quality scan).
const kPlayOverlayOnLightBg = SystemUiOverlayStyle(
  statusBarIconBrightness: _posApp ? Brightness.dark : Brightness.light,
  statusBarBrightness: _posApp ? Brightness.light : Brightness.dark,
  systemNavigationBarIconBrightness: _posApp ? Brightness.dark : Brightness.light,
  systemStatusBarContrastEnforced: false,
  systemNavigationBarContrastEnforced: false,
);

const kPlayOverlayOnDarkBg = SystemUiOverlayStyle(
  statusBarIconBrightness: _posApp ? Brightness.dark : Brightness.light,
  statusBarBrightness: _posApp ? Brightness.light : Brightness.dark,
  systemNavigationBarIconBrightness: _posApp ? Brightness.dark : Brightness.light,
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
  await hideNavigationBarIfHrm();
}

const _systemBars = MethodChannel('com.sboxhrm/system_bars');

/// SBOX HRM, SBOX POS trên Android: ẩn thanh điều hướng (vuốt từ mép dưới lên để hiện tạm).
/// SystemChrome.edgeToEdge làm thanh hiện lại → gọi sau mỗi lần đặt chế độ hệ thống.
Future<void> hideNavigationBarIfHrm() async {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
  try {
    await _systemBars.invokeMethod<bool>('hideNavigationBar');
  } catch (_) {
    // Bản Android cũ chưa có kênh: giữ thanh như cũ.
  }
}
