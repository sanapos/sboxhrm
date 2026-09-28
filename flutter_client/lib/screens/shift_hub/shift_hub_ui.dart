import 'package:flutter/material.dart';
import 'package:zkteco_flutter_client/l10n/app_tr.dart';

import '../../theme/sbox_tokens.dart';

/// Tiện ích giao diện Trung tâm ca làm việc.
class ShiftUi {
  ShiftUi._();

  static const _palette = [
    Color(0xFF158DC0),
    Color(0xFFF59E0B),
    Color(0xFF7C3AED),
    Color(0xFF10B981),
    Color(0xFFEF4444),
    Color(0xFF0EA5E9),
    Color(0xFFEC4899),
    Color(0xFF64748B),
  ];

  static Color shiftColor(int index) => _palette[index % _palette.length];

  static const weekdays = ['T2', 'T3', 'T4', 'T5', 'T6', 'T7', 'CN'];
  static const weekdaysLong = ['Thứ Hai', 'Thứ Ba', 'Thứ Tư', 'Thứ Năm', 'Thứ Sáu', 'Thứ Bảy', 'Chủ Nhật'];

  static DateTime monday(DateTime d) => DateTime(d.year, d.month, d.day).subtract(Duration(days: d.weekday - 1));
  static String key(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  static DateTime? parse(dynamic v) => v == null ? null : DateTime.tryParse(v.toString());
  static String dm(DateTime d) => '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}';
  static String dmy(DateTime d) => '${dm(d)}/${d.year}';
  static String weekLabel(DateTime mon) {
    final sun = mon.add(const Duration(days: 6));
    return '${dm(mon)} – ${dmy(sun)}';
  }

  static num n(dynamic v) => v is num ? v : num.tryParse('$v') ?? 0;

  static const leaveTypes = <String, String>{
    'AnnualLeave': 'Phép năm',
    'PersonalPaid': 'Việc riêng có lương',
    'PersonalUnpaid': 'Việc riêng không lương',
    'SickLeave': 'Nghỉ ốm',
    'CompensatoryLeave': 'Nghỉ bù',
    'MaternityLeave': 'Thai sản',
    'Holiday': 'Nghỉ lễ',
    'LongTermLeave': 'Nghỉ dài hạn',
  };

  static const statusLabels = <String, String>{
    'Pending': 'Chờ duyệt',
    'Approved': 'Đã duyệt',
    'Rejected': 'Từ chối',
    'Cancelled': 'Đã huỷ',
    'TargetAccepted': 'Chờ quản lý duyệt',
    'RejectedByTarget': 'Đồng nghiệp từ chối',
    'RejectedByManager': 'Quản lý từ chối',
  };

  static Color statusColor(String? s) => switch (s) {
        'Approved' => SboxColors.success,
        'Rejected' || 'RejectedByTarget' || 'RejectedByManager' => SboxColors.danger,
        'Cancelled' => SboxColors.slate400,
        'TargetAccepted' => SboxColors.violet,
        _ => SboxColors.warning,
      };

  /// Trạng thái định mức: none / short / tight / ok / full / over.
  static Color coverageColor(String? s) => switch (s) {
        'short' => SboxColors.danger,
        'tight' => SboxColors.warning,
        'full' => SboxColors.brand600,
        'over' => SboxColors.violet,
        'ok' => SboxColors.success,
        _ => SboxColors.slate400,
      };

  static String coverageLabel(String? s) => switch (s) {
        'short' => 'Thiếu người',
        'tight' => 'Sát định mức',
        'full' => 'Đủ chỗ',
        'over' => 'Vượt định mức',
        'ok' => 'Đạt',
        _ => 'Chưa đặt định mức',
      };

  static Widget pill(String text, Color color, {IconData? icon, bool solid = false}) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(
          color: solid ? color : color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(99),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (icon != null) ...[Icon(icon, size: 11, color: solid ? Colors.white : color), const SizedBox(width: 3)],
          Text(tr(text),
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: solid ? Colors.white : color)),
        ]),
      );

  static Widget statusPill(String? s) => pill(statusLabels[s] ?? s ?? '', statusColor(s));

  static Widget sectionTitle(String t, {IconData? icon, Widget? trailing}) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(children: [
          if (icon != null) ...[Icon(icon, size: 18, color: SboxColors.brand600), const SizedBox(width: 8)],
          Expanded(
            child: Text(tr(t), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: SboxColors.slate900)),
          ),
          if (trailing != null) trailing,
        ]),
      );

  /// Thanh chọn tuần: ← [dd/MM – dd/MM/yyyy] → + nút «Tuần này».
  static Widget weekNav({
    required DateTime monday,
    required VoidCallback onPrev,
    required VoidCallback onNext,
    required VoidCallback onToday,
    required VoidCallback onPick,
  }) {
    final isThisWeek = key(monday) == key(ShiftUi.monday(DateTime.now()));
    return Row(mainAxisSize: MainAxisSize.min, children: [
      IconButton.outlined(onPressed: onPrev, icon: const Icon(Icons.chevron_left_rounded), visualDensity: VisualDensity.compact),
      TextButton.icon(
        onPressed: onPick,
        icon: const Icon(Icons.calendar_month_rounded, size: 18),
        label: Text(weekLabel(monday), style: const TextStyle(fontWeight: FontWeight.w700)),
      ),
      IconButton.outlined(onPressed: onNext, icon: const Icon(Icons.chevron_right_rounded), visualDensity: VisualDensity.compact),
      if (!isThisWeek) ...[
        const SizedBox(width: 4),
        TextButton(onPressed: onToday, child: Text(tr('Tuần này'))),
      ],
    ]);
  }

  static Widget stat(String label, String value, IconData icon, Color color, {VoidCallback? onTap}) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: SboxColors.slate200),
          ),
          child: Row(children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
              child: Icon(icon, color: color, size: 18),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(tr(label), maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11.5, color: SboxColors.slate500)),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: SboxColors.slate900)),
                ),
              ]),
            ),
          ]),
        ),
      );

  static Widget statGrid(List<Widget> items, {double minWidth = 170}) => LayoutBuilder(builder: (context, c) {
        final cols = (c.maxWidth / minWidth).floor().clamp(2, 6);
        final w = (c.maxWidth - (cols - 1) * 10) / cols;
        return Wrap(spacing: 10, runSpacing: 10, children: [for (final i in items) SizedBox(width: w, child: i)]);
      });

  static Future<String?> askText(BuildContext context, String title, {String? hint, bool required = false}) async {
    final ctl = TextEditingController();
    final r = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr(title)),
        content: SizedBox(
          width: 420,
          child: TextField(
            controller: ctl,
            autofocus: true,
            minLines: 2,
            maxLines: 4,
            decoration: InputDecoration(hintText: hint == null ? null : tr(hint), border: const OutlineInputBorder()),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr('Huỷ'))),
          FilledButton(
            onPressed: () {
              if (required && ctl.text.trim().isEmpty) return;
              Navigator.pop(ctx, ctl.text.trim());
            },
            child: Text(tr('Xác nhận')),
          ),
        ],
      ),
    );
    ctl.dispose();
    return r;
  }
}
