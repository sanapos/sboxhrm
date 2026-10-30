import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zkteco_flutter_client/models/pos_product.dart';
import 'package:zkteco_flutter_client/models/pos_sell_industry.dart';
import 'package:zkteco_flutter_client/screens/pos/pos_material_report_screen.dart';
import 'package:zkteco_flutter_client/screens/pos/pos_product_editor_page.dart';
import 'package:zkteco_flutter_client/utils/pos_sell_settings_helper.dart';

import 'guide_shot_kit.dart';
import 'pos_catalog_guide_common.dart';
import 'pos_guide_common.dart';

/// Ảnh cho bước «Nguyên vật liệu & định lượng» (id: pos_bom): tạo NVL, định lượng 1 ly trà sữa,
/// báo cáo nguyên vật liệu.

Map<String, Object?> _mat(String code, String name, String unit, num onHand, num used, num value, num perDay,
        num? daysLeft, String level, String levelText, {num received = 0, num wasted = 0}) =>
    {
      'code': code, 'name': name, 'unit': unit, 'onHand': onHand, 'usedQty': used, 'usedValue': value,
      'avgPerDay': perDay, 'daysLeft': daysLeft, 'receivedQty': received, 'wastedQty': wasted,
      'level': level, 'levelText': levelText,
      'dishes': [{'name': 'Trà sữa trân châu đường đen', 'qty': used}],
    };

final _report = {
  'verdict': 'yellow',
  'verdictText': '2 nguyên liệu cần nhập trong tuần',
  'verdictDetail': 'Siro đường đen còn đủ khoảng 1,5 ngày, trân châu còn 3,2 ngày theo mức bán 7 ngày qua.',
  'summary': {
    'materialCount': 5, 'redCount': 1, 'yellowCount': 1, 'usedValue': 4860000, 'usedPerDay': 694000,
    'usedCount': 5, 'wastedValue': 96000, 'negativeCount': 0, 'noRecipeDishCount': 1,
  },
  'recommendations': [
    {'level': 'red', 'title': 'Nhập ngay Siro đường đen', 'detail': 'Còn 2.400 ml, mỗi ngày dùng ~1.600 ml.'},
    {'level': 'yellow', 'title': 'Nhập Trân châu đen trong 3 ngày tới', 'detail': 'Còn 3.500 g, mỗi ngày dùng ~1.100 g.'},
  ],
  'materials': [
    _mat('NVL-DUONGDEN', 'Siro đường đen', 'ml', 2400, 11200, 1008000, 1600, 1.5, 'red', 'Sắp hết'),
    _mat('NVL-TRANCHAU', 'Trân châu đen (đã nấu)', 'g', 3500, 7700, 346500, 1100, 3.2, 'yellow', 'Nên nhập'),
    _mat('NVL-TRADEN', 'Trà đen pha sẵn', 'ml', 12000, 37800, 2268000, 5400, 2.2 * 3, 'green', 'Đủ dùng'),
    _mat('NVL-SUATUOI', 'Sữa tươi không đường', 'ml', 18000, 25200, 806400, 3600, 5, 'green', 'Đủ dùng'),
    _mat('NVL-LY700', 'Ly nhựa 700ml + nắp', 'Cái', 420, 315, 409500, 45, 9.3, 'green', 'Đủ dùng'),
  ],
  'topDishes': [
    {'name': 'Trà sữa trân châu đường đen', 'value': 3620000},
    {'name': 'Trà sữa matcha', 'value': 840000},
    {'name': 'Trân châu trắng (topping)', 'value': 400000},
  ],
  'daily': const [],
  'noRecipeDishes': [
    {'name': 'Trà đào cam sả', 'soldQty': 42, 'onHand': -42},
  ],
};

Future<void> _editor(WidgetTester t, String name, Size size, Widget page, List<String> crumbs,
    {Future<void> Function(WidgetTester t)? act, required List<GuideMark> marks}) async {
  await guideShot(
    t,
    name: name,
    screen: withPosPackage(page),
    api: catalogApi(),
    crumbs: crumbs,
    size: size,
    act: act,
    marks: marks,
  );
}

void main() {
  setUp(() => PosSellSettingsHelper.lastProfile = PosSellProfile.restaurant);

  for (final (suffix, size) in [('', desktopSize), ('-mobile', mobileSize)]) {
    final mobile = suffix.isNotEmpty;

    testWidgets('pos-bom-1$suffix: tạo nguyên vật liệu', (t) async {
      await _editor(t, 'pos-bom-1$suffix', size, const PosProductEditorPage(productType: PosProductType.material),
          const ['POS', 'Hàng hóa', 'Tạo nguyên vật liệu'],
          act: (t) async {
            await t.enterText(catalogField('Tên hàng *'), 'Sữa tươi không đường');
            await t.tap(find.text('Nhóm hàng').first);
            await t.pump(const Duration(milliseconds: 400));
            await t.tap(find.text('Nguyên vật liệu').last);
            await t.pump(const Duration(milliseconds: 400));
            t.widget<TextField>(catalogField('Giá vốn')).controller!.text = '32';
            await t.enterText(catalogField('Tồn kho'), '18000');
            await t.pump();
            await catalogReveal(t, catalogField(mobile ? 'Tên hàng *' : 'Tên hàng *'), alignment: mobile ? 0.0 : 0.05);
          },
          marks: [
            GuideMark(1, [catalogField('Tên hàng *'), GuideMark.within(find.text('Nhóm hàng').first, 'Row')]),
            if (!mobile) GuideMark(2, [catalogField('Giá vốn')]),
            if (!mobile) GuideMark(3, [catalogField('Tồn kho')]),
          ]);
    });

    testWidgets('pos-bom-2$suffix: định lượng 1 ly', (t) async {
      await _editor(t, 'pos-bom-2$suffix', size,
          PosProductEditorPage(productType: PosProductType.goods, product: catalogPosProduct('p2')),
          const ['POS', 'Hàng hóa', 'Trà sữa trân châu đường đen'],
          act: (t) async => catalogReveal(t, find.text('Định lượng nguyên vật liệu'), alignment: 0.1),
          marks: [
            GuideMark(1, [catalogField('Thêm nguyên vật liệu')]),
            GuideMark(2, [find.text('NVL'), find.text('ĐVT'), find.text('Ly nhựa 700ml + nắp'), find.text('Cái').last], pad: 10),
          ]);
    });

    testWidgets('pos-bom-3$suffix: báo cáo nguyên vật liệu', (t) async {
      await guideShot(
        t,
        name: 'pos-bom-3$suffix',
        screen: withPosPackage(const PosMaterialReportScreen()),
        api: catalogApi(materialsReport: _report),
        crumbs: const ['POS', 'Báo cáo', 'Nguyên vật liệu'],
        size: size,
        act: (t) async => catalogReveal(t, find.text('Hết / sắp hết'), alignment: 0.05),
        marks: [
          GuideMark(1, [
            find.text('Hết / sắp hết'),
            find.text('Cần nhập trong tuần'),
            find.text('Đủ dưới 5 ngày / dưới tồn tối thiểu'),
          ], pad: 16),
          GuideMark(2, [find.text('Món chưa khai định lượng'), find.text('Bán ra không trừ nguyên liệu')], pad: 16),
        ],
      );
    });
  }
}
