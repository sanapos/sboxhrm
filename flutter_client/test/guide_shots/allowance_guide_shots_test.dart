import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:zkteco_flutter_client/screens/allowance_settings_screen.dart';

import 'guide_shot_kit.dart';
import 'hrm_extras_common.dart';

/// Ảnh cho bước hướng dẫn «Phụ cấp» (id: allowance).

final _allowances = [
  {'id': 'a1', 'name': 'Phụ cấp ăn trưa', 'code': 'AN_TRUA', 'type': 'Daily', 'amount': 30000, 'isActive': true, 'isTaxable': false},
  {'id': 'a2', 'name': 'Phụ cấp xăng xe', 'code': 'XANG', 'type': 'Fixed', 'amount': 500000, 'isActive': true, 'isTaxable': true},
  {'id': 'a3', 'name': 'Phụ cấp chuyên cần', 'code': 'CC', 'type': 'Fixed', 'amount': 500000, 'isActive': true, 'isTaxable': true, 'isInsuranceApplicable': true},
  {
    'id': 'a4', 'name': 'Phụ cấp ca đêm', 'code': 'CA_DEM', 'type': 'PerShift', 'amount': 50000, 'isActive': true, 'isTaxable': true,
    'shiftIds': ['s4'], 'minWorkPercent': 90,
  },
  {'id': 'a5', 'name': 'Phụ cấp trách nhiệm trưởng ca', 'code': 'TN', 'type': 'Fixed', 'amount': 800000, 'isActive': true, 'isTaxable': true, 'employeeIds': ['e2']},
];

final _shifts = [
  {'id': 's1', 'name': 'Ca sáng', 'startTime': '06:00', 'endTime': '14:00', 'isActive': true},
  {'id': 's2', 'name': 'Ca chiều', 'startTime': '14:00', 'endTime': '22:00', 'isActive': true},
  {'id': 's3', 'name': 'Ca hành chính', 'startTime': '08:00', 'endTime': '17:00', 'isActive': true},
  {'id': 's4', 'name': 'Ca đêm', 'startTime': '22:00', 'endTime': '06:00', 'isActive': true},
];

MockClient get _api => guideApi({
      '/api/allowances': {'items': _allowances},
      '/api/employees': {'items': extrasEmployees, 'totalCount': extrasEmployees.length},
      '/api/shifts/templates': _shifts,
    });

const _crumbs = ['Thiết lập SBOX', 'Phụ cấp'];

Future<void> _openEditor(WidgetTester t) async {
  await t.tap(find.text('Thêm phụ cấp').first);
  await extrasSettle(t);
  await t.tap(inDialog(find.text('Ca đêm')).first);
  await extrasSettle(t, 3);
  await t.tap(inDialog(find.widgetWithText(FilterChip, 'Ca đêm')));
  await extrasSettle(t, 3);
}

void main() {
  for (final (suffix, size) in [('', desktopSize), ('-mobile', mobileSize)]) {
    testWidgets('allowance-1$suffix: danh sách phụ cấp', (t) async {
      await guideShot(
        t,
        name: 'allowance-1$suffix',
        screen: const AllowanceSettingsScreen(),
        api: _api,
        crumbs: _crumbs,
        size: size,
        marks: [
          GuideMark(1, [GuideMark.button(find.text('Thêm phụ cấp'))]),
          GuideMark(2, [find.textContaining('Tất cả ('), find.textContaining('Theo ngày công (')], pad: 6),
          GuideMark(3, [GuideMark.within(find.text('Phụ cấp ca đêm'), 'SboxCard')], pad: 2),
        ],
      );
    });

    testWidgets('allowance-2$suffix: thêm phụ cấp — mẫu nhanh, cách tính, ca', (t) async {
      await guideShot(
        t,
        name: 'allowance-2$suffix',
        screen: const AllowanceSettingsScreen(),
        api: _api,
        crumbs: [..._crumbs, 'Thêm phụ cấp'],
        size: size,
        act: _openEditor,
        marks: [
          GuideMark(1, [inDialog(find.text('Mẫu nhanh')), inDialog(find.widgetWithText(ActionChip, 'Ca đêm'))], pad: 6),
          GuideMark(2, [inDialog(fieldLabeled('Tên phụ cấp *')), inDialog(fieldLabeled('Số tiền'))], pad: 4),
          GuideMark(3, [inDialog(find.text('Ca được hưởng')), inDialog(find.widgetWithText(FilterChip, 'Ca đêm'))], pad: 6),
        ],
      );
    });

    testWidgets('allowance-3$suffix: thuế, bảo hiểm, áp dụng cho ai', (t) async {
      await guideShot(
        t,
        name: 'allowance-3$suffix',
        screen: const AllowanceSettingsScreen(),
        api: _api,
        crumbs: [..._crumbs, 'Thêm phụ cấp'],
        size: size,
        act: (t) async {
          await _openEditor(t);
          await scrollInto(t, inDialog(find.text('Áp dụng cho tất cả nhân viên')), alignment: 0.8);
          await extrasSettle(t, 3);
        },
        marks: [
          GuideMark(1, [inDialog(find.text('Điều kiện nhận')), inDialog(find.text('Số giờ tối thiểu'))], pad: 6),
          GuideMark(2, [
            GuideMark.within(inDialog(find.text('Tính vào thu nhập chịu thuế TNCN')), 'SwitchListTile'),
            GuideMark.within(inDialog(find.text('Tính vào lương đóng bảo hiểm')), 'SwitchListTile'),
          ], pad: 4),
          GuideMark(3, [GuideMark.within(inDialog(find.text('Áp dụng cho tất cả nhân viên')), 'SwitchListTile')], pad: 4),
        ],
      );
    });
  }
}
