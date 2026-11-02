import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zkteco_flutter_client/models/pos_product.dart';
import 'package:zkteco_flutter_client/models/pos_sell_industry.dart';
import 'package:zkteco_flutter_client/screens/pos/pos_product_detail_screen.dart';
import 'package:zkteco_flutter_client/screens/pos_products_screen.dart';
import 'package:zkteco_flutter_client/utils/pos_sell_settings_helper.dart';
import 'package:zkteco_flutter_client/widgets/pos/pos_product_expansion_panel.dart';

import 'guide_shot_kit.dart';
import 'pos_guide_common.dart';
import 'pos_stock_guide_common.dart';

/// Ảnh cho bước hướng dẫn «Tồn kho & thẻ kho» (id: pos_stock_card) — quán cà phê.

final _categories = [
  {'id': 'c3', 'name': 'Bánh ngọt', 'productCount': 1},
  {'id': 'c4', 'name': 'Nguyên liệu', 'productCount': 4},
];

Map<String, Object?> _p(String id, String code, String name, String cat, String catName, num cost, num onHand, String unit,
        {num min = 0, num max = 0, num reserved = 0, int type = 0}) =>
    {
      'id': id, 'productCode': code, 'name': name, 'categoryId': cat, 'categoryName': catName, 'basePrice': 0,
      'costPrice': cost, 'onHandQty': onHand, 'reservedQty': reserved, 'minStockQty': min, 'maxStockQty': max,
      'productType': '$type', 'baseUnitName': unit, 'isActive': true, 'isDirectSale': type == 0,
    };

final _milk = _p('p2', 'SUADAC', 'Sữa đặc', 'c4', 'Nguyên liệu', 27500, 6, 'Hộp', min: 12, max: 60, reserved: 2);

final _products = [
  _p('p1', 'HATCF', 'Hạt cà phê Robusta', 'c4', 'Nguyên liệu', 255000, 8.5, 'Kg', min: 5, max: 30),
  _milk,
  _p('p3', 'SUATUOI', 'Sữa tươi không đường 1L', 'c4', 'Nguyên liệu', 32000, 0, 'Hộp', min: 6, max: 40),
  _p('p4', 'LYNHUA', 'Ly nhựa 500ml', 'c4', 'Nguyên liệu', 900, 420, 'Cái', min: 200, max: 2000),
  _p('p7', 'TIRA', 'Bánh tiramisu', 'c3', 'Bánh ngọt', 22000, 10, 'Cái', min: 4, max: 20),
];

String _ago(int days, int hours) => DateTime.now().subtract(Duration(days: days, hours: hours)).toIso8601String();

Map<String, Object?> _tx(String id, String type, num change, num after, String ref, String? partner, int days, int hours,
        {String by = 'Nguyễn Văn An'}) =>
    {
      'id': id, 'productId': 'p2', 'productCode': 'SUADAC', 'productName': 'Sữa đặc', 'unitName': 'Hộp',
      'transactionType': type, 'qtyChange': change, 'qtyAfter': after, 'referenceNo': ref, 'partnerName': partner,
      'createdAt': _ago(days, hours), 'createdBy': by, 'unitCost': 27500, 'lineAmount': change.abs() * 27500,
      if (type == 'Sale') 'saleOrderId': 'o$id', if (type == 'Purchase') 'stockReceiptId': 'r$id',
      if (type == 'Adjust') 'stockCountId': 'k$id',
    };

final _txs = [
  _tx('6', 'Sale', -2, 6, 'HD002318', 'Khách lẻ', 0, 1, by: 'Trần Thị Mai'),
  _tx('5', 'Sale', -4, 8, 'HD002301', 'Chị Lan', 0, 5, by: 'Trần Thị Mai'),
  _tx('4', 'Adjust', -1, 12, 'KK000030', null, 1, 2),
  _tx('3', 'Sale', -35, 13, 'HD002270', 'Khách lẻ', 2, 3, by: 'Lê Văn Bình'),
  _tx('2', 'Purchase', 48, 48, 'PN000127', 'Sữa & nguyên liệu Minh Châu', 2, 6),
];

