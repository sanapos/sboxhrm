import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zkteco_flutter_client/screens/pos/pos_qr_online_orders_screen.dart';
import 'package:zkteco_flutter_client/screens/pos/pos_qr_table_order_screen.dart';

import 'guide_shot_kit.dart';
import 'pos_guide_common.dart';

/// Ảnh cho bước «Menu QR / bán online» (pos_qr_order) — quán cà phê có QR tại bàn và đặt online.

String _ago(int minutes) => DateTime.now().subtract(Duration(minutes: minutes)).toIso8601String();

final _tables = {
  'enabled': true,
  'autoPrintKitchen': true,
  'requireOpenSession': false,
  'requireGeofence': false,
  'requireOrderConfirmation': true,
  'enableOnline': true,
  'onlineMinOrder': 50000,
  'onlineShipFee': 15000,
  'onlineFreeShipFrom': 200000,
  'onlineAutoConfirm': false,
  'onlineAutoPrintKitchen': true,
  'onlineUrl': 'https://sboxhrm.com/o/caphemoc',
  'storeName': 'Cà Phê Mộc',
  'storePhone': '0912345678',
  'storeAddress': '12 Nguyễn Trãi, Q.1, TP.HCM',
  'tables': [
    {'id': 't1', 'name': 'Bàn 1', 'areaName': 'Tầng 1', 'url': 'https://sboxhrm.com/q/caphemoc/t1'},
    {'id': 't2', 'name': 'Bàn 2', 'areaName': 'Tầng 1', 'url': 'https://sboxhrm.com/q/caphemoc/t2'},
    {'id': 't3', 'name': 'Bàn 3', 'areaName': 'Tầng 1', 'url': 'https://sboxhrm.com/q/caphemoc/t3'},
    {'id': 't4', 'name': 'Bàn 1', 'areaName': 'Sân vườn', 'url': 'https://sboxhrm.com/q/caphemoc/t4'},
  ],
};

final _statuses = [
  {'code': 'pending', 'label': 'Chờ xác nhận'},
  {'code': 'preparing', 'label': 'Đang chuẩn bị'},
  {'code': 'shipping', 'label': 'Đang giao'},
  {'code': 'delivered', 'label': 'Đã giao'},
  {'code': 'cancelled', 'label': 'Đã hủy'},
];

final _orders = [
  {
    'id': 'q1', 'orderNo': 'ON000087', 'status': 'pending', 'statusLabel': 'Chờ xác nhận', 'customerName': 'Chị Mai',
    'phone': '0905123456', 'address': '45 Lê Lợi, Q.1, TP.HCM', 'note': 'Ít đá, giao trước 10h',
    'total': 125000, 'isPaid': false, 'canPay': true, 'canPrintProvisional': true, 'createdAt': _ago(4),
    'lines': [
      {'name': 'Cà phê sữa đá', 'qty': 2, 'lineTotal': 58000},
      {'name': 'Trà đào cam sả', 'qty': 1, 'lineTotal': 42000},
      {'name': 'Bánh croissant', 'qty': 1, 'lineTotal': 25000},
    ],
  },
  {
    'id': 'q2', 'orderNo': 'ON000086', 'status': 'preparing', 'statusLabel': 'Đang chuẩn bị', 'customerName': 'Anh Khoa',
    'phone': '0938765432', 'address': '8 Pasteur, Q.3, TP.HCM', 'total': 88000, 'isPaid': true, 'canPay': false,
    'createdAt': _ago(18),
    'lines': [
      {'name': 'Bạc xỉu', 'qty': 2, 'lineTotal': 64000},
      {'name': 'Bánh mì que', 'qty': 2, 'lineTotal': 24000},
    ],
  },
];

final _api = posGuideApi((req) {
  final p = req.url.path;
  if (p.endsWith('/api/pos/qr-order/tables')) return _tables;
  if (p.contains('/api/pos/qr-order/online-orders') || p.contains('/api/pos/qr-order/online')) {
    return {'statuses': _statuses, 'orders': _orders, 'productFilters': []};
  }
  return null;
});

void main() {
  for (final (suffix, size) in [('', desktopSize), ('-mobile', mobileSize)]) {
    final mobile = suffix.isNotEmpty;
    const crumbs = ['POS', 'Menu QR / Online'];

    testWidgets('pos-qr-order-1$suffix: QR từng bàn', (t) async {
      await guideShot(
        t,
        name: 'pos-qr-order-1$suffix',
        screen: withPosPackage(const PosQrTableOrderScreen()),
        api: _api,
        crumbs: crumbs,
        size: size,
        act: (t) async => guideScrollTo(t, find.textContaining('In tất cả QR'), alignment: mobile ? 0.45 : 0.55),
        marks: [
          if (!mobile) GuideMark(1, [find.text('Tự in phiếu bếp')]),
          GuideMark(2, [find.text('Bật xác nhận order (QR)')]),
          GuideMark(3, [GuideMark.button(find.textContaining('In tất cả QR'))]),
          GuideMark(4, [find.text('Tầng 1 · Bàn 1'), find.byTooltip('In QR').first]),
        ],
      );
    });

    testWidgets('pos-qr-order-2$suffix: đặt hàng online', (t) async {
      await guideShot(
        t,
        name: 'pos-qr-order-2$suffix',
        screen: withPosPackage(const PosQrTableOrderScreen()),
        api: _api,
        crumbs: crumbs,
        size: size,
        act: (t) async => guideScrollTo(t, find.text('Đặt hàng online ngoài cửa hàng'), alignment: 0.08),
        marks: [
          GuideMark(1, [find.text('Đặt hàng online ngoài cửa hàng'), find.textContaining('QR riêng cho khách ngoài quán')]),
          GuideMark(2, [find.text('Quy tắc đơn online'), find.textContaining('Tối thiểu 50.000')]),
          GuideMark(3, [find.text('Tự xác nhận đơn online'), find.text('Tự in bếp khi đơn online được xác nhận')]),
        ],
      );
    });

    testWidgets('pos-qr-order-3$suffix: đơn online', (t) async {
      await guideShot(
        t,
        name: 'pos-qr-order-3$suffix',
        screen: withPosPackage(const PosQrOnlineOrdersScreen()),
        api: _api,
        crumbs: const ['POS', 'Menu QR / Online', 'Đơn online'],
        size: size,
        act: (t) async {
          await t.tap(find.text('ON000087'));
          for (var i = 0; i < 6; i++) {
            await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
            await t.pump(const Duration(milliseconds: 100));
          }
        },
        marks: [
          GuideMark(1, [find.text('Đơn ON000087')]),
          GuideMark(2, [find.textContaining('Cà phê sữa đá').last, find.text('Ít đá, giao trước 10h')]),
          GuideMark(3, [GuideMark.button(find.text('In bếp')), GuideMark.button(find.text('Thanh toán'))]),
          GuideMark(4, [GuideMark.button(find.text('Xác nhận đơn')), GuideMark.button(find.text('Hủy đơn'))]),
        ],
      );
    });
  }
}
