import 'package:excel/excel.dart' as excel_lib;
import 'package:flutter/material.dart';
import 'package:zkteco_flutter_client/l10n/app_tr.dart';

import '../../services/api_service.dart';
import '../../theme/sbox_tokens.dart';
import '../../utils/excel_download_helper.dart';
import '../../utils/excel_report_builder.dart';
import '../../widgets/notification_overlay.dart';
import 'schedule_board_data.dart';
import 'shift_hub_ui.dart';

/// Sao chép lịch giữa các ngày / tuần / tháng và xuất Excel cho Bảng xếp ca
/// (chuyển từ màn «Lịch làm việc (đầy đủ)» cũ).
///
/// Sao chép chỉ điền ô còn trống (không ghi đè lịch đã có, bỏ qua ngày nghỉ phép đã duyệt),
/// gom theo (ca, ngày) để gọi `POST /api/workschedules/bulk` một lần cho nhiều nhân viên.
class ScheduleCopier {
  ScheduleCopier(this.api, {this.department, this.search});
  final ApiService api;
  final String? department;
  final String? search;

  int created = 0, failed = 0, skipped = 0;

  Future<BoardData?> load(DateTime from, DateTime to) async {
    final r = await api.getShiftHubBoard(from: from, to: to, department: department, search: search ?? '');
    if (r['isSuccess'] != true || r['data'] is! Map) return null;
    return BoardData(Map<String, dynamic>.from(r['data'] as Map));
  }

  /// [dateMap]: ngày nguồn → ngày đích (yyyy-MM-dd).
  Future<void> fill(BoardData src, BoardData dst, Map<String, String> dateMap) async {
    final dstById = {for (final e in dst.employees) e['id'].toString(): e};
    final groups = <String, List<String>>{};
    final dayOffs = <(String, String)>[];
    for (final e in src.employees) {
      final id = e['id'].toString();
      final d = dstById[id];
      if (d == null) continue;
      for (final m in dateMap.entries) {
        final items = BoardData.items(BoardData.cell(e, m.key));
        if (items.isEmpty) continue;
        final dc = BoardData.cell(d, m.value);
        if (BoardData.hasSchedule(dc) || BoardData.leaveApproved(dc)) {
          skipped++;
          continue;
        }
        for (final it in items) {
          if (it['isDayOff'] == true) {
            dayOffs.add((id, m.value));
          } else if (it['shiftId'] != null) {
            groups.putIfAbsent('${it['shiftId']}|${m.value}', () => []).add(id);
          }
        }
      }
    }
    for (final g in groups.entries) {
      final p = g.key.split('|');
      final r = await api.bulkCreateWorkSchedules({
        'employeeUserIds': g.value,
        'shiftId': p[0],
        'startDate': p[1],
        'endDate': p[1],
        'workDays': [BoardData.date(p[1]).weekday % 7],
      });
      r['isSuccess'] == true ? created += g.value.length : failed += g.value.length;
    }
    for (final (id, day) in dayOffs) {
      final r = await api.createWorkSchedule({'employeeUserId': id, 'date': day, 'isDayOff': true});
      r['isSuccess'] == true ? created++ : failed++;
    }
  }

  void report(String title) {
    final msg = created == 0 && failed == 0
        ? 'Không có lịch nào để chép${skipped > 0 ? ' (đích đã có lịch: $skipped ô)' : ''}'
        : 'Đã tạo $created lịch${skipped > 0 ? ', bỏ qua $skipped ô đã có lịch / nghỉ phép' : ''}${failed > 0 ? ', $failed lỗi' : ''}';
    failed > 0
        ? NotificationOverlayManager().showError(title: title, message: msg)
        : NotificationOverlayManager().showSuccess(title: title, message: msg);
  }
}

Widget _note(String s) => Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Text(tr(s), style: const TextStyle(fontSize: 12, color: SboxColors.slate500)),
    );

/// Chép lịch tuần trước sang tuần [monday].
Future<bool> copyPreviousWeek(BuildContext context, ScheduleCopier cp, DateTime monday) async {
  final prev = monday.subtract(const Duration(days: 7));
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(tr('Sao chép lịch tuần trước')),
      content: Text(tr('Chép lịch ${ShiftUi.weekLabel(prev)} sang ${ShiftUi.weekLabel(monday)}. '
          'Chỉ điền ngày còn trống, không ghi đè lịch đã có.')),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Huỷ'))),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Sao chép'))),
      ],
    ),
  );
  if (ok != true) return false;
  final src = await cp.load(prev, prev.add(const Duration(days: 6)));
  final dst = await cp.load(monday, monday.add(const Duration(days: 6)));
  if (src == null || dst == null) {
    NotificationOverlayManager().showError(title: 'Sao chép lịch', message: 'Không tải được lịch');
    return false;
  }
  await cp.fill(src, dst, {for (var i = 0; i < 7; i++) ShiftUi.key(prev.add(Duration(days: i))): ShiftUi.key(monday.add(Duration(days: i)))});
  cp.report('Sao chép lịch tuần trước');
  return cp.created > 0;
}

