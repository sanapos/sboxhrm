import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zkteco_flutter_client/screens/shift_hub/shift_hub_screen.dart';
import 'package:zkteco_flutter_client/screens/shift_hub/shift_hub_ui.dart';

import 'guide_shot_kit.dart';
import 'hrm_extras_common.dart';

/// Ảnh cho bước hướng dẫn «Ca làm việc: lịch, đăng ký, nghỉ, đổi ca, định mức» (id: work_schedule).
/// Màn «Ca làm việc» tính tuần theo đồng hồ máy → dữ liệu mẫu dựng quanh tuần hiện tại.

const _templates = [
  {'id': 't1', 'name': 'Ca sáng', 'start': '06:00', 'end': '14:00', 'colorIndex': 0, 'active': true},
  {'id': 't2', 'name': 'Ca chiều', 'start': '14:00', 'end': '22:00', 'colorIndex': 1, 'active': true},
  {'id': 't3', 'name': 'Hành chính', 'start': '08:00', 'end': '17:00', 'colorIndex': 2, 'active': true},
];

DateTime get _today => DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);
DateTime get _mon => ShiftUi.monday(DateTime.now());
List<String> get _days => [for (var i = 0; i < 7; i++) ShiftUi.key(_mon.add(Duration(days: i)))];

/// «Lịch của tôi» — Trần Thị Mai: ca sáng / chiều, 1 ngày nghỉ, 1 đồng nghiệp xin đổi ca.
Map<String, Object?> _my() {
  const plan = ['t1', 't1', 't1', 'off', 't1', 't2', 't2'];
  final days = <Map<String, Object?>>[];
  for (var i = 0; i < 7; i++) {
    final date = _mon.add(Duration(days: i));
    final p = plan[i];
    final tpl = _templates.where((t) => t['id'] == p).firstOrNull;
    days.add({
      'date': _days[i],
      'isToday': date == _today,
      'isPast': date.isBefore(_today),
      if (p == 'off') 'schedule': {'scheduleId': 'm$i', 'isDayOff': true, 'note': 'Nghỉ tuần'},
      if (tpl != null) 'schedule': {'scheduleId': 'm$i', 'shiftId': p, 'start': tpl['start'], 'end': tpl['end']},
      'leaves': const [],
      'swaps': const [],
      'schedules': const [],
    });
  }
  return {
    'days': days,
    'templates': _templates,
    'incomingSwaps': [
      {
        'id': 'sw1', 'otherName': 'Lê Văn Hùng', 'theirShift': 'Ca chiều', 'theirDate': _days[4],
        'myShift': 'Ca sáng', 'myDate': _days[4], 'reason': 'Đi học buổi sáng',
      },
    ],
    'summary': {'shifts': 6, 'hours': 45, 'dayOff': 1, 'pendingRegistrations': 0, 'pendingLeaves': 0, 'pendingSwaps': 1},
  };
}

/// Mẫu xếp 7 ngày (T2 → CN): mã ca hoặc 'off' / 'leave' / null.
const _staff = [
  ('NV001', 'Nguyễn Văn An', 'Quản lý', ['t3', 't3', 't3', 't3', 't3', 't3', 'off']),
  ('NV003', 'Trần Thị Mai', 'Thu ngân', ['t1', 't1', 't1', 'off', 't1', 't2', null]),
  ('NV004', 'Lê Văn Hùng', 'Thu ngân', ['t2', 't2', 'off', 't2', 't2', 't2', 't2']),
  ('NV005', 'Phạm Thu Hà', 'Phục vụ', ['t1', 'leave', 't1', 't1', 'off', 't1', 't1']),
  ('NV006', 'Võ Minh Tuấn', 'Phục vụ', ['t2', 't2', 't2', 't2', 't2', 'off', 't2']),
  ('NV007', 'Đặng Ngọc Lan', 'Pha chế', ['t1', 't2', 't1', 't2', 't1', 't2', 'off']),
];

Map<String, Object?> _board() {
  final days = _days;
  final employees = <Map<String, Object?>>[];
  final count = <String, int>{};
  final leaveCount = <String, int>{};
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
        leaveCount['${days[i]}|t1'] = (leaveCount['${days[i]}|t1'] ?? 0) + 1;
      } else {
        cells[days[i]] = {'scheduleId': '$code-$i', 'shiftId': p};
        total += p == 't3' ? 8 : 7.5;
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
            'date': d, 'shiftId': t['id'], 'effective': n, 'scheduled': n + (leaveCount['$d|${t['id']}'] ?? 0),
            'onLeave': leaveCount['$d|${t['id']}'] ?? 0, 'pending': 0,
            'min': min, 'max': min + 2, 'hasQuota': true,
            'status': n < min ? 'short' : (n == min ? 'tight' : 'ok'),
          };
        }(),
  ];
  return {
    'days': days,
    'today': ShiftUi.key(DateTime.now()),
    'templates': _templates,
    'departments': ['Cửa hàng Q.1'],
    'employees': employees,
    'coverage': coverage,
    'summary': {'employees': 6, 'unscheduled': 0, 'plannedHours': 241, 'shortSlots': 6, 'pendingRegistrations': 1, 'pendingLeaves': 1},
  };
}

