import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:zkteco_flutter_client/l10n/app_tr.dart';

import '../../theme/sbox_tokens.dart';

/// Nhãn / màu / biểu tượng dùng chung cho kiến nghị – khiếu nại.
class FeedbackUi {
  FeedbackUi._();

  static const categories = <String, String>{
    'Complaint': 'Khiếu nại',
    'Suggestion': 'Kiến nghị / đề xuất',
    'General': 'Góp ý chung',
    'Other': 'Khác',
  };

  static const categoryHints = <String, String>{
    'Complaint': 'Quyền lợi bị ảnh hưởng, cần xem xét và trả lời',
    'Suggestion': 'Đề xuất thay đổi, cải tiến',
    'General': 'Ý kiến, góp ý, câu hỏi chung',
    'Other': 'Nội dung khác',
  };

  static const topics = <String>[
    'Lương thưởng',
    'Chế độ phúc lợi',
    'Môi trường làm việc',
    'An toàn lao động',
    'Ứng xử / quan hệ',
    'Cơ sở vật chất',
    'Quy trình / chính sách',
    'Ca làm / chấm công',
    'Khác',
  ];

  static const statuses = <String, String>{
    'Pending': 'Chờ tiếp nhận',
    'InProgress': 'Đang xử lý',
    'Resolved': 'Đã giải quyết',
    'Closed': 'Đã đóng',
  };

  static const priorities = <int, String>{3: 'Khẩn cấp', 2: 'Cao', 1: 'Bình thường', 0: 'Thấp'};

  static IconData categoryIcon(String? c) => switch (c) {
        'Complaint' => Icons.report_gmailerrorred_rounded,
        'Suggestion' => Icons.lightbulb_rounded,
        'General' => Icons.forum_rounded,
        _ => Icons.more_horiz_rounded,
      };

  static Color categoryColor(String? c) => switch (c) {
        'Complaint' => SboxColors.danger,
        'Suggestion' => SboxColors.warning,
        'General' => SboxColors.brand600,
        _ => SboxColors.slate500,
      };

  static Color statusColor(String? s) => switch (s) {
        'Pending' => SboxColors.warning,
        'InProgress' => SboxColors.brand600,
        'Resolved' => SboxColors.success,
        _ => SboxColors.slate500,
      };

  static IconData statusIcon(String? s) => switch (s) {
        'Pending' => Icons.mark_email_unread_rounded,
        'InProgress' => Icons.autorenew_rounded,
        'Resolved' => Icons.task_alt_rounded,
        _ => Icons.lock_rounded,
      };

  static Color priorityColor(int p) => switch (p) {
        3 => SboxColors.danger,
        2 => SboxColors.warning,
        0 => SboxColors.slate400,
        _ => SboxColors.brand500,
      };

  static int n(dynamic v) => v is num ? v.toInt() : int.tryParse('$v') ?? 0;
  static DateTime? date(dynamic v) => v == null ? null : DateTime.tryParse(v.toString())?.toLocal();
  static bool isOpen(String? s) => s == 'Pending' || s == 'InProgress';

  static String ago(DateTime? d) {
    if (d == null) return '';
    final diff = DateTime.now().difference(d);
    if (diff.inMinutes < 1) return 'vừa xong';
    if (diff.inMinutes < 60) return '${diff.inMinutes} phút trước';
    if (diff.inHours < 24) return '${diff.inHours} giờ trước';
    if (diff.inDays < 7) return '${diff.inDays} ngày trước';
    return DateFormat('dd/MM/yyyy').format(d);
  }

  /// «Còn 5 giờ» / «Quá hạn 2 ngày».
  static String dueText(DateTime? due) {
    if (due == null) return '';
    final diff = due.difference(DateTime.now());
    String fmt(Duration d) {
      final a = d.abs();
      if (a.inDays >= 1) return '${a.inDays} ngày';
      if (a.inHours >= 1) return '${a.inHours} giờ';
      return '${a.inMinutes.clamp(1, 59)} phút';
    }

    return diff.isNegative ? 'Quá hạn ${fmt(diff)}' : 'Còn ${fmt(diff)}';
  }

  static Widget pill(String text, Color color, {IconData? icon, bool solid = false}) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: solid ? color : color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(99),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: solid ? Colors.white : color),
            const SizedBox(width: 4),
          ],
          Text(tr(text),
              style: TextStyle(
                  fontSize: 11.5, fontWeight: FontWeight.w700, color: solid ? Colors.white : color)),
        ]),
      );

  static Widget statusPill(String? s) =>
      pill(statuses[s] ?? s ?? '', statusColor(s), icon: statusIcon(s));

  static Widget priorityPill(int p) => pill(priorities[p] ?? '', priorityColor(p),
      icon: p >= 2 ? Icons.priority_high_rounded : null, solid: p == 3);

  static Widget duePill(Map<String, dynamic> f) {
    if (!isOpen(f['status']?.toString())) return const SizedBox.shrink();
    final due = date(f['dueAt']);
    if (due == null) return const SizedBox.shrink();
    final overdue = f['overdue'] == true;
    final soon = !overdue && due.difference(DateTime.now()).inHours < 12;
    return pill(dueText(due), overdue ? SboxColors.danger : soon ? SboxColors.warning : SboxColors.slate500,
        icon: Icons.schedule_rounded);
  }

  static Widget stars(int value, {double size = 16, ValueChanged<int>? onTap}) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 1; i <= 5; i++)
            GestureDetector(
              onTap: onTap == null ? null : () => onTap(i),
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: onTap == null ? 0 : 3),
                child: Icon(i <= value ? Icons.star_rounded : Icons.star_outline_rounded,
                    size: size, color: const Color(0xFFF5A524)),
              ),
            ),
        ],
      );
}
