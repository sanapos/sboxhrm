import 'package:flutter/material.dart';

/// Định nghĩa một ô truy cập nhanh (theo moduleCode).
class MobileQuickActionDef {
  const MobileQuickActionDef({
    required this.moduleCode,
    required this.label,
    required this.icon,
  });

  final String moduleCode;
  final String label;
  final IconData icon;
}

/// Các module gán được vào lưới «Thêm» — lấy từ nhóm Trang chủ.
abstract final class MobileQuickActionsCatalog {
  static const items = [
    MobileQuickActionDef(
      moduleCode: 'PosSell',
      label: 'Bán hàng',
      icon: Icons.point_of_sale_outlined,
    ),
    MobileQuickActionDef(
      moduleCode: 'PosProducts',
      label: 'Hàng hóa',
      icon: Icons.inventory_2_outlined,
    ),
    MobileQuickActionDef(
      moduleCode: 'PosSaleOrders',
      label: 'Hoá đơn',
      icon: Icons.receipt_long_outlined,
    ),
    MobileQuickActionDef(
      moduleCode: 'PosSalesReport',
      label: 'Báo cáo POS',
      icon: Icons.bar_chart_outlined,
    ),
    MobileQuickActionDef(
      moduleCode: 'Employee',
      label: 'Nhân sự',
      icon: Icons.people_outline,
    ),
    MobileQuickActionDef(
      moduleCode: 'Department',
      label: 'Phòng ban',
      icon: Icons.business_outlined,
    ),
    MobileQuickActionDef(
      moduleCode: 'Payroll',
      label: 'Bảng lương',
      icon: Icons.payments_outlined,
    ),
    MobileQuickActionDef(
      moduleCode: 'Payslip',
      label: 'Phiếu lương',
      icon: Icons.receipt_outlined,
    ),
    MobileQuickActionDef(
      moduleCode: 'Leave',
      label: 'Nghỉ phép',
      icon: Icons.event_busy_outlined,
    ),
    MobileQuickActionDef(
      moduleCode: 'Attendance',
      label: 'Chấm công máy',
      icon: Icons.access_time_outlined,
    ),
    MobileQuickActionDef(
      moduleCode: 'AttendanceSummary',
      label: 'Tổng hợp CC',
      icon: Icons.summarize_outlined,
    ),
    MobileQuickActionDef(
      moduleCode: 'Task',
      label: 'Công việc',
      icon: Icons.task_alt_outlined,
    ),
    MobileQuickActionDef(
      moduleCode: 'Communication',
      label: 'Truyền thông',
      icon: Icons.campaign_outlined,
    ),
    MobileQuickActionDef(
      moduleCode: 'AdvanceRequests',
      label: 'Tạm ứng',
      icon: Icons.request_quote_outlined,
    ),
    MobileQuickActionDef(
      moduleCode: 'BonusPenalty',
      label: 'Thưởng phạt',
      icon: Icons.emoji_events_outlined,
    ),
    MobileQuickActionDef(
      moduleCode: 'Asset',
      label: 'Tài sản',
      icon: Icons.inventory_outlined,
    ),
    MobileQuickActionDef(
      moduleCode: 'Feedback',
      label: 'Góp ý',
      icon: Icons.feedback_outlined,
    ),
    MobileQuickActionDef(
      moduleCode: 'FieldCheckIn',
      label: 'Check-in',
      icon: Icons.location_on_outlined,
    ),
    MobileQuickActionDef(
      moduleCode: 'KPI',
      label: 'KPI',
      icon: Icons.track_changes_outlined,
    ),
    MobileQuickActionDef(
      moduleCode: 'Production',
      label: 'Sản xuất',
      icon: Icons.precision_manufacturing_outlined,
    ),
    MobileQuickActionDef(
      moduleCode: 'SettingsHub',
      label: 'Cài đặt',
      icon: Icons.settings_outlined,
    ),
    MobileQuickActionDef(
      moduleCode: 'Notification',
      label: 'Thông báo',
      icon: Icons.notifications_outlined,
    ),
    MobileQuickActionDef(
      moduleCode: 'PosPurchaseReceipts',
      label: 'Nhập hàng',
      icon: Icons.move_to_inbox_outlined,
    ),
    MobileQuickActionDef(
      moduleCode: 'PosStockCounts',
      label: 'Kiểm kho',
      icon: Icons.fact_check_outlined,
    ),
  ];

  static Map<String, MobileQuickActionDef> get map =>
      {for (final i in items) i.moduleCode: i};
}