String _iso(int dayIndex, [String time = '00:00:00']) => '${_days[dayIndex]}T$time';

final _api = guideApi({
  '/api/shift-hub/my': _my(),
  '/api/shift-hub/board': _board(),
  '/api/shift-hub/counts': {'total': 3, 'swapsForMe': 1},
  '/api/workschedules/registrations': {
    'items': [
      {'id': 'r6', 'employeeName': 'Trần Thị Mai', 'shiftName': 'Ca chiều', 'date': _iso(6), 'status': 'Pending',
       'note': 'Muốn làm thêm cuối tuần', 'createdAt': _iso(0, '09:12:00')},
    ],
  },
  '/api/Leaves/pending': {
    'items': [
      {'id': 'l1', 'employeeName': 'Võ Minh Tuấn', 'type': 'Annual', 'startDate': _iso(5), 'endDate': _iso(5),
       'reason': 'Về quê', 'shiftNames': ['Ca chiều'], 'remainingAnnualLeaveDays': 6, 'status': 'Pending',
       'createdAt': _iso(0, '10:30:00')},
    ],
  },
  '/api/shiftswaps/pending-approval': [
    {'id': 'sw2', 'requesterName': 'Đặng Ngọc Lan', 'targetName': 'Phạm Thu Hà', 'requesterShiftName': 'Ca chiều',
     'targetShiftName': 'Ca sáng', 'requesterDate': _iso(3), 'targetDate': _iso(3), 'reason': 'Lịch học',
     'status': 'TargetAccepted', 'createdAt': _iso(0, '11:05:00')},
  ],
  '/api/shifts/pending': [],
});

const _crumbs = ['Chấm công', 'Ca làm việc'];

void main() {
  for (final (suffix, size) in [('', desktopSize), ('-mobile', mobileSize)]) {
    testWidgets('schedule-hub-1$suffix: lịch của tôi, thao tác trên từng ngày', (t) async {
      await guideShot(
        t,
        name: 'schedule-hub-1$suffix',
        screen: const ShiftHubScreen(initialTab: 'my'),
        api: _api,
        crumbs: _crumbs,
        size: size,
        act: (t) async {
          // Thẻ chủ nhật luôn là hôm nay hoặc tương lai → có nút thao tác.
          final sun = ShiftUi.weekdays[6];
          await guideScrollTo(t, find.text(sun), alignment: 0.45);
          final menu = find.byTooltip('Thao tác');
          await t.tap(menu.last);
          await extrasSettle(t, 4);
        },
        marks: [
          GuideMark(1, [find.byType(PopupMenuItem<String>).first, find.byType(PopupMenuItem<String>).last]),
          if (size.width >= 600)
            GuideMark(2, [find.textContaining('muốn đổi ca').last, find.textContaining('Bạn nhường').first, find.text('Từ chối').first], pad: 10),
        ],
      );
    });

    testWidgets('schedule-hub-2$suffix: bảng xếp ca, định mức theo ca', (t) async {
      await guideShot(
        t,
        name: 'schedule-hub-2$suffix',
        screen: const ShiftHubScreen(initialTab: 'board'),
        api: _api,
        crumbs: _crumbs,
        size: size,
        act: size.width < 600
            ? (t) async {
                await t.tap(find.text('Từng ngày'));
                await extrasSettle(t, 3);
                await guideScrollTo(t, find.textContaining('người · cần').first, alignment: 0.3);
              }
            : null,
        marks: size.width < 600
            ? [
                GuideMark(1, [find.textContaining('người · cần').first, find.textContaining('người · cần').last]),
              ]
            : [
                GuideMark(1, [find.text('Định mức theo ca'), find.textContaining(RegExp(r'^\d+ / \d')).last]),
                GuideMark(2, [find.byTooltip('Thao tác nhanh').first]),
              ],
      );
    });

    testWidgets('schedule-hub-3$suffix: cần duyệt, duyệt nhiều yêu cầu', (t) async {
      await guideShot(
        t,
        name: 'schedule-hub-3$suffix',
        screen: const ShiftHubScreen(initialTab: 'inbox'),
        api: _api,
        crumbs: _crumbs,
        size: size,
        act: (t) async {
          await t.tap(find.byType(Checkbox).first);
          await extrasSettle(t, 3);
        },
        marks: [
          GuideMark(1, [find.textContaining('Tất cả (').first]),
          GuideMark(2, [find.byType(Checkbox).first, find.byType(Checkbox).last]),
          GuideMark(3, [GuideMark.button(find.textContaining(RegExp(r'^Duyệt \d')))]),
        ],
      );
    });
  }
}
