import 'package:flutter/material.dart';

import 'pos_theme.dart';
String posSaleOrderStatusLabel(String status) => switch (status) {
      'Completed' => 'Hoàn thành',
      'Cancelled' => 'Đã hủy',
      'Draft' => 'Đang xử lý',
      _ => status,
    };

String? posSaleReturnStatusLabel(String? returnStatus) => switch (returnStatus) {
      'Full' => 'Trả hết',
      'Partial' => 'Trả một phần',
      _ => null,
    };

Color posSaleOrderStatusColor(String status) => switch (status) {
      'Completed' => Colors.green,
      'Cancelled' => Colors.grey,
      _ => Colors.orange,
    };

Widget posSaleOrderStatusChip(String status, {String? returnStatus}) {
  final color = posSaleOrderStatusColor(status);
  final returnLabel = posSaleReturnStatusLabel(returnStatus);
  return Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
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
      ),
      if (returnLabel != null) ...[
        const SizedBox(width: 4),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: Colors.orange.shade50,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            returnLabel,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: Colors.orange.shade800,
            ),
          ),
        ),
      ],
    ],
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
