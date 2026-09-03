import 'package:flutter/material.dart';

/// Đánh dấu màn POS đang nằm trong shell mobile 5-tab (KiotViet).
class PosHubScope extends InheritedWidget {
  const PosHubScope({
    super.key,
    required this.embeddedInHub,
    this.pushedSubPage = false,
    required super.child,
  });

  /// Tab Tổng quan / Hàng hoá / Bán / Hoá đơn / Nhiều hơn.
  final bool embeddedInHub;

  /// Mở từ menu «Nhiều hơn» (cần nút quay lại, không hiện toolbar ngang).
  final bool pushedSubPage;

  static Widget pushed({required Widget child}) => PosHubScope(
        embeddedInHub: false,
        pushedSubPage: true,
        child: child,
      );

  static bool of(BuildContext context) {
    return context
            .dependOnInheritedWidgetOfExactType<PosHubScope>()
            ?.embeddedInHub ??
        false;
  }

  static bool pushedSubPageOf(BuildContext context) {
    return context
            .dependOnInheritedWidgetOfExactType<PosHubScope>()
            ?.pushedSubPage ??
        false;
  }

  @override
  bool updateShouldNotify(PosHubScope oldWidget) =>
      embeddedInHub != oldWidget.embeddedInHub ||
      pushedSubPage != oldWidget.pushedSubPage;
}

/// Module POS mở shell 5-tab trên mobile (không gồm báo cáo 14 mẫu).
abstract final class PosHubModules {
  static const primary = {
    'PosProducts',
    'PosSell',
    'PosSaleOrders',
  };

  static bool isPrimary(String? code) =>
      code != null && primary.contains(code);

  static int tabIndexForModule(String? code) => switch (code) {
        'PosProducts' => 1,
        'PosSell' => 2,
        'PosSaleOrders' => 3,
        _ => 2,
      };

  static const tabLabels = [
    'Tổng quan',
    'Hàng hoá',
    'Bán hàng',
    'Hoá đơn',
    'Nhiều hơn',
  ];
}
