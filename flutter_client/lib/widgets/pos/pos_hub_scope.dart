import 'package:flutter/material.dart';

/// Đánh dấu màn POS đang nằm trong shell mobile 5-tab (KiotViet).
class PosHubScope extends InheritedWidget {
  const PosHubScope({
    super.key,
    required this.embeddedInHub,
    required super.child,
  });

  final bool embeddedInHub;

  static bool of(BuildContext context) {
    return context
            .dependOnInheritedWidgetOfExactType<PosHubScope>()
            ?.embeddedInHub ??
        false;
  }

  @override
  bool updateShouldNotify(PosHubScope oldWidget) =>
      embeddedInHub != oldWidget.embeddedInHub;
}

/// Module POS mở shell 5-tab trên mobile.
abstract final class PosHubModules {
  static const primary = {
    'PosSalesReport',
    'PosProducts',
    'PosSell',
    'PosSaleOrders',
  };

  static bool isPrimary(String? code) =>
      code != null && primary.contains(code);

  static int tabIndexForModule(String? code) => switch (code) {
        'PosSalesReport' => 0,
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
