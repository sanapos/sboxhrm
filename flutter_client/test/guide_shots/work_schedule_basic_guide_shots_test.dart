import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zkteco_flutter_client/screens/shift_hub/shift_hub_screen.dart';
import 'package:zkteco_flutter_client/screens/shift_hub/shift_hub_ui.dart';

import 'guide_shot_kit.dart';

/// Ảnh cho bước hướng dẫn «Phân lịch làm việc lần đầu» (id: work_schedule_basic).
/// Bảng xếp ca tuần hiện tại (màn tính «hôm nay» theo đồng hồ máy).

const _templates = [
  {'id': 't1', 'name': 'Ca sáng', 'start': '06:00', 'end': '14:00', 'colorIndex': 0, 'active': true},
  {'id': 't2', 'name': 'Ca chiều', 'start': '14:00', 'end': '22:00', 'colorIndex': 1, 'active': true},
  {'id': 't3', 'name': 'Hành chính', 'start': '08:00', 'end': '17:00', 'colorIndex': 2, 'active': true},
];

/// Mẫu xếp 7 ngày (T2 → CN): mã ca hoặc 'off' (ngày nghỉ) / 'leave' (nghỉ phép) / null (chưa xếp).
const _staff = [
  ('NV001', 'Nguyễn Văn An', 'Quản lý', ['t3', 't3', 't3', 't3', 't3', 't3', 'off']),
  ('NV002', 'Bùi Quốc Bảo', 'Pha chế', [null, null, null, null, null, null, null]),
  ('NV003', 'Trần Thị Mai', 'Thu ngân', ['t1', 't1', 't1', 'off', 't1', 't1', 't1']),
  ('NV004', 'Lê Văn Hùng', 'Thu ngân', ['t2', 't2', 'off', 't2', 't2', 't2', 't2']),
  ('NV005', 'Phạm Thu Hà', 'Phục vụ', ['t1', 'leave', 't1', 't1', 'off', 't1', 't1']),
  ('NV006', 'Võ Minh Tuấn', 'Phục vụ', ['t2', 't2', 't2', 't2', 't2', 'off', 't2']),
  ('NV007', 'Đặng Ngọc Lan', 'Pha chế', ['t1', 't2', 't1', 't2', 't1', 't2', 'off']),
];

Map<String, Object?> _board() {
  final mon = ShiftUi.monday(DateTime.now());
  final days = [for (var i = 0; i < 7; i++) ShiftUi.key(mon.add(Duration(days: i)))];
  final hours = {'t1': 7.5, 't2': 7.5, 't3': 8.0};
  final employees = <Map<String, Object?>>[];
  final count = <String, int>{};
  for (final (code, name, pos, plan) in _staff) {
    final cells = <String, Object?>{};
    var total = 0.0;
    for (var i = 0; i < 7; i++) {
      final p = plan[i];
      if (p == null) continue;
      if (p == 'off') {
        cells[days[i]] = {'scheduleId': '$code-$i', 'isDayOff': true};
      } else if (p == 'leave') {
        cells[days[i]] = {'scheduleId': '$code-$i', 'shiftId': 't1', 'leave': {'status': 'Approved', 'type': 'Annual'}};
      } else {
        cells[days[i]] = {'scheduleId': '$code-$i', 'shiftId': p};
        total += hours[p]!;
        count['${days[i]}|$p'] = (count['${days[i]}|$p'] ?? 0) + 1;
      }
    }
    employees.add({
      'id': code, 'code': code, 'name': name, 'department': 'Cửa hàng Q.1', 'position': pos,
      'cells': cells, 'totals': {'hours': total},
    });
  }
  final coverage = [
    for (final d in days)
      for (final t in _templates)
        () {
          final n = count['$d|${t['id']}'] ?? 0;
          final min = t['id'] == 't3' ? 1 : 2;
          return {
            'date': d, 'shiftId': t['id'], 'effective': n, 'scheduled': n, 'onLeave': 0, 'pending': 0,
            'min': min, 'max': min + 2, 'hasQuota': true,
            'status': n < min ? 'short' : (n == min ? 'tight' : 'ok'),
          };
        }(),
  ];
  return {
    'days': days,
    'today': ShiftUi.key(DateTime.now()),
    'templates': _templates,
    'departments': ['Cửa hàng Q.1', 'Kho'],
    'employees': employees,
    'coverage': coverage,
    'summary': {'employees': 7, 'unscheduled': 1, 'plannedHours': 278, 'shortSlots': 3, 'pendingRegistrations': 0, 'pendingLeaves': 0},
  };
}

