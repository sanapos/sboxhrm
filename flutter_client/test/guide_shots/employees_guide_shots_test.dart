import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zkteco_flutter_client/screens/employees_screen.dart';

import 'guide_shot_kit.dart';

/// Ảnh cho bước hướng dẫn «Thêm nhân viên» (id: employees).

Map<String, dynamic> _e(String id, String code, String last, String first, String dept, String pos,
        {String status = 'Active', String join = '2025-03-01', String? phone}) =>
    {
      'id': id, 'employeeCode': code, 'pin': code.replaceAll(RegExp(r'\D'), ''), 'lastName': last, 'firstName': first,
      'department': dept, 'position': pos, 'workStatus': status, 'joinDate': '${join}T00:00:00',
      'phoneNumber': phone ?? '09${id.hashCode.abs() % 100000000}'.padRight(10, '0').substring(0, 10),
      'branchName': 'Cơm Gà Nam',
    };

final _employees = [
  _e('e1', '1', 'Nguyễn Văn', 'Hùng', 'Ban quản lý', 'Chủ cửa hàng', join: '2023-01-05', phone: '0903123456'),
  _e('e2', '2', 'Trần Thị', 'Lan', 'Phục vụ', 'Trưởng ca', join: '2023-06-12', phone: '0912345678'),
  _e('e3', '3', 'Lê Văn', 'Minh', 'Bếp', 'Bếp trưởng', join: '2023-08-20', phone: '0987654321'),
  _e('e4', '4', 'Phạm Thị', 'Hoa', 'Thu ngân', 'Thu ngân', join: '2024-02-01', phone: '0938111222'),
  _e('e5', '5', 'Võ Minh', 'Tuấn', 'Phục vụ', 'Nhân viên phục vụ', join: '2024-05-15', phone: '0977333444'),
  _e('e6', '6', 'Đặng Thu', 'Hà', 'Bếp', 'Phụ bếp', status: 'Probation', join: '2026-10-01', phone: '0966555777'),
  _e('e7', '7', 'Bùi Quốc', 'Bảo', 'Phục vụ', 'Nhân viên phục vụ', join: '2025-11-03', phone: '0909888999'),
  _e('e8', '8', 'Hồ Ngọc', 'Ánh', 'Kế toán', 'Kế toán viên', join: '2024-09-09', phone: '0935246810'),
];

final _departments = [
  {'id': 'ql', 'name': 'Ban quản lý', 'code': 'BQL', 'isActive': true, 'positions': ['Chủ cửa hàng', 'Quản lý ca']},
  {'id': 'bep', 'name': 'Bếp', 'code': 'BEP', 'isActive': true, 'positions': ['Bếp trưởng', 'Phụ bếp']},
  {'id': 'pv', 'name': 'Phục vụ', 'code': 'PV', 'isActive': true, 'positions': ['Trưởng ca', 'Nhân viên phục vụ']},
  {'id': 'tn', 'name': 'Thu ngân', 'code': 'TN', 'isActive': true, 'positions': ['Thu ngân']},
  {'id': 'kt', 'name': 'Kế toán', 'code': 'KT', 'isActive': true, 'positions': ['Kế toán viên']},
];

final _api = guideApi({
  '/api/employees/delete-eligibility': {},
  '/api/employees': {'items': _employees, 'totalCount': _employees.length},
  '/api/Departments': {'items': _departments, 'totalCount': _departments.length},
  '/api/departments': {'items': _departments, 'totalCount': _departments.length},
  '/api/branches/select': [
    {'id': 'b1', 'name': 'Cơm Gà Nam'},
  ],
});

const _crumbs = ['Hồ sơ nhân sự'];

/// Trong form (hộp thoại) — trang danh sách phía sau cũng có chữ «Phòng ban», «Chức vụ».
/// Kit chỉ cuộn vùng cuộn đầu tiên (trang sau), nên tự cuộn trong hộp thoại.
Finder _inForm(Finder f) => find.descendant(of: find.byType(Dialog), matching: f);

Finder _field(String label) =>
    find.ancestor(of: _inForm(find.text(label)), matching: find.byType(InputDecorator)).first;

Future<void> _openAddForm(WidgetTester t) async {
  await t.tap(find.byIcon(Icons.person_add).first);
  for (var i = 0; i < 8; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  for (final (suffix, size) in [('', desktopSize), ('-mobile', mobileSize)]) {
    final mobile = size == mobileSize;

    testWidgets('employees-1$suffix: danh sách, Thêm nhân viên / Nhập Excel', (t) async {
      await guideShot(
        t,
        name: 'employees-1$suffix',
        screen: const EmployeesScreen(),
        api: _api,
        crumbs: _crumbs,
        size: size,
        marks: [
          GuideMark(1, [
            GuideMark.button(find.byIcon(Icons.person_add)),
            if (!mobile) GuideMark.button(find.byIcon(Icons.upload_file)),
          ]),
        ],
      );
    });

    testWidgets('employees-2$suffix: mã NV, họ tên', (t) async {
      await guideShot(
        t,
        name: 'employees-2$suffix',
        screen: const EmployeesScreen(),
        api: _api,
        crumbs: [..._crumbs, 'Thêm nhân viên'],
        size: size,
        act: (t) async {
          await _openAddForm(t);
          await t.enterText(find.widgetWithText(TextField, 'Mã nhân viên *').first, '9');
          await t.enterText(find.widgetWithText(TextField, 'Tên nhân viên *').first, 'Ngô Thanh Tâm');
        },
        marks: [
          GuideMark(1, [find.widgetWithText(TextField, 'Mã nhân viên *').first]),
          GuideMark(2, [find.widgetWithText(TextField, 'Tên nhân viên *').first]),
        ],
      );
    });

    testWidgets('employees-3$suffix: phòng ban, chức vụ, ngày vào làm', (t) async {
      await guideShot(
        t,
        name: 'employees-3$suffix',
        screen: const EmployeesScreen(),
        api: _api,
        crumbs: [..._crumbs, 'Thêm nhân viên'],
        size: size,
        act: (t) async {
          await _openAddForm(t);
          await Scrollable.ensureVisible(t.element(_inForm(find.text('Phòng ban')).first), alignment: 0.15);
          await t.pump();
          await t.tap(_field('Phòng ban'));
          for (var i = 0; i < 4; i++) {
            await t.pump(const Duration(milliseconds: 100));
          }
          await t.tap(find.text('Bếp').last);
          for (var i = 0; i < 4; i++) {
            await t.pump(const Duration(milliseconds: 100));
          }
          await t.tap(_field('Chức vụ'));
          for (var i = 0; i < 4; i++) {
            await t.pump(const Duration(milliseconds: 100));
          }
          await t.tap(find.text('Phụ bếp').last);
          for (var i = 0; i < 4; i++) {
            await t.pump(const Duration(milliseconds: 100));
          }
        },
        marks: [
          GuideMark(1, [_field('Phòng ban'), _field('Chức vụ')]),
          GuideMark(2, [_field('Ngày vào làm')]),
          GuideMark(3, [_field('Trạng thái')]),
        ],
      );
    });
  }
}
