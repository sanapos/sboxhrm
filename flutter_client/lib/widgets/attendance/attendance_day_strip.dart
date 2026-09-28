import 'package:flutter/material.dart';
import 'package:zkteco_flutter_client/l10n/app_tr.dart';

import '../../theme/sbox_tokens.dart';

/// Trạng thái 1 ngày công trên lịch mini.
enum AttendanceDayState { full, partial, late, absent, off, future, none }

/// Chỉ đếm ngày đã qua (≤ hôm nay), không phải ngày nghỉ tuần — dùng làm «công chuẩn đến hôm nay».
/// Trước đây đếm cả những ngày chưa tới nên xem tháng hiện tại luôn thấy thiếu công.
int expectedWorkDaysSoFar(Iterable<DateTime> dates, bool Function(DateTime d) isOff) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  return dates.where((d) => !DateTime(d.year, d.month, d.day).isAfter(today) && !isOff(d)).length;
}

/// Lịch mini theo tuần (T2 → CN): mỗi ô 1 ngày, màu theo trạng thái công.
/// Nhìn nhanh ngày đủ công / thiếu / đi muộn / vắng / nghỉ ngay trên thẻ nhân viên (điện thoại).
class AttendanceDayStrip extends StatelessWidget {
  const AttendanceDayStrip({super.key, required this.days, this.showLegend = false, this.maxDays = 42});

  final List<(DateTime, AttendanceDayState)> days;
  final bool showLegend;
  final int maxDays;

  static Color colorOf(AttendanceDayState s) => switch (s) {
        AttendanceDayState.full => SboxColors.success,
        AttendanceDayState.partial => const Color(0xFF86EFAC),
        AttendanceDayState.late => SboxColors.warning,
        AttendanceDayState.absent => SboxColors.danger,
        AttendanceDayState.off => SboxColors.slate200,
        AttendanceDayState.future => Colors.transparent,
        AttendanceDayState.none => SboxColors.slate100,
      };

  static String labelOf(AttendanceDayState s) => switch (s) {
        AttendanceDayState.full => 'Đủ công',
        AttendanceDayState.partial => 'Thiếu giờ',
        AttendanceDayState.late => 'Muộn / sớm',
        AttendanceDayState.absent => 'Vắng',
        AttendanceDayState.off => 'Nghỉ',
        AttendanceDayState.future => 'Chưa tới',
        AttendanceDayState.none => 'Không có ca',
      };

  @override
  Widget build(BuildContext context) {
    if (days.isEmpty || days.length > maxDays) return const SizedBox.shrink();
    final sorted = [...days]..sort((a, b) => a.$1.compareTo(b.$1));
    final lead = sorted.first.$1.weekday - 1; // ô trống đầu để thẳng cột thứ
    final cells = <Widget>[
      for (var i = 0; i < lead; i++) const SizedBox.shrink(),
      for (final (d, s) in sorted) _cell(d, s),
    ];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        for (final w in const ['T2', 'T3', 'T4', 'T5', 'T6', 'T7', 'CN'])
          Expanded(
            child: Text(w,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.w700, color: SboxColors.slate400)),
          ),
      ]),
      const SizedBox(height: 3),
      GridView.count(
        crossAxisCount: 7,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 3,
        crossAxisSpacing: 3,
        childAspectRatio: 1.35,
        children: cells,
      ),
      if (showLegend) ...[
        const SizedBox(height: 6),
        Wrap(spacing: 10, runSpacing: 4, children: [
          for (final s in const [
            AttendanceDayState.full,
            AttendanceDayState.partial,
            AttendanceDayState.late,
            AttendanceDayState.absent,
            AttendanceDayState.off,
          ])
            Row(mainAxisSize: MainAxisSize.min, children: [
              Container(
                width: 9,
                height: 9,
                decoration: BoxDecoration(color: colorOf(s), borderRadius: BorderRadius.circular(2)),
              ),
              const SizedBox(width: 3),
              Text(tr(labelOf(s)), style: const TextStyle(fontSize: 10, color: SboxColors.slate500)),
            ]),
        ]),
      ],
    ]);
  }

  Widget _cell(DateTime d, AttendanceDayState s) {
    final c = colorOf(s);
    final dark = s == AttendanceDayState.full || s == AttendanceDayState.absent || s == AttendanceDayState.late;
    return Tooltip(
      message: '${d.day}/${d.month}: ${tr(labelOf(s))}',
      child: Container(
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: c,
          borderRadius: BorderRadius.circular(4),
          border: s == AttendanceDayState.future ? Border.all(color: SboxColors.slate200) : null,
        ),
        child: Text('${d.day}',
            style: TextStyle(
                fontSize: 9.5,
                fontWeight: FontWeight.w700,
                color: dark ? Colors.white : SboxColors.slate500)),
      ),
    );
  }
}
