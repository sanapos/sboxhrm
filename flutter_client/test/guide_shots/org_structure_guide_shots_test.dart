import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zkteco_flutter_client/screens/departments_v2/dp_screen.dart';

import 'guide_shot_kit.dart';

/// Ảnh cho bước hướng dẫn «Phòng ban, chức vụ & chi nhánh» (id: org_structure).

Map<String, dynamic> _d(String id, String name, String code, String? parent, int direct, int total, int kids,
        {String? manager, int order = 0, List<String> positions = const []}) =>
    {
      'id': id, 'name': name, 'code': code, 'parentId': parent, 'directCount': direct, 'totalCount': total,
      'childCount': kids, 'managerId': manager == null ? null : 'm$id', 'managerName': manager,
      'managerPosition': manager == null ? null : 'Trưởng phòng', 'sortOrder': order, 'isActive': true,
      'positions': positions,
    };

final _overview = {
  'items': [
    _d('ql', 'Ban quản lý', 'BQL', null, 2, 2, 0, manager: 'Nguyễn Văn Hùng', positions: ['Chủ cửa hàng', 'Quản lý ca']),
    _d('bep', 'Bếp', 'BEP', null, 6, 6, 0, manager: 'Lê Văn Minh', order: 1, positions: ['Bếp trưởng', 'Phụ bếp']),
    _d('pv', 'Phục vụ', 'PV', null, 9, 9, 0, manager: 'Trần Thị Lan', order: 2, positions: ['Trưởng ca', 'Nhân viên phục vụ']),
    _d('tn', 'Thu ngân', 'TN', null, 3, 3, 0, order: 3, positions: ['Thu ngân']),
    _d('kt', 'Kế toán', 'KT', null, 1, 1, 0, order: 4, positions: ['Kế toán viên']),
  ],
  'totalEmployees': 21,
  'unassigned': 0,
};

final _members = [
  {'id': 'e1', 'name': 'Lê Văn Minh', 'employeeCode': 'NV003', 'position': 'Bếp trưởng', 'branchName': 'Cơm Gà Nam'},
  {'id': 'e2', 'name': 'Phạm Quốc Dũng', 'employeeCode': 'NV008', 'position': 'Phụ bếp', 'branchName': 'Cơm Gà Nam'},
  {'id': 'e3', 'name': 'Đặng Thu Hà', 'employeeCode': 'NV012', 'position': 'Phụ bếp', 'branchName': 'Cơm Gà Nam', 'probation': true},
];

final _api = guideApi({
  '/departments/v2/overview': _overview,
  '/members': _members,
  '/employee-search': _members,
});

const _crumbs = ['Cài đặt', 'Phòng ban'];

void main() {
  for (final (suffix, size) in [('', desktopSize), ('-mobile', mobileSize)]) {
    testWidgets('org-structure-1$suffix: cây phòng ban, nút Thêm phòng ban', (t) async {
      await guideShot(
        t,
        name: 'org-structure-1$suffix',
        screen: const DepartmentsV2Screen(),
        api: _api,
        crumbs: _crumbs,
        size: size,
        marks: [
          GuideMark(1, [GuideMark.button(find.text('Thêm phòng ban'))]),
          GuideMark(2, [GuideMark.button(find.text('Bếp').first)], pad: 2),
        ],
      );
    });

    testWidgets('org-structure-2$suffix: tên phòng ban + chức vụ', (t) async {
      await guideShot(
        t,
        name: 'org-structure-2$suffix',
        screen: const DepartmentsV2Screen(),
        api: _api,
        crumbs: [..._crumbs, 'Thêm phòng ban'],
        size: size,
        act: (t) async {
          await t.tap(find.text('Thêm phòng ban').first);
          for (var i = 0; i < 6; i++) {
            await t.pump(const Duration(milliseconds: 100));
          }
          await t.enterText(find.widgetWithText(TextField, 'Tên phòng ban *'), 'Pha chế');
          final pos = find.widgetWithText(TextField, 'Thêm chức vụ');
          for (final p in ['Trưởng quầy bar', 'Nhân viên pha chế']) {
            await t.enterText(pos, p);
            await t.testTextInput.receiveAction(TextInputAction.done);
            await t.pump();
          }
        },
        marks: [
          GuideMark(1, [find.widgetWithText(TextField, 'Tên phòng ban *'), find.widgetWithText(TextField, 'Mã')]),
          GuideMark(2, [find.text('Chức vụ trong phòng'), find.widgetWithText(TextField, 'Thêm chức vụ')]),
          GuideMark(3, [GuideMark.button(find.text('Lưu phòng ban'))]),
        ],
      );
    });
  }
}
