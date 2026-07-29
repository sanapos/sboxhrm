import 'package:flutter/material.dart';

import '../../utils/pos_doc_status.dart';
import 'pos_theme.dart';
import '../../l10n/app_tr.dart';
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
      'Cancelled' => Colors.red,
      _ => Colors.orange,
    };

bool posSaleOrderIsCancelled(String status) => status == 'Cancelled';

Color posSaleOrderAccentColor(String status, {Color fallback = PosTheme.kiotBlue}) =>
    posSaleOrderIsCancelled(status) ? Colors.red.shade700 : fallback;

Color posSaleOrderRowBackground(String status) =>
    posSaleOrderIsCancelled(status)
        ? Colors.red.shade50.withValues(alpha: 0.55)
        : Colors.white;

TextStyle? posSaleOrderCancelledTextStyle(String status, {TextStyle? base}) {
  if (!posSaleOrderIsCancelled(status)) return base;
  return (base ?? const TextStyle()).copyWith(
    color: Colors.red.shade800,
    decoration: TextDecoration.lineThrough,
    decorationColor: Colors.red.shade400,
  );
}

Widget posSaleOrderStatusChip(String status, {String? returnStatus}) {
  final returnLabel = posSaleReturnStatusLabel(returnStatus);
  return Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      posDocStatusChip(status, completedLabel: 'Hoàn thành'),
      if (returnLabel != null) ...[
        const SizedBox(width: 4),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: Colors.orange.shade50,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            tr(returnLabel),
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
          tr(title),
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
