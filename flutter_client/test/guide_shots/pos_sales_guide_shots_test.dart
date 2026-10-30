import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:zkteco_flutter_client/screens/pos_sell_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zkteco_flutter_client/services/pos_network_monitor.dart';
import 'package:zkteco_flutter_client/services/pos_offline_service.dart';

import 'guide_shot_kit.dart';
import 'pos_guide_common.dart';

/// Ảnh cho các bước bán hàng — quán cà phê: chọn hàng (pos_sales), sửa món (pos_sale_edit),
/// khách hàng & thanh toán (pos_sale_pay).

final _categories = [
  {'id': 'c1', 'name': 'Cà phê', 'productCount': 4},
  {'id': 'c2', 'name': 'Trà & nước ép', 'productCount': 2},
  {'id': 'c3', 'name': 'Bánh ngọt', 'productCount': 1},
];

Map<String, Object?> _p(String id, String code, String name, String cat, String catName, num price,
        {num onHand = 100, String unit = 'Ly', Map<String, Object?> extra = const {}}) =>
    {
      'id': id, 'productCode': code, 'name': name, 'categoryId': cat, 'categoryName': catName,
      'basePrice': price, 'costPrice': price * 0.3, 'onHandQty': onHand, 'productType': '0',
      'baseUnitName': unit, 'isActive': true, 'isDirectSale': true,
      ...extra,
    };

/// Ghi chú nhanh + tùy chọn thêm (topping) + hoa hồng pha chế — cho ảnh sửa món.
const _drinkExtras = <String, Object?>{
  'saleQuickNotes': ['Ít đá', 'Ít ngọt', 'Nhiều sữa', 'Mang đi'],
  'commissionMode': 'Percent', 'commissionPercent': 3,
};
const _teaExtras = <String, Object?>{
  'saleQuickNotes': ['Ít đá', 'Không đường', 'Mang đi'],
  'allowToppings': true,
  'toppingOptions': [
    {'id': 'tp1', 'toppingProductId': 'tp1', 'toppingName': 'Trân châu trắng', 'toppingProductName': 'Trân châu trắng', 'extraPrice': 8000, 'sortOrder': 1},
    {'id': 'tp2', 'toppingProductId': 'tp2', 'toppingName': 'Thạch đào', 'toppingProductName': 'Thạch đào', 'extraPrice': 6000, 'sortOrder': 2},
    {'id': 'tp3', 'toppingProductId': 'tp3', 'toppingName': 'Kem cheese', 'toppingProductName': 'Kem cheese', 'extraPrice': 10000, 'sortOrder': 3},
  ],
  'commissionMode': 'Percent', 'commissionPercent': 3,
};

final _products = [
  _p('p1', 'CFD', 'Cà phê đen đá', 'c1', 'Cà phê', 25000),
  _p('p2', 'CFS', 'Cà phê sữa đá', 'c1', 'Cà phê', 29000, extra: _drinkExtras),
  _p('p3', 'BX', 'Bạc xỉu', 'c1', 'Cà phê', 32000),
  _p('p4', 'CFM', 'Cà phê muối', 'c1', 'Cà phê', 35000),
  _p('p5', 'TDCS', 'Trà đào cam sả', 'c2', 'Trà & nước ép', 39000, extra: _teaExtras),
  _p('p6', 'NECAM', 'Nước ép cam', 'c2', 'Trà & nước ép', 35000),
  _p('p7', 'TIRA', 'Bánh tiramisu', 'c3', 'Bánh ngọt', 45000, unit: 'Cái'),
];

final _api = _sellApi();

