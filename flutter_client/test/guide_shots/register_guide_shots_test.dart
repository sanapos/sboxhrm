import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zkteco_flutter_client/screens/register_screen.dart';

import 'guide_shot_kit.dart';

/// Ảnh cho bước hướng dẫn «Đăng ký phần mềm» (id: register).

final _packages = [
  {
    'id': 'pk1', 'name': 'Dùng thử 14 ngày', 'description': 'Đủ chấm công, lương, bán hàng cho cửa hàng nhỏ',
    'defaultDurationDays': 14, 'trialDays': 14, 'maxUsers': 10, 'maxDevices': 2, 'maxAccessDevices': 10, 'maxBranches': 1,
    'allowWeb': true, 'allowMobile': true, 'monthlyPrice': 199000, 'yearlyPrice': 1990000,
    'modules': [
      for (final m in ['Chấm công', 'Tính lương', 'Lịch làm việc', 'Nghỉ phép', 'Bán hàng', 'Kho hàng', 'Báo cáo'])
        {'displayName': m, 'category': 'Chức năng'},
    ],
  },
  {
    'id': 'pk2', 'name': 'Chuyên nghiệp', 'description': 'Nhiều chi nhánh, KPI, hóa đơn điện tử',
    'defaultDurationDays': 30, 'maxUsers': 50, 'maxDevices': 10, 'maxAccessDevices': 50, 'maxBranches': 5,
    'allowWeb': true, 'allowMobile': true, 'monthlyPrice': 499000, 'yearlyPrice': 4990000,
  },
];

final _api = guideApi({
  '/api/auth/publicservicepackages': _packages,
  '/api/Auth/CheckStoreCode': {'available': true, 'suggestions': <String>[]},
  '/api/Auth/CheckEmail': {'available': true},
});

const _crumbs = ['sboxhrm.com', 'Đăng ký'];

Finder _field(String hint) =>
    find.byWidgetPredicate((w) => w is TextField && w.decoration?.hintText == hint);

Finder _box(String hint) => find.ancestor(of: _field(hint), matching: find.byType(TextFormField)).first;

Future<void> _fill(WidgetTester t) async {
  await t.enterText(_field('Nhập tên doanh nghiệp của bạn'), 'Cơm Gà Nam');
  await t.pump(const Duration(milliseconds: 100));
  await t.enterText(_field('Nhập email đăng nhập'), 'chu.cuahang@gmail.com');
  await t.enterText(_field('Nhập số điện thoại liên hệ'), '0912345678');
  await t.enterText(_field('Nhập mật khẩu'), 'Comganam@2026');
  await t.enterText(_field('Nhập lại mật khẩu'), 'Comganam@2026');
  // Chờ kiểm tra mã / email (debounce 500–600ms).
  for (var i = 0; i < 10; i++) {
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
    await t.pump(const Duration(milliseconds: 120));
  }
}

void main() {
  for (final (suffix, size) in [('', desktopSize), ('-mobile', mobileSize)]) {
    testWidgets('register-1$suffix: tên doanh nghiệp, mã cửa hàng', (t) async {
      await guideShot(
        t,
        name: 'register-1$suffix',
        screen: const RegisterScreen(),
        api: _api,
        crumbs: _crumbs,
        size: size,
        act: (t) async {
          await _fill(t);
          await guideScrollTo(t, _field('Nhập tên doanh nghiệp của bạn'), alignment: 0.1);
        },
        marks: [
          GuideMark(1, [_box('Nhập tên doanh nghiệp của bạn')]),
          GuideMark(2, [_box('Ví dụ: sanapos — chỉ chữ và số, không dấu')]),
        ],
      );
    });

    testWidgets('register-2$suffix: email, SĐT', (t) async {
      await guideShot(
        t,
        name: 'register-2$suffix',
        screen: const RegisterScreen(),
        api: _api,
        crumbs: _crumbs,
        size: size,
        act: (t) async {
          await _fill(t);
          await guideScrollTo(t, _field('Nhập email đăng nhập'), alignment: 0.15);
        },
        marks: [
          GuideMark(1, [_box('Nhập email đăng nhập')]),
          GuideMark(2, [_box('Nhập số điện thoại liên hệ')]),
        ],
      );
    });

    testWidgets('register-3$suffix: chọn gói, mật khẩu, đăng ký', (t) async {
      await guideShot(
        t,
        name: 'register-3$suffix',
        screen: const RegisterScreen(),
        api: _api,
        crumbs: _crumbs,
        size: size,
        act: (t) async {
          await _fill(t);
          await guideScrollTo(t, find.byType(FilledButton), alignment: 0.85);
        },
        marks: [
          GuideMark(1, [find.byType(DropdownButtonFormField<String>).last]),
          GuideMark(2, [_box('Nhập mật khẩu'), _box('Nhập lại mật khẩu')]),
          GuideMark(3, [find.byType(FilledButton)]),
        ],
      );
    });
  }
}
