import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// Khoảng đệm dưới cho thanh điều hướng đáy.
///
/// Gốc app ([padAwaySystemBars]) đã chừa vùng thanh vuốt iPhone (rút gọn theo
/// [iosHomeIndicatorClearance]) và đặt viewPadding = 0 cho cây con — thường trả 2.
/// Còn nhánh viewPadding > 0 cho màn nào tự vẽ dưới vùng an toàn.
double sboxBottomNavInset(BuildContext context) {
  final inset = MediaQuery.viewPaddingOf(context).bottom;
  if (inset <= 0) return 2;
  return math.max(inset - 16, 8);
}
