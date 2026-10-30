import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zkteco_flutter_client/screens/shift_templates_v2/st_common.dart';
import 'package:zkteco_flutter_client/screens/shift_templates_v2/st_editor.dart';
import 'package:zkteco_flutter_client/screens/shift_templates_v2/st_list_screen.dart';

import 'guide_shot_kit.dart';

/// Ảnh cho bước hướng dẫn «Cấu hình ca làm việc» (id: shifts).

final _shifts = [
  {
    'id': 's1', 'name': 'Ca sáng', 'code': 'SANG', 'startTime': '06:00', 'endTime': '14:00',
    'breakTimeMinutes': 30, 'lateGraceMinutes': 10, 'earlyLeaveGraceMinutes': 5, 'earlyCheckInMinutes': 60, 'isActive': true,
  },
  {
    'id': 's2', 'name': 'Ca chiều', 'code': 'CHIEU', 'startTime': '14:00', 'endTime': '22:00',
    'breakTimeMinutes': 30, 'lateGraceMinutes': 10, 'earlyLeaveGraceMinutes': 5, 'earlyCheckInMinutes': 60, 'isActive': true,
  },
  {
    'id': 's3', 'name': 'Ca hành chính', 'code': 'HC', 'startTime': '08:00', 'endTime': '17:00',
    'lunchBreakStartTime': '12:00', 'lunchBreakEndTime': '13:00', 'lateGraceMinutes': 5, 'earlyCheckInMinutes': 60, 'isActive': true,
  },
  {
    'id': 's4', 'name': 'Ca đêm', 'code': 'DEM', 'startTime': '21:30', 'endTime': '06:00',
    'breakTimeMinutes': 30, 'lateGraceMinutes': 10, 'earlyCheckInMinutes': 60, 'isActive': true,
  },
  {
    'id': 's5', 'name': 'Ca gãy (trưa + tối)', 'code': 'GAY', 'startTime': '10:00', 'endTime': '21:00',
    'lunchBreakStartTime': '14:00', 'lunchBreakEndTime': '17:00', 'isActive': false,
  },
];

final _usage = [
  {'shiftId': 's1', 'schedules': 412, 'upcomingSchedules': 38, 'employees': 9, 'hasData': true, 'canDelete': false, 'salaryLevels': 1},
  {'shiftId': 's2', 'schedules': 380, 'upcomingSchedules': 35, 'employees': 8, 'hasData': true, 'canDelete': false},
  {'shiftId': 's3', 'schedules': 220, 'upcomingSchedules': 20, 'employees': 4, 'hasData': true, 'canDelete': false},
  {'shiftId': 's4', 'schedules': 96, 'upcomingSchedules': 8, 'employees': 2, 'hasData': true, 'canDelete': false},
];

final _api = guideApi({
  '/api/shifts/templates/usage': _usage,
  '/api/shifts/templates': _shifts,
  '/api/shift-salary-levels': {'items': []},
});

const _crumbs = ['Cài đặt', 'Thiết lập ca'];

Finder _step(String label) => GuideMark.within(find.text(label), '_MinuteStepper');

void main() {
  for (final (suffix, size) in [('', desktopSize), ('-mobile', mobileSize)]) {
    testWidgets('shifts-1$suffix: danh sách ca, nút Thêm ca', (t) async {
      await guideShot(
        t,
        name: 'shifts-1$suffix',
        screen: const ShiftTemplatesV2Screen(),
        api: _api,
        crumbs: _crumbs,
        size: size,
        marks: [
          GuideMark(1, [GuideMark.button(find.text('Thêm ca'))]),
          GuideMark(2, [GuideMark.button(find.byTooltip('Thao tác'))]),
        ],
      );
    });

    testWidgets('shifts-2$suffix: nhập tên, giờ vào / ra', (t) async {
      await guideShot(
        t,
        name: 'shifts-2$suffix',
        screen: const ShiftTemplateEditorPage(),
        api: _api,
        crumbs: [..._crumbs, 'Thêm ca'],
        size: size,
        act: (t) async {
          await t.enterText(find.byType(TextField).first, 'Ca tối');
        },
        marks: [
          GuideMark(1, [find.byType(TextField).first]),
          GuideMark(2, [GuideMark.button(find.text('Giờ vào')), GuideMark.button(find.text('Giờ ra'))]),
          GuideMark(3, [find.text('Mẫu nhanh'), find.textContaining('Ca sáng')], pad: 8),
        ],
      );
    });

    testWidgets('shifts-3$suffix: ân hạn trễ / sớm, tăng ca', (t) async {
      final shift = ShiftTpl.fromJson(_shifts.first);
      await guideShot(
        t,
        name: 'shifts-3$suffix',
        screen: ShiftTemplateEditorPage(shift: shift, usage: ShiftUsage(_usage.first)),
        api: _api,
        crumbs: [..._crumbs, 'Ca sáng'],
        size: size,
        act: (t) async {
          await guideScrollTo(t, find.text('Miễn trễ'), alignment: 0.15);
        },
        marks: [
          GuideMark(1, [_step('Miễn trễ'), _step('Giới hạn đi trễ')]),
          GuideMark(2, [_step('Miễn về sớm'), _step('Giới hạn về sớm')]),
          GuideMark(3, [_step('Tăng ca trước ca'), _step('Tăng ca sau ca')]),
        ],
      );
    });
  }
}
