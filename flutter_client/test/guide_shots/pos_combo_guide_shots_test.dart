import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zkteco_flutter_client/models/pos_product.dart';
import 'package:zkteco_flutter_client/models/pos_sell_industry.dart';
import 'package:zkteco_flutter_client/screens/pos/pos_product_editor_page.dart';
import 'package:zkteco_flutter_client/utils/pos_sell_settings_helper.dart';

import 'guide_shot_kit.dart';
import 'pos_catalog_guide_common.dart';
import 'pos_guide_common.dart';

/// Ảnh cho bước «Combo» (id: pos_combo): combo sáng = cà phê sữa + bánh tiramisu.

Future<void> _shot(WidgetTester t, String name, Size size,
    {Future<void> Function(WidgetTester t)? act, required List<GuideMark> marks}) async {
  await guideShot(
    t,
    name: name,
    screen: withPosPackage(PosProductEditorPage(productType: PosProductType.combo, product: catalogPosProduct('p4'))),
    api: catalogApi(sellSettings: {'sellProfile': 'restaurant', 'enableStaffCommission': true}),
    crumbs: const ['POS', 'Hàng hóa', 'Sửa combo'],
    size: size,
    act: act,
    marks: marks,
  );
}

Finder _switchTile(String title) => find.ancestor(of: find.text(title), matching: find.byType(SwitchListTile)).first;

void main() {
  setUp(() => PosSellSettingsHelper.lastProfile = PosSellProfile.restaurant);

  for (final (suffix, size) in [('', desktopSize), ('-mobile', mobileSize)]) {
    testWidgets('pos-combo-1$suffix: thành phần combo', (t) async {
      await _shot(t, 'pos-combo-1$suffix', size,
          act: (t) async => catalogReveal(t, find.widgetWithText(TextField, 'Thêm hàng hóa hoặc dịch vụ'), alignment: 0.2),
          marks: [
            GuideMark(1, [find.widgetWithText(TextField, 'Thêm hàng hóa hoặc dịch vụ')]),
            GuideMark(2, [
              find.textContaining('Có thể bán khoảng'),
              find.text('Cà phê sữa đá'),
              find.text('TIRA'),
              find.text('45.000'),
            ], pad: 10),
          ]);
    });

    testWidgets('pos-combo-2$suffix: tồn kho combo, hiện thành phần', (t) async {
      await _shot(t, 'pos-combo-2$suffix', size,
          act: (t) async => catalogReveal(t, find.text('Quản lý tồn kho combo'), alignment: 0.05),
          marks: [
            GuideMark(1, [_switchTile('Quản lý tồn kho combo')]),
            GuideMark(2, [_switchTile('Hiện chi tiết thành phần khi bán')]),
          ]);
    });

    testWidgets('pos-combo-3$suffix: giá combo, hoa hồng', (t) async {
      await _shot(t, 'pos-combo-3$suffix', size,
          act: (t) async {
            await guideScrollTo(t, find.text('Giá bán').last, alignment: 0.2);
            await t.tap(find.text('Giá bán').last);
            await t.pump(const Duration(milliseconds: 500));
            t.widget<TextField>(find.widgetWithText(TextField, 'Giá bán').last).controller!.text = '65.000';
            await t.pump();
            await catalogReveal(t, find.text('Giá bán').last, alignment: 0.2);
          },
          marks: [
            GuideMark(1, [find.widgetWithText(TextField, 'Giá bán').last]),
            GuideMark(2, [find.textContaining('Tổng GT thành phần')], pad: 8),
          ]);
    });
  }
}
