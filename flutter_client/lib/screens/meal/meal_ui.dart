import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:zkteco_flutter_client/l10n/app_tr.dart';

import '../../theme/sbox_tokens.dart';

/// Tiện ích giao diện dùng chung cho các màn chấm cơm / căn tin.
class MealUi {
  MealUi._();

  static const _weekdays = ['Thứ Hai', 'Thứ Ba', 'Thứ Tư', 'Thứ Năm', 'Thứ Sáu', 'Thứ Bảy', 'Chủ Nhật'];
  static final _money = NumberFormat('#,##0', 'vi_VN');

  static String weekday(DateTime d) => _weekdays[d.weekday - 1];
  static String dateLong(DateTime d) => '${weekday(d)}, ${DateFormat('dd/MM/yyyy').format(d)}';
  static String money(num? v) => '${_money.format(v ?? 0)}đ';
  static String time(DateTime d) => DateFormat('HH:mm').format(d);
  static String ymd(DateTime d) => DateFormat('yyyy-MM-dd').format(d);
  static bool sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

  static num n(dynamic v) => v is num ? v : num.tryParse('$v') ?? 0;

  /// Biểu tượng theo tên buổi ăn.
  static IconData sessionIcon(String name) {
    final s = name.toLowerCase();
    if (s.contains('sáng')) return Icons.free_breakfast_rounded;
    if (s.contains('trưa')) return Icons.lunch_dining_rounded;
    if (s.contains('chiều') || s.contains('tối')) return Icons.dinner_dining_rounded;
    if (s.contains('đêm') || s.contains('khuya')) return Icons.nightlight_round;
    return Icons.restaurant_rounded;
  }

  /// Biểu tượng theo nhóm món.
  static IconData dishIcon(String? category) {
    final c = (category ?? '').toLowerCase();
    if (c.contains('canh') || c.contains('súp')) return Icons.soup_kitchen_rounded;
    if (c.contains('rau') || c.contains('chay')) return Icons.eco_rounded;
    if (c.contains('tráng') || c.contains('trái') || c.contains('hoa quả')) return Icons.icecream_rounded;
    if (c.contains('cơm') || c.contains('tinh bột')) return Icons.rice_bowl_rounded;
    if (c.contains('uống') || c.contains('nước')) return Icons.local_drink_rounded;
    return Icons.set_meal_rounded;
  }

  /// Nhãn trạng thái buổi ăn: open / upcoming / closed.
  static Widget phaseChip(String phase) {
    final (label, color) = switch (phase) {
      'open' => ('Đang phục vụ', SboxColors.success),
      'upcoming' => ('Sắp tới', SboxColors.brand600),
      _ => ('Đã qua', SboxColors.slate500),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(99)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (phase == 'open')
          Container(
            width: 7,
            height: 7,
            margin: const EdgeInsets.only(right: 5),
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
        Text(tr(label), style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: color)),
      ]),
    );
  }

  /// Thẻ khung trắng bo góc dùng chung.
  static Widget card({required Widget child, EdgeInsets padding = const EdgeInsets.all(16), Color? color}) =>
      Container(
        padding: padding,
        decoration: BoxDecoration(
          color: color ?? Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: SboxColors.slate200),
        ),
        child: child,
      );

  static Widget sectionTitle(String title, {IconData? icon, Widget? trailing}) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(children: [
          if (icon != null) ...[Icon(icon, size: 18, color: SboxColors.brand600), const SizedBox(width: 8)],
          Expanded(
            child: Text(tr(title),
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: SboxColors.slate900)),
          ),
          if (trailing != null) trailing,
        ]),
      );

  /// Ô số liệu nhỏ: nhãn + giá trị lớn.
  static Widget stat(String label, String value, {IconData? icon, Color color = SboxColors.brand600, String? note}) =>
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: SboxColors.slate200),
        ),
        child: Row(children: [
          if (icon != null) ...[
            Container(
              padding: const EdgeInsets.all(9),
              decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(tr(label), maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, color: SboxColors.slate500)),
              const SizedBox(height: 2),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(value,
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: SboxColors.slate900)),
              ),
              if (note != null)
                Text(tr(note), maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11, color: SboxColors.slate400)),
            ]),
          ),
        ]),
      );

  /// Lưới ô số liệu tự chia cột theo bề rộng.
  static Widget statGrid(List<Widget> items, {double minWidth = 180}) => LayoutBuilder(builder: (context, c) {
        final cols = (c.maxWidth / minWidth).floor().clamp(2, items.length.clamp(2, 6));
        final w = (c.maxWidth - (cols - 1) * 10) / cols;
        return Wrap(spacing: 10, runSpacing: 10, children: [for (final i in items) SizedBox(width: w, child: i)]);
      });
}
