import 'package:flutter/material.dart';

/// 4-based spacing scale.
abstract final class AppSpace {
  static const double xxs = 4;
  static const double xs = 8;
  static const double sm = 12;
  static const double md = 16;
  static const double lg = 24;
  static const double xl = 32;
  static const double xxl = 48;

  static EdgeInsets all(double v) => EdgeInsets.all(v);
  static EdgeInsets page(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    if (w < 768) return const EdgeInsets.all(sm);
    if (w < 1024) return const EdgeInsets.all(md);
    return const EdgeInsets.all(lg);
  }

  static EdgeInsets symmetric({double h = md, double v = sm}) =>
      EdgeInsets.symmetric(horizontal: h, vertical: v);
}
