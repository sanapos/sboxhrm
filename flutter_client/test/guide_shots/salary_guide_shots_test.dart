import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zkteco_flutter_client/screens/salary_v2/sl_common.dart';
import 'package:zkteco_flutter_client/screens/salary_v2/sl_editor.dart';
import 'package:zkteco_flutter_client/screens/salary_v2/sl_screen.dart';
import 'package:zkteco_flutter_client/services/api_service.dart';

import 'guide_shot_kit.dart';

/// Ảnh cho bước hướng dẫn «Thiết lập lương & kiểu chấm công» (id: salary).

final _monthly = {
  'id': 'b1', 'name': 'Lương Lê Văn Minh (3)', 'rateType': 'Monthly', 'rate': 9000000, 'completionSalary': 1500000,
  'socialInsuranceType': 1, 'insuranceSalary': 9000000, 'attendanceMode': 'both', 'paidLeaveType': 'off-4',
  'description': 'attendanceType:both|shifts:Ca sáng, Ca chiều|shiftsPerDay:1|hoursPerWorkDay:8',
  'hourlyOvertimeType': 1, 'holidayOvertimeType': 1, 'paidLeaveDays': 12,
};
final _daily = {
  'id': 'b2', 'rateType': 'Daily', 'rate': 300000, 'dailyFixedRate': 300000, 'socialInsuranceType': 0,
  'attendanceMode': 'checkin', 'paidLeaveType': 'off-4', 'description': 'attendanceType:checkin|shifts:Ca chiều|shiftsPerDay:1|hoursPerWorkDay:8',
};
final _hourly = {
  'id': 'b3', 'rateType': 'Hourly', 'rate': 28000, 'socialInsuranceType': 0,
  'attendanceMode': 'both', 'paidLeaveType': 'none', 'description': 'attendanceType:both|shiftsPerDay:1|hoursPerWorkDay:8',
};

final _employees = [
  {'id': 'e3', 'employeeCode': '3', 'lastName': 'Lê Văn', 'firstName': 'Minh', 'department': 'Bếp', 'position': 'Bếp trưởng'},
  {'id': 'e2', 'employeeCode': '2', 'lastName': 'Trần Thị', 'firstName': 'Lan', 'department': 'Phục vụ', 'position': 'Trưởng ca'},
  {'id': 'e5', 'employeeCode': '5', 'lastName': 'Võ Minh', 'firstName': 'Tuấn', 'department': 'Phục vụ', 'position': 'Nhân viên phục vụ'},
  {'id': 'e4', 'employeeCode': '4', 'lastName': 'Phạm Thị', 'firstName': 'Hoa', 'department': 'Thu ngân', 'position': 'Thu ngân'},
  {'id': 'e9', 'employeeCode': '9', 'lastName': 'Ngô Thanh', 'firstName': 'Tâm', 'department': 'Bếp', 'position': 'Phụ bếp'},
];

final _shifts = [
  {'id': 's1', 'name': 'Ca sáng'},
  {'id': 's2', 'name': 'Ca chiều'},
  {'id': 's3', 'name': 'Ca hành chính'},
];

final _api = guideApi({
  '/api/employees': {'items': _employees},
  '/api/benefits/employees': [
    {'employeeId': 'e3', 'benefitId': 'b1', 'benefit': _monthly},
    {'employeeId': 'e2', 'benefitId': 'b2', 'benefit': _daily},
    {'employeeId': 'e5', 'benefitId': 'b2', 'benefit': _daily},
    {'employeeId': 'e4', 'benefitId': 'b3', 'benefit': _hourly},
  ],
  '/api/shifts/templates': _shifts,
  '/api/allowances': {
    'items': [
      {'id': 'a1', 'name': 'Phụ cấp ăn trưa', 'type': 'Daily', 'amount': 30000, 'isActive': true, 'employeeIds': ['e3', 'e2', 'e5']},
      {'id': 'a2', 'name': 'Phụ cấp trách nhiệm', 'type': 'Fixed', 'amount': 500000, 'isActive': true, 'employeeIds': ['e3']},
    ],
  },
  '/api/settings/insurance': {'maxInsuranceSalary': 46800000, 'defaultRegion': 1, 'minSalaryRegion1': 4960000},
  '/api/settings/salary': {'standardWorkDays': 26, 'overtimeRate': 1.5, 'weekendRate': 2, 'holidayRate': 3},
});

const _crumbs = ['Thiết lập lương'];

SalaryEditor _editor() => SalaryEditor(
      ctx: SlContext(
        api: ApiService(),
        shifts: _shifts,
        insurance: const {'maxInsuranceSalary': 46800000},
        store: {'standardWorkDays': 26},
      ),
      employee: SlEmployee(_employees.first, {'benefitId': 'b1', 'benefit': _monthly}),
    );

void main() {
  for (final (suffix, size) in [('', desktopSize), ('-mobile', mobileSize)]) {
    testWidgets('salary-1$suffix: chọn nhân viên', (t) async {
      await guideShot(
        t,
        name: 'salary-1$suffix',
        screen: const SalaryV2Screen(canEditOverride: true),
        api: _api,
        crumbs: _crumbs,
        size: size,
        marks: [
          GuideMark(1, [GuideMark.button(find.textContaining('Ngô Thanh Tâm').first)], pad: 2),
        ],
      );
    });

    testWidgets('salary-2$suffix: loại lương, lương cơ bản', (t) async {
      await guideShot(
        t,
        name: 'salary-2$suffix',
        screen: _editor(),
        api: _api,
        crumbs: [..._crumbs, 'Lê Văn Minh'],
        size: size,
        marks: [
          GuideMark(1, [GuideMark.within(find.text('Loại lương'), 'SettingsTile')]),
          GuideMark(2, [
            GuideMark.within(find.text('Lương cơ bản'), 'SettingsTile'),
            GuideMark.within(find.text('Lương hoàn thành'), 'SettingsTile'),
          ], pad: 0),
        ],
      );
    });

    testWidgets('salary-3$suffix: cách chấm công, ca làm việc', (t) async {
      await guideShot(
        t,
        name: 'salary-3$suffix',
        screen: _editor(),
        api: _api,
        crumbs: [..._crumbs, 'Lê Văn Minh'],
        size: size,
        act: (t) async {
          await guideScrollTo(t, find.text('Cách chấm công'), alignment: 0.05);
        },
        marks: [
          GuideMark(1, [find.text('Cách chấm công'), find.text('Đủ công theo lịch')]),
          GuideMark(2, [find.text('Ca làm việc'), find.widgetWithText(FilterChip, 'Ca hành chính')]),
        ],
      );
    });
  }
}
