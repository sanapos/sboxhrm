import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zkteco_flutter_client/models/pos_product.dart';
import 'package:zkteco_flutter_client/screens/pos/pos_product_editor_page.dart';
import 'package:zkteco_flutter_client/screens/pos_purchase_receipt_editor_screen.dart';

import 'guide_shot_kit.dart';
import 'pos_goods_guide_common.dart';
import 'pos_guide_common.dart';

/// Ảnh cho bước hướng dẫn «Lô / HSD, bảo hành, hàng gia công» (id: pos_lots) — tạp hóa / điện máy / nhôm kính.

Widget _editor(Map<String, Object?> product) => withPosPackage(PosProductEditorPage(
      productType: PosProductType.goods,
      product: PosProduct.fromJson(product),
    ));

Map<String, Object?> _line(String id, Map<String, Object?> p, num qty, num cost, {String? lot, String? mfg, String? exp}) => {
      'id': id, 'productId': p['id'], 'productCode': p['productCode'], 'productName': p['name'], 'qty': qty,
      'costPrice': cost, 'lineTotal': qty * cost, 'unitName': p['baseUnitName'], 'vatRate': 0, 'vatAmount': 0,
      'lotNo': lot, 'manufactureDate': mfg, 'expiryDate': exp, 'trackExpiry': p['trackExpiry'] == true,
    };

final _receipt = {
  'id': 'r1', 'receiptNo': 'PN000214', 'status': 'Draft', 'supplierId': 's2', 'supplierCode': 'NCC02',
  'supplierName': 'Sữa Minh Châu', 'totalCost': 1512000, 'grandTotal': 1512000, 'paidAmount': 0,
  'balanceDue': 1512000, 'createdAt': DateTime.now().toIso8601String(), 'createdBy': 'Nguyễn Văn An',
  'lines': [
    _line('1', milkProduct, 48, 31500, lot: 'VNM2610A', mfg: '2026-10-20', exp: '2027-04-20'),
  ],
};

Object? _receiptApi(String p) {
  if (p.endsWith('/api/pos/purchase/suppliers')) return {'items': goodsSuppliers, 'total': goodsSuppliers.length};
  if (p.endsWith('/api/pos/purchase/receipts/r1')) return _receipt;
  if (p.endsWith('/payments')) return const [];
  return null;
}

void main() {
  // Máy quét Sunmi (màn nhập hàng nghe mã vạch) không có trong test.
  setUpAll(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockStreamHandler(const EventChannel('com.sboxhrm/sunmi_scanner'), MockStreamHandler.inline(onListen: (_, __) {})));

  for (final (suffix, size) in [('', desktopSize), ('-mobile', mobileSize)]) {
    final mobile = suffix.isNotEmpty;

    testWidgets('pos-lots-1$suffix: bật mục trên form hàng hóa', (t) async {
      await guideShot(
        t,
        name: 'pos-lots-1$suffix',
        screen: withPosPackage(const PosProductEditorPage(productType: PosProductType.goods)),
        api: goodsApi(),
        crumbs: const ['POS', 'Hàng hóa', 'Thêm hàng'],
        size: size,
        act: (t) async {
          await pumpFrames(t);
          await t.tap(find.byTooltip('Tùy chọn hiển thị form'));
          await pumpFrames(t);
          // Điện thoại: danh sách mục dài — cuộn trong hộp thoại tới mục cần bật.
          if (mobile) {
            await Scrollable.ensureVisible(t.element(find.text('Bảo hành, seri & lô/HSD').last), alignment: 0.5);
            await t.pump();
          }
        },
        marks: [
          if (!mobile)
            GuideMark(1, [
              GuideMark.within(find.text('Tạp hóa / siêu thị'), 'ChoiceChip'),
              GuideMark.within(find.text('Vật liệu / nội thất'), 'ChoiceChip'),
            ], pad: 6),
          GuideMark(2, [GuideMark.within(find.text('Bảo hành, seri & lô/HSD').last, 'CheckboxListTile')], pad: 4),
          GuideMark(3, [GuideMark.button(find.text('Lưu').last)]),
        ],
      );
    });

    testWidgets('pos-lots-2$suffix: bảo hành, seri', (t) async {
      await guideShot(
        t,
        name: 'pos-lots-2$suffix',
        screen: _editor(riceCookerProduct),
        api: goodsApi(),
        crumbs: const ['POS', 'Hàng hóa', 'Nồi cơm điện 1,8L'],
        size: size,
        act: (t) async {
          await pumpFrames(t);
          await scrollFormTo(t, find.text('Bảo hành, seri & lô/HSD'));
        },
        marks: [
          GuideMark(1, [find.widgetWithText(TextField, 'Thời hạn bảo hành (tháng)')]),
          GuideMark(2, [GuideMark.within(find.text('Bắt buộc nhập seri máy khi bán'), 'SwitchListTile')]),
        ],
      );
    });

    testWidgets('pos-lots-3$suffix: theo dõi lô / HSD', (t) async {
      await guideShot(
        t,
        name: 'pos-lots-3$suffix',
        screen: _editor(milkProduct),
        api: goodsApi(),
        crumbs: const ['POS', 'Hàng hóa', 'Sữa tươi tiệt trùng 1L'],
        size: size,
        act: (t) async {
          await pumpFrames(t);
          await scrollFormTo(t, find.text('Theo dõi lô / HSD'), alignment: 0.3);
        },
        marks: [
          GuideMark(1, [GuideMark.within(find.text('Theo dõi lô / HSD'), 'SwitchListTile')]),
          GuideMark(2, [find.widgetWithText(TextField, 'Cảnh báo trước HSD (ngày)')]),
        ],
      );
    });

    testWidgets('pos-lots-4$suffix: hàng gia công, vị trí', (t) async {
      await guideShot(
        t,
        name: 'pos-lots-4$suffix',
        screen: _editor(doorProduct),
        api: goodsApi(),
        crumbs: const ['POS', 'Hàng hóa', 'Cửa nhôm Xingfa'],
        size: size,
        act: (t) async {
          await pumpFrames(t);
          await scrollFormTo(t, find.text('Hàng gia công'));
        },
        marks: [
          GuideMark(1, [GuideMark.within(find.text('Là hàng gia công'), 'SwitchListTile')]),
          GuideMark(2, [GuideMark.within(find.text('Tính giá theo m²'), 'SwitchListTile')]),
          if (!mobile) GuideMark(3, [find.widgetWithText(TextField, 'Giá tối thiểu mỗi bộ')]),
        ],
      );
    });

    testWidgets('pos-lots-5$suffix: nhập hàng theo lô', (t) async {
      await guideShot(
        t,
        name: 'pos-lots-5$suffix',
        screen: withPosPackage(const PosPurchaseReceiptEditorScreen(receiptId: 'r1')),
        api: goodsApi(_receiptApi),
        crumbs: const ['POS', 'Nhập hàng NCC', 'PN000214'],
        size: size,
        act: (t) async {
          await pumpFrames(t, 10);
          await scrollFormTo(t, find.widgetWithText(TextField, 'Mã lô'), alignment: 0.4);
        },
        marks: [
          GuideMark(1, [find.widgetWithText(TextField, 'Mã lô')]),
          GuideMark(2, [GuideMark.button(find.textContaining('NSX:')), GuideMark.button(find.textContaining('HSD:'))]),
        ],
      );
    });
  }
}
