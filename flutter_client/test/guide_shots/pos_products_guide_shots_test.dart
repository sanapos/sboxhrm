import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zkteco_flutter_client/models/pos_product.dart';
import 'package:zkteco_flutter_client/models/pos_sell_industry.dart';
import 'package:zkteco_flutter_client/screens/pos/pos_product_editor_page.dart';
import 'package:zkteco_flutter_client/screens/pos_products_screen.dart';
import 'package:zkteco_flutter_client/utils/pos_sell_settings_helper.dart';

import 'guide_shot_kit.dart';
import 'pos_guide_common.dart';

/// Ảnh cho bước hướng dẫn «Hàng hóa, giá & combo» (id: pos_products) — quán cà phê.

final _categories = [
  {'id': 'c1', 'name': 'Cà phê', 'productCount': 4},
  {'id': 'c2', 'name': 'Trà & nước ép', 'productCount': 3},
  {'id': 'c3', 'name': 'Bánh ngọt', 'productCount': 2},
  {'id': 'c4', 'name': 'Nguyên liệu', 'productCount': 3},
];

Map<String, Object?> _p(String id, String code, String name, String cat, String catName, num price, num cost,
        {num onHand = 0, int type = 0, String unit = 'Ly', bool fav = false}) =>
    {
      'id': id, 'productCode': code, 'name': name, 'categoryId': cat, 'categoryName': catName,
      'basePrice': price, 'costPrice': cost, 'onHandQty': onHand, 'productType': '$type',
      'baseUnitName': unit, 'isActive': true, 'isDirectSale': true, 'isFavorite': fav,
    };

final _products = [
  _p('p1', 'CFD', 'Cà phê đen đá', 'c1', 'Cà phê', 25000, 7000, onHand: 120, fav: true),
  _p('p2', 'CFS', 'Cà phê sữa đá', 'c1', 'Cà phê', 29000, 9000, onHand: 150, fav: true),
  _p('p3', 'BX', 'Bạc xỉu', 'c1', 'Cà phê', 32000, 10000, onHand: 80),
  _p('p4', 'CFM', 'Cà phê muối', 'c1', 'Cà phê', 35000, 11000, onHand: 60),
  _p('p5', 'TDCS', 'Trà đào cam sả', 'c2', 'Trà & nước ép', 39000, 12000, onHand: 90),
  _p('p6', 'NECAM', 'Nước ép cam', 'c2', 'Trà & nước ép', 35000, 14000, onHand: 40),
  _p('p7', 'TIRA', 'Bánh tiramisu', 'c3', 'Bánh ngọt', 45000, 22000, onHand: 12, unit: 'Cái'),
  _p('p8', 'CBSANG', 'Combo sáng: Cà phê sữa + bánh', 'c3', 'Bánh ngọt', 65000, 31000, type: 2, unit: 'Phần'),
  _p('p9', 'HATCF', 'Hạt cà phê Robusta', 'c4', 'Nguyên liệu', 0, 260000, onHand: 8.5, type: 3, unit: 'Kg'),
  _p('p10', 'SUADAC', 'Sữa đặc', 'c4', 'Nguyên liệu', 0, 28000, onHand: 24, type: 3, unit: 'Hộp'),
];

final _api = posGuideApi((req) {
  final p = req.url.path;
  if (p.endsWith('/api/pos/catalog/categories')) return _categories;
  if (p.endsWith('/api/pos/products')) {
    return {'items': _products, 'totalCount': _products.length, 'total': _products.length, 'page': 1, 'totalPages': 1};
  }
  return null;
});

/// Cuộn khung dọc đầu tiên xuống [dy] px (để phần cần đánh dấu không nằm dưới thanh nút cuối form).
Future<void> _scrollBy(WidgetTester t, double dy) async {
  final v = find.byWidgetPredicate((w) => w is Scrollable && axisDirectionToAxis(w.axisDirection) == Axis.vertical);
  final pos = t.state<ScrollableState>(v.first).position;
  pos.jumpTo((pos.pixels + dy).clamp(0, pos.maxScrollExtent));
  await t.pump();
}

void main() {
  setUp(() => PosSellSettingsHelper.lastProfile = PosSellProfile.restaurant);

  for (final (suffix, size) in [('', desktopSize), ('-mobile', mobileSize)]) {
    final mobile = suffix.isNotEmpty;
    testWidgets('pos-products-1$suffix: danh sách hàng hóa', (t) async {
      await guideShot(
        t,
        name: 'pos-products-1$suffix',
        screen: withPosPackage(const PosProductsScreen()),
        api: _api,
        crumbs: const ['POS', 'Hàng hóa'],
        size: size,
        marks: [
          GuideMark(1, [mobile ? GuideMark.button(find.byIcon(Icons.add)) : GuideMark.button(find.text('Tạo mới'))]),
          GuideMark(2, [mobile ? GuideMark.button(find.byIcon(Icons.search)) : find.byType(TextField).first]),
          GuideMark(3, [find.text('Cà phê sữa đá'), find.text('29.000'), find.text('CFS')], pad: 12),
        ],
      );
    });

    testWidgets('pos-products-2$suffix: thêm món', (t) async {
      await guideShot(
        t,
        name: 'pos-products-2$suffix',
        screen: withPosPackage(const PosProductEditorPage(productType: PosProductType.goods)),
        api: _api,
        crumbs: const ['POS', 'Hàng hóa', 'Thêm hàng'],
        size: size,
        act: (t) async {
          await t.enterText(find.widgetWithText(TextField, 'Mã hàng'), 'CFCD');
          await t.enterText(find.widgetWithText(TextField, 'Tên hàng *'), 'Cà phê cốt dừa');
          await t.tap(find.text('Nhóm hàng').first);
          await t.pump(const Duration(milliseconds: 400));
          await t.tap(find.text('Cà phê').last);
          await t.pump(const Duration(milliseconds: 400));
          // Ô tiền mở bàn phím số riêng (readOnly) — gán thẳng như sau khi bấm số.
          t.widget<TextField>(find.widgetWithText(TextField, 'Giá vốn')).controller!.text = '12.000';
          t.widget<TextField>(find.widgetWithText(TextField, 'Giá bán')).controller!.text = '39.000';
          await t.pump();
          if (mobile) await _scrollBy(t, 90);
        },
        marks: [
          GuideMark(1, [find.text('Chụp hoặc chọn ảnh'), find.textContaining('Chạm để đổi ảnh')], pad: 4),
          GuideMark(2, [find.widgetWithText(TextField, 'Mã hàng'), find.widgetWithText(TextField, 'Tên hàng *')]),
          GuideMark(3, [GuideMark.within(find.text('Nhóm hàng').first, 'Row')]),
          GuideMark(4, [find.widgetWithText(TextField, 'Giá vốn'), find.widgetWithText(TextField, 'Giá bán')]),
        ],
      );
    });
  }
}
