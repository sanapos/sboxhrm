import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zkteco_flutter_client/screens/pos/pos_warranty_lookup_screen.dart';

import 'guide_shot_kit.dart';
import 'pos_guide_common.dart';

/// Ảnh cho bước «Bảo hành» (pos_warranty) — cửa hàng điện máy.

String _day(int ago) => DateTime.now().subtract(Duration(days: ago)).toIso8601String();

final _claims = [
  {
    'id': 'c1', 'claimNo': 'BH2610-003', 'claimType': 'Repair', 'status': 'Done', 'productName': 'Nồi cơm điện Sharp 1.8L',
    'serialNumber': 'SH18-2409-7731', 'contactName': 'Chị Lan', 'contactPhone': '0912345678',
    'receivedDate': _day(6), 'expectedReturnDate': _day(-1), 'description': 'Không nấu chín, đèn báo nhấp nháy',
    'deviceCondition': 'Vỏ trầy nhẹ', 'accessories': 'Lồng nồi, dây nguồn', 'assignedTo': 'Anh Tuấn kỹ thuật',
    'resolution': 'Thay rơ-le nhiệt', 'fee': 0,
  },
  {
    'id': 'c2', 'claimNo': 'BH2610-004', 'claimType': 'Repair', 'status': 'Processing', 'productName': 'Máy xay sinh tố Philips',
    'serialNumber': 'PH-HR2221-0088', 'contactName': 'Anh Minh', 'contactPhone': '0987654321',
    'receivedDate': _day(3), 'expectedReturnDate': _day(-2), 'description': 'Kêu to, lưỡi dao không quay',
    'deviceCondition': 'Bình xay nứt nhẹ', 'accessories': 'Bình xay', 'assignedTo': 'Anh Tuấn kỹ thuật',
  },
  {
    'id': 'c3', 'claimNo': 'BH2610-005', 'claimType': 'Repair', 'status': 'Received', 'productName': 'Quạt đứng Senko',
    'serialNumber': 'SK-DH1600-5521', 'contactName': 'Cô Hoa', 'contactPhone': '0905111222',
    'receivedDate': _day(1), 'expectedReturnDate': _day(-4), 'description': 'Không xoay đảo chiều',
  },
];

final _machines = [
  {
    'id': 'w1', 'productName': 'Nồi cơm điện Sharp 1.8L', 'serialNumber': 'SH18-2409-7731', 'orderNo': 'HD000412',
    'customerName': 'Chị Lan', 'customerPhone': '0912345678', 'saleDate': _day(120), 'warrantyMonths': 12,
    'warrantyExpiry': _day(-245), 'status': 'Active', 'claimCount': 1, 'openClaimStatus': 'Done',
  },
  {
    'id': 'w2', 'productName': 'Tivi Samsung 55 inch', 'serialNumber': 'SS55-CU7000-1209', 'imei': '',
    'orderNo': 'HD000398', 'customerName': 'Anh Hùng', 'customerPhone': '0938222333', 'saleDate': _day(300),
    'warrantyMonths': 24, 'warrantyExpiry': _day(-430), 'status': 'Active', 'claimCount': 0,
  },
  {
    'id': 'w3', 'productName': 'Máy lọc nước Kangaroo', 'serialNumber': 'KG-KG10A3-4410', 'orderNo': 'HD000351',
    'customerName': 'Chị Thu', 'customerPhone': '0977444555', 'saleDate': _day(350), 'warrantyMonths': 12,
    'warrantyExpiry': _day(-15), 'status': 'Active', 'claimCount': 0,
  },
];

final _report = {
  'from': _day(30), 'to': _day(0), 'inShopNow': 2, 'readyToReturn': 1, 'overdueNow': 0, 'activeWarranties': 186,
  'expiring30': 7, 'totalClaims': 14, 'repairs': 11, 'replaces': 3, 'rejected': 1, 'outOfWarranty': 2,
  'avgDays': 3.5, 'feeCollected': 450000, 'feeUnpaid': 150000,
  'byMonth': [
    {'month': '08/2026', 'claims': 9, 'replaces': 1, 'fee': 200000},
    {'month': '09/2026', 'claims': 12, 'replaces': 2, 'fee': 350000},
    {'month': '10/2026', 'claims': 14, 'replaces': 3, 'fee': 600000},
  ],
  'byProduct': [
    {'productName': 'Máy xay sinh tố Philips', 'claims': 5, 'replaces': 1, 'sold': 40, 'ratePercent': 12.5},
    {'productName': 'Nồi cơm điện Sharp 1.8L', 'claims': 4, 'replaces': 0, 'sold': 62, 'ratePercent': 6.5},
  ],
};

