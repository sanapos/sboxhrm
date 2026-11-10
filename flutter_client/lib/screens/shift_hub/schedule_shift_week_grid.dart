import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:zkteco_flutter_client/l10n/app_tr.dart';

import '../../theme/sbox_tokens.dart';
import 'schedule_board_data.dart';
import 'shift_hub_ui.dart';

/// Bảng tuần theo ca: hàng = ca mẫu, cột = 7 ngày. Ô = số người / định mức (màu theo độ phủ)
/// + tên người đã xếp (máy tính). Chạm ô: chọn nhân viên cho ca ngày đó; chạm đầu ngày: xem ngày.
/// Thay cho tab «Theo ca» của màn Lịch làm việc cũ.
class ScheduleShiftWeekGrid extends StatelessWidget {
  const ScheduleShiftWeekGrid({
    super.key,
    required this.data,
    required this.compact,
    required this.onCell,
    required this.onDay,
  });

  final BoardData data;
  final bool compact;
  final void Function(String day, Map<String, dynamic> tpl) onCell;
  final void Function(String day) onDay;

  @override
  Widget build(BuildContext context) {
    final days = data.days;
    final tpls = data.templates;
    return LayoutBuilder(builder: (context, c) {
      final inner = c.maxWidth - 2;
      final labelW = compact ? 74.0 : 170.0;
      final minDay = compact ? 40.0 : 120.0;
      final dayW = days.isEmpty ? minDay : math.max(minDay, (inner - labelW) / days.length);
      final width = labelW + dayW * days.length;
      final rowH = compact ? 56.0 : 96.0;
      final today = data.today;

      Widget dayHead(String d) {
        final dt = BoardData.date(d);
        final isToday = d == today;
        return InkWell(
          onTap: () => onDay(d),
          child: Container(
            width: dayW,
            padding: const EdgeInsets.symmetric(vertical: 6),
            color: isToday ? SboxColors.brand50 : SboxColors.slate50,
            child: Column(children: [
              Text(ShiftUi.weekdays[dt.weekday - 1],
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: isToday ? SboxColors.brand700 : SboxColors.slate500)),
              Text(compact ? '${dt.day}' : ShiftUi.dm(dt),
                  style: TextStyle(fontWeight: FontWeight.w800, color: isToday ? SboxColors.brand700 : SboxColors.slate800)),
            ]),
          ),
        );
      }

      final table = SizedBox(
        width: math.max(width, inner),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Container(
              width: labelW,
              height: 44,
              alignment: Alignment.centerLeft,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              color: SboxColors.slate50,
              child: Text(tr('Ca / Ngày'), style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: SboxColors.slate600)),
            ),
            for (final d in days) dayHead(d),
          ]),
          for (final t in tpls)
            Container(
              height: rowH,
              decoration: const BoxDecoration(border: Border(top: BorderSide(color: SboxColors.slate100))),
              child: Row(children: [
                SizedBox(width: labelW, child: _label(t)),
                for (final d in days) SizedBox(width: dayW, child: _cell(d, t)),
              ]),
            ),
        ]),
      );

      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Container(
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: SboxColors.slate200)),
          clipBehavior: Clip.antiAlias,
          child: tpls.isEmpty
              ? Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(tr('Chưa có ca mẫu — vào Thiết lập → Ca mẫu để tạo ca'),
                      textAlign: TextAlign.center, style: const TextStyle(color: SboxColors.slate500)),
                )
              : SingleChildScrollView(scrollDirection: Axis.horizontal, child: table),
        ),
        const SizedBox(height: 6),
        Text(tr('Chạm ô để chọn nhân viên cho ca ngày đó · Chạm ngày để xem bảng từng ngày'),
            style: const TextStyle(fontSize: 11, color: SboxColors.slate500)),
      ]);
    });
  }

  Widget _label(Map<String, dynamic> t) {
    final color = ShiftUi.shiftColor(ShiftUi.n(t['colorIndex']).toInt());
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(children: [
        Container(width: 4, height: 30, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3))),
        const SizedBox(width: 6),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
            Text(t['name'].toString(), maxLines: compact ? 2 : 1, overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: compact ? 11 : 12.5, fontWeight: FontWeight.w800)),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text('${t['start']}–${t['end']}', maxLines: 1, style: TextStyle(fontSize: compact ? 9.5 : 11, color: SboxColors.slate500)),
            ),
          ]),
        ),
      ]),
    );
  }

  Widget _cell(String day, Map<String, dynamic> t) {
    final tid = t['id'].toString();
    final cv = data.cov(day, tid);
    final status = cv?['status']?.toString();
    final color = cv?['hasQuota'] == true ? ShiftUi.coverageColor(status) : ShiftUi.shiftColor(ShiftUi.n(t['colorIndex']).toInt());
    final names = data.employeesIn(day, tid).map((e) => _shortName(e['name']?.toString() ?? '')).toList();
    final eff = cv == null ? names.length : ShiftUi.n(cv['effective']).toInt();
    final min = ShiftUi.n(cv?['min']).toInt(), max = ShiftUi.n(cv?['max']).toInt();
    final pending = ShiftUi.n(cv?['pending']).toInt();
    final past = today != null && day.compareTo(today!) < 0;
    final empty = eff == 0 && pending == 0;
    return InkWell(
      onTap: () => onCell(day, t),
      child: Container(
        margin: const EdgeInsets.all(3),
        padding: EdgeInsets.symmetric(horizontal: compact ? 2 : 6, vertical: 4),
        decoration: BoxDecoration(
          color: empty ? (past ? null : SboxColors.slate50) : color.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: status == 'short' ? SboxColors.danger : (empty ? SboxColors.slate200 : color.withValues(alpha: 0.5))),
        ),
        child: empty && !past
            ? const Center(child: Icon(Icons.group_add_rounded, size: 16, color: SboxColors.slate300))
            : Column(
                crossAxisAlignment: compact ? CrossAxisAlignment.center : CrossAxisAlignment.start,
                mainAxisAlignment: compact ? MainAxisAlignment.center : MainAxisAlignment.start,
                children: [
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      cv?['hasQuota'] == true ? '$eff/${min == max ? '$min' : '$min–$max'}' : '$eff',
                      style: TextStyle(fontSize: compact ? 13 : 13.5, fontWeight: FontWeight.w800, color: color),
                    ),
                  ),
                  if (pending > 0) Text(tr('+$pending chờ'), style: const TextStyle(fontSize: 10, color: SboxColors.warning)),
                  if (!compact && names.isNotEmpty)
                    Expanded(
                      child: Text(
                        names.length <= 4 ? names.join(', ') : '${names.take(4).join(', ')} +${names.length - 4}',
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 11, color: SboxColors.slate700, height: 1.25),
                      ),
                    ),
                ],
              ),
      ),
    );
  }

  String? get today => data.today;

  static String _shortName(String full) {
    final p = full.trim().split(RegExp(r'\s+'));
    return p.length >= 2 ? p.sublist(p.length - (p.length >= 3 ? 2 : 1)).join(' ') : full;
  }
}