/// [commission]: bật «Hoa hồng nhân viên» — dòng món hiện «Chọn NV hoa hồng».
MockClient _sellApi({bool commission = false}) => posGuideApi((req) {
  final p = req.url.path;
  if (p.endsWith('/api/pos/catalog/categories')) return _categories;
  if (commission && p.endsWith('/api/pos/sell-settings')) {
    return {'id': 'ss1', 'sellProfile': 'retail', 'enableStaffCommission': true};
  }
  if (req.method == 'POST' && p.endsWith('/api/pos/sales/invoice-slots')) {
    return {
      'addedSlot': 2,
      'items': [
        {'invoiceSlot': 1, 'lineCount': 3, 'total': 142000},
        {'id': 'draft-2', 'invoiceSlot': 2, 'lineCount': 0, 'total': 0},
      ],
    };
  }
  if (p.endsWith('/api/pos/sales/sellers')) {
    return [
      {'employeeId': 'e1', 'displayName': 'Nguyễn Văn An', 'isSelf': true},
      {'employeeId': 'e2', 'displayName': 'Trần Thị Mai'},
      {'employeeId': 'e3', 'displayName': 'Lê Hoàng Phúc'},
    ];
  }
  if (p.endsWith('/api/pos/customers') || p.endsWith('/api/pos/customers/search')) {
    return {'items': _customers, 'totalCount': _customers.length, 'total': _customers.length};
  }
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

final _customers = [
  {'id': 'k1', 'customerCode': 'KH0901234567', 'name': 'Chị Lan', 'phone': '0901234567', 'totalPurchase': 2350000, 'currentDebt': 0},
  {'id': 'k2', 'customerCode': 'KH0912888999', 'name': 'Anh Minh', 'phone': '0912888999', 'totalPurchase': 1180000, 'currentDebt': 150000},
];

/// Kênh máy thật (máy quét Sunmi, thư mục app) không có trong test — trả rỗng.
void _mockDeviceChannels() {
  final m = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  m.setMockStreamHandler(const EventChannel('com.sboxhrm/sunmi_scanner'), MockStreamHandler.inline(onListen: (_, __) {}));
  m.setMockMethodCallHandler(const MethodChannel('plugins.flutter.io/path_provider'),
      (_) async => Directory.systemTemp.createTempSync('sbox_guide').path);
}

/// Thêm món có topping / hoa hồng → app tự mở bảng chọn topping, chọn nhân viên: đóng lại.
Future<void> _closeAutoSheets(WidgetTester t) async {
  for (var i = 0; i < 4; i++) {
    if (find.text('Lưu nhân viên').evaluate().isNotEmpty) {
      await t.tap(find.text('Lưu nhân viên').last);
    } else if (find.textContaining('Topping —').evaluate().isNotEmpty && find.text('Xong').evaluate().isNotEmpty) {
      await t.tap(find.text('Xong').last);
    } else {
      return;
    }
    await t.pump(const Duration(milliseconds: 400));
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await t.pump(const Duration(milliseconds: 200));
  }
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
    await _closeAutoSheets(t);
  }
  if (mobile) {
    // Bảng chọn món giữ số lượng nháp — nút cuối bảng (cùng tên «Chọn hàng») mới đưa vào hóa đơn.
    await t.tap(find.widgetWithText(FilledButton, 'Chọn hàng').last);
    await t.pump(const Duration(milliseconds: 600));
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await t.pump(const Duration(milliseconds: 200));
    await _closeAutoSheets(t);
  }
}

/// Nút «+» thêm hóa đơn (máy tính có tooltip; điện thoại là nút + cùng hàng «HĐ 1»).
Finder _addInvoiceBtn() => find.byTooltip('Thêm hóa đơn').evaluate().isNotEmpty
    ? find.byTooltip('Thêm hóa đơn').first
    : _onRow(find.byIcon(Icons.add), find.textContaining('HĐ 1')).first;

/// Ô nhập có nội dung đúng bằng [v].
Finder _field(String v) => find.byWidgetPredicate((w) => w is TextField && w.controller?.text == v);

/// Nút − / + số lượng (biểu tượng khác nhau giữa máy tính và điện thoại).
Finder _qtyIcon(bool plus) => find.byWidgetPredicate((w) =>
    w is Icon && (plus ? const [Icons.add, Icons.add_rounded] : const [Icons.remove, Icons.remove_rounded]).contains(w.icon));

/// Chữ hoặc nội dung ô nhập đúng bằng [v].
Finder _textOrField(String v) => find.byWidgetPredicate(
    (w) => (w is Text && w.data == v) || (w is TextField && w.controller?.text == v));

Future<void> _settle(WidgetTester t, [int ms = 600]) async {
  await t.pump(Duration(milliseconds: ms));
  await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
  await t.pump(const Duration(milliseconds: 300));
}

/// Phần tử [f] nằm cùng hàng (theo chiều dọc) với chữ [rowText] — vd nút «…» của đúng món.
Finder _onRow(Finder f, Finder rowText) => find.byElementPredicate((e) {
      final rows = rowText.evaluate().toList();
      if (rows.isEmpty) return false;
      final box = e.renderObject;
      final rb = rows.last.renderObject;
      if (box is! RenderBox || rb is! RenderBox || !box.hasSize || !rb.hasSize) return false;
      final y = box.localToGlobal(box.size.center(Offset.zero)).dy;
      final ry = rb.localToGlobal(rb.size.center(Offset.zero)).dy;
      return (y - ry).abs() < 60 && f.evaluate().contains(e);
    });

/// Mở màn thanh toán sau khi đã có hàng.
Future<void> _openPay(WidgetTester t) async {
  await _fillCart(t);
  await t.tap(find.textContaining('Thanh toán').last);
  await _settle(t);
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


    testWidgets('pos-sales-3$suffix: nhiều hóa đơn', (t) async {
      await guideShot(
        t,
        name: 'pos-sales-3$suffix',
        screen: withPosPackage(const PosSellScreen()),
        api: _api,
        crumbs: const ['POS', 'Bán hàng'],
        size: size,
        act: (t) async {
          await _fillCart(t);
          await t.tap(_addInvoiceBtn());
          await _settle(t);
        },
        marks: [
          GuideMark(1, [find.textContaining('HĐ 1').first, find.textContaining('HĐ 2').first], pad: 10),
          GuideMark(2, [_addInvoiceBtn()], pad: 6),
        ],
      );
    }, timeout: const Timeout(Duration(seconds: 120)));

    testWidgets('pos-sale-edit-1$suffix: thao tác trên dòng món', (t) async {
      await guideShot(
        t,
        name: 'pos-sale-edit-1$suffix',
        screen: withPosPackage(const PosSellScreen()),
        api: _sellApi(commission: true),
        crumbs: const ['POS', 'Bán hàng'],
        size: size,
        act: (t) async {
          await _fillCart(t);
          if (mobile) {
            await t.tap(_onRow(find.byIcon(Icons.more_horiz), find.text('Cà phê sữa đá')).first);
            await _settle(t);
          }
        },
        marks: mobile
            ? [
                GuideMark(1, [GuideMark.button(find.text('Ghi chú').last)], pad: -3),
                GuideMark(2, [GuideMark.button(find.text('Giá & chiết khấu').last)], pad: -3),
                GuideMark(3, [GuideMark.button(find.text('Tách dòng').last), GuideMark.button(find.text('Gộp dòng').last)], pad: -3),
                GuideMark(4, [GuideMark.button(find.text('Xóa khỏi hóa đơn').last)]),
              ]
            : [
                GuideMark(1, [
                  _onRow(_qtyIcon(false), find.text('Cà phê sữa đá')).first,
                  _onRow(_qtyIcon(true), find.text('Cà phê sữa đá')).first,
                ], pad: 6),
                GuideMark(2, [find.text('Cà phê sữa đá').last, find.text('Chọn NV hoa hồng').last], pad: 6),
                GuideMark(3, [find.text('58.000').last, find.text('29.000').last], pad: 6),
              ],
      );
    }, timeout: const Timeout(Duration(seconds: 120)));

    testWidgets('pos-sale-edit-2$suffix: giá & chiết khấu', (t) async {
      await guideShot(
        t,
        name: 'pos-sale-edit-2$suffix',
        screen: withPosPackage(const PosSellScreen()),
        api: _api,
        crumbs: const ['POS', 'Bán hàng'],
        size: size,
        act: (t) async {
          await _fillCart(t);
          if (mobile) {
            await t.tap(_onRow(find.byIcon(Icons.more_horiz), find.text('Cà phê sữa đá')).first);
            await _settle(t);
            await t.tap(find.text('Giá & chiết khấu').last);
          } else {
            await t.tap(find.text('58.000').last);
          }
          await _settle(t);
        },
        marks: [
          GuideMark(1, [find.text('Đơn giá').last, _onRow(find.byType(TextField), find.text('Đơn giá')).first], pad: 6),
          GuideMark(2, [find.text('Chiết khấu').last, _onRow(find.byType(TextField), find.text('Chiết khấu')).first], pad: 6),
          GuideMark(3, [GuideMark.button(find.text('Áp dụng').last)]),
        ],
      );
    }, timeout: const Timeout(Duration(seconds: 120)));

    testWidgets('pos-sale-edit-3$suffix: ghi chú & topping', (t) async {
      await guideShot(
        t,
        name: 'pos-sale-edit-3$suffix',
        screen: withPosPackage(const PosSellScreen()),
        api: _api,
        crumbs: const ['POS', 'Bán hàng'],
        size: size,
        act: (t) async {
          await _fillCart(t);
          if (mobile) {
            await t.tap(_onRow(find.byIcon(Icons.more_horiz), find.text('Trà đào cam sả')).first);
            await _settle(t);
            await t.tap(find.text('Ghi chú').last);
          } else {
            await t.tap(find.text('Trà đào cam sả').last);
          }
          await _settle(t);
          await t.tap(find.text('Ít đá').last);
          await t.pump(const Duration(milliseconds: 200));
        },
        marks: [
          GuideMark(1, [find.text('Ít đá').last, find.text('Không đường').last, find.text('Mang đi').last], pad: 10),
          GuideMark(2, [find.text('Tùy chọn thêm').last, find.textContaining('Kem cheese').last], pad: 8),
          GuideMark(3, [GuideMark.button(find.text('Xong').last)]),
        ],
      );
    }, timeout: const Timeout(Duration(seconds: 120)));

    testWidgets('pos-sale-pay-1$suffix: khách, giảm giá, voucher', (t) async {
      await guideShot(
        t,
        name: 'pos-sale-pay-1$suffix',
        screen: withPosPackage(const PosSellScreen()),
        api: _api,
        crumbs: const ['POS', 'Bán hàng', 'Thanh toán'],
        size: size,
        act: _openPay,
        marks: [
          GuideMark(1, mobile
              ? [GuideMark.button(_textOrField('Người tiêu dùng').first)]
              : [_textOrField('Người tiêu dùng').first, find.byTooltip('Thêm khách hàng')], pad: 6),
          GuideMark(2, [find.text('Giảm giá').last, _textOrField('0').first], pad: 8),
          GuideMark(3, [find.text('Mã voucher'), find.text('Áp dụng').last], pad: 10),
          GuideMark(4, [find.text('Khách cần trả'), _onRow(find.text('142.000'), find.text('Khách cần trả')).first], pad: 6),
        ],
      );
    }, timeout: const Timeout(Duration(seconds: 120)));

    testWidgets('pos-sale-pay-2$suffix: bàn phím tiền khách đưa', (t) async {
      await guideShot(
        t,
        name: 'pos-sale-pay-2$suffix',
        screen: withPosPackage(const PosSellScreen()),
        api: _api,
        crumbs: const ['POS', 'Bán hàng', 'Thanh toán'],
        size: size,
        act: (t) async {
          await _openPay(t);
          await t.tap(_field('142.000').last);
          await _settle(t, 400);
          await t.tap(find.text('+200k').last);
          await t.pump(const Duration(milliseconds: 200));
        },
        marks: [
          GuideMark(1, [find.text('+1k').last, find.text('+500k').last], pad: 6),
          GuideMark(2, [find.textContaining('200.000').last], pad: 8),
          GuideMark(3, [GuideMark.button(find.text('Xong').last)]),
        ],
      );
    }, timeout: const Timeout(Duration(seconds: 120)));

    testWidgets('pos-sale-pay-3$suffix: tiền trả khách', (t) async {
      await guideShot(
        t,
        name: 'pos-sale-pay-3$suffix',
        screen: withPosPackage(const PosSellScreen()),
        api: _api,
        crumbs: const ['POS', 'Bán hàng', 'Thanh toán'],
        size: size,
        act: (t) async {
          await _openPay(t);
          await t.tap(_field('142.000').last);
          await _settle(t, 400);
          await t.tap(find.text('+200k').last);
          await t.pump(const Duration(milliseconds: 200));
          await t.tap(find.text('Xong').last);
          await _settle(t, 400);
        },
        marks: [
          GuideMark(1, [_field('200.000').last], pad: 6),
          GuideMark(2, [find.text('Tiền trả khách').last, _onRow(find.text('58.000'), find.text('Tiền trả khách')).first], pad: 6),
          GuideMark(3, [GuideMark.button(find.textContaining(mobile ? 'Hoàn thành' : 'HOÀN TẤT').last)]),
        ],
      );
    }, timeout: const Timeout(Duration(seconds: 120)));
  }

}
