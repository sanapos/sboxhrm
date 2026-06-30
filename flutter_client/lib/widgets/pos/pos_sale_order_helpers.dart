import 'package:flutter/material.dart';

import 'pos_theme.dart';
String posSaleOrderStatusLabel(String status) => switch (status) {
      'Completed' => 'Hoàn thành',
      'Cancelled' => 'Đã hủy',
      'Draft' => 'Đang xử lý',
      _ => status,
    };

Color posSaleOrderStatusColor(String status) => switch (status) {
      'Completed' => Colors.green,
      'Cancelled' => Colors.grey,
      _ => Colors.orange,
    };

Widget posSaleOrderStatusChip(String status) {
  final color = posSaleOrderStatusColor(status);
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Text(
      posSaleOrderStatusLabel(status),
      style: TextStyle(
        fontSize: 11,
        color: color is MaterialColor ? color.shade700 : color,
        fontWeight: FontWeight.w600,
      ),
    ),
  );
}

Widget saleFilterSection(String title, Widget content) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: PosTheme.textSecondary,
          ),
        ),
        const SizedBox(height: 8),
        content,
        const SizedBox(height: 16),
      ],
    );