/// Chép lịch một ngày của tuần đang xem sang các ngày khác trong tuần.
Future<bool> copyDay(BuildContext context, ScheduleCopier cp, BoardData week, String initialDay) async {
  final days = week.days;
  var src = days.contains(initialDay) ? initialDay : days.first;
  final targets = <String>{};
  String lbl(String d) => '${ShiftUi.weekdays[BoardData.date(d).weekday - 1]} ${ShiftUi.dm(BoardData.date(d))}';
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, set) => AlertDialog(
        title: Text(tr('Sao chép lịch một ngày')),
        content: SizedBox(
          width: 460,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(tr('Ngày nguồn'), style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final d in days)
                ChoiceChip(
                  label: Text(lbl(d)),
                  selected: src == d,
                  onSelected: (_) => set(() {
                    src = d;
                    targets.remove(d);
                  }),
                ),
            ]),
            const SizedBox(height: 14),
            Text(tr('Chép sang'), style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final d in days.where((d) => d != src))
                FilterChip(
                  label: Text(lbl(d)),
                  selected: targets.contains(d),
                  onSelected: (v) => set(() => v ? targets.add(d) : targets.remove(d)),
                ),
            ]),
            _note('Chỉ điền ô còn trống của nhân viên đang hiển thị; không ghi đè lịch đã có.'),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Huỷ'))),
          FilledButton(onPressed: targets.isEmpty ? null : () => Navigator.pop(ctx, true), child: Text(tr('Sao chép'))),
        ],
      ),
    ),
  );
  if (ok != true) return false;
  // Một nguồn → nhiều đích: chép lần lượt từng ngày đích.
  for (final t in targets) {
    await cp.fill(week, week, {src: t});
  }
  cp.report('Sao chép lịch ngày ${lbl(src)}');
  return cp.created > 0;
}

/// Chép lịch tuần [monday] sang N tuần tiếp theo.
Future<bool> copyWeekForward(BuildContext context, ScheduleCopier cp, BoardData week, DateTime monday) async {
  var n = 1;
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, set) {
        final last = monday.add(Duration(days: 7 * n));
        return AlertDialog(
          title: Text(tr('Sao chép tuần này sang các tuần sau')),
          content: SizedBox(
            width: 440,
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(tr('Tuần nguồn: ${ShiftUi.weekLabel(monday)}')),
              const SizedBox(height: 12),
              Row(children: [
                Text(tr('Số tuần:'), style: const TextStyle(fontWeight: FontWeight.w700)),
                IconButton(onPressed: n > 1 ? () => set(() => n--) : null, icon: const Icon(Icons.remove_circle_outline_rounded)),
                Text('$n', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                IconButton(onPressed: n < 12 ? () => set(() => n++) : null, icon: const Icon(Icons.add_circle_outline_rounded)),
              ]),
              Text(tr('Chép sang ${ShiftUi.dm(monday.add(const Duration(days: 7)))} → ${ShiftUi.weekLabel(last)}'),
                  style: const TextStyle(color: SboxColors.slate600)),
              _note('Chỉ điền ô còn trống; không ghi đè lịch đã có. Tối đa 12 tuần.'),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Huỷ'))),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Sao chép'))),
          ],
        );
      },
    ),
  );
  if (ok != true) return false;
  for (var k = 1; k <= n; k++) {
    final mon = monday.add(Duration(days: 7 * k));
    final dst = await cp.load(mon, mon.add(const Duration(days: 6)));
    if (dst == null) {
      cp.failed++;
      continue;
    }
    await cp.fill(week, dst, {for (var i = 0; i < 7; i++) ShiftUi.key(monday.add(Duration(days: i))): ShiftUi.key(mon.add(Duration(days: i)))});
  }
  cp.report('Sao chép sang $n tuần');
  return cp.created > 0;
}

