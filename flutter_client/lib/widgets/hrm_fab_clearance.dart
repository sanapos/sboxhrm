import 'package:flutter/material.dart';

import '../utils/responsive_helper.dart';

/// Tránh FAB góc phải che menu ⋮ / action cuối danh sách trên mobile.
class HrmFabClearance extends StatelessWidget {
  const HrmFabClearance({
    super.key,
    required this.child,
    required this.fabVisible,
    this.extendedFab = false,
  });

  final Widget child;
  final bool fabVisible;
  final bool extendedFab;

  @override
  Widget build(BuildContext context) {
    if (!fabVisible || !Responsive.useUnifiedPageScroll(context)) {
      return child;
    }
    return Padding(
      padding: Responsive.fabListInsets(
        context,
        extendedFab: extendedFab,
      ),
      child: child,
    );
  }
}
