import 'package:flutter/material.dart';

import '../utils/responsive_helper.dart';

/// Chỉ thêm khoảng trống **dưới** FAB — không padding phải (tránh lệch cả trang).
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
      padding: Responsive.fabBodyInsets(
        context,
        extendedFab: extendedFab,
      ),
      child: child,
    );
  }
}
