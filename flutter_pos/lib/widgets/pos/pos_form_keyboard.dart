import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Padding đáy khi IME mở — [maxFraction] trần theo chiều cao màn.
double posImeBottomPad(BuildContext context, {double maxFraction = 0.55}) {
  final mq = MediaQuery.of(context);
  final raw = mq.viewInsets.bottom;
  if (raw <= 0) return 0;
  final cap = mq.size.height * maxFraction;
  return math.min(raw, cap);
}

/// Pad đáy theo IME (có animation) — giữ ô ghi chú/tìm kiếm phía trên bàn phím.
class PosImeAvoidingPadding extends StatelessWidget {
  const PosImeAvoidingPadding({
    super.key,
    required this.child,
    this.maxFraction = 0.55,
    this.extraGap = 8,
  });

  final Widget child;
  final double maxFraction;
  final double extraGap;

  @override
  Widget build(BuildContext context) {
    final ime = posImeBottomPad(context, maxFraction: maxFraction);
    final pad = ime > 0 ? ime + extraGap : 0.0;
    return AnimatedPadding(
      duration: const Duration(milliseconds: 140),
      curve: Curves.easeOut,
      padding: EdgeInsets.only(bottom: pad),
      child: child,
    );
  }
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

/// Cuộn [context] vào vùng nhìn thấy phía trên IME (gọi khi focus TextField).
void posScrollIntoViewAboveIme(
  BuildContext context, {
  double alignment = 0.12,
  Duration duration = const Duration(milliseconds: 200),
}) {
  void run() {
    if (!context.mounted) return;
    Scrollable.ensureVisible(
      context,
      alignment: alignment,
      duration: duration,
      curve: Curves.easeOut,
    );
  }

  WidgetsBinding.instance.addPostFrameCallback((_) => run());
  Future<void>.delayed(const Duration(milliseconds: 280), run);
}

/// Bọc field chữ: focus → cuộn lên trên IME.
class PosImeAwareFocus extends StatelessWidget {
  const PosImeAwareFocus({
    super.key,
    required this.child,
    this.alignment = 0.12,
  });

  final Widget child;
  final double alignment;

  @override
  Widget build(BuildContext context) {
    return Focus(
      canRequestFocus: false,
      onFocusChange: (has) {
        if (has) {
          posScrollIntoViewAboveIme(context, alignment: alignment);
        }
      },
      child: child,
    );
  }
}
