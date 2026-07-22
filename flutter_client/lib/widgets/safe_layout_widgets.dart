import 'package:flutter/material.dart';

/// Hàng filter chip cùng chiều cao — không dùng [IntrinsicHeight].
class SafeEqualHeightRow extends StatelessWidget {
  const SafeEqualHeightRow({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    if (children.isEmpty) return const SizedBox.shrink();
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0) const SizedBox(width: 8),
          Expanded(child: children[i]),
        ],
      ],
    );
  }
}

/// Timeline / approval step — tránh [IntrinsicHeight] + [Expanded] line.
class SafeTimelineRow extends StatelessWidget {
  const SafeTimelineRow({
    super.key,
    required this.indicator,
    required this.child,
    this.isLast = false,
    this.gutterWidth = 30,
    this.lineHeight = 40,
    this.lineColor,
    this.gap = 10,
    this.bottomPadding = 16,
  });

  final Widget indicator;
  final Widget child;
  final bool isLast;
  final double gutterWidth;
  final double lineHeight;
  final Color? lineColor;
  final double gap;
  final double bottomPadding;

  @override
  Widget build(BuildContext context) {
    final line = lineColor ?? Colors.grey.shade300;
    return Padding(
      padding: EdgeInsets.only(bottom: isLast ? 0 : bottomPadding),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: gutterWidth,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                indicator,
                if (!isLast) ...[
                  const SizedBox(height: 4),
                  Container(width: 2, height: lineHeight, color: line),
                ],
              ],
            ),
          ),
          SizedBox(width: gap),
          Expanded(child: child),
        ],
      ),
    );
  }
}

/// Lưới cố định bằng [Wrap] — không tạo viewport lồng trong scroll view.
class SafeFixedGrid extends StatelessWidget {
  const SafeFixedGrid({
    super.key,
    required this.crossAxisCount,
    required this.itemCount,
    required this.itemBuilder,
    this.spacing = 4,
    this.runSpacing = 4,
    this.childAspectRatio,
    this.itemHeight,
  });

  final int crossAxisCount;
  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;
  final double spacing;
  final double runSpacing;
  final double? childAspectRatio;
  final double? itemHeight;

  @override
  Widget build(BuildContext context) {
    if (itemCount <= 0) return const SizedBox.shrink();
    return LayoutBuilder(
      builder: (context, constraints) {
        final count = crossAxisCount.clamp(1, 12);
        final cellWidth =
            (constraints.maxWidth - spacing * (count - 1)) / count;
        final cellHeight = itemHeight ??
            (childAspectRatio != null && childAspectRatio! > 0
                ? cellWidth / childAspectRatio!
                : null);

        return Wrap(
          spacing: spacing,
          runSpacing: runSpacing,
          children: [
            for (var i = 0; i < itemCount; i++)
              SizedBox(
                width: cellWidth,
                height: cellHeight,
                child: itemBuilder(context, i),
              ),
          ],
        );
      },
    );
  }
}
