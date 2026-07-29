import 'package:flutter/material.dart';
import 'package:zkteco_flutter_client/l10n/app_tr.dart';

/// Chuẩn hóa trạng thái phiếu POS từ API (enum string, số, hoặc lowercase).
String normalizePosDocStatus(dynamic raw, {String fallback = 'Draft'}) {
  if (raw == null) return fallback;
  if (raw is num) {
    return switch (raw.toInt()) {
      1 => _completedLike(fallback),
      2 => 'Cancelled',
      _ => fallback,
    };
  }
  final s = raw.toString().trim();
  if (s.isEmpty) return fallback;
  if (RegExp(r'^\d+$').hasMatch(s)) {
    return normalizePosDocStatus(int.parse(s), fallback: fallback);
  }
  final lower = s.toLowerCase();
  return switch (lower) {
    'draft' || 'inprogress' || 'in_progress' => fallback == 'InProgress'
        ? 'InProgress'
        : 'Draft',
    'completed' || 'complete' => 'Completed',
    'cancelled' || 'canceled' || 'cancel' => 'Cancelled',
    _ => s,
  };
}

String _completedLike(String fallback) =>
    fallback == 'InProgress' ? 'Completed' : 'Completed';

String posDocStatusLabel(String status, {String completedLabel = 'Hoàn thành'}) =>
    switch (status) {
      'Completed' => completedLabel,
      'Cancelled' => 'Đã hủy',
      'Draft' => 'Phiếu tạm',
      'InProgress' => 'Đang kiểm',
      _ => status,
    };

Color posDocStatusColor(String status) => switch (status) {
      'Completed' => Colors.green,
      'Cancelled' => Colors.red,
      'InProgress' => Colors.blue,
      _ => Colors.orange,
    };

TextStyle posDocCancelledTextStyle({double fontSize = 13}) => TextStyle(
      fontSize: fontSize,
      color: Colors.red.shade700,
      decoration: TextDecoration.lineThrough,
      decorationColor: Colors.red.shade400,
    );

TextStyle posDocNoTextStyle(
  String status, {
  Color activeColor = const Color(0xFF2563EB),
  double fontSize = 13,
  FontWeight fontWeight = FontWeight.w600,
}) {
  if (status == 'Cancelled') {
    return posDocCancelledTextStyle(fontSize: fontSize)
        .copyWith(fontWeight: fontWeight);
  }
  if (status == 'Draft' || status == 'InProgress') {
    return TextStyle(
      fontSize: fontSize,
      fontWeight: fontWeight,
      color: Colors.orange.shade800,
    );
  }
  return TextStyle(
    fontSize: fontSize,
    fontWeight: fontWeight,
    color: activeColor,
  );
}

Color? posDocRowBackground(String status) => switch (status) {
      'Cancelled' => const Color(0xFFF8FAFC),
      'Draft' || 'InProgress' => const Color(0xFFFFF7ED),
      _ => null,
    };

/// Banner trên editor phiếu tạm / đã hủy.
Widget? posDocStatusBanner(String status, {String completedLabel = 'Hoàn thành'}) {
  if (status == 'Draft') {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.orange.shade50,
        border: Border(
          bottom: BorderSide(color: Colors.orange.shade200),
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.edit_note, size: 18, color: Colors.orange.shade800),
          const SizedBox(width: 8),
          Expanded(
            child: Text(tr('Phiếu tạm — chưa ảnh hưởng tồn kho'),
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Colors.orange.shade900,
              ),
            ),
          ),
        ],
      ),
    );
  }
  if (status == 'InProgress') {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        border: Border(bottom: BorderSide(color: Colors.blue.shade200)),
      ),
      child: Row(
        children: [
          Icon(Icons.fact_check_outlined, size: 18, color: Colors.blue.shade800),
          const SizedBox(width: 8),
          Expanded(
            child: Text(tr('Đang kiểm kê — chưa cân bằng kho'),
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Colors.blue.shade900,
              ),
            ),
          ),
        ],
      ),
    );
  }
  if (status == 'Cancelled') {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        border: Border(bottom: BorderSide(color: Colors.red.shade200)),
      ),
      child: Row(
        children: [
          Icon(Icons.cancel_outlined, size: 18, color: Colors.red.shade800),
          const SizedBox(width: 8),
          Expanded(
            child: Text(tr('Phiếu đã hủy · ${posDocStatusLabel(status, completedLabel: completedLabel)}'),
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Colors.red.shade900,
              ),
            ),
          ),
        ],
      ),
    );
  }
  return null;
}

/// Chip trạng thái thống nhất cho mọi chứng từ POS (bán, nhập, xuất, kiểm kho).
Widget posDocStatusChip(String status, {String completedLabel = 'Hoàn thành'}) {
  final color = posDocStatusColor(status);
  final label = posDocStatusLabel(status, completedLabel: completedLabel);
  final isCancelled = status == 'Cancelled';
  final isDraft = status == 'Draft' || status == 'InProgress';
  return Container(
    padding: EdgeInsets.fromLTRB(isCancelled ? 6 : 8, 2, 8, 2),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(12),
      border: isCancelled
          ? Border.all(color: Colors.red.shade200, width: 1)
          : isDraft
              ? Border.all(color: Colors.orange.shade200, width: 1)
              : null,
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (isCancelled) ...[
          Icon(Icons.cancel, size: 13, color: Colors.red.shade700),
          const SizedBox(width: 3),
        ] else if (isDraft) ...[
          Icon(Icons.schedule, size: 13, color: Colors.orange.shade800),
          const SizedBox(width: 3),
        ],
        Text(
          tr(label),
          style: TextStyle(
            fontSize: 11,
            color: color is MaterialColor ? color.shade700 : color,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    ),
  );
}
