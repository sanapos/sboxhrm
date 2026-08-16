import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// A6/Android 6 + `adjustResize`: cộng viewInsets vào Dialog làm form bị co mất.
/// Gỡ inset IME khỏi MediaQuery của dialog — cửa sổ đã co sẵn.
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