/// Chép lịch theo ngày trong tháng: ngày 1 → ngày 1… (tháng đích ngắn hơn: bỏ ngày thừa).
Future<bool> copyMonth(BuildContext context, ScheduleCopier cp, DateTime around) async {
  var src = DateTime(around.year, around.month);
  var dst = DateTime(around.year, around.month + 1);
  final months = [for (var i = -6; i <= 12; i++) DateTime(around.year, around.month + i)];
  String lbl(DateTime m) => 'Tháng ${m.month}/${m.year}';
  Widget pick(DateTime v, ValueChanged<DateTime> on) => DropdownButton<DateTime>(
        value: months.firstWhere((m) => m.year == v.year && m.month == v.month),
        items: [for (final m in months) DropdownMenuItem(value: m, child: Text(tr(lbl(m))))],
        onChanged: (m) => m == null ? null : on(m),
      );
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, set) => AlertDialog(
        title: Text(tr('Sao chép lịch tháng')),
        content: SizedBox(
          width: 420,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [SizedBox(width: 90, child: Text(tr('Tháng nguồn'))), pick(src, (m) => set(() => src = m))]),
            Row(children: [SizedBox(width: 90, child: Text(tr('Tháng đích'))), pick(dst, (m) => set(() => dst = m))]),
            _note('Chép theo ngày trong tháng (ngày 1 → ngày 1…); tháng đích ít ngày hơn thì bỏ ngày thừa. '
                'Chỉ điền ô còn trống.'),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Huỷ'))),
          FilledButton(
            onPressed: src.year == dst.year && src.month == dst.month ? null : () => Navigator.pop(ctx, true),
            child: Text(tr('Sao chép')),
          ),
        ],
      ),
    ),
  );
  if (ok != true) return false;
  final srcEnd = DateTime(src.year, src.month + 1, 0), dstEnd = DateTime(dst.year, dst.month + 1, 0);
  final s = await cp.load(src, srcEnd);
  final d = await cp.load(dst, dstEnd);
  if (s == null || d == null) {
    NotificationOverlayManager().showError(title: 'Sao chép lịch tháng', message: 'Không tải được lịch');
    return false;
  }
  final n = srcEnd.day < dstEnd.day ? srcEnd.day : dstEnd.day;
  await cp.fill(s, d, {
    for (var i = 1; i <= n; i++) ShiftUi.key(DateTime(src.year, src.month, i)): ShiftUi.key(DateTime(dst.year, dst.month, i)),
  });
  cp.report('Sao chép ${lbl(src)} → ${lbl(dst)}');
  return cp.created > 0;
}

/// Xuất Excel tuần đang xem: sheet «Theo nhân viên» (NV × ngày) và «Theo ca» (ca × ngày, tên người).
Future<void> exportScheduleExcel(BoardData data, DateTime monday, {String? department}) async {
  try {
    final wb = excel_lib.Excel.createExcel();
    final days = data.days;
    String head(String d) => '${ShiftUi.weekdays[BoardData.date(d).weekday - 1]} ${ShiftUi.dm(BoardData.date(d))}';
    void put(excel_lib.Sheet s, int col, int row, Object v) => s.cell(excel_lib.CellIndex.indexByColumnRow(columnIndex: col, rowIndex: row)).value =
        v is num ? excel_lib.DoubleCellValue(v.toDouble()) : excel_lib.TextCellValue('$v');
    final title = 'Tuần ${ShiftUi.weekLabel(monday)}${department != null ? ' · Bộ phận: $department' : ''}';

    final a = wb['Theo nhân viên'];
    put(a, 0, 0, 'LỊCH LÀM VIỆC THEO NHÂN VIÊN');
    put(a, 0, 1, title);
    put(a, 0, 3, 'Mã NV');
    put(a, 1, 3, 'Nhân viên');
    put(a, 2, 3, 'Bộ phận');
    for (var i = 0; i < days.length; i++) {
      put(a, 3 + i, 3, head(days[i]));
    }
    put(a, 3 + days.length, 3, 'Giờ công');
    var r = 4;
    for (final e in data.employees) {
      put(a, 0, r, e['code'] ?? '');
      put(a, 1, r, e['name'] ?? '');
      put(a, 2, r, e['department'] ?? '');
      for (var i = 0; i < days.length; i++) {
        final c = BoardData.cell(e, days[i]);
        final parts = <String>[
          if (BoardData.leaveApproved(c)) 'Nghỉ phép',
          if (BoardData.dayOffItem(c) != null) 'Nghỉ',
          if (BoardData.shiftItems(c).isNotEmpty) data.shiftNames(c),
        ];
        put(a, 3 + i, r, parts.join(' · '));
      }
      put(a, 3 + days.length, r, ShiftUi.n((e['totals'] as Map?)?['hours']));
      r++;
    }

    final b = wb['Theo ca'];
    put(b, 0, 0, 'LỊCH LÀM VIỆC THEO CA');
    put(b, 0, 1, title);
    put(b, 0, 3, 'Ca làm việc');
    for (var i = 0; i < days.length; i++) {
      put(b, 1 + i, 3, head(days[i]));
    }
    put(b, 1 + days.length, 3, 'Tổng lượt');
    r = 4;
    for (final t in data.templates) {
      put(b, 0, r, '${t['name']} (${t['start']}–${t['end']})');
      var total = 0;
      for (var i = 0; i < days.length; i++) {
        final names = data.employeesIn(days[i], t['id'].toString()).map((e) => e['name']).toList();
        total += names.length;
        put(b, 1 + i, r, names.join(', '));
      }
      put(b, 1 + days.length, r, total);
      r++;
    }
    wb.delete('Sheet1');
    final bytes = ExcelReportBuilder.encodeReport(wb);
    if (bytes == null) throw Exception('Không tạo được file');
    final name = 'LichLamViec_${ShiftUi.key(monday)}.xlsx';
    await ExcelDownloadHelper.saveExcelBytes(bytes, name);
    NotificationOverlayManager().showSuccess(title: 'Xuất Excel', message: 'Đã xuất $name');
  } catch (e) {
    NotificationOverlayManager().showError(title: 'Xuất Excel', message: '$e');
  }
}
