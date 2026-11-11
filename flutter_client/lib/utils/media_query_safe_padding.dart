import 'dart:math' as math;

import 'package:flutter/foundation.dart' show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter/widgets.dart';

import 'system_ui_inset_mode.dart';

/// Khoảng thêm dưới nav — không cộng vào status bar (tránh khe trắng trên).
const kSystemBarClearance = 4.0;

/// Khi edge-to-edge báo padding = 0 nhưng status bar vẫn đè (A7 C20Lite).
const kFallbackStatusBarInset = 24.0;

/// Khi cửa sổ đã trừ nav bar, vẫn nâng footer khỏi mép dưới.
const kFallbackBottomClearance = 8.0;

/// Chừa khoảng dự phòng cho status / nav bar chỉ trên điện thoại — Windows / macOS / web không có
/// (trước đây mọi nền tảng trừ web đều cộng → app Windows có dải đen 24 px trên, 12 px dưới).
bool get _phone =>
    !kIsWeb && (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS);

bool get _ios => !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

/// iPhone có thanh vuốt báo vùng an toàn dưới 34pt (iPad 20pt). Chừa trọn vùng đó (cộng thêm 4)
/// ở gốc app làm thanh điều hướng đáy và nút cuối màn nổi cao, trống một dải lớn bên dưới.
/// Vạch vuốt chỉ cao 5pt, cách mép dưới ~8pt — giữ phần đủ để nút không đè lên vạch.
double iosHomeIndicatorClearance(double inset) => math.max(inset - 16, 12);

/// SBOX HRM và SBOX POS (không đặt SBOX_APP) trên Android: MainActivity ẩn thanh điều hướng.
const _hidesNavApp = String.fromEnvironment('SBOX_APP') == '';
bool get _hrmHidesNavBar => _hidesNavApp && !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

double _maxInset(Iterable<double> values) {
  var m = 0.0;
  for (final v in values) {
    if (v > m) m = v;
  }
  return m;
}

/// Edge-to-edge: [MediaQuery.padding] có thể = 0 trong khi View vẫn có inset.
MediaQueryData mediaQueryWithSystemPadding(
  MediaQueryData mq, {
  MediaQueryData? rawView,
  bool? immersive,
}) {
  final hideBars = immersive ?? SystemUiInsetMode.immersive.value;
  final raw = rawView ?? mq;
  final topSys = _maxInset([
    mq.padding.top,
    mq.viewPadding.top,
    raw.padding.top,
    raw.viewPadding.top,
  ]);
  final botSys = _maxInset([
    mq.padding.bottom,
    mq.viewPadding.bottom,
    raw.padding.bottom,
    raw.viewPadding.bottom,
  ]);
  final ime = mq.viewInsets.bottom;
  if (hideBars) {
    return mq.copyWith(
      padding: EdgeInsets.only(
        left: _maxInset([mq.padding.left, mq.viewPadding.left, raw.padding.left]),
        top: topSys,
        right: _maxInset(
            [mq.padding.right, mq.viewPadding.right, raw.padding.right]),
        bottom: ime > 1 ? mq.padding.bottom : botSys,
      ),
    );
  }
  final top = topSys > 0.5
      ? topSys
      : (_phone ? kFallbackStatusBarInset : 0.0);
  final bottom = ime > 1
      ? mq.padding.bottom
      : _phone
          ? botSys > 0.5
              ? (_ios ? iosHomeIndicatorClearance(botSys) : botSys + kSystemBarClearance)
              // SBOX HRM / POS Android chủ động ẩn thanh điều hướng (vuốt lên hiện tạm, đè lên app):
              // inset = 0 là thật, không chừa khe 12dp — nút dưới cùng sát mép màn.
              : _hrmHidesNavBar
                  ? 0.0
                  : kFallbackBottomClearance + kSystemBarClearance
          : botSys + (kIsWeb ? kSystemBarClearance : 0.0); // web giữ như cũ
  return mq.copyWith(
    padding: EdgeInsets.only(
      left: _maxInset([mq.padding.left, mq.viewPadding.left, raw.padding.left]),
      top: top,
      right:
          _maxInset([mq.padding.right, mq.viewPadding.right, raw.padding.right]),
      bottom: bottom,
    ),
  );
}

/// Khi [padding.top] vẫn = 0 (SafeArea không ăn), chừa [viewPadding].
Widget withFallbackTopInset(BuildContext context, Widget child) {
  final mq = MediaQuery.of(context);
  if (mq.padding.top > 0.5) return child;
  final top = mq.viewPadding.top;
  if (top <= 0) return child;
  return Padding(padding: EdgeInsets.only(top: top), child: child);
}

/// Đẩy UI khỏi status / nav bar. Clip + giảm [size] vì desktop shell dùng
/// [MediaQuery.size] full cửa sổ và vẽ đè ra ngoài Padding (không clip).
Widget padAwaySystemBars(BuildContext context, Widget child, {bool? immersive}) {
  final hideBars = immersive ?? SystemUiInsetMode.immersive.value;
  final inherited = MediaQuery.of(context);
  final raw = MediaQueryData.fromView(View.of(context));
  var top = inherited.padding.top > 0.5
      ? inherited.padding.top
      : _maxInset(
          [inherited.viewPadding.top, raw.padding.top, raw.viewPadding.top]);
  var bottom = inherited.padding.bottom > 0.5
      ? inherited.padding.bottom
      : _maxInset([
          inherited.viewPadding.bottom,
          raw.padding.bottom,
          raw.viewPadding.bottom,
        ]);
  // Bàn phím đang mở: inset IME tính từ đáy màn, đã phủ cả thanh điều hướng. Đệm thêm
  // viewPadding (thanh điều hướng ~48dp) làm màn bị đẩy dư → dải nền trống giữa ô đang gõ
  // và bàn phím (đo trên C20: inset 376dp = đúng mép bàn phím, dư đúng 48dp).
  if (inherited.viewInsets.bottom > 1) bottom = 0;
  if (hideBars) {
    if (top <= 0.5) top = 0;
    if (inherited.viewInsets.bottom <= 1 && bottom <= 0.5) bottom = 0;
  } else if (_phone) {
    if (top < kFallbackStatusBarInset) {
      top = kFallbackStatusBarInset;
    }
    if (inherited.viewInsets.bottom <= 1 &&
        bottom < kFallbackBottomClearance &&
        !_hrmHidesNavBar) {
      bottom = kFallbackBottomClearance + kSystemBarClearance;
    }
  }
  // Điện thoại nằm ngang (V2s): thanh điều hướng nằm mép phải — edge-to-edge vẽ thân trang
  // xuống dưới nó (chỉ AppBar tự né) → mọi thẻ / ô nhập bị cắt mép phải. Chừa luôn 2 bên.
  final left = inherited.padding.left;
  final right = inherited.padding.right;
  if (top <= 0 && bottom <= 0 && left <= 0 && right <= 0) return child;
  final newSize = Size(
    (inherited.size.width - left - right).clamp(0.0, inherited.size.width),
    (inherited.size.height - top - bottom).clamp(0.0, inherited.size.height),
  );
  return Padding(
    padding: EdgeInsets.only(left: left, top: top, right: right, bottom: bottom),
    child: ClipRect(
      child: MediaQuery(
        data: inherited.copyWith(
          size: newSize,
          padding: EdgeInsets.zero,
          viewPadding: EdgeInsets.zero,
        ),
        child: child,
      ),
    ),
  );
}
