import 'package:flutter/material.dart';

import '../../theme/sbox_tokens.dart';

/// Nhãn / biểu tượng / màu cho mã loại thông báo (CategoryCode phía server).
class NotificationCategoryMeta {
  const NotificationCategoryMeta(this.code, this.label, this.icon, this.color);
  final String code;
  final String label;
  final IconData icon;
  final Color color;

  static const _all = <String, NotificationCategoryMeta>{
    'attendance': NotificationCategoryMeta('attendance', 'Chấm công', Icons.fingerprint_rounded, SboxColors.brand500),
    'travel_attendance': NotificationCategoryMeta('travel_attendance', 'Chấm công đi đường', Icons.directions_car_rounded, SboxColors.brand500),
    'device': NotificationCategoryMeta('device', 'Thiết bị', Icons.router_rounded, SboxColors.info),
    'approval': NotificationCategoryMeta('approval', 'Cần duyệt', Icons.approval_rounded, SboxColors.danger),
    'shift': NotificationCategoryMeta('shift', 'Ca làm việc', Icons.calendar_month_rounded, SboxColors.violet),
    'leave': NotificationCategoryMeta('leave', 'Nghỉ phép', Icons.event_busy_rounded, SboxColors.violet),
    'overtime': NotificationCategoryMeta('overtime', 'Tăng ca', Icons.more_time_rounded, Color(0xFFF97316)),
    'payroll': NotificationCategoryMeta('payroll', 'Lương', Icons.payments_rounded, SboxColors.success),
    'transaction': NotificationCategoryMeta('transaction', 'Thu chi', Icons.account_balance_wallet_rounded, SboxColors.success),
    'penalty': NotificationCategoryMeta('penalty', 'Phiếu phạt', Icons.gavel_rounded, SboxColors.danger),
    'meal': NotificationCategoryMeta('meal', 'Suất ăn', Icons.restaurant_rounded, Color(0xFFF97316)),
    'hr': NotificationCategoryMeta('hr', 'Nhân sự', Icons.badge_rounded, Color(0xFFEC4899)),
    'task': NotificationCategoryMeta('task', 'Công việc', Icons.task_alt_rounded, SboxColors.brand600),
    'kpi': NotificationCategoryMeta('kpi', 'KPI', Icons.trending_up_rounded, SboxColors.success),
    'business_trip': NotificationCategoryMeta('business_trip', 'Công tác', Icons.flight_takeoff_rounded, SboxColors.info),
    'pos': NotificationCategoryMeta('pos', 'Bán hàng', Icons.point_of_sale_rounded, SboxColors.brand500),
    'feedback': NotificationCategoryMeta('feedback', 'Kiến nghị', Icons.forum_rounded, SboxColors.warning),
    'internal_comm': NotificationCategoryMeta('internal_comm', 'Thông báo nội bộ', Icons.campaign_rounded, SboxColors.violet),
    'system': NotificationCategoryMeta('system', 'Hệ thống', Icons.settings_rounded, SboxColors.slate500),
    'none': NotificationCategoryMeta('none', 'Khác', Icons.notifications_rounded, SboxColors.slate500),
  };

  static NotificationCategoryMeta of(String? code) {
    final c = (code ?? '').trim().toLowerCase();
    if (c.isEmpty) return _all['none']!;
    return _all[c] ??
        NotificationCategoryMeta(c, c.replaceAll('_', ' '), Icons.notifications_rounded, SboxColors.slate500);
  }

  /// Loại có thể chọn khi quản lý soạn thông báo gửi nhân viên.
  static List<NotificationCategoryMeta> get composable => [
        for (final c in const ['internal_comm', 'attendance', 'shift', 'hr', 'payroll', 'meal', 'task', 'system'])
          _all[c]!,
      ];
}

/// Mức độ thông báo (khớp enum NotificationType phía server).
class NotificationLevelMeta {
  const NotificationLevelMeta(this.value, this.label, this.icon, this.color);
  final int value;
  final String label;
  final IconData icon;
  final Color color;

  static const levels = [
    NotificationLevelMeta(0, 'Thông tin', Icons.info_outline_rounded, SboxColors.info),
    NotificationLevelMeta(1, 'Tin vui', Icons.celebration_rounded, SboxColors.success),
    NotificationLevelMeta(5, 'Nhắc nhở', Icons.alarm_rounded, SboxColors.brand500),
    NotificationLevelMeta(2, 'Quan trọng', Icons.priority_high_rounded, SboxColors.warning),
  ];

  static NotificationLevelMeta of(int v) =>
      levels.firstWhere((l) => l.value == v, orElse: () => levels.first);
}
