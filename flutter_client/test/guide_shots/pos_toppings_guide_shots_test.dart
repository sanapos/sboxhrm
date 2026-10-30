import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zkteco_flutter_client/models/pos_product.dart';
import 'package:zkteco_flutter_client/models/pos_sell_industry.dart';
import 'package:zkteco_flutter_client/screens/pos/pos_product_editor_page.dart';
import 'package:zkteco_flutter_client/screens/pos/pos_topping_groups_screen.dart';
import 'package:zkteco_flutter_client/utils/pos_sell_settings_helper.dart';

import 'guide_shot_kit.dart';
import 'pos_catalog_guide_common.dart';
import 'pos_guide_common.dart';

/// Ảnh cho bước «Topping» (id: pos_toppings): nhóm topping dùng chung, sửa nhóm, gắn nhóm vào món.

Future<void> _settle(WidgetTester t, [int frames = 8]) async {
  for (var i = 0; i < frames; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  setUp(() => PosSellSettingsHelper.lastProfile = PosSellProfile.restaurant);

  for (final (suffix, size) in [('', desktopSize), ('-mobile', mobileSize)]) {
    testWidgets('pos-toppings-1$suffix: nhóm topping', (t) async {
      await guideShot(
        t,
        name: 'pos-toppings-1$suffix',
        screen: withPosPackage(const PosToppingGroupsScreen()),
        api: catalogApi(),
        crumbs: const ['POS', 'Hàng hóa', 'Nhóm topping'],
        size: size,
        marks: [
          GuideMark(1, [find.ancestor(of: find.text('Topping trà sữa'), matching: find.byType(ListTile)).first]),
          GuideMark(2, [GuideMark.button(find.text('Thêm nhóm'))]),
        ],
      );
    });

    testWidgets('pos-toppings-2$suffix: sửa nhóm topping', (t) async {
      await guideShot(
        t,
        name: 'pos-toppings-2$suffix',
        screen: withPosPackage(const PosToppingGroupsScreen()),
        api: catalogApi(),
        crumbs: const ['POS', 'Hàng hóa', 'Nhóm topping'],
        size: size,
        act: (t) async {
          await t.tap(find.text('Topping trà sữa').first);
          await _settle(t);
        },
        marks: [
          GuideMark(1, [find.widgetWithText(TextField, 'Topping trà sữa')]),
          GuideMark(2, [find.text('Trân châu trắng').last, find.textContaining('+10.000 đ').last], pad: 10),
          GuideMark(3, [GuideMark.button(find.text('Thêm sản phẩm topping'))]),
        ],
      );
    });

    testWidgets('pos-toppings-3$suffix: gắn nhóm topping vào món', (t) async {
      await guideShot(
        t,
        name: 'pos-toppings-3$suffix',
        screen: withPosPackage(PosProductEditorPage(productType: PosProductType.goods, product: catalogPosProduct('p2'))),
        api: catalogApi(),
        crumbs: const ['POS', 'Hàng hóa', 'Trà sữa trân châu đường đen'],
        size: size,
        act: (t) async {
          await t.tap(find.text('Mô tả').first);
          await _settle(t, 10);
          await catalogReveal(t, find.text('Tùy chọn thêm'), alignment: 0.05);
        },
        marks: [
          GuideMark(1, [find.ancestor(of: find.text('Cho phép tùy chọn thêm khi bán'), matching: find.byType(SwitchListTile)).first]),
          GuideMark(2, [
            find.ancestor(of: find.textContaining('Topping trà sữa ('), matching: find.byType(FilterChip)).first,
            find.ancestor(of: find.textContaining('Kem phủ ('), matching: find.byType(FilterChip)).first,
          ]),
          GuideMark(3, [GuideMark.button(find.text('Quản lý nhóm'))]),
        ],
      );
    });
  }
}
