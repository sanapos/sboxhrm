import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zkteco_flutter_client/screens/meal_tracking_screen.dart';

import 'guide_shot_kit.dart';
import 'hrm_extras_common.dart';

/// Ảnh cho bước hướng dẫn «Chấm cơm» (id: meal).

final _sessions = [
  {'id': 'm1', 'name': 'Sáng', 'startTime': '06:30', 'endTime': '08:00', 'pricePerMeal': 20000, 'isActive': true, 'createdAt': '2026-09-01T00:00:00Z'},
  {'id': 'm2', 'name': 'Trưa', 'startTime': '11:00', 'endTime': '13:00', 'pricePerMeal': 30000, 'isActive': true, 'createdAt': '2026-09-01T00:00:00Z'},
  {'id': 'm3', 'name': 'Tối', 'startTime': '17:30', 'endTime': '19:00', 'pricePerMeal': 30000, 'isActive': true, 'createdAt': '2026-09-01T00:00:00Z'},
];

Map<String, dynamic> _live(String id, String name, String from, String to,
        {required int served, required int registered, required int walkIn, required List<String> noShow, required int price, required List<String> dishes}) =>
    {
      'id': id, 'name': name, 'startTime': from, 'endTime': to, 'served': served, 'registered': registered,
      'walkIn': walkIn, 'noShow': noShow.length, 'noShowNames': noShow, 'amount': served * price,
      'dishes': [for (final d in dishes) {'dishName': d}],
    };

final _canteen = {
  'currentSessionId': 'm2',
  'totals': {'served': 61, 'people': 34, 'registered': 66, 'walkIn': 4, 'noShow': 9, 'amount': 1650000, 'unprinted': 0},
  'sessions': [
    _live('m1', 'Sáng', '06:30', '08:00', served: 18, registered: 20, walkIn: 1, noShow: ['Võ Minh Tuấn', 'Bùi Quốc Bảo', 'Đặng Thu Hà'],
        price: 20000, dishes: ['Bánh mì ốp la', 'Cà phê sữa']),
    _live('m2', 'Trưa', '11:00', '13:00', served: 31, registered: 32, walkIn: 2, noShow: ['Hồ Ngọc Ánh', 'Trần Thị Lan', 'Phạm Thị Hoa'],
        price: 30000, dishes: ['Cơm gà xối mỡ', 'Canh bí đỏ', 'Dưa hấu']),
    _live('m3', 'Tối', '17:30', '19:00', served: 12, registered: 14, walkIn: 1, noShow: ['Lê Văn Minh', 'Nguyễn Văn Hùng', 'Võ Minh Tuấn'],
        price: 30000, dishes: ['Bún bò Huế']),
  ],
  'recent': [
    {'ticketNo': 'P-0131', 'name': 'Lê Văn Minh', 'department': 'Bếp', 'session': 'Trưa', 'time': '11:52', 'source': 'Máy chấm cơm', 'printed': true},
    {'ticketNo': 'P-0130', 'name': 'Phạm Thị Hoa', 'department': 'Thu ngân', 'session': 'Trưa', 'time': '11:49', 'source': 'Máy chấm cơm', 'printed': true},
    {'ticketNo': 'P-0129', 'name': 'Võ Minh Tuấn', 'department': 'Phục vụ', 'session': 'Trưa', 'time': '11:47', 'source': 'Quầy', 'printed': true},
  ],
};

Map<String, dynamic> _debt(String id, String name, String code, int meals, int charged, int paid) => {
      'employeeUserId': id, 'employeeName': name, 'employeeCode': code, 'totalMeals': meals,
      'totalCharged': charged, 'totalPaid': paid, 'balance': charged - paid,
    };

final _debts = [
  _debt('u3', 'Lê Văn Minh', '3', 44, 1240000, 0),
  _debt('u2', 'Trần Thị Lan', '2', 38, 1060000, 1060000),
  _debt('u4', 'Phạm Thị Hoa', '4', 40, 1120000, 500000),
  _debt('u5', 'Võ Minh Tuấn', '5', 29, 790000, 790000),
  _debt('u8', 'Hồ Ngọc Ánh', '8', 21, 630000, 0),
];

final _api = guideApi({
  '/api/meals/sessions': _sessions,
  '/api/meals/canteen/live': _canteen,
  '/api/meals/debt/summary': _debts,
  '/api/meals/dishes': [],
  '/api/meals/menu/weekly': [],
  '/api/meals/today': {},
  '/api/employees': {'items': extrasEmployees, 'totalCount': extrasEmployees.length},
});

const _crumbs = ['Chấm cơm'];

Finder _tile(String title) => find.ancestor(of: find.text(title).last, matching: find.byType(ListTile)).first;

Future<void> _openTab(WidgetTester t, String label) async {
  await t.tap(find.text(label).first);
  await extrasSettle(t, 8);
}

void main() {
  for (final (suffix, size) in [('', desktopSize), ('-mobile', mobileSize)]) {
    final mobile = size.width < 600;

    testWidgets('meal-1$suffix: thêm buổi ăn', (t) async {
      await guideShot(
        t,
        name: 'meal-1$suffix',
        screen: withExtrasPackage(const MealTrackingScreen()),
        api: _api,
        crumbs: [..._crumbs, 'Quản lý buổi ăn'],
        size: size,
        act: (t) async {
          if (mobile) {
            // Điện thoại: màn không có thao tác chính → mọi thao tác gom trong nút «Thao tác».
            await t.tap(find.byIcon(Icons.apps_rounded));
            await extrasSettle(t, 4);
          }
          await t.tap(mobile ? find.text('Quản lý buổi ăn').last : topAction('Quản lý buổi ăn'));
          await extrasSettle(t, 4);
          await t.tap(find.byIcon(Icons.add).last);
          await extrasSettle(t, 4);
          await t.enterText(fieldLabeled('Tên buổi ăn *'), 'Trưa');
          await t.enterText(fieldLabeled('Giá mỗi suất (đ)'), '30000');
          await t.pump();
        },
        marks: [
          GuideMark(1, [fieldLabeled('Tên buổi ăn *')]),
          GuideMark(2, [fieldLabeled('Giá mỗi suất (đ)')]),
          GuideMark(3, [_tile('Giờ bắt đầu'), _tile('Giờ kết thúc')]),
        ],
      );
    });

    testWidgets('meal-2$suffix: căn tin', (t) async {
      await guideShot(
        t,
        name: 'meal-2$suffix',
        screen: withExtrasPackage(const MealTrackingScreen()),
        api: _api,
        crumbs: [..._crumbs, 'Căn tin'],
        size: size,
        act: (t) => _openTab(t, 'Căn tin'),
        marks: [
          GuideMark(1, [cardOf(find.text('Suất đã phục vụ').first), cardOf(find.text('Đăng ký chưa ăn').first)], pad: 4),
          GuideMark(2, [cardOf(find.textContaining('Sáng  ·').first)], pad: 4),
        ],
      );
    });

    testWidgets('meal-3$suffix: công nợ tiền cơm', (t) async {
      await guideShot(
        t,
        name: 'meal-3$suffix',
        screen: withExtrasPackage(const MealTrackingScreen()),
        api: _api,
        crumbs: [..._crumbs, 'Công nợ'],
        size: size,
        act: (t) async {
          await t.ensureVisible(find.text('Công nợ').first);
          await _openTab(t, 'Công nợ');
        },
        marks: [
          GuideMark(1, [GuideMark.button(find.text('Tính tiền cơm tháng'))]),
          GuideMark(2, [cardOf(find.text('Lê Văn Minh').first)], pad: 4),
        ],
      );
    });
  }
}
