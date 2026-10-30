import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:zkteco_flutter_client/screens/pos/pos_cashier_shift_screen.dart';
import 'package:zkteco_flutter_client/screens/pos/pos_sell_industry_settings_screen.dart';

import 'guide_shot_kit.dart';
import 'pos_guide_common.dart';

/// Ảnh cho bước hướng dẫn «Ca thu ngân & tổng kết cuối ngày» (id: pos_eod) — quán cà phê.

final _today = DateTime.now();
/// Giờ địa phương → chuỗi UTC như API trả (app tự đổi về giờ máy).
String _at(int h, int m) => DateTime(_today.year, _today.month, _today.day, h, m).toUtc().toIso8601String();

final _openShift = {
  'id': 'cs2',
  'status': 'Open',
  'openedAt': _at(14, 0),
  'openedByName': 'Trần Thị Mai',
  'openingCash': 1000000,
  'expectedCash': 3485000,
  'branchName': 'Cà Phê Mộc',
};

final _morningShift = {
  'id': 'cs1',
  'status': 'Closed',
  'openedAt': _at(6, 30),
  'closedAt': _at(14, 0),
  'openedByName': 'Lê Hoàng Nam',
  'closedByName': 'Lê Hoàng Nam',
  'openingCash': 1000000,
  'expectedCash': 4120000,
  'countedCash': 4100000,
  'difference': -20000,
};

MockClient _apiFor({required bool open}) => posGuideApi((req) {
      final p = req.url.path;
      if (p.endsWith('/api/pos/sell-settings')) {
        return {'id': 'ss1', 'sellProfile': 'restaurant', 'defaultSellMode': 'normal', 'enableResources': true, 'showFloorPlan': true, 'enableCashierShift': true};
      }
      if (p.endsWith('/api/pos/cashier-shifts/current')) {
        return {'enabled': true, 'open': open, 'shift': open ? _openShift : null};
      }
      if (p.endsWith('/api/pos/cashier-shifts')) {
        return {'items': [if (open) _openShift, _morningShift]};
      }
      return null;
    });

void main() {
  for (final (suffix, size) in [('', desktopSize), ('-mobile', mobileSize)]) {
    testWidgets('pos-eod-1$suffix: bật ca thu ngân', (t) async {
      await guideShot(
        t,
        name: 'pos-eod-1$suffix',
        screen: withPosPackage(const PosSellIndustrySettingsScreen()),
        api: _apiFor(open: false),
        crumbs: const ['Thiết lập SBOX', 'Ngành hàng & cách bán'],
        size: size,
        act: (t) async => guideScrollTo(t, find.text('Ca thu ngân (mở ca / đóng két)'), alignment: 0.4),
        marks: [
          GuideMark(1, [GuideMark.within(find.text('Ca thu ngân (mở ca / đóng két)'), 'SwitchListTile')]),
        ],
      );
    });

    testWidgets('pos-eod-2$suffix: mở ca', (t) async {
      await guideShot(
        t,
        name: 'pos-eod-2$suffix',
        screen: withPosPackage(const PosCashierShiftScreen()),
        api: _apiFor(open: false),
        crumbs: const ['POS', 'Bán hàng', 'Ca thu ngân'],
        size: size,
        act: (t) async {
          t.widget<TextField>(find.widgetWithText(TextField, 'Tiền mặt đầu ca')).controller!.text = '1.000.000';
          await t.pump();
        },
        marks: [
          GuideMark(1, [find.widgetWithText(TextField, 'Tiền mặt đầu ca')]),
          GuideMark(2, [GuideMark.button(find.text('Mở ca').last)]),
        ],
      );
    });

    testWidgets('pos-eod-3$suffix: đóng ca, đếm két', (t) async {
      await guideShot(
        t,
        name: 'pos-eod-3$suffix',
        screen: withPosPackage(const PosCashierShiftScreen()),
        api: _apiFor(open: true),
        crumbs: const ['POS', 'Bán hàng', 'Ca thu ngân'],
        size: size,
        act: (t) async {
          t.widget<TextField>(find.widgetWithText(TextField, 'Tiền mặt đếm được')).controller!.text = '3.480.000';
          await t.pump();
          await guideScrollTo(t, find.text('Đóng ca'), alignment: 0.8);
        },
        marks: [
          GuideMark(1, [find.text('Tiền mặt kỳ vọng'), find.text('3.485.000 đ')], pad: 8),
          GuideMark(2, [find.widgetWithText(TextField, 'Tiền mặt đếm được')]),
          GuideMark(3, [GuideMark.button(find.text('Đóng ca'))]),
        ],
      );
    });
  }
}
