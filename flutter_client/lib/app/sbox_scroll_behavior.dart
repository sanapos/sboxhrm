import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// Cuộn chung toàn app: web / máy tính kéo bằng chuột cũng cuộn được (mặc định Flutter chỉ cho kéo
/// bằng tay / bút) — hàng chip, tab, bảng rộng cuộn ngang được mà không cần giữ Shift + lăn chuột.
/// Thanh cuộn (dọc và ngang) vẫn do MaterialScrollBehavior tự hiện trên máy tính.
class SboxScrollBehavior extends MaterialScrollBehavior {
  const SboxScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => const {
        PointerDeviceKind.touch,
        PointerDeviceKind.stylus,
        PointerDeviceKind.invertedStylus,
        PointerDeviceKind.mouse,
        PointerDeviceKind.trackpad,
        PointerDeviceKind.unknown,
      };
}
