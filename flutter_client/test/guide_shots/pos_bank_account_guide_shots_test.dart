import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zkteco_flutter_client/screens/pos/pos_payment_gateway_settings_screen.dart';

import 'guide_shot_kit.dart';
import 'pos_guide_common.dart';

/// Ảnh cho bước «Tài khoản nhận tiền & VietQR» (pos_bank_account).

final _banks = [
  {
    'id': 'b1', 'accountName': 'NGUYEN VAN AN', 'accountNumber': '0071001234567', 'bankCode': '970436',
    'bankName': 'Ngân hàng TMCP Ngoại thương Việt Nam', 'bankShortName': 'Vietcombank', 'isDefault': true,
    'isActive': true, 'note': 'Tài khoản chính quán', 'vietQRTemplate': 'compact2',
  },
  {
    'id': 'b2', 'accountName': 'NGUYEN VAN AN', 'accountNumber': '19035678901011', 'bankCode': '970407',
    'bankName': 'Ngân hàng TMCP Kỹ thương Việt Nam', 'bankShortName': 'Techcombank', 'isDefault': false,
    'isActive': true, 'vietQRTemplate': 'compact2',
  },
];

final _vietQrBanks = [
  {'id': 1, 'code': 'VCB', 'bin': '970436', 'name': 'Ngân hàng TMCP Ngoại thương Việt Nam', 'shortName': 'Vietcombank'},
  {'id': 2, 'code': 'TCB', 'bin': '970407', 'name': 'Ngân hàng TMCP Kỹ thương Việt Nam', 'shortName': 'Techcombank'},
  {'id': 3, 'code': 'MB', 'bin': '970422', 'name': 'Ngân hàng TMCP Quân đội', 'shortName': 'MBBank'},
  {'id': 4, 'code': 'ACB', 'bin': '970416', 'name': 'Ngân hàng TMCP Á Châu', 'shortName': 'ACB'},
];

final _api = posGuideApi((req) {
  final p = req.url.path;
  if (p.endsWith('/api/pos/sales/bank-accounts') || p.endsWith('/api/BankAccounts')) return _banks;
  if (p.endsWith('/api/BankAccounts/vietqr-banks')) return _vietQrBanks;
  if (p.contains('payment-gateway/settings')) {
    return {'tingeeEnabled': false, 'defaultTransferProvider': 'VietQr', 'platformTingeeConfigured': true};
  }
  if (p.contains('notification-credits') && !p.contains('packages') && !p.contains('purchases') &&
      !p.contains('ledgers')) {
    return {'remainingCount': 0};
  }
  if (p.contains('tingee/status')) return {'linkedAccounts': []};
  return null;
});

void main() {
  for (final (suffix, size) in [('', desktopSize), ('-mobile', mobileSize)]) {
    const crumbs = ['Thiết lập SBOX', 'Tài khoản nhận tiền'];

    testWidgets('pos-bank-account-1$suffix: STK nhận tiền, thêm / sửa, tự báo CK', (t) async {
      await guideShot(
        t,
        name: 'pos-bank-account-1$suffix',
        screen: withPosPackage(const PosPaymentGatewaySettingsScreen()),
        api: _api,
        crumbs: crumbs,
        size: size,
        act: (t) async => guideScrollTo(t, find.text('Tài khoản ngân hàng cửa hàng'), alignment: 0.15),
        marks: [
          GuideMark(1, [find.byType(DropdownButtonFormField<String?>)]),
          GuideMark(2, [GuideMark.button(find.text('Thêm STK')), GuideMark.button(find.text('Sửa'))]),
          GuideMark(3, [find.text('Tự báo có tiền (Tingee)')]),
        ],
      );
    });

    testWidgets('pos-bank-account-2$suffix: form tài khoản ngân hàng', (t) async {
      await guideShot(
        t,
        name: 'pos-bank-account-2$suffix',
        screen: withPosPackage(const PosPaymentGatewaySettingsScreen()),
        api: _api,
        crumbs: crumbs,
        size: size,
        act: (t) async {
          await guideScrollTo(t, find.text('Sửa'), alignment: 0.4);
          await t.tap(GuideMark.button(find.text('Sửa')));
          for (var i = 0; i < 6; i++) {
            await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
            await t.pump(const Duration(milliseconds: 100));
          }
        },
        marks: [
          GuideMark(1, [GuideMark.within(find.text('Ngân hàng *'), 'InputDecorator')]),
          GuideMark(2, [
            GuideMark.within(find.text('Tên chủ tài khoản *'), 'InputDecorator'),
            GuideMark.within(find.text('Số tài khoản *'), 'InputDecorator'),
          ]),
          GuideMark(3, [find.text('Tài khoản mặc định VietQR')]),
        ],
      );
    });
  }
}
