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

final _modeDropdown = find.ancestor(
    of: find.text('Giá tính theo'), matching: find.byType(DropdownButtonFormField<PosServiceBillingMode>));

final _commissionDropdown =
    find.ancestor(of: find.text('Cách tính hoa hồng'), matching: find.byType(DropdownButtonFormField<String>));

Finder _field(String label) => find.widgetWithText(TextField, label);

void _setMoney(WidgetTester t, String label, String value) {
  t.widget<TextField>(_field(label)).controller!.text = value;
}

/// Đưa [f] lên [alignment] khung cuộn; lặp vì mục vừa mở rộng chỉ có chiều cao thật sau vài khung hình.
Future<void> _reveal(WidgetTester t, Finder f, {double alignment = 0.15}) async {
  for (var i = 0; i < 3; i++) {
    await t.pump(const Duration(milliseconds: 300));
    await Scrollable.ensureVisible(t.element(f.first), alignment: alignment);
  }
  await t.pump(const Duration(milliseconds: 300));
}

Future<void> _expand(WidgetTester t, String title) async {
  await guideScrollTo(t, find.text(title), alignment: 0.1);
  await t.tap(find.text(title));
  await t.pump(const Duration(milliseconds: 500));
}

void main() {
  for (final (suffix, size) in [('', desktopSize), ('-mobile', mobileSize)]) {
    testWidgets('ind-room-hourly-3$suffix: dịch vụ tính giờ karaoke', (t) async {
      await _shot(t, 'ind-room-hourly-3$suffix', PosSellProfile.roomHourly, 'Giờ hát phòng thường', size,
          act: (t) async {
            _setMoney(t, 'Giá bán (1 giờ)', '120.000');
            await t.enterText(_field('Tính tối thiểu (phút)'), '30');
            await guideScrollTo(t, find.text('Tính tiền theo thời gian (phòng / bàn)'), alignment: 0.05);
          },
          marks: [
            GuideMark(1, [GuideMark.within(find.text('Số lượng tính theo thời gian sử dụng?'), 'Row')]),
            GuideMark(2, [_field('Giá bán (1 giờ)'), _modeDropdown]),
            GuideMark(3, [_field('Block tính thời gian sử dụng dịch vụ (phút)'), _field('Tính tối thiểu (phút)')]),
          ]);
    });

    testWidgets('ind-salon-2$suffix: gói liệu trình nhiều buổi', (t) async {
      await _shot(t, 'ind-salon-2$suffix', PosSellProfile.salon, 'Gói massage cổ vai gáy 10 buổi', size,
          act: (t) async {
            await _expand(t, 'Tính giờ / gói buổi');
            t.widget<DropdownButtonFormField<PosServiceBillingMode>>(find.byType(DropdownButtonFormField<PosServiceBillingMode>).first)
                .onChanged!(PosServiceBillingMode.perSession);
            await t.pump(const Duration(milliseconds: 300));
            await t.enterText(_field('Số buổi trong gói'), '10');
            await t.enterText(_field('Hạn gói (ngày)'), '180');
            await _reveal(t, find.text('Cách tính giá dịch vụ'), alignment: 0.1);
          },
          marks: [
            GuideMark(1, [find.text('Cách tính giá dịch vụ'), _field('Số buổi trong gói')]),
            GuideMark(2, [_field('Hạn gói (ngày)')]),
          ]);
    });

    testWidgets('ind-commission-1$suffix: hoa hồng theo buổi', (t) async {
      await _shot(t, 'ind-commission-1$suffix', PosSellProfile.salon, 'Gói massage cổ vai gáy 10 buổi', size,
          act: (t) async {
            await _expand(t, 'Hoa hồng nhân viên');
            t.widget<DropdownButtonFormField<String>>(_commissionDropdown).onChanged!('PercentOfLine');
            await t.pump(const Duration(milliseconds: 300));
            await t.enterText(_field('% hoa hồng'), '10');
            await t.tap(find.text('Mỗi buổi làm'));
            await t.pump(const Duration(milliseconds: 300));
            await _reveal(t, find.text('Hoa hồng nhân viên'), alignment: 0.05);
          },
          marks: [
            GuideMark(1, [_commissionDropdown, _field('% hoa hồng')]),
            GuideMark(2, [find.byType(SegmentedButton<bool>)]),
          ]);
    });

    testWidgets('ind-gym-1$suffix: thẻ tập theo thời gian', (t) async {
      await _shot(t, 'ind-gym-1$suffix', PosSellProfile.gym, 'Thẻ tập 1 tháng', size,
          act: (t) async {
            await _expand(t, 'Tính giờ / gói buổi');
            await _reveal(t, find.text('Tính giờ / gói buổi'), alignment: 0.05);
            await t.tap(find.text('Thẻ tập theo thời gian (không giới hạn buổi)'));
            await t.pump();
            await _reveal(t, find.text('Tính giờ / gói buổi'), alignment: 0.05);
          },
          marks: [
            GuideMark(1, [GuideMark.within(find.text('Thẻ tập theo thời gian (không giới hạn buổi)'), 'ListTile')]),
            GuideMark(2, [_field('Hạn gói (ngày)')]),
          ]);
    });

    testWidgets('ind-hotel-3$suffix: tiền phòng theo ngày', (t) async {
      await _shot(t, 'ind-hotel-3$suffix', PosSellProfile.hotel, 'Phòng đôi qua đêm', size,
          act: (t) async {
            await guideScrollTo(t, find.text('Số lượng tính theo thời gian sử dụng?'), alignment: 0.15);
            await t.tap(find.text('Số lượng tính theo thời gian sử dụng?'));
            await t.pump(const Duration(milliseconds: 300));
            _setMoney(t, 'Giá bán (1 giờ)', '650.000');
            t.widget<DropdownButtonFormField<PosServiceBillingMode>>(_modeDropdown)
                .onChanged!(PosServiceBillingMode.perDay);
            await t.pump(const Duration(milliseconds: 300));
            await guideScrollTo(t, find.text('Tính tiền theo thời gian (phòng / bàn)'), alignment: 0.05);
          },
          marks: [
            GuideMark(1, [GuideMark.within(find.text('Số lượng tính theo thời gian sử dụng?'), 'Row')]),
            GuideMark(2, [_field('Giá bán (1 ngày / đêm)'), _modeDropdown]),
          ]);
    });
  }
}
