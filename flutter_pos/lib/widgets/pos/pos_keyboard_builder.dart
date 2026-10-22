import 'package:flutter/widgets.dart';

/// Dựng lại khi bàn phím ảo bật / tắt. Trong thân `Scaffold`, `MediaQuery.viewInsets` luôn = 0
/// (Scaffold tự thu nhỏ thân) nên không dùng được để biết bàn phím đang mở — đọc thẳng từ [View].
/// [visibleHeight]: chiều cao màn hình (dp) còn lại phía trên bàn phím.
class PosKeyboardBuilder extends StatefulWidget {
  const PosKeyboardBuilder({super.key, required this.builder});

  final Widget Function(BuildContext context, bool keyboardOpen, double visibleHeight) builder;

  @override
  State<PosKeyboardBuilder> createState() => _PosKeyboardBuilderState();
}

class _PosKeyboardBuilderState extends State<PosKeyboardBuilder> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeMetrics() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final view = View.of(context);
    final dpr = view.devicePixelRatio;
    final inset = view.viewInsets.bottom / dpr;
    final height = view.physicalSize.height / dpr;
    return widget.builder(context, inset > 0, height - inset);
  }
}
