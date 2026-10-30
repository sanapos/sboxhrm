import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zkteco_flutter_client/screens/pos/pos_sell_industry_settings_screen.dart';
import 'package:zkteco_flutter_client/screens/pos/pos_store_settings_hub_screen.dart';

import 'guide_shot_kit.dart';
import 'pos_guide_common.dart';

/// Ảnh cho bước hướng dẫn «Thiết lập SBOX lần đầu cho POS» (id: pos_setup) — quán cà phê.

final sellSettings = {
  'id': 'ss1',
  'sellProfile': 'restaurant',
  'defaultSellMode': 'normal',
  'enableResources': true,
  'showFloorPlan': true,
  'allowProvisionalBill': true,
  'enableCashierShift': true,
  'loyaltyEnabled': true,
};

final _api = posGuideApi((req) {
  final p = req.url.path;
  if (p.endsWith('/api/pos/sell-settings')) return sellSettings;
  if (p.endsWith('/api/pos/commercial-profile')) {
    return {
      'companyName': 'Hộ kinh doanh Cà Phê Mộc',
      'taxCode': '0316789123',
      'address': '125 Nguyễn Trãi, P. Bến Thành, Q.1, TP.HCM',
      'phone': '0909 123 456',
      'bankAccountNumber': '0071000123456',
      'bankName': 'Vietcombank',
      'bankAccountHolder': 'NGUYEN VAN AN',
    };
  }
  if (p.endsWith('/api/pos/qr-order/tables')) {
    return {
      'storeName': 'Cà Phê Mộc',
      'storeAddress': '125 Nguyễn Trãi, P. Bến Thành, Q.1, TP.HCM',
      'storePhone': '0909 123 456',
      'tables': [],
    };
  }
  return null;
});

void main() {
  for (final (suffix, size) in [('', desktopSize), ('-mobile', mobileSize)]) {
    final mobile = suffix.isNotEmpty;

    testWidgets('pos-setup-1$suffix: chọn ngành hàng', (t) async {
      await guideShot(
        t,
        name: 'pos-setup-1$suffix',
        screen: withPosPackage(const PosSellIndustrySettingsScreen()),
        api: _api,
        crumbs: const ['Thiết lập SBOX', 'Ngành hàng & cách bán'],
        size: size,
        act: (t) async {
          // Máy tính: đẩy ô «Chế độ bán» xuống cuối khung để thấy cả danh sách ngành phía trên.
          mobile
              ? await guideScrollTo(t, find.text('Nhà hàng / Cafe'), alignment: 0.35)
              : await guideScrollTo(t, find.text('Chế độ bán mặc định'), alignment: 0.85);
        },
        marks: [
          GuideMark(1, [GuideMark.button(find.text('Nhà hàng / Cafe'))]),
          if (!mobile) GuideMark(2, [find.text('Chế độ bán mặc định'), find.byType(DropdownButtonFormField<String>).first]),
        ],
      );
    });

    testWidgets('pos-setup-2$suffix: thông tin cửa hàng', (t) async {
      await guideShot(
        t,
        name: 'pos-setup-2$suffix',
        screen: withPosPackage(const PosStoreSettingsHubScreen(canEditOverride: true)),
        api: _api,
        crumbs: const ['Thiết lập SBOX', 'Thông tin cửa hàng'],
        size: size,
        act: (t) async => guideScrollTo(t, find.text('In trên hóa đơn bán hàng'), alignment: 0.05),
        marks: [
          GuideMark(1, [
            find.widgetWithText(TextField, 'Tên cửa hàng *'),
            find.widgetWithText(TextField, 'Số điện thoại').first,
          ]),
          GuideMark(2, [find.text('Thuế VAT khi bán'), find.text('Giá bán đã bao gồm thuế')]),
        ],
      );
    });
  }
}
