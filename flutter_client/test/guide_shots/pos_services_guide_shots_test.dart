import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zkteco_flutter_client/models/pos_product.dart';
import 'package:zkteco_flutter_client/models/pos_sell_industry.dart';
import 'package:zkteco_flutter_client/screens/pos/pos_product_editor_page.dart';
import 'package:zkteco_flutter_client/utils/pos_sell_settings_helper.dart';

import 'guide_shot_kit.dart';
import 'pos_catalog_guide_common.dart';
import 'pos_guide_common.dart';

/// Ảnh cho bước «Dịch vụ & tính giờ» (id: pos_services): giá cố định (spa), tính giờ theo block
/// có giá giờ đầu (bi-a), gói giờ đếm ngược (karaoke).

Future<void> _shot(WidgetTester t, String name, PosSellProfile profile, String serviceName, Size size,
    {required Future<void> Function(WidgetTester t) act, required List<GuideMark> marks}) async {
  PosSellSettingsHelper.lastProfile = profile;
  await guideShot(
    t,
    name: name,
    screen: withPosPackage(const PosProductEditorPage(productType: PosProductType.service)),
    api: catalogApi(sellSettings: {'sellProfile': profile.name, 'enableResources': true}),
    crumbs: const ['POS', 'Hàng hóa', 'Thêm dịch vụ'],
    size: size,
    act: (t) async {
      await t.enterText(catalogField('Tên dịch vụ *'), serviceName);
      await t.pump();
      await act(t);
    },
    marks: marks,
  );
}

void _money(WidgetTester t, String label, String value) {
  t.widget<TextField>(catalogField(label)).controller!.text = value;
}

Future<void> _expand(WidgetTester t, String title) async {
  await guideScrollTo(t, find.text(title), alignment: 0.1);
  await t.tap(find.text(title));
  await t.pump(const Duration(milliseconds: 500));
}

final _billingDropdown = find.ancestor(
    of: find.text('Cách tính giá dịch vụ'), matching: find.byType(DropdownButtonFormField<PosServiceBillingMode>));

void main() {
  for (final (suffix, size) in [('', desktopSize), ('-mobile', mobileSize)]) {
    final mobile = suffix.isNotEmpty;

    testWidgets('pos-services-1$suffix: dịch vụ giá cố định', (t) async {
      await _shot(t, 'pos-services-1$suffix', PosSellProfile.salon, 'Gội đầu dưỡng sinh', size,
          act: (t) async {
            await _expand(t, 'Giá vốn, giá bán');
            _money(t, 'Giá bán', '120.000');
            await _expand(t, 'Tính giờ / gói buổi');
            await t.enterText(catalogField('Thời lượng mặc định (phút)'), '45');
            await t.pump();
            await catalogReveal(t, mobile ? find.text('Tính giờ / gói buổi') : find.text('Giá vốn, giá bán'),
                alignment: mobile ? 0.05 : 0.0);
          },
          marks: [
            if (!mobile) GuideMark(1, [catalogField('Giá bán')]),
            // Cùng số với bản máy tính (chung một chú thích); điện thoại không đủ chỗ cho ô giá ①.
            GuideMark(2, [_billingDropdown]),
            GuideMark(3, [catalogField('Thời lượng mặc định (phút)')]),
          ]);
    });

    testWidgets('pos-services-2$suffix: tính giờ theo block, giá giờ đầu', (t) async {
      await _shot(t, 'pos-services-2$suffix', PosSellProfile.roomHourly, 'Giờ chơi bi-a bàn lỗ', size,
          act: (t) async {
            _money(t, 'Giá bán (1 giờ)', '80.000');
            await t.enterText(catalogField('Block tính thời gian sử dụng dịch vụ (phút)'), '15');
            await t.enterText(catalogField('Tính tối thiểu (phút)'), '30');
            await t.enterText(catalogField('Số block giờ đầu tiên'), '4');
            await t.pump(const Duration(milliseconds: 300));
            _money(t, 'Giá cho 4 block giờ đầu tiên', '70.000');
            // Ô tiền gán thẳng không báo form → nhập lại một ô để bảng xem trước tính lại.
            await t.enterText(catalogField('Tính tối thiểu (phút)'), '30');
            await t.pump(const Duration(milliseconds: 300));
            await catalogReveal(t, catalogField('Block tính thời gian sử dụng dịch vụ (phút)'), alignment: 0.08);
          },
          marks: [
            GuideMark(1, [catalogField('Block tính thời gian sử dụng dịch vụ (phút)'), catalogField('Tính tối thiểu (phút)')]),
            GuideMark(2, [catalogField('Số block giờ đầu tiên'), catalogField('Giá cho 4 block giờ đầu tiên')]),
          ]);
    });

    testWidgets('pos-services-3$suffix: xem trước tiền giờ', (t) async {
      await _shot(t, 'pos-services-3$suffix', PosSellProfile.roomHourly, 'Giờ chơi bi-a bàn lỗ', size,
          act: (t) async {
            _money(t, 'Giá bán (1 giờ)', '80.000');
            await t.enterText(catalogField('Block tính thời gian sử dụng dịch vụ (phút)'), '15');
            await t.enterText(catalogField('Tính tối thiểu (phút)'), '30');
            await t.pump(const Duration(milliseconds: 300));
            await catalogReveal(t, find.text('Xem trước: khách dùng bao lâu thì trả bao nhiêu'), alignment: 0.3);
          },
          marks: [
            GuideMark(1, [
              find.text('Xem trước: khách dùng bao lâu thì trả bao nhiêu'),
              find.text('Thành tiền'),
              find.text('240.000 đ'),
            ], pad: 8),
          ]);
    });

    testWidgets('pos-services-4$suffix: gói giờ đếm ngược', (t) async {
      await _shot(t, 'pos-services-4$suffix', PosSellProfile.roomHourly, 'Gói hát 2 giờ phòng VIP', size,
          act: (t) async {
            // Gói giờ bán theo giá trọn gói: bỏ «tính theo thời gian», giá nằm ở «Giá vốn, giá bán».
            await t.tap(find.text('Số lượng tính theo thời gian sử dụng?'));
            await t.pump(const Duration(milliseconds: 400));
            await guideScrollTo(t, find.text('Gói giờ đếm ngược'), alignment: 0.2);
            await t.enterText(catalogField('Thời lượng gói (phút)'), '120');
            await t.enterText(catalogField('Báo trước khi hết (phút)'), '10');
            await t.pump(const Duration(milliseconds: 300));
            await catalogReveal(t, find.text('Gói giờ đếm ngược'), alignment: 0.15);
          },
          marks: [
            GuideMark(1, [catalogField('Thời lượng gói (phút)')]),
            GuideMark(2, [catalogField('Báo trước khi hết (phút)')]),
            GuideMark(3, [find.ancestor(of: find.text('Dịch vụ tính quá giờ'), matching: find.byType(InputDecorator)).first]),
          ]);
    });
  }
}
