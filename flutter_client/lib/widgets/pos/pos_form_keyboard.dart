import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Padding đáy khi IME mở — tối đa ~1/3 chiều cao màn (A6 T1 landscape).
double posImeBottomPad(BuildContext context, {double maxFraction = 1 / 3}) {
  final mq = MediaQuery.of(context);
  final raw = mq.viewInsets.bottom;
  if (raw <= 0) return 0;
  final cap = mq.size.height * maxFraction;
  return math.min(raw, cap);
}

/// Gỡ inset IME khỏi MediaQuery của dialog — tránh form co mất.
Widget wrapPosFormDialog(BuildContext context, Widget dialog) {
  return MediaQuery.removeViewInsets(
    context: context,
    removeBottom: true,
    child: dialog,
  );
}

void hidePosSoftKeyboard({int alsoAfterMs = 320}) {
  void run() {
    FocusManager.instance.primaryFocus?.unfocus();
    SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
  }

  run();
  WidgetsBinding.instance.addPostFrameCallback((_) => run());
  if (alsoAfterMs > 0) {
    Future<void>.delayed(Duration(milliseconds: alsoAfterMs), run);
  }
}