final _api = posGuideApi((req) {
  final p = req.url.path;
  if (p.endsWith('/api/pos/warranty/claims')) return {'items': _claims, 'total': _claims.length};
  if (p.endsWith('/api/pos/warranty/report')) return _report;
  if (p.endsWith('/api/pos/warranty/expiring')) return {'items': [_machines[2]], 'total': 1};
  if (p.endsWith('/api/pos/warranty')) return {'items': _machines, 'total': _machines.length};
  return null;
});

void main() {
  for (final (suffix, size) in [('', desktopSize), ('-mobile', mobileSize)]) {
    final mobile = suffix.isNotEmpty;
    const crumbs = ['POS', 'Bảo hành'];

    testWidgets('pos-warranty-1$suffix: phiếu bảo hành', (t) async {
      await guideShot(
        t,
        name: 'pos-warranty-1$suffix',
        screen: withPosPackage(const PosWarrantyLookupScreen()),
        api: _api,
        crumbs: crumbs,
        size: size,
        marks: [
          GuideMark(1, [find.text('Máy ở cửa hàng').first, find.text('Tất cả').first]),
          GuideMark(2, [find.text('BH2610-003 · Nồi cơm điện Sharp 1.8L'), find.text('Sửa xong — chờ trả')]),
          GuideMark(3, [GuideMark.button(find.text('Trả khách')), GuideMark.button(find.text('In phiếu').first)]),
          if (!mobile)
            GuideMark(4, [GuideMark.button(find.text('Hoàn tất')), GuideMark.button(find.text('Từ chối'))]),
        ],
      );
    });

    testWidgets('pos-warranty-2$suffix: máy đã bán', (t) async {
      await guideShot(
        t,
        name: 'pos-warranty-2$suffix',
        screen: withPosPackage(const PosWarrantyLookupScreen()),
        api: _api,
        crumbs: crumbs,
        size: size,
        act: (t) async {
          await t.tap(find.text('Máy đã bán'));
          await t.pumpAndSettle(const Duration(milliseconds: 100));
          if (mobile) await guideScrollTo(t, find.text('SS55-CU7000-1209'), alignment: 0.05);
        },
        marks: [
          if (!mobile) GuideMark(1, [find.textContaining('Tìm seri / IMEI'), find.text('Khách đã trả hàng')]),
          GuideMark(2, [find.text('SS55-CU7000-1209'), find.textContaining('BH 24 tháng')]),
          GuideMark(3, [GuideMark.button(find.text('Tiếp nhận BH').first)]),
          GuideMark(4, [GuideMark.button(find.text('Đổi máy').at(1))]),
        ],
      );
    });

    testWidgets('pos-warranty-3$suffix: báo cáo', (t) async {
      await guideShot(
        t,
        name: 'pos-warranty-3$suffix',
        screen: withPosPackage(const PosWarrantyLookupScreen()),
        api: _api,
        crumbs: crumbs,
        size: size,
        act: (t) async {
          await t.ensureVisible(find.text('Báo cáo'));
          await t.pumpAndSettle(const Duration(milliseconds: 100));
          await t.tap(find.text('Báo cáo'));
          await t.pumpAndSettle(const Duration(milliseconds: 100));
          for (var i = 0; i < 4; i++) {
            await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
            await t.pump(const Duration(milliseconds: 100));
          }
        },
        marks: [
          GuideMark(1, [find.text('Hiện tại'), find.textContaining('hết hạn trong 30 ngày')], pad: 10),
          GuideMark(2, [find.text('Phí sửa đã thu'), find.textContaining('Chưa thu 150.000')], pad: 12),
          if (!mobile) GuideMark(3, [find.text('Mặt hàng hay bảo hành'), find.text('Nồi cơm điện Sharp 1.8L').last]),
        ],
      );
    });
  }
}
