import 'package:flutter/material.dart';

/// Header cố định chiều cao — ghim đầu [CustomScrollView] đến khi hết nội dung bảng phía dưới.
class PinnedBoxHeaderDelegate extends SliverPersistentHeaderDelegate {
  final double extent;
  final Widget child;
  final Color backgroundColor;
  final double elevation;

  PinnedBoxHeaderDelegate({
    required this.extent,
    required this.child,
    this.backgroundColor = Colors.white,
    this.elevation = 2,
  });

  @override
  double get minExtent => extent;

  @override
  double get maxExtent => extent;

  @override
  Widget build(
      BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Material(
      color: backgroundColor,
      elevation: overlapsContent || shrinkOffset > 0 ? elevation : 0,
      shadowColor: Colors.black26,
      child: child,
    );
  }

  @override
  bool shouldRebuild(covariant PinnedBoxHeaderDelegate oldDelegate) =>
      extent != oldDelegate.extent ||
      child != oldDelegate.child ||
      backgroundColor != oldDelegate.backgroundColor;
}
