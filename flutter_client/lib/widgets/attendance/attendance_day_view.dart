import 'package:flutter/material.dart';
import 'package:zkteco_flutter_client/l10n/app_tr.dart';

import '../../theme/sbox_tokens.dart';
import '../hrm_page_chrome.dart';
import '../sbox/sbox_charts.dart';
import 'attendance_employee_list.dart';

/// Trạng thái một NV trong MỘT ngày — cho chế độ «Theo ngày» (chủ hỏi: hôm nay ai đi, ai vắng, ai trễ).
class AttendanceDayEntry {
  AttendanceDayEntry({
    required this.name,
    this.hourly = false,
    this.punchText = '',
    this.hours = 0,
    this.lateMinutes = 0,
    this.earlyMinutes = 0,
    this.present = false,
    this.working = false,
    this.missing = false,
    this.absent = false,
    this.leave = false,
    this.off = false,
    this.notYet = false,
    this.offLabel = 'Nghỉ',
    this.onTap,
  });

  final String name;
  final bool hourly;

  /// «08:02 – 17:05» (các lần chấm trong ngày).
  final String punchText;
  final double hours;
  final int lateMinutes;
  final int earlyMinutes;

  /// Có chấm trong ngày.
  final bool present;

  /// Hôm nay: đã vào, chưa ra.
  final bool working;

  /// Ngày đã qua: số lần chấm lẻ (quên vào / ra).
  final bool missing;
  final bool absent;
  final bool leave;

  /// Nghỉ tuần / không xếp lịch / ngày lễ.
  final bool off;

  /// Hôm nay chưa chấm (chưa kết luận vắng).
  final bool notYet;
  final String offLabel;
  final VoidCallback? onTap;

  bool get hasIssue => absent || missing || lateMinutes > 0;
}

/// Bộ lọc chip của chế độ «Theo ngày»: khóa → (nhãn, điều kiện, tô đỏ).
const _dayChips = <(String, String, bool)>[
  ('all', 'Tất cả', false),
  ('present', 'Có mặt', false),
  ('working', 'Đang làm', false),
  ('late', 'Đi trễ', true),
  ('early', 'Về sớm', false),
  ('missing', 'Thiếu chấm', false),
  ('absent', 'Vắng', true),
  ('notYet', 'Chưa chấm', false),
  ('leave', 'Nghỉ phép', false),
  ('off', 'Nghỉ / không lịch', false),
];

bool attendanceDayEntryMatches(AttendanceDayEntry e, String key) => switch (key) {
      'present' => e.present,
      'working' => e.working,
      'late' => e.lateMinutes > 0,
      'early' => e.earlyMinutes > 0,
      'missing' => e.missing,
      'absent' => e.absent,
      'notYet' => e.notYet,
      'leave' => e.leave,
      'off' => e.off,
      _ => true,
    };

/// Nút chuyển «Theo nhân viên / Theo ngày».
class AttendanceViewToggle extends StatelessWidget {
  const AttendanceViewToggle({super.key, required this.byDay, required this.onChanged});
  final bool byDay;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<bool>(
      showSelectedIcon: false,
      style: const ButtonStyle(visualDensity: VisualDensity.compact),
      segments: [
        ButtonSegment(value: false, icon: const Icon(Icons.groups_rounded, size: 18), label: Text(tr('Theo nhân viên'))),
        ButtonSegment(value: true, icon: const Icon(Icons.today_rounded, size: 18), label: Text(tr('Theo ngày'))),
      ],
      selected: {byDay},
      onSelectionChanged: (s) => onChanged(s.first),
    );
  }
}

