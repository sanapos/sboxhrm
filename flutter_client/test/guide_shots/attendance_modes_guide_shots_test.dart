import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zkteco_flutter_client/screens/salary_v2/sl_common.dart';
import 'package:zkteco_flutter_client/screens/salary_v2/sl_editor.dart';
import 'package:zkteco_flutter_client/services/api_service.dart';

import 'guide_shot_kit.dart';

/// Ảnh cho bước hướng dẫn «Kiểu chấm công» (id: attendance_modes) — ô «Cách chấm công»
/// trong Thiết lập lương của từng nhân viên.

final _monthly = {
  'id': 'b1', 'rateType': 'Monthly', 'rate': 9000000, 'completionSalary': 1500000,
  'socialInsuranceType': 1, 'insuranceSalary': 9000000, 'attendanceMode': 'both', 'paidLeaveType': 'off-4',
  'description': 'attendanceType:both|shifts:Ca sáng, Ca chiều|shiftsPerDay:1|hoursPerWorkDay:8',
  'hourlyOvertimeType': 1, 'holidayOvertimeType': 1, 'paidLeaveDays': 12,
};
final _daily = {
  'id': 'b2', 'rateType': 'Daily', 'rate': 300000, 'dailyFixedRate': 300000, 'socialInsuranceType': 0,
  'attendanceMode': 'checkin', 'paidLeaveType': 'off-4',
  'description': 'attendanceType:checkin|shifts:Ca chiều|shiftsPerDay:1|hoursPerWorkDay:8',
};

final _minh = {'id': 'e3', 'employeeCode': '3', 'lastName': 'Lê Văn', 'firstName': 'Minh', 'department': 'Bếp', 'position': 'Bếp trưởng'};
final _lan = {'id': 'e2', 'employeeCode': '2', 'lastName': 'Trần Thị', 'firstName': 'Lan', 'department': 'Phục vụ', 'position': 'Trưởng ca'};

final _shifts = [
  {'id': 's1', 'name': 'Ca sáng'},
  {'id': 's2', 'name': 'Ca chiều'},
  {'id': 's3', 'name': 'Ca hành chính'},
];

final _api = guideApi({
  '/api/employees': {'items': [_minh, _lan]},
  '/api/shifts/templates': _shifts,
  '/api/settings/insurance': {'maxInsuranceSalary': 46800000, 'defaultRegion': 1, 'minSalaryRegion1': 5310000},
  '/api/settings/salary': {'standardWorkDays': 26, 'overtimeRate': 1.5, 'weekendRate': 2, 'holidayRate': 3},
});

SalaryEditor _editor(Map<String, dynamic> emp, Map<String, dynamic> benefit) => SalaryEditor(
      ctx: SlContext(
        api: ApiService(),
        shifts: _shifts,
        insurance: const {'maxInsuranceSalary': 46800000},
        store: {'standardWorkDays': 26},
      ),
      employee: SlEmployee(emp, {'benefitId': benefit['id'], 'benefit': benefit}),
    );

const _crumbs = ['Thiết lập lương'];

/// Cả dòng lựa chọn (nút tròn + tên + mô tả).
Finder _opt(String title) => GuideMark.within(find.text(title), '_Opt');

void main() {
  for (final (suffix, size) in [('', desktopSize), ('-mobile', mobileSize)]) {
    testWidgets('attendance-modes-1$suffix: các cách chấm công', (t) async {
      await guideShot(
        t,
        name: 'attendance-modes-1$suffix',
        screen: _editor(_minh, _monthly),
        api: _api,
        crumbs: [..._crumbs, 'Lê Văn Minh'],
        size: size,
        act: (t) async => guideScrollTo(t, find.text('Cách chấm công'), alignment: 0.08),
        marks: [
          GuideMark(1, [_opt('Chấm vào và ra')], pad: 2),
          GuideMark(2, [_opt('Chỉ chấm vào'), _opt('Chỉ chấm ra')], pad: 2),
          GuideMark(3, [_opt('Chấm 2 lần trong ngày'), _opt('Ca nguyên ngày')], pad: 2),
          GuideMark(4, [_opt('Không chấm công')], pad: 2),
        ],
      );
    });

    testWidgets('attendance-modes-2$suffix: cửa hàng chỉ chấm 1 lần', (t) async {
      await guideShot(
        t,
        name: 'attendance-modes-2$suffix',
        screen: _editor(_lan, _daily),
        api: _api,
        crumbs: [..._crumbs, 'Trần Thị Lan'],
        size: size,
        act: (t) async => guideScrollTo(t, find.text('Cách chấm công'), alignment: 0.08),
        marks: [
          GuideMark(1, [_opt('Chỉ chấm vào')], pad: 2),
          GuideMark(2, [find.widgetWithText(FilterChip, 'Ca chiều')], pad: 4),
        ],
      );
    });
  }
}
