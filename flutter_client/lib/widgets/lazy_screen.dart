import 'package:flutter/material.dart';

/// Builds [builder] ?? only after the screen is first shown (or [eager] is true).
/// Keeps off-screen tabs from running [initState] / API until opened.
class LazyScreen extends StatefulWidget {
  const LazyScreen({
    super.key,
    required this.builder,
    this.active = true,
    this.eager = false,
    this.placeholder,
  });

  final WidgetBuilder builder;
  final bool active;
  final bool eager;
  final Widget? placeholder;

  @override
  State<LazyScreen> createState() => _LazyScreenState();
}

class _LazyScreenState extends State<LazyScreen> {
  Widget? _built;

  @override
  void didUpdateWidget(LazyScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if ((widget.active || widget.eager) && _built == null) {
      _built = widget.builder(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.eager || widget.active) {
      _built ??= widget.builder(context);
      return _built!;
    }
    return widget.placeholder ?? const SizedBox.shrink();
  }
}
