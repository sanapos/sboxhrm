import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/widgets.dart';

import 'system_ui_inset_mode.dart';

/// Khoảng thêm dưới nav — không cộng vào status bar (tránh khe trắng trên).
const kSystemBarClearance = 4.0;

/// Khi edge-to-edge báo padding = 0 nhưng status bar vẫn đè (A7 C20Lite).
const kFallbackStatusBarInset = 24.0;

/// Khi cửa sổ đã trừ nav bar, vẫn nâng footer khỏi mép dưới.
const kFallbackBottomClearance = 8.0;

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
      : (kIsWeb ? 0.0 : kFallbackStatusBarInset);
  final bottom = ime > 1
      ? mq.padding.bottom
      : (botSys > 0.5 ? botSys : (kIsWeb ? 0.0 : kFallbackBottomClearance)) +
          kSystemBarClearance;
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
  if (hideBars) {
    if (top <= 0.5) top = 0;
    if (inherited.viewInsets.bottom <= 1 && bottom <= 0.5) bottom = 0;
  } else if (!kIsWeb) {
    if (top < kFallbackStatusBarInset) {
      top = kFallbackStatusBarInset;
    }
    if (inherited.viewInsets.bottom <= 1 &&
        bottom < kFallbackBottomClearance) {
      bottom = kFallbackBottomClearance + kSystemBarClearance;
    }
  }
  if (top <= 0 && bottom <= 0) return child;
  final newSize = Size(
    inherited.size.width,
    (inherited.size.height - top - bottom).clamp(0.0, inherited.size.height),
  );
  return Padding(
    padding: EdgeInsets.only(top: top, bottom: bottom),
    child: ClipRect(
      child: MediaQuery(
        data: inherited.copyWith(
          size: newSize,
          padding: EdgeInsets.only(
            left: inherited.padding.left,
            right: inherited.padding.right,
          ),
          viewPadding: EdgeInsets.only(
            left: inherited.viewPadding.left,
            right: inherited.viewPadding.right,
          ),
        ),
        child: child,
      ),
    ),
  );
}
