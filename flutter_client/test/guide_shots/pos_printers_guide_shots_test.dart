import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zkteco_flutter_client/screens/pos/pos_printers_tabs_screen.dart';
import 'package:zkteco_flutter_client/screens/pos_print_templates_screen.dart';

import 'guide_shot_kit.dart';
import 'pos_guide_common.dart';

/// Ảnh cho bước hướng dẫn «Máy in & mẫu in (K80 / tem)» (id: pos_printers) — quán cà phê.

const _receiptHtml = '<div style="text-align:center"><b>CÀ PHÊ MỘC</b><br>12 Nguyễn Huệ, Q.1<br>'
    '<b>HÓA ĐƠN BÁN HÀNG</b><br>Số: {Ma_Don_Hang}</div><table>{Chi_Tiet_Hang}</table>'
    '<div style="text-align:right"><b>Tổng cộng: {Tong_Tien}</b></div><div style="text-align:center">Cảm ơn quý khách!</div>';

List<Map<String, Object?>> _templates(String type) => [
      {
        'id': 't1', 'name': 'Hóa đơn K80 — Cà phê Mộc', 'documentType': type, 'paperSize': 'K80',
        'htmlContent': _receiptHtml, 'isDefault': true, 'isActive': true, 'sortOrder': 0,
      },
      {
        'id': 't2', 'name': 'Hóa đơn K58 (máy nhỏ)', 'documentType': type, 'paperSize': 'K58',
        'htmlContent': _receiptHtml, 'isDefault': false, 'isActive': true, 'sortOrder': 1,
      },
    ];

final _printers = [
  {
    'id': 'pr1', 'name': 'Máy in quầy thu ngân', 'connectionType': 'Lan', 'lanHost': '192.168.1.50', 'lanPort': 9100,
    'paperSize': 'K80', 'printerBrand': 'Xprinter', 'openCashDrawer': true, 'isActive': true,
  },
  {
    'id': 'pr2', 'name': 'Máy in bếp / pha chế', 'connectionType': 'Lan', 'lanHost': '192.168.1.51', 'lanPort': 9100,
    'paperSize': 'K80', 'printerBrand': 'Xprinter', 'isActive': true,
  },
  {
    'id': 'pr3', 'name': 'Máy in tem ly', 'connectionType': 'Usb', 'usbDeviceName': 'Xprinter XP-365B',
    'paperSize': 'Tem 50x30', 'printerBrand': 'Xprinter', 'isActive': true,
  },
];

final _api = posGuideApi((req) {
  final p = req.url.path;
  if (p.endsWith('/api/pos/printers')) return _printers;
  if (p.endsWith('/api/pos/print-templates')) return _templates(req.url.queryParameters['documentType'] ?? 'Invoice');
  return null;
});

void main() {
  for (final (suffix, size) in [('', desktopSize), ('-mobile', mobileSize)]) {
    final mobile = suffix.isNotEmpty;
    testWidgets('pos-printers-1$suffix: máy in', (t) async {
      await guideShot(
        t,
        name: 'pos-printers-1$suffix',
        screen: withPosPackage(const PosPrintersTabsScreen(debugTabs: (device: true, cloud: true))),
        api: _api,
        crumbs: const ['Thiết lập SBOX', 'Máy in'],
        size: size,
        act: (t) async {
          // Bật «In hóa đơn khi thanh toán» như cửa hàng đang dùng.
          await t.tap(find.byType(Switch).first);
          await t.pump(const Duration(milliseconds: 300));
        },
        marks: [
          GuideMark(1, [find.text('Trên máy này').first, find.text('Máy in cloud').first], pad: 8),
          GuideMark(2, [find.text('In hóa đơn khi thanh toán'), find.byType(Switch).first], pad: 10),
          GuideMark(3, [find.text('Chưa chọn máy in hóa đơn cloud'), find.textContaining('A6 in HĐ')], pad: 10),
          GuideMark(4, [find.text('Mẫu in hóa đơn'), find.textContaining('Cà phê Mộc')], pad: 10),
        ],
      );
    });

    testWidgets('pos-printers-2$suffix: mẫu in', (t) async {
      await guideShot(
        t,
        name: 'pos-printers-2$suffix',
        screen: withPosPackage(const PosPrintTemplatesScreen(embeddedInSettings: true)),
        api: _api,
        crumbs: const ['Thiết lập SBOX', 'Mẫu in'],
        size: size,
        marks: [
          GuideMark(
              1,
              mobile
                  ? [find.text('Hóa đơn bán hàng').first, find.byIcon(Icons.arrow_drop_down).first]
                  : [find.text('Hóa đơn bán hàng').first, find.textContaining('Tem thông số')],
              pad: 8),
          GuideMark(2, [GuideMark.button(find.textContaining('Dùng mẫu'))]),
          GuideMark(3, [GuideMark.button(find.text('In thử'))]),
        ],
      );
    });
  }
}
