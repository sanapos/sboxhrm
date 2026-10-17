import 'package:flutter/foundation.dart';

/// Chiều cao bàn phím ảo trình duyệt (CSS px). Ngoài web luôn 0 — hệ điều hành đã báo qua viewInsets.
final ValueNotifier<double> posWebKeyboardInset = ValueNotifier<double>(0);

void posStartWebKeyboardWatch() {}

bool posWebHasTouchPoints() => false;

void posFocusWebEditingElement() {}

void posArmWebImeForGesture() {}
