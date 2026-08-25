import 'package:flutter/widgets.dart';

/// Edge-to-edge (iOS/Android): [MediaQuery.padding] có thể = 0 trong khi
/// [viewPadding] vẫn có notch / home indicator. AppBar và SafeArea dùng padding
/// nên header tràn lên hàng trạng thái.
MediaQueryData mediaQueryWithSystemPadding(MediaQueryData mq) {
  final p = mq.padding;
  final v = mq.viewPadding;
  if (p.top >= v.top - 0.5 && p.bottom >= v.bottom - 0.5) return mq;
  return mq.copyWith(
    padding: EdgeInsets.only(
      left: p.left > 0 ? p.left : v.left,
      top: p.top > 0 ? p.top : v.top,
      right: p.right > 0 ? p.right : v.right,
      bottom: p.bottom > 0 ? p.bottom : v.bottom,
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
