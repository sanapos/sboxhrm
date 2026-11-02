import 'package:flutter_test/flutter_test.dart';
import 'package:zkteco_flutter_client/screens/pos_purchase_receipt_editor_screen.dart';
import 'package:zkteco_flutter_client/screens/pos_supplier_list_screen.dart';

import 'guide_shot_kit.dart';
import 'pos_guide_common.dart';
import 'pos_stock_guide_common.dart';

/// Ảnh cho bước hướng dẫn «Nhà cung cấp & nhập hàng» (id: pos_suppliers) — quán cà phê.

void main() {
  setUp(mockStockDeviceChannels);

  for (final (suffix, size) in [('', desktopSize), ('-mobile', mobileSize)]) {
    final mobile = suffix.isNotEmpty;

    testWidgets('pos-suppliers-1$suffix: danh sách nhà cung cấp', (t) async {
      await guideShot(
        t,
        name: 'pos-suppliers-1$suffix',
        screen: withPosPackage(const PosSupplierListScreen()),
        api: stockApi(),
        crumbs: const ['POS', 'Nhà cung cấp'],
        size: size,
        marks: [
          GuideMark(1, [GuideMark.button(find.text('Thêm NCC'))]),
          GuideMark(2, [find.text('Đang nợ NCC'), find.textContaining('5.488.000')], pad: 10),
          GuideMark(3, [find.text('Đại lý cà phê Tây Nguyên').first, find.textContaining('4.638.0', findRichText: true).first], pad: 8),
        ],
      );
    });

    testWidgets('pos-suppliers-2$suffix: phiếu nhập hàng', (t) async {
      await guideShot(
        t,
        name: 'pos-suppliers-2$suffix',
        screen: withPosPackage(const PosPurchaseReceiptEditorScreen(receiptId: 'r1')),
        api: stockApi(),
        crumbs: const ['POS', 'Nhà cung cấp', 'Phiếu nhập PN000128'],
        size: size,
        act: (t) => stockFrames(t),
        marks: mobile
            ? [
                GuideMark(1, [find.text('Hạt cà phê Robusta').first, find.textContaining('Thành tiền: 2.550.000')], pad: 8),
                GuideMark(3, [GuideMark.button(find.text('Lưu tạm')), GuideMark.button(find.text('Hoàn thành'))]),
              ]
            : [
                GuideMark(1, [find.text('Hạt cà phê Robusta').first, find.text('768.000').first], pad: 8),
                GuideMark(2, [
                  GuideMark.within(find.text('Nhà cung cấp').first, 'DropdownButtonFormField<String>'),
                  GuideMark.within(find.text('Phương thức thanh toán').first, 'InputDecorator'),
                ]),
                GuideMark(3, [GuideMark.button(find.text('Lưu tạm')), GuideMark.button(find.text('Hoàn thành'))]),
              ],
      );
    });

    testWidgets('pos-suppliers-3$suffix: trả nợ nhà cung cấp', (t) async {
      await guideShot(
        t,
        name: 'pos-suppliers-3$suffix',
        screen: withPosPackage(const PosSupplierListScreen()),
        api: stockApi(),
        crumbs: const ['POS', 'Nhà cung cấp'],
        size: size,
        act: (t) async {
          await t.tap(find.byTooltip('Thao tác').first);
          await stockFrames(t, 4);
        },
        marks: [
          GuideMark(1, [find.text('Sổ đối chiếu công nợ')], pad: 8),
          GuideMark(2, [find.text('Trả nợ')], pad: 8),
          GuideMark(3, [find.text('Nhập nợ đầu kỳ / điều chỉnh')], pad: 8),
        ],
      );
    });
  }
}
