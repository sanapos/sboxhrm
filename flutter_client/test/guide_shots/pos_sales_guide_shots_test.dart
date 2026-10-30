import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zkteco_flutter_client/screens/pos_sell_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zkteco_flutter_client/services/pos_network_monitor.dart';
import 'package:zkteco_flutter_client/services/pos_offline_service.dart';

import 'guide_shot_kit.dart';
import 'pos_guide_common.dart';

/// Ảnh cho bước hướng dẫn «Quy trình bán hàng» (id: pos_sales) — quán cà phê.

final _categories = [
  {'id': 'c1', 'name': 'Cà phê', 'productCount': 4},
  {'id': 'c2', 'name': 'Trà & nước ép', 'productCount': 2},
  {'id': 'c3', 'name': 'Bánh ngọt', 'productCount': 1},
];

Map<String, Object?> _p(String id, String code, String name, String cat, String catName, num price,
        {num onHand = 100, String unit = 'Ly'}) =>
    {
      'id': id, 'productCode': code, 'name': name, 'categoryId': cat, 'categoryName': catName,
      'basePrice': price, 'costPrice': price * 0.3, 'onHandQty': onHand, 'productType': '0',
      'baseUnitName': unit, 'isActive': true, 'isDirectSale': true,
    };

final _products = [
  _p('p1', 'CFD', 'Cà phê đen đá', 'c1', 'Cà phê', 25000),
  _p('p2', 'CFS', 'Cà phê sữa đá', 'c1', 'Cà phê', 29000),
  _p('p3', 'BX', 'Bạc xỉu', 'c1', 'Cà phê', 32000),
  _p('p4', 'CFM', 'Cà phê muối', 'c1', 'Cà phê', 35000),
  _p('p5', 'TDCS', 'Trà đào cam sả', 'c2', 'Trà & nước ép', 39000),
  _p('p6', 'NECAM', 'Nước ép cam', 'c2', 'Trà & nước ép', 35000),
  _p('p7', 'TIRA', 'Bánh tiramisu', 'c3', 'Bánh ngọt', 45000, unit: 'Cái'),
];

final _api = posGuideApi((req) {
  final p = req.url.path;
  if (p.endsWith('/api/pos/catalog/categories')) return _categories;
  // Tài khoản nhận chuyển khoản — nút «Chuyển khoản» ở màn thanh toán mới bấm được.
  if (p.endsWith('/api/pos/sales/bank-accounts')) {
    return [
      {'id': 'b1', 'bankName': 'Vietcombank', 'bankShortName': 'VCB', 'bankCode': 'VCB', 'accountNumber': '0071000123456',
        'accountName': 'NGUYEN VAN AN', 'isActive': true, 'isDefault': true},
    ];
  }
  if (p.endsWith('/api/pos/products') || p.endsWith('/api/pos/sales/products')) {
    return {'items': _products, 'totalCount': _products.length, 'total': _products.length, 'page': 1, 'totalPages': 1};
  }
  return null;
});

/// Kênh máy thật (máy quét Sunmi, thư mục app) không có trong test — trả rỗng.
void _mockDeviceChannels() {
  final m = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  m.setMockStreamHandler(const EventChannel('com.sboxhrm/sunmi_scanner'), MockStreamHandler.inline(onListen: (_, __) {}));
  m.setMockMethodCallHandler(const MethodChannel('plugins.flutter.io/path_provider'),
      (_) async => Directory.systemTemp.createTempSync('sbox_guide').path);
}

/// Thêm 2 Cà phê sữa đá + Trà đào + Tiramisu vào hóa đơn (điện thoại: qua «Chọn hàng»).
Future<void> _fillCart(WidgetTester t) async {
  final mobile = t.view.physicalSize.width < 600;
  if (mobile) {
    await t.tap(find.text('Chọn hàng'));
    await t.pump(const Duration(milliseconds: 600));
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await t.pump(const Duration(milliseconds: 300));
  }
  for (final name in ['Cà phê sữa đá', 'Cà phê sữa đá', 'Trà đào cam sả', 'Bánh tiramisu']) {
    // Máy tính: lưới món bên trái (tên món cũng hiện trong giỏ bên phải); điện thoại: bảng chọn món.
    await t.tap(mobile ? find.text(name).last : find.text(name).first);
    await t.pump(const Duration(milliseconds: 300));
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await t.pump(const Duration(milliseconds: 100));
  }
  if (mobile) {
    // Bảng chọn món giữ số lượng nháp — nút cuối bảng (cùng tên «Chọn hàng») mới đưa vào hóa đơn.
    await t.tap(find.widgetWithText(FilledButton, 'Chọn hàng').last);
    await t.pump(const Duration(milliseconds: 600));
  }
}

void main() {
  setUp(_mockDeviceChannels);

  // Dịch vụ nền của màn bán (đo mạng, đồng bộ đơn offline) tạo hẹn giờ lặp lần đầu khởi động —
  // khởi động trước ở vùng thời gian thật để test không báo «hẹn giờ còn treo».
  setUpAll(() async {
    _mockDeviceChannels();
    SharedPreferences.setMockInitialValues({});
    await PosNetworkMonitor.instance.start();
    await PosOfflineService.instance.init('s1');
  });

  for (final (suffix, size) in [('', desktopSize), ('-mobile', mobileSize)]) {
    final mobile = suffix.isNotEmpty;
    testWidgets('pos-sales-1$suffix: màn bán hàng', (t) async {
      await guideShot(
        t,
        name: 'pos-sales-1$suffix',
        screen: withPosPackage(const PosSellScreen()),
        api: _api,
        crumbs: const ['POS', 'Bán hàng'],
        size: size,
        act: _fillCart,
        marks: [
          GuideMark(1, mobile ? [GuideMark.button(find.text('Quét mã'))] : [find.byIcon(Icons.search).first, find.textContaining('Tìm hàng')], pad: 10),
          GuideMark(2, [mobile ? GuideMark.button(find.text('Chọn hàng')) : GuideMark.within(find.text('Cà phê sữa đá').first, 'GestureDetector')]),
          GuideMark(3, [find.text('Cà phê sữa đá').last, find.textContaining('58.000'), if (mobile) find.byIcon(Icons.remove).last], pad: 10),
          GuideMark(4, [GuideMark.button(find.textContaining('Thanh toán'))]),
        ],
      );
    }, timeout: const Timeout(Duration(seconds: 120)));

    testWidgets('pos-sales-2$suffix: thanh toán', (t) async {
      await guideShot(
        t,
        name: 'pos-sales-2$suffix',
        screen: withPosPackage(const PosSellScreen()),
        api: _api,
        crumbs: const ['POS', 'Bán hàng', 'Thanh toán'],
        size: size,
        act: (t) async {
          await _fillCart(t);
          await t.tap(find.textContaining('Thanh toán').last);
          await t.pump(const Duration(milliseconds: 600));
          await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
          await t.pump(const Duration(milliseconds: 400));
        },
        marks: [
          GuideMark(1, [GuideMark.button(find.text('Tiền mặt').first), GuideMark.button(find.text('Ghi nợ'))]),
          GuideMark(2, [GuideMark.button(find.text('In hóa đơn'))]),
          GuideMark(3, [GuideMark.button(find.text(mobile ? 'Hoàn thành' : 'HOÀN TẤT THANH TOÁN (F9)'))]),
        ],
      );
    }, timeout: const Timeout(Duration(seconds: 120)));

  }
}
