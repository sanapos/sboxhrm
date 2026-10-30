import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zkteco_flutter_client/screens/pos/pos_customers_screen.dart';

import 'guide_shot_kit.dart';
import 'pos_guide_common.dart';

/// Ảnh cho bước hướng dẫn «Khách hàng, điểm & công nợ» (id: pos_customers) — quán cà phê.

Map<String, Object?> _c(String id, String code, String name, String phone,
        {num total = 0, num debt = 0, num points = 0, int orders = 0, String? birthday, int lastDays = 3}) =>
    {
      'id': id, 'customerCode': code, 'name': name, 'phone': phone, 'totalPurchase': total,
      'currentDebt': debt, 'pointBalance': points, 'orderCount': orders, 'isActive': true,
      'birthday': birthday,
      'lastPurchaseAt': DateTime.now().subtract(Duration(days: lastDays)).toIso8601String(),
    };

final _customers = [
  _c('k1', 'KH0001', 'Trần Thị Mai', '0903 456 789', total: 4850000, points: 485, orders: 62, birthday: '1992-03-14', lastDays: 1),
  _c('k2', 'KH0002', 'Công ty TNHH Minh Phát', '0283 822 1188', total: 12600000, debt: 1850000, points: 1260, orders: 18, lastDays: 2),
  _c('k3', 'KH0003', 'Lê Hoàng Nam', '0912 334 556', total: 1320000, points: 132, orders: 21, birthday: '1998-11-02', lastDays: 5),
  _c('k4', 'KH0004', 'Phạm Ngọc Anh', '0938 112 233', total: 760000, points: 76, orders: 9, lastDays: 12),
  _c('k5', 'KH0005', 'Võ Minh Khoa', '0977 889 900', total: 2140000, debt: 320000, points: 214, orders: 30, lastDays: 4),
];

final _api = posGuideApi((req) {
  final p = req.url.path;
  if (p.endsWith('/api/pos/customers')) {
    return {
      'items': _customers,
      'total': _customers.length,
      'sumDebt': 2170000,
      'sumPurchase': 21670000,
      'sumPoints': 2167,
      'birthdaysThisMonth': 1,
    };
  }
  if (p.endsWith('/api/pos/customers/tiers')) return [];
  if (p.endsWith('/history')) {
    return {
      'orders': [
        {'id': 'o1', 'orderNo': 'HD000412', 'createdAt': '2026-10-28T09:12:00', 'payableTotal': 1250000, 'paidAmount': 0, 'balanceDue': 1250000, 'paymentMethod': 'debt', 'status': 'Completed'},
        {'id': 'o2', 'orderNo': 'HD000398', 'createdAt': '2026-10-21T14:30:00', 'payableTotal': 600000, 'paidAmount': 0, 'balanceDue': 600000, 'paymentMethod': 'debt', 'status': 'Completed'},
        {'id': 'o3', 'orderNo': 'HD000350', 'createdAt': '2026-10-02T10:05:00', 'payableTotal': 980000, 'paidAmount': 980000, 'balanceDue': 0, 'paymentMethod': 'transfer', 'status': 'Completed'},
      ],
      'payments': [],
    };
  }
  if (p.endsWith('/api/pos/quotes/customer-care')) return {'quotes': [], 'activities': []};
  if (p.endsWith('/purchase-history')) return {'products': []};
  if (p.endsWith('/points')) return {'items': []};
  if (p.contains('/api/pos/customers/k2')) return _customers[1];
  return null;
});

void main() {
  for (final (suffix, size) in [('', desktopSize), ('-mobile', mobileSize)]) {
    final mobile = suffix.isNotEmpty;

    testWidgets('pos-customers-1$suffix: danh sách khách', (t) async {
      await guideShot(
        t,
        name: 'pos-customers-1$suffix',
        screen: withPosPackage(const PosCustomersScreen()),
        api: _api,
        crumbs: const ['POS', 'Khách hàng POS'],
        size: size,
        marks: [
          GuideMark(1, [mobile ? GuideMark.button(find.byIcon(Icons.person_add_alt_1_outlined)) : GuideMark.button(find.text('Thêm khách'))]),
          GuideMark(2, [find.text('Công ty TNHH Minh Phát'), find.text('0283 822 1188'), if (mobile) find.textContaining('1.850.000')], pad: 10),
        ],
      );
    });

    testWidgets('pos-customers-2$suffix: công nợ, thu nợ', (t) async {
      await guideShot(
        t,
        name: 'pos-customers-2$suffix',
        screen: withPosPackage(const PosCustomersScreen()),
        api: _api,
        crumbs: const ['POS', 'Khách hàng POS', 'Chi tiết khách'],
        size: size,
        act: (t) async {
          await t.tap(find.text('Công ty TNHH Minh Phát').first);
          await t.pump(const Duration(milliseconds: 600));
          await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
          await t.pump(const Duration(milliseconds: 400));
        },
        marks: [
          GuideMark(1, [find.text('Công nợ').first, find.textContaining('1.850.000').first], pad: 12),
          GuideMark(2, [GuideMark.button(find.text('Thu nợ'))]),
        ],
      );
    });
  }
}
