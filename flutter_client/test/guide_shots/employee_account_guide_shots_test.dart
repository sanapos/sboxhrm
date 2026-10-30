import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zkteco_flutter_client/screens/accounts_v2/ac_screen.dart';

import 'guide_shot_kit.dart';

/// Ảnh cho bước hướng dẫn «Tạo tài khoản & phân quyền» (id: employee_account).

final _now = DateTime.now().toUtc();
Map<String, dynamic> _acc(String id, String user, String last, String first, String role,
        {bool owner = false, bool active = true, int? loginHours, String? empId}) =>
    {
      'id': id,
      'userName': user,
      'email': '$user@comganam.vn',
      'firstName': first,
      'lastName': last,
      'roles': [role],
      'isOwner': owner,
      'isActive': active,
      'employeeId': empId,
      'lastLoginAt': loginHours == null ? null : _now.subtract(Duration(hours: loginHours)).toIso8601String(),
    };

final _accounts = [
  _acc('me', 'hung', 'Nguyễn Văn', 'Hùng', 'Admin', owner: true, loginHours: 0, empId: 'e1'),
  _acc('u2', 'lan', 'Trần Thị', 'Lan', 'Manager', loginHours: 3, empId: 'e2'),
  _acc('u3', 'anh.kt', 'Hồ Ngọc', 'Ánh', 'Accountant', loginHours: 26, empId: 'e8'),
  _acc('u4', 'hoa', 'Phạm Thị', 'Hoa', 'Cashier', loginHours: 5, empId: 'e4'),
  _acc('u5', 'tuan', 'Võ Minh', 'Tuấn', 'Waiter', loginHours: 9, empId: 'e5'),
];

final _api = guideApi({
  '/api/accounts/role-policy': {
    'isOwner': true,
    'myRole': 'Admin',
    'assignableRoles': ['Manager', 'Accountant', 'Cashier', 'Waiter', 'Employee'],
  },
  '/api/accounts': _accounts,
  '/api/employees': {
    'items': [
      {'id': 'e9', 'firstName': 'Tâm', 'lastName': 'Ngô Thanh', 'employeeCode': '9', 'phoneNumber': '0918 246 357'},
      {'id': 'e3', 'firstName': 'Minh', 'lastName': 'Lê Văn', 'employeeCode': '3'},
      {'id': 'e7', 'firstName': 'Bảo', 'lastName': 'Bùi Quốc', 'employeeCode': '7'},
    ],
  },
  '/api/pos/service-areas': [
    {'id': 'a1', 'name': 'Tầng 1'},
    {'id': 'a2', 'name': 'Sân vườn'},
  ],
});

const _crumbs = ['Cài đặt', 'Tài khoản'];

Finder _inDialog(Finder f) => find.descendant(of: find.byType(Dialog), matching: f);

Future<void> _settle(WidgetTester t) async {
  for (var i = 0; i < 6; i++) {
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await t.pump(const Duration(milliseconds: 100));
  }
}

/// Mở «Thêm tài khoản», liên kết hồ sơ Ngô Thanh Tâm (form tự điền tên, SĐT).
Future<void> _openAndLink(WidgetTester t) async {
  await t.tap(find.text('Thêm tài khoản').first);
  await _settle(t);
  final search = _inDialog(find.widgetWithText(TextField, 'Tìm theo tên hoặc mã nhân viên'));
  await t.tap(search);
  await t.enterText(search, 'Tâm');
  await _settle(t);
  await t.tap(find.textContaining('Ngô Thanh Tâm').last);
  await _settle(t);
  await t.enterText(_inDialog(find.widgetWithText(TextField, 'Email *')), 'tam@comganam.vn');
  await t.pump();
}

void main() {
  for (final (suffix, size) in [('', desktopSize), ('-mobile', mobileSize)]) {
    testWidgets('employee-account-1$suffix: danh sách, Thêm tài khoản', (t) async {
      await guideShot(
        t,
        name: 'employee-account-1$suffix',
        screen: const AccountsV2Screen(permOverride: {'view', 'create', 'edit', 'delete'}, myUserId: 'me'),
        api: _api,
        crumbs: _crumbs,
        size: size,
        marks: [
          GuideMark(1, [GuideMark.button(find.text('Thêm tài khoản'))]),
        ],
      );
    });

    testWidgets('employee-account-2$suffix: liên kết hồ sơ + thông tin đăng nhập', (t) async {
      await guideShot(
        t,
        name: 'employee-account-2$suffix',
        screen: const AccountsV2Screen(permOverride: {'view', 'create', 'edit', 'delete'}, myUserId: 'me'),
        api: _api,
        crumbs: [..._crumbs, 'Thêm tài khoản'],
        size: size,
        act: _openAndLink,
        marks: [
          GuideMark(1, [
            _inDialog(find.text('Liên kết hồ sơ nhân viên')),
            _inDialog(find.byTooltip('Bỏ liên kết')),
            _inDialog(find.textContaining('Không bắt buộc')),
          ]),
          GuideMark(2, [
            _inDialog(find.widgetWithText(TextField, 'Họ và tên *')),
            _inDialog(find.widgetWithText(TextField, 'Mật khẩu *')),
          ]),
        ],
      );
    });

    testWidgets('employee-account-3$suffix: chọn vai trò', (t) async {
      await guideShot(
        t,
        name: 'employee-account-3$suffix',
        screen: const AccountsV2Screen(permOverride: {'view', 'create', 'edit', 'delete'}, myUserId: 'me'),
        api: _api,
        crumbs: [..._crumbs, 'Thêm tài khoản'],
        size: size,
        act: (t) async {
          await _openAndLink(t);
          final cashier = _inDialog(find.text('Thu ngân')).first;
          await Scrollable.ensureVisible(t.element(cashier), alignment: 0.5);
          await t.pump();
          await t.tap(cashier);
          await _settle(t);
          await Scrollable.ensureVisible(t.element(_inDialog(find.text('Vai trò'))), alignment: 0.05);
          await t.pump();
        },
        marks: [
          GuideMark(1, [
            _inDialog(find.text('Vai trò')),
            GuideMark.within(_inDialog(find.text('Quản lý')).first, '_RoleChoice'),
            GuideMark.within(_inDialog(find.text('Nhân viên')).first, '_RoleChoice'),
          ]),
          GuideMark(2, [_inDialog(find.text('Khu vực bán hàng được xem')), _inDialog(find.text('Sân vườn'))]),
        ],
      );
    });
  }
}
