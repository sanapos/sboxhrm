import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zkteco_flutter_client/models/pos_product.dart';
import 'package:zkteco_flutter_client/screens/pos/pos_price_lists_screen.dart';
import 'package:zkteco_flutter_client/screens/pos/pos_product_editor_page.dart';

import 'guide_shot_kit.dart';
import 'pos_goods_guide_common.dart';
import 'pos_guide_common.dart';

/// Ảnh cho bước hướng dẫn «Đơn vị tính & bảng giá» (id: pos_units) — tạp hóa.

Widget _beerEditor() => withPosPackage(PosProductEditorPage(
      productType: PosProductType.goods,
      product: PosProduct.fromJson(beerProduct),
    ));

void main() {
  for (final (suffix, size) in [('', desktopSize), ('-mobile', mobileSize)]) {
    final mobile = suffix.isNotEmpty;
    testWidgets('pos-units-1$suffix: đơn vị cơ bản + quy đổi', (t) async {
      await guideShot(
        t,
        name: 'pos-units-1$suffix',
        screen: _beerEditor(),
        api: goodsApi(),
        crumbs: const ['POS', 'Hàng hóa', 'Bia Tiger lon 330ml'],
        size: size,
        act: (t) async {
          await pumpFrames(t);
          await scrollFormTo(t, find.text('Đơn vị tính cơ bản'));
        },
        marks: [
          GuideMark(1, [find.widgetWithText(TextField, 'Tên đơn vị cơ bản *')]),
          GuideMark(2, [GuideMark.within(find.text('Lốc'), 'Container'), GuideMark.within(find.text('Thùng'), 'Container')], pad: 4),
          GuideMark(3, [GuideMark.button(find.text('Thêm đơn vị quy đổi'))]),
        ],
      );
    });

    testWidgets('pos-units-2$suffix: thiết lập đơn vị tính', (t) async {
      await guideShot(
        t,
        name: 'pos-units-2$suffix',
        screen: _beerEditor(),
        api: goodsApi(),
        crumbs: const ['POS', 'Hàng hóa', 'Bia Tiger lon 330ml'],
        size: size,
        act: (t) async {
          await pumpFrames(t);
          await scrollFormTo(t, find.text('Thêm đơn vị quy đổi'), alignment: 0.5);
          await t.tap(find.text('Thêm đơn vị quy đổi'));
          await pumpFrames(t);
        },
        marks: [
          GuideMark(1, [find.widgetWithText(TextField, 'Tên đơn vị cơ bản')]),
          GuideMark(2, [find.widgetWithText(TextField, 'Lốc'), find.widgetWithText(TextField, mobile ? '105.000' : '395.000')]),
          if (!mobile) ...[
            GuideMark(3, [GuideMark.button(find.text('Thêm đơn vị'))]),
            GuideMark(4, [find.text('Giá trị thuộc tính'), find.text('Tồn kho').last], pad: 10),
          ],
        ],
      );
    });

    testWidgets('pos-units-3$suffix: danh sách bảng giá', (t) async {
      await guideShot(
        t,
        name: 'pos-units-3$suffix',
        screen: withPosPackage(const PosPriceListsScreen()),
        api: goodsApi(_priceListApi),
        crumbs: const ['POS', 'Hàng hóa', 'Bảng giá'],
        size: size,
        act: (t) async => pumpFrames(t),
        marks: [
          GuideMark(1, [GuideMark.button(find.text('Thêm bảng giá'))]),
          GuideMark(2, [find.text('Khuyến mãi Tết'), find.textContaining('Mặc định ·')], pad: 10),
          GuideMark(3, [find.byTooltip('Sao chép bảng giá').last, find.byTooltip('Cài mặc định / ngày').last], pad: 4),
        ],
      );
    });

    testWidgets('pos-units-4$suffix: giá trong bảng giá', (t) async {
      await guideShot(
        t,
        name: 'pos-units-4$suffix',
        screen: withPosPackage(const PosPriceListsScreen()),
        api: goodsApi(_priceListApi),
        crumbs: const ['POS', 'Hàng hóa', 'Bảng giá'],
        size: size,
        act: (t) async {
          await pumpFrames(t);
          await t.tap(find.text('Giá sỉ cho đại lý').first);
          await pumpFrames(t, 10);
        },
        marks: [
          GuideMark(1, [find.byType(TextField).first, GuideMark.button(find.text('Thêm nhiều SP'))]),
          GuideMark(2, [find.textContaining('TIGER330 · Thùng'), find.text('375.000')], pad: 8),
          GuideMark(3, [find.text('Chiết khấu nhanh'), GuideMark.button(find.text('Nhiều hơn'))], pad: 6),
          GuideMark(4, [GuideMark.button(find.text('Lưu bảng giá'))]),
        ],
      );
    });
  }
}

final _priceLists = [
  {'id': 'pl1', 'name': 'Giá sỉ cho đại lý', 'isDefault': false, 'isActive': true, 'sortOrder': 1, 'itemCount': 4},
  {
    'id': 'pl2', 'name': 'Khuyến mãi Tết', 'isDefault': true, 'isActive': true, 'sortOrder': 2, 'itemCount': 2,
    'validFrom': '2027-01-25', 'validTo': '2027-02-10',
  },
];

Map<String, Object?> _pli(String id, String productId, String name, num price, {String? unitId, String? unitName}) => {
      'id': id, 'productId': productId, 'productName': name, 'price': price,
      if (unitId != null) 'unitId': unitId, if (unitName != null) 'unitName': unitName,
    };

Object? _priceListApi(String p) {
  if (p.endsWith('/api/pos/price-lists')) return _priceLists;
  if (p.endsWith('/api/pos/price-lists/pl1/items')) {
    return [
      _pli('i1', 'g1', 'Bia Tiger lon 330ml', 17000, unitId: 'u0', unitName: 'Lon'),
      _pli('i2', 'g1', 'Bia Tiger lon 330ml', 99000, unitId: 'u1', unitName: 'Lốc'),
      _pli('i3', 'g1', 'Bia Tiger lon 330ml', 375000, unitId: 'u2', unitName: 'Thùng'),
      _pli('i4', 'g2', 'Sữa tươi tiệt trùng không đường 1L', 33500),
    ];
  }
  return null;
}
