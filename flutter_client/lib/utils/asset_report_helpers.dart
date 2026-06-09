import 'package:flutter/material.dart';
import 'api_datetime.dart';

double assetReportMoney(dynamic v) {
  if (v is double) return v;
  if (v is num) return v.toDouble();
  return double.tryParse(v?.toString() ?? '') ?? 0;
}

String assetReportFormatDate(dynamic v) {
  final d = parseApiCalendarDate(v);
  if (d == null) return v?.toString() ?? '—';
  return '${d.day.toString().padLeft(2, '0')}/'
      '${d.month.toString().padLeft(2, '0')}/'
      '${d.year}';
}

Color assetReportStatusColor(String? statusName) {
  final s = statusName?.toLowerCase() ?? '';
  if (s.contains('hỏng') || s.contains('hong')) {
    return const Color(0xFFDC2626);
  }
  if (s.contains('bảo trì') || s.contains('bao tri')) {
    return const Color(0xFFF59E0B);
  }
  if (s.contains('kho')) return const Color(0xFF0284C7);
  if (s.contains('đang dùng') || s.contains('dang dung')) {
    return const Color(0xFF16A34A);
  }
  return const Color(0xFF6B7280);
}

/// Nhãn ngắn cho chip chọn mục báo cáo (mobile).
const assetReportMobileSections = <({String label, IconData icon})>[
  (label: 'Tổng quan', icon: Icons.dashboard_outlined),
  (label: 'Danh mục', icon: Icons.inventory_2_outlined),
  (label: 'Cấp phát', icon: Icons.person_outline),
  (label: 'Chuyển giao', icon: Icons.swap_horiz),
  (label: 'Kho', icon: Icons.warehouse_outlined),
  (label: 'Kiểm kê', icon: Icons.fact_check_outlined),
  (label: 'Bảo hành', icon: Icons.verified_outlined),
];