final _api = guideApi({
  '/api/shift-hub/board': _board(),
  '/api/shift-hub/counts': {'total': 0, 'swapsForMe': 0},
});

const _crumbs = ['Ca làm việc', 'Xếp ca'];

/// Ô lịch của nhân viên [name] ngày thứ [weekday] (1 = T2) trên lưới tuần.
Finder _cellOf(String name, int weekday) => _Lazy(() {
      final row = find.ancestor(of: find.textContaining(name), matching: find.byType(Row)).first;
      final cells = find.descendant(of: row, matching: find.byType(InkWell));
      return cells.at(cells.evaluate().length - 8 + weekday);
    });

/// Finder tính lúc tìm (sau khi màn đã dựng), không phải lúc khai báo điểm đánh dấu.
class _Lazy extends Finder {
  _Lazy(this.make);
  final Finder Function() make;

  @override
  String get description => 'ô lịch';

  @override
  Iterable<Element> findInCandidates(Iterable<Element> candidates) => make().evaluate();
}

/// Dòng chọn trong bảng «Xếp ca» (ListTile) có chữ [label].
Finder _tile(String label) => find.ancestor(of: find.text(label).last, matching: find.byType(ListTile)).first;

Finder _weekLabel() => find.text(ShiftUi.weekLabel(ShiftUi.monday(DateTime.now())));

void main() {
  for (final (suffix, size) in [('', desktopSize), ('-mobile', mobileSize)]) {
    final mobile = size.width < 600;

    testWidgets('work-schedule-1$suffix: bảng xếp ca tuần', (t) async {
      await guideShot(
        t,
        name: 'work-schedule-1$suffix',
        screen: const ShiftHubScreen(initialTab: 'board'),
        api: _api,
        crumbs: _crumbs,
        size: size,
        marks: [
          GuideMark(1, [_weekLabel(), if (mobile) find.text('Tuần này')], pad: 10),
          GuideMark(2, [find.textContaining('Quốc Bảo'), _cellOf('Quốc Bảo', 7)], pad: 4),
        ],
      );
    });

    testWidgets('work-schedule-2$suffix: chọn ca cho một ngày', (t) async {
      await guideShot(
        t,
        name: 'work-schedule-2$suffix',
        screen: const ShiftHubScreen(initialTab: 'board'),
        api: _api,
        crumbs: _crumbs,
        size: size,
        act: (t) async {
          await t.tap(_cellOf('Quốc Bảo', 6));
          await t.pump(const Duration(milliseconds: 600));
        },
        marks: [
          GuideMark(1, [_tile('Ca sáng'), _tile('Hành chính')], pad: 2),
          GuideMark(2, [_tile('Ngày nghỉ')], pad: 2),
        ],
      );
    });

    testWidgets('work-schedule-3$suffix: sao chép lịch tuần trước', (t) async {
      await guideShot(
        t,
        name: 'work-schedule-3$suffix',
        screen: const ShiftHubScreen(initialTab: 'board'),
        api: _api,
        crumbs: _crumbs,
        size: size,
        act: (t) async {
          await t.tap(mobile ? find.byIcon(Icons.more_vert_rounded).first : find.text('Thao tác nhanh'));
          await t.pump(const Duration(milliseconds: 600));
        },
        marks: [
          GuideMark(1, [find.text('Sao chép lịch tuần trước')], pad: 10),
        ],
      );
    });
  }
}
