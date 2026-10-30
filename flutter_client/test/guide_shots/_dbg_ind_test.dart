import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zkteco_flutter_client/models/pos_product.dart';
import 'package:zkteco_flutter_client/models/pos_sell_industry.dart';
import 'package:zkteco_flutter_client/screens/pos/pos_product_editor_page.dart';
import 'package:zkteco_flutter_client/utils/pos_sell_settings_helper.dart';

import 'guide_shot_kit.dart';
import 'pos_guide_common.dart';

/// Ảnh tab «Ngành hàng» — khai báo dịch vụ theo ngành trên màn Thêm dịch vụ:
/// karaoke tính giờ, gói liệu trình salon, hoa hồng, thẻ tập gym, tiền phòng khách sạn.

final _categories = [
  {'id': 'c1', 'name': 'Dịch vụ', 'productCount': 6},
];

String _profileKey(PosSellProfile p) => switch (p) {
      PosSellProfile.roomHourly => 'roomHourly',
      PosSellProfile.salon => 'salon',
      PosSellProfile.gym => 'gym',
      PosSellProfile.hotel => 'hotel',
      PosSellProfile.restaurant => 'restaurant',
      PosSellProfile.retail => 'retail',
    };

Future<void> _shot(
  WidgetTester t,
  String name,
  PosSellProfile profile,
  String serviceName,
  Size size, {
  Future<void> Function(WidgetTester t)? act,
  required List<GuideMark> marks,
}) async {
  PosSellSettingsHelper.lastProfile = profile;
  await guideShot(
    t,
    name: name,
    screen: withPosPackage(const PosProductEditorPage(productType: PosProductType.service)),
    api: posGuideApi((req) {
      final p = req.url.path;
      if (p.endsWith('/api/pos/sell-settings')) {
        return {'id': 'ss1', 'sellProfile': _profileKey(profile), 'enableResources': true, 'enableStaffCommission': true};
      }
      if (p.endsWith('/api/pos/catalog/categories')) return _categories;
      return null;
    }),
    crumbs: const ['POS', 'Hàng hóa', 'Thêm dịch vụ'],
    size: size,
    act: (t) async {
      await t.enterText(find.widgetWithText(TextField, 'Tên dịch vụ *'), serviceName);
      await t.pump();
      if (act != null) await act(t);
    },
    marks: marks,
  );
}

Finder _field(String label) => find.widgetWithText(TextField, label);

void _setMoney(WidgetTester t, String label, String value) {
  t.widget<TextField>(_field(label)).controller!.text = value;
}

Future<void> _expand(WidgetTester t, String title) async {
  await guideScrollTo(t, find.text(title), alignment: 0.1);
  await t.tap(find.text(title));
  await t.pump(const Duration(milliseconds: 500));
}

void main() {
  testWidgets('dbg gym', (t) async {
    await _shot(t, 'dbg-gym', PosSellProfile.gym, 'Thẻ tập 1 tháng', desktopSize,
        act: (t) async {
          await _expand(t, 'Tính giờ / gói buổi');
          await guideScrollTo(t, find.text('Thẻ tập theo thời gian (không giới hạn buổi)'), alignment: 0.2);
        },
        marks: const []);
  });
  testWidgets('dbg salon', (t) async {
    await _shot(t, 'dbg-salon', PosSellProfile.salon, 'Gói massage', desktopSize,
        act: (t) async {
          await _expand(t, 'Tính giờ / gói buổi');
          await guideScrollTo(t, _field('Số buổi trong gói'), alignment: 0.1);
        },
        marks: const []);
  });
}
