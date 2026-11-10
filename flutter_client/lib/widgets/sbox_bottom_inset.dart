import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// Khoảng đệm dưới cho thanh điều hướng đáy.
///
/// iPhone có thanh vuốt báo vùng an toàn 34pt; chừa trọn vùng đó làm thanh điều hướng
/// nổi cao, chừa trống lớn bên dưới. Giữ lại phần đủ để nút không đè lên thanh vuốt
/// (vạch cao 5pt, cách mép dưới ~8pt). Máy không có thanh vuốt: đệm 2.
double sboxBottomNavInset(BuildContext context) {
  final inset = MediaQuery.viewPaddingOf(context).bottom;
  if (inset <= 0) return 2;
  return math.max(inset - 16, 8);
}
