import 'dart:async';

import 'package:flutter/material.dart';

/// Chữ tự vẽ lại mỗi giây khi [running] — dùng cho đồng hồ dòng tính giờ (karaoke / bi-a).
/// Không phụ thuộc màn cha setState: trước đây đồng hồ chỉ nhảy khi số block đổi nên «lúc chạy lúc không».
class PosTickingText extends StatefulWidget {
  const PosTickingText({
    super.key,
    required this.running,
    required this.text,
    this.style,
    this.interval = const Duration(seconds: 1),
  });

  final bool running;
  final String Function() text;
  final TextStyle? style;
  final Duration interval;

  @override
  State<PosTickingText> createState() => _PosTickingTextState();
}

class _PosTickingTextState extends State<PosTickingText> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(covariant PosTickingText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.interval != widget.interval) {
      _tick?.cancel();
      _tick = null;
    }
    _sync();
  }

  void _sync() {
    if (widget.running) {
      _tick ??= Timer.periodic(widget.interval, (_) {
        if (mounted) setState(() {});
      });
    } else {
      _tick?.cancel();
      _tick = null;
    }
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Text(widget.text(), style: widget.style);
}
