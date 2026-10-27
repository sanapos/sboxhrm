import 'package:flutter/material.dart';

import '../theme/sbox_tokens.dart';
/// Hàng filter chip cùng chiều cao — không dùng [IntrinsicHeight].
class SafeEqualHeightRow extends StatelessWidget {
  const SafeEqualHeightRow({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    if (children.isEmpty) return const SizedBox.shrink();
    // Không dùng CrossAxisAlignment.stretch — trong Column/scroll unbounded
    // stretch dễ lỗi layout (chiều cao vô hạn) → bộ lọc biến mất, chỉ còn khoảng trắng.
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0) const SizedBox(width: 8),
          Expanded(child: children[i]),
        ],
      ],
    );
  }
}

/// Lưới ô lọc: 2 cột trên màn hẹp, 3 cột khi đủ rộng — 6 ô lọc chỉ chiếm 2 hàng
/// trên desktop, không bị khung header (giới hạn chiều cao) cắt mất hàng cuối.
class SafeFilterChipGrid extends StatelessWidget {
  const SafeFilterChipGrid({
    super.key,
    required this.children,
    this.wideBreakpoint = 1000,
    this.spacing = 8,
  });

  final List<Widget> children;
  final double wideBreakpoint;
  final double spacing;

  @override
  Widget build(BuildContext context) {
    if (children.isEmpty) return const SizedBox.shrink();
    return LayoutBuilder(
      builder: (context, constraints) {
        final cols = constraints.maxWidth >= wideBreakpoint ? 3 : 2;
        final rows = <Widget>[];
        for (var i = 0; i < children.length; i += cols) {
          final slice = children.sublist(
              i, (i + cols).clamp(0, children.length).toInt());
          if (rows.isNotEmpty) rows.add(SizedBox(height: spacing));
          rows.add(SafeEqualHeightRow(children: [
            ...slice,
            // Giữ độ rộng cột đều ở hàng cuối thiếu ô.
            for (var k = slice.length; k < cols; k++) const SizedBox.shrink(),
          ]));
        }
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: rows,
        );
      },
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
    final line = lineColor ?? SboxColors.slate300;
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