final _api = stockApi((req) {
  final p = req.url.path;
  if (p.endsWith('/api/pos/catalog/categories')) return _categories;
  if (p.endsWith('/api/pos/products')) {
    return {'items': _products, 'totalCount': _products.length, 'total': _products.length, 'page': 1, 'totalPages': 1};
  }
  if (p.endsWith('/api/pos/products/p2')) return _milk;
  if (p.endsWith('/api/pos/stock')) return {'items': _txs, 'total': _txs.length};
  return null;
});

Finder _panelText(String s) =>
    find.descendant(of: find.byType(PosProductExpansionPanel), matching: find.text(s));

/// Ô tồn «0» chữ đỏ (hết hàng) trong danh sách.
final _redZero = find.byWidgetPredicate((w) =>
    w is Text && w.data == '0' && (w.style?.color?.r ?? 0) > 0.6 && (w.style?.color?.g ?? 1) < 0.4);

Finder _panelRich(String s) => find.descendant(
    of: find.byType(PosProductExpansionPanel), matching: find.textContaining(s, findRichText: true));

Future<void> _expandMilk(WidgetTester t, String tab) async {
  await t.tap(find.text('Sữa đặc').first);
  await stockFrames(t, 5);
  await t.tap(_panelText(tab).first);
  await stockFrames(t, 4);
}

void main() {
  setUp(() {
    mockStockDeviceChannels();
    PosSellSettingsHelper.lastProfile = PosSellProfile.restaurant;
  });

  for (final (suffix, size) in [('', desktopSize), ('-mobile', mobileSize)]) {
    final mobile = suffix.isNotEmpty;

    testWidgets('pos-stock-card-1$suffix: tồn kho, định mức', (t) async {
      await guideShot(
        t,
        name: 'pos-stock-card-1$suffix',
        screen: withPosPackage(mobile ? PosProductDetailScreen(product: PosProduct.fromJson(_milk)) : const PosProductsScreen()),
        api: _api,
        crumbs: mobile ? const ['POS', 'Hàng hóa', 'Sữa đặc'] : const ['POS', 'Hàng hóa'],
        size: size,
        act: (t) async {
          await stockFrames(t, 4);
          if (!mobile) await _expandMilk(t, 'Tồn kho');
        },
        marks: mobile
            ? [GuideMark(2, [find.text('Tồn kho').first, find.text('12 - 60')], pad: 10)]
            : [
                GuideMark(1, [GuideMark.within(find.textContaining('Tồn kho:', findRichText: true).first, 'SboxFilterChip<PosStockFilter>')]),
                GuideMark(2, [_panelRich('Tồn kho: 6'), _panelRich('Định mức tồn')], pad: 12),
                GuideMark(3, [find.text('SUATUOI'), _redZero], pad: 6),
              ],
      );
    });

    testWidgets('pos-stock-card-2$suffix: thẻ kho', (t) async {
      await guideShot(
        t,
        name: 'pos-stock-card-2$suffix',
        screen: withPosPackage(mobile ? PosProductDetailScreen(product: PosProduct.fromJson(_milk)) : const PosProductsScreen()),
        api: _api,
        crumbs: mobile ? const ['POS', 'Hàng hóa', 'Sữa đặc'] : const ['POS', 'Hàng hóa'],
        size: size,
        act: (t) async {
          await stockFrames(t, 4);
          if (mobile) {
            // Nút «Thẻ kho» ở thẻ «Thao tác» cuối trang — cuộn tới rồi mới bấm.
            await t.ensureVisible(find.text('Thẻ kho').first);
            await t.pump();
            await t.tap(find.text('Thẻ kho').first);
            await stockFrames(t, 5);
          } else {
            await _expandMilk(t, 'Thẻ kho');
          }
        },
        marks: mobile
            ? [
                GuideMark(1, [find.textContaining('Thẻ kho —', findRichText: true)], pad: 6),
                GuideMark(2, [find.textContaining('HD002318', findRichText: true).first, find.textContaining('HD002301', findRichText: true).first, find.text('Chị Lan'), find.textContaining('Tồn: 8', findRichText: true)], pad: 8),
              ]
            : [
                GuideMark(1, [_panelText('Thẻ kho').first]),
                GuideMark(2, [find.text('HD002318'), find.textContaining('Minh Châu').last, find.text('+48')], pad: 8),
                GuideMark(3, [GuideMark.button(_panelText('Xuất file').first)]),
              ],
      );
    });
  }
}
