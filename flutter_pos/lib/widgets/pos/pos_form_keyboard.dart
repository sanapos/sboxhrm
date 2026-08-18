import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Padding đáy khi IME mở — tối đa ~1/3 chiều cao màn (A6 T1 landscape).
/// Tránh sheet/dialog cộng full viewInsets → form bị đẩy mất / bàn phím chiếm nửa màn.
double posImeBottomPad(BuildContext context, {double maxFraction = 1 / 3}) {
  final mq = MediaQuery.of(context);
  final raw = mq.viewInsets.bottom;
  if (raw <= 0) return 0;
  final cap = mq.size.height * maxFraction;
  return math.min(raw, cap);
}

/// A6/Android 6: với `adjustPan`, không cộng thêm full IME vào Dialog.
/// Gỡ inset khỏi MediaQuery dialog — tránh form co mất.
Widget wrapPosFormDialog(BuildContext context, Widget dialog) {
  return MediaQuery.removeViewInsets(
    context: context,
    removeBottom: true,
    child: dialog,
  );
}

/// Tắt IME khi mở form. Dialog hay focus ô đầu → bàn phím che hết form.
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
