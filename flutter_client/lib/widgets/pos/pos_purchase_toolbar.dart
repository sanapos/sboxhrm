import 'package:flutter/material.dart';

import 'pos_theme.dart';

/// Sidebar lọc kiểu KiotViet cho màn nhập/trả hàng NCC.
class PosPurchaseFilterPanel extends StatelessWidget {
  const PosPurchaseFilterPanel({
    super.key,
    required this.child,
    this.width = 240,
  });

  final Widget child;
  final double width;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(right: BorderSide(color: Colors.grey.shade200)),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(12),
        child: child,
      ),
    );
  }
}

Widget purchaseFilterSection(String title, Widget content) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(title,
            style: const TextStyle(
                fontSize: 12, fontWeight: FontWeight.w600, color: PosTheme.textSecondary)),
        const SizedBox(height: 8),
        content,
        const SizedBox(height: 16),
      ],
    );

Widget purchaseStatusChip(String status, {String completedLabel = 'Đã nhập hàng'}) {
  final color = switch (status) {
    'Completed' => Colors.green,
    'Cancelled' => Colors.grey,
    _ => Colors.orange,
  };
  final label = switch (status) {
    'Completed' => completedLabel,
    'Cancelled' => 'Đã hủy',
    'Draft' => 'Phiếu tạm',
    _ => status,
  };
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Text(label,
        style: TextStyle(
            fontSize: 11,
            color: color is MaterialColor ? color.shade700 : color,
            fontWeight: FontWeight.w600)),
  );
}
