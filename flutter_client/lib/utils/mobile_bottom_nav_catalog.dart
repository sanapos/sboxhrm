import 'package:flutter/material.dart';

/// Định nghĩa một chức năng gán vào ô thanh điều hướng mobile.
class MobileBottomNavItemDef {
  const MobileBottomNavItemDef({
    required this.id,
    required this.label,
    required this.icon,
    required this.activeIcon,
    this.moduleCode,
    this.centerStyle = false,
  });

  final String id;
  final String label;
  final IconData icon;
  final IconData activeIcon;

  /// Dùng kiểm tra quyền; null = luôn hiện (drawer, pos more).
  final String? moduleCode;
  final bool centerStyle;
}

abstract final class MobileBottomNavCatalog {
  static const emptyId = '_empty';
  static const drawerId = '_drawer';
  static const posMoreId = '_posMore';

  static const mainItems = [
    MobileBottomNavItemDef(
      id: 'Home',
      label: 'Trang chủ',
      icon: Icons.home_outlined,
      activeIcon: Icons.home,
      moduleCode: 'Home',
    ),
    MobileBottomNavItemDef(
      id: 'Dashboard',
      label: 'Tổng quan',
      icon: Icons.dashboard_outlined,
      activeIcon: Icons.dashboard,
      moduleCode: 'Dashboard',
    ),
    MobileBottomNavItemDef(
      id: 'MobileAttendance',
      label: 'Chấm công',
      icon: Icons.fingerprint_outlined,
      activeIcon: Icons.fingerprint,
      moduleCode: 'MobileAttendance',
      centerStyle: true,
    ),
    MobileBottomNavItemDef(
      id: 'Task',
      label: 'Công việc',
      icon: Icons.task_alt_outlined,
      activeIcon: Icons.task_alt,
      moduleCode: 'Task',
    ),
    MobileBottomNavItemDef(
      id: 'PosSell',
      label: 'Bán hàng',
      icon: Icons.point_of_sale_outlined,
      activeIcon: Icons.point_of_sale,
      moduleCode: 'PosSell',
      centerStyle: true,
    ),
    MobileBottomNavItemDef(
      id: 'PosProducts',
      label: 'Hàng hóa',
      icon: Icons.inventory_2_outlined,
      activeIcon: Icons.inventory_2,
      moduleCode: 'PosProducts',
    ),
    MobileBottomNavItemDef(
      id: 'PosSaleOrders',
      label: 'Đơn hàng',
      icon: Icons.receipt_long_outlined,
      activeIcon: Icons.receipt_long,
      moduleCode: 'PosSaleOrders',
    ),
    MobileBottomNavItemDef(
      id: 'Employee',
      label: 'Nhân sự',
      icon: Icons.people_outline,
      activeIcon: Icons.people,
      moduleCode: 'Employee',
    ),
    MobileBottomNavItemDef(
      id: 'Payroll',
      label: 'Bảng lương',
      icon: Icons.payments_outlined,
      activeIcon: Icons.payments,
      moduleCode: 'Payroll',
    ),
    MobileBottomNavItemDef(
      id: 'Leave',
      label: 'Nghỉ phép',
      icon: Icons.event_busy_outlined,
      activeIcon: Icons.event_busy,
      moduleCode: 'Leave',
    ),
    MobileBottomNavItemDef(
      id: 'Communication',
      label: 'Truyền thông',
      icon: Icons.campaign_outlined,
      activeIcon: Icons.campaign,
      moduleCode: 'Communication',
    ),
    MobileBottomNavItemDef(
      id: 'PosSalesReport',
      label: 'Báo cáo POS',
      icon: Icons.bar_chart_outlined,
      activeIcon: Icons.bar_chart,
      moduleCode: 'PosSalesReport',
    ),
    MobileBottomNavItemDef(
      id: 'SettingsHub',
      label: 'Cài đặt',
      icon: Icons.settings_outlined,
      activeIcon: Icons.settings,
      moduleCode: 'SettingsHub',
    ),
    MobileBottomNavItemDef(
      id: 'Notification',
      label: 'Thông báo',
      icon: Icons.notifications_outlined,
      activeIcon: Icons.notifications,
      moduleCode: 'Notification',
    ),
    MobileBottomNavItemDef(
      id: 'Payslip',
      label: 'Phiếu lương',
      icon: Icons.receipt_outlined,
      activeIcon: Icons.receipt,
      moduleCode: 'Payslip',
    ),
    MobileBottomNavItemDef(
      id: drawerId,
      label: 'Thêm',
      icon: Icons.grid_view_outlined,
      activeIcon: Icons.grid_view_rounded,
    ),
  ];

  static const posItems = [
    MobileBottomNavItemDef(
      id: 'PosSalesReport',
      label: 'Tổng quan',
      icon: Icons.insights_outlined,
      activeIcon: Icons.insights,
      moduleCode: 'PosSalesReport',
    ),
    MobileBottomNavItemDef(
      id: 'PosProducts',
      label: 'Hàng hoá',
      icon: Icons.inventory_2_outlined,
      activeIcon: Icons.inventory_2,
      moduleCode: 'PosProducts',
    ),
    MobileBottomNavItemDef(
      id: 'PosSell',
      label: 'Bán hàng',
      icon: Icons.shopping_bag_outlined,
      activeIcon: Icons.shopping_bag,
      moduleCode: 'PosSell',
      centerStyle: true,
    ),
    MobileBottomNavItemDef(
      id: 'PosSaleOrders',
      label: 'Hoá đơn',
      icon: Icons.receipt_long_outlined,
      activeIcon: Icons.receipt_long,
      moduleCode: 'PosSaleOrders',
    ),
    MobileBottomNavItemDef(
      id: posMoreId,
      label: 'Nhiều hơn',
      icon: Icons.menu_outlined,
      activeIcon: Icons.menu,
    ),
  ];

  static Map<String, MobileBottomNavItemDef> mapFor(List<MobileBottomNavItemDef> items) =>
      {for (final i in items) i.id: i};

  static int posTabIndexFor(String slotId) => switch (slotId) {
        'PosSalesReport' => 0,
        'PosProducts' => 1,
        'PosSell' => 2,
        'PosSaleOrders' => 3,
        posMoreId => 4,
        _ => 2,
      };

  static String posSlotIdForTab(int tab) => switch (tab) {
        0 => 'PosSalesReport',
        1 => 'PosProducts',
        2 => 'PosSell',
        3 => 'PosSaleOrders',
        _ => posMoreId,
      };
}