/// Dải chọn ngày + chip trạng thái (đếm NGƯỜI) + danh sách người của ngày đã chọn.
/// [issuesByDay]: số người có vấn đề (vắng / trễ / thiếu chấm) mỗi ngày — chấm đỏ trên dải ngày.
List<Widget> attendanceDayViewSlivers({
  required BuildContext context,
  required List<DateTime> dates,
  required DateTime selectedDay,
  required ValueChanged<DateTime> onDay,
  required Map<DateTime, int> issuesByDay,
  required List<AttendanceDayEntry> entries,
  required String chipKey,
  required ValueChanged<String> onChip,
  required ScrollController dayStripController,
}) {
  const weekdays = ['T2', 'T3', 'T4', 'T5', 'T6', 'T7', 'CN'];
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final counts = {for (final c in _dayChips) c.$1: entries.where((e) => attendanceDayEntryMatches(e, c.$1)).length};
  final key = (counts[chipKey] ?? 0) == 0 ? 'all' : chipKey;
  final shown = entries.where((e) => attendanceDayEntryMatches(e, key)).toList()
    ..sort((a, b) {
      int rank(AttendanceDayEntry e) => e.absent
          ? 0
          : e.missing
              ? 1
              : e.lateMinutes > 0
                  ? 2
                  : e.notYet
                      ? 3
                      : e.present
                          ? 4
                          : 5;
      final c = rank(a).compareTo(rank(b));
      return c != 0 ? c : a.name.compareTo(b.name);
    });

  Widget dayCell(DateTime d) {
    final sel = d == selectedDay;
    final issues = issuesByDay[d] ?? 0;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: Material(
        color: sel ? HrmPageChrome.primaryNavy : Colors.white,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () => onDay(d),
          child: Container(
            width: 46,
            padding: const EdgeInsets.symmetric(vertical: 5),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: sel ? HrmPageChrome.primaryNavy : SboxColors.slate200),
            ),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text(d == today ? tr('Nay') : weekdays[d.weekday - 1],
                  style: TextStyle(fontSize: 10, color: sel ? Colors.white70 : SboxColors.slate500)),
              Text('${d.day}/${d.month}',
                  style: TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w700, color: sel ? Colors.white : SboxColors.slate900)),
              const SizedBox(height: 2),
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: issues > 0 ? SboxColors.danger : Colors.transparent,
                  shape: BoxShape.circle,
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  Widget row(AttendanceDayEntry e) {
    final parts = <AttendanceMetricPart>[
      if (e.punchText.isNotEmpty) AttendanceMetricPart(e.punchText),
      if (e.lateMinutes > 0) AttendanceMetricPart('trễ ${e.lateMinutes} phút', color: SboxColors.warningText),
      if (e.earlyMinutes > 0) AttendanceMetricPart('về sớm ${e.earlyMinutes} phút', color: SboxColors.warningText),
      if (e.missing) AttendanceMetricPart('thiếu chấm', color: SboxColors.warningText),
      if (e.working) AttendanceMetricPart('đang làm', color: SboxColors.successText),
    ];
    final (String primary, Color? color) = e.absent
        ? ('Vắng', SboxColors.danger)
        : e.leave
            ? ('Nghỉ phép', SboxColors.slate600)
            : e.notYet
                ? ('Chưa chấm', SboxColors.warningText)
                : e.off
                    ? (e.offLabel, SboxColors.slate500)
                    : (e.hours > 0 ? '${SboxFmt.number(double.parse(e.hours.toStringAsFixed(1)))} giờ' : '—', null);
    return AttendanceEmployeeRow(
      name: e.name,
      hourly: e.hourly,
      parts: parts.isEmpty ? [const AttendanceMetricPart('Không chấm')] : parts,
      primary: primary,
      primaryColor: color,
      onTap: e.onTap,
    );
  }

  return [
    SliverPadding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
      sliver: SliverToBoxAdapter(
        child: SizedBox(
          height: 70,
          child: ListView(
            controller: dayStripController,
            scrollDirection: Axis.horizontal,
            children: [for (final d in dates) dayCell(d)],
          ),
        ),
      ),
    ),
    SliverPadding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      sliver: SliverToBoxAdapter(
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: [
            for (final c in _dayChips)
              if (c.$1 == 'all' || (counts[c.$1] ?? 0) > 0)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ChoiceChip(
                    label: Text(tr('${c.$2} ${counts[c.$1]}')),
                    selected: key == c.$1,
                    showCheckmark: false,
                    visualDensity: VisualDensity.compact,
                    labelStyle: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: key == c.$1 ? Colors.white : (c.$3 ? SboxColors.dangerText : SboxColors.slate700),
                    ),
                    selectedColor: c.$3 ? SboxColors.danger : HrmPageChrome.primaryNavy,
                    onSelected: (_) => onChip(c.$1),
                  ),
                ),
          ]),
        ),
      ),
    ),
    SliverPadding(
      // Đáy chừa chỗ cho nút nổi (BOSS «Thao tác»).
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
      sliver: attendanceEmployeeListSliver(
        [for (final e in shown) () => row(e)],
        emptyText: 'Không có nhân viên trong ngày này',
      ),
    ),
  ];
}
