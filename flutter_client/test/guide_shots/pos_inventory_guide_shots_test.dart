import 'package:flutter_test/flutter_test.dart';
import 'package:zkteco_flutter_client/screens/warehouse/wh_mobile_nav.dart';

import 'guide_shot_kit.dart';
import 'pos_guide_common.dart';

/// Ảnh cho bước hướng dẫn «Kho: nhập, xuất, kiểm kê» (id: pos_inventory) — quán cà phê.

Map<String, Object?> _line(String id, String code, String name, num qty, num cost, String unit,
        {String? lot, String? exp}) =>
    {
      'id': id, 'productId': 'p$id', 'productCode': code, 'productName': name, 'qty': qty,
      'costPrice': cost, 'lineTotal': qty * cost, 'unitName': unit, 'vatRate': 0, 'vatAmount': 0,
      'lotNo': lot, 'expiryDate': exp, 'trackExpiry': exp != null,
    };

final _draftLines = [
  _line('1', 'HATCF', 'Hạt cà phê Robusta', 10, 255000, 'Kg'),
  _line('2', 'SUADAC', 'Sữa đặc', 48, 27500, 'Hộp', lot: 'L2410', exp: '2027-04-30'),
  _line('3', 'SUATUOI', 'Sữa tươi không đường 1L', 24, 32000, 'Hộp', lot: 'ST1026', exp: '2026-11-20'),
];

Map<String, Object?> _receipt(String id, String no, String status, String supCode, String sup, num total,
        {num paid = 0, int days = 0, List<Map<String, Object?>> lines = const []}) =>
    {
      'id': id, 'receiptNo': no, 'status': status, 'supplierId': 's$supCode', 'supplierCode': supCode,
      'supplierName': sup, 'totalCost': total, 'grandTotal': total, 'paidAmount': paid, 'balanceDue': total - paid,
      'createdAt': DateTime.now().subtract(Duration(days: days, hours: 2)).toIso8601String(),
      'importDate': status == 'Completed' ? DateTime.now().subtract(Duration(days: days)).toIso8601String() : null,
      'createdBy': 'Nguyễn Văn An', 'lineCount': lines.length, 'totalQty': lines.fold<num>(0, (a, l) => a + (l['qty'] as num)),
      'lines': lines,
    };

final _receipts = [
  _receipt('r1', 'PN000128', 'Draft', 'NCC01', 'Đại lý cà phê Tây Nguyên', 4638000, lines: _draftLines),
  _receipt('r2', 'PN000127', 'Completed', 'NCC02', 'Sữa & nguyên liệu Minh Châu', 2860000, paid: 2860000, days: 2),
  _receipt('r3', 'PN000126', 'Completed', 'NCC03', 'Bánh ngọt Hương Quê', 1350000, paid: 500000, days: 4),
  _receipt('r4', 'PN000125', 'Completed', 'NCC01', 'Đại lý cà phê Tây Nguyên', 5100000, paid: 5100000, days: 9),
];

final _api = posGuideApi((req) {
  final p = req.url.path;
  if (p.endsWith('/api/pos/purchase/suppliers')) {
    return {
      'items': [
        {'id': 'sNCC01', 'code': 'NCC01', 'name': 'Đại lý cà phê Tây Nguyên'},
        {'id': 'sNCC02', 'code': 'NCC02', 'name': 'Sữa & nguyên liệu Minh Châu'},
        {'id': 'sNCC03', 'code': 'NCC03', 'name': 'Bánh ngọt Hương Quê'},
      ],
      'total': 3,
    };
  }
  if (p.endsWith('/api/pos/purchase/receipts')) return {'items': _receipts, 'total': _receipts.length};
  if (p.endsWith('/api/pos/purchase/receipts/r1')) return _receipts.first;
  if (p.endsWith('/payments')) return [];
  if (p.endsWith('/api/pos/stock/counts')) return {'items': _counts, 'total': _counts.length};
  if (p.endsWith('/api/pos/stock/counts/k1')) return _counts.first;
  return null;
});

Map<String, Object?> _cl(String id, String code, String name, num sys, num counted, num cost, String unit) => {
      'id': id, 'productId': 'p$id', 'productCode': code, 'productName': name, 'systemQty': sys,
      'countedQty': counted, 'diffQty': counted - sys, 'diffValue': (counted - sys) * cost, 'costPrice': cost,
      'unitName': unit, 'isChecked': true,
    };

final _countLines = [
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
    'totalDiffQty': sum('diffQty'), 'totalDiffValue': sum('diffValue'),
    'totalActualQty': sum('countedQty'),
    'totalActualValue': lines.fold<num>(0, (a, l) => a + (l['countedQty'] as num) * (l['costPrice'] as num)),
    'qtyIncrease': 0, 'qtyDecrease': -sum('diffQty'), 'lines': lines,
  };
}

final _counts = [
  _count('k1', 'KK000031', 'Draft', 0, _countLines),
  _count('k2', 'KK000030', 'Completed', 30, const []),
];

void main() {
  for (final (suffix, size) in [('', desktopSize), ('-mobile', mobileSize)]) {
    final mobile = suffix.isNotEmpty;
    testWidgets('pos-inventory-1$suffix: phiếu nhập hàng', (t) async {
      await guideShot(
        t,
        name: 'pos-inventory-1$suffix',
        screen: withPosPackage(const WhAdaptivePurchaseReceiptList()),
        api: _api,
        crumbs: const ['POS', 'Nhập hàng NCC'],
        size: size,
        act: (t) async {
          await t.tap(find.text('PN000128').first);
          await t.pump(const Duration(milliseconds: 500));
          await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
          await t.pump(const Duration(milliseconds: 400));
        },
        marks: mobile
            ? [
                GuideMark(1, [find.text('Phiếu tạm').first, find.text('Đại lý cà phê Tây Nguyên').first, find.text('4.638.000 đ').first], pad: 10),
                GuideMark(2, [find.textContaining('SL: 10'), find.text('Hạt cà phê Robusta'), find.text('768.000 đ')], pad: 10),
                GuideMark(3, [GuideMark.button(find.text('Hoàn thành nhập'))]),
              ]
            : [
                GuideMark(1, [GuideMark.button(find.text('Tạo phiếu nhập'))]),
                GuideMark(2, [find.text('PN000128').first, find.text('Phiếu tạm').first], pad: 10),
                GuideMark(3, [GuideMark.button(find.text('Nhập hàng vào kho'))]),
              ],
      );
    });

    testWidgets('pos-inventory-2$suffix: kiểm kho', (t) async {
      await guideShot(
        t,
        name: 'pos-inventory-2$suffix',
        screen: withPosPackage(const WhAdaptiveStockCountList()),
        api: _api,
        crumbs: const ['POS', 'Kiểm kho'],
        size: size,
        act: (t) async {
          await t.tap(find.text('KK000031').first);
          await t.pump(const Duration(milliseconds: 500));
          await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
          await t.pump(const Duration(milliseconds: 400));
        },        marks: [
          GuideMark(1, mobile
              ? [find.textContaining('Thực tế: 8,2'), find.text('Hạt cà phê Robusta'), find.text('-44.000 đ')]
              : [find.text('Tồn kho'), find.text('Giá trị lệch'), find.text('-44.000 đ')], pad: 10),
          GuideMark(2, [GuideMark.button(find.text('Cân bằng kho'))]),
        ],
      );
    });
  }
}
