import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zkteco_flutter_client/screens/pos_stock_count_editor_screen.dart';
import 'package:zkteco_flutter_client/screens/warehouse/editors/wh_mobile_stock_count_editor.dart';
import 'package:zkteco_flutter_client/screens/warehouse/wh_mobile_nav.dart';

import 'guide_shot_kit.dart';
import 'pos_guide_common.dart';
import 'pos_stock_guide_common.dart';

/// Ảnh cho bước hướng dẫn «Kiểm kho» (id: pos_stock_count) — quán cà phê.

Map<String, Object?> _cl(String id, String code, String name, num sys, num counted, num cost, String unit) => {
      'id': id, 'productId': 'p$id', 'productCode': code, 'productName': name, 'systemQty': sys,
      'countedQty': counted, 'diffQty': counted - sys, 'diffValue': (counted - sys) * cost, 'costPrice': cost,
      'unitName': unit, 'isChecked': true,
    };

final _lines = [
  _cl('1', 'HATCF', 'Hạt cà phê Robusta', 8.5, 8.2, 255000, 'Kg'),
  _cl('2', 'SUADAC', 'Sữa đặc', 24, 24, 27500, 'Hộp'),
  _cl('3', 'SUATUOI', 'Sữa tươi không đường 1L', 12, 11, 32000, 'Hộp'),
  _cl('4', 'TIRA', 'Bánh tiramisu', 12, 10, 22000, 'Cái'),
];

Map<String, Object?> _count(String id, String no, String status, int days, List<Map<String, Object?>> lines) {
  num sum(String k) => lines.fold<num>(0, (a, l) => a + (l[k] as num));
  return {
    'id': id, 'countNo': no, 'name': 'Kiểm kho cuối tháng', 'status': status,
    'createdAt': DateTime.now().subtract(Duration(days: days, hours: 1)).toIso8601String(),
    'createdBy': 'Nguyễn Văn An', 'lineCount': lines.length, 'checkedCount': lines.length,
    'totalDiffQty': sum('diffQty'), 'totalDiffValue': sum('diffValue'), 'totalActualQty': sum('countedQty'),
    'totalActualValue': lines.fold<num>(0, (a, l) => a + (l['countedQty'] as num) * (l['costPrice'] as num)),
    'qtyIncrease': 0, 'qtyDecrease': -sum('diffQty'), 'lines': lines, 'note': 'Kiểm nguyên liệu quầy bar',
  };
}

final _counts = [
  _count('k1', 'KK000031', 'Draft', 0, _lines),
  _count('k2', 'KK000030', 'Completed', 30, const []),
];

final _api = stockApi((req) {
  final p = req.url.path;
  if (p.endsWith('/api/pos/stock/counts')) return {'items': _counts, 'total': _counts.length};
  if (p.endsWith('/api/pos/stock/counts/k1')) return _counts.first;
  return null;
});

void main() {
  setUp(mockStockDeviceChannels);

  for (final (suffix, size) in [('', desktopSize), ('-mobile', mobileSize)]) {
    final mobile = suffix.isNotEmpty;

    testWidgets('pos-stock-count-1$suffix: danh sách phiếu kiểm', (t) async {
      await guideShot(
        t,
        name: 'pos-stock-count-1$suffix',
        screen: withPosPackage(const WhAdaptiveStockCountList()),
        api: _api,
        crumbs: const ['POS', 'Kiểm kho'],
        size: size,
        marks: [
          GuideMark(1, [mobile ? find.byType(FloatingActionButton) : GuideMark.button(find.text('Tạo phiếu kiểm kê'))]),
          GuideMark(2, [find.text('KK000031').first, mobile ? find.textContaining('152.500', findRichText: true).first : find.text('Phiếu tạm').first], pad: 8),
        ],
      );
    });

    testWidgets('pos-stock-count-2$suffix: nhập số đếm', (t) async {
      await guideShot(
        t,
        name: 'pos-stock-count-2$suffix',
        screen: withPosPackage(mobile ? const WhMobileStockCountEditor(countId: 'k1') : const PosStockCountEditorScreen(countId: 'k1')),
        api: _api,
        crumbs: const ['POS', 'Kiểm kho', 'KK000031'],
        size: size,
        act: (t) => stockFrames(t),
        marks: mobile
            ? [
                GuideMark(1, [find.widgetWithText(TextField, 'Tìm hoặc quét mã hàng…')]),
                GuideMark(2, [find.text('Hạt cà phê Robusta').first, find.textContaining('Lệch: -0,3', findRichText: true).first, find.text('8,2').first], pad: 8),
                GuideMark(3, [GuideMark.button(find.text('Cân bằng kho'))]),
              ]
            : [
                GuideMark(1, [find.widgetWithText(TextField, 'Tìm hàng hóa (F3)')]),
                GuideMark(2, [find.text('Thực tế'), find.text('-44.000 đ')], pad: 8),
                GuideMark(3, [GuideMark.button(find.text('Hoàn thành'))]),
              ],
      );
    });

    testWidgets('pos-stock-count-3$suffix: cân bằng kho', (t) async {
      await guideShot(
        t,
        name: 'pos-stock-count-3$suffix',
        screen: withPosPackage(const WhAdaptiveStockCountList()),
        api: _api,
        crumbs: const ['POS', 'Kiểm kho'],
        size: size,
        act: (t) async {
          await t.tap(find.text('KK000031').first);
          await stockFrames(t, 6);
        },
        marks: [
          GuideMark(1, mobile
              ? [find.textContaining('Thực tế: 8,2', findRichText: true), find.text('Hạt cà phê Robusta'), find.text('-44.000 đ')]
              : [find.text('Tồn kho'), find.text('Giá trị lệch'), find.text('-44.000 đ')], pad: 10),
          GuideMark(2, [GuideMark.button(find.text('Cân bằng kho'))]),
        ],
      );
    });
  }
}
