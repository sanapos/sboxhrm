import 'package:flutter_test/flutter_test.dart';
import 'package:zkteco_flutter_client/screens/warehouse/wh_mobile_nav.dart';

import 'guide_shot_kit.dart';
import 'pos_guide_common.dart';
import 'pos_stock_guide_common.dart';

/// Ảnh cho bước hướng dẫn «Trả hàng nhập, xuất hủy, xuất dùng nội bộ» (id: pos_stock_docs) — quán cà phê.

String _ago(int days, [int hours = 3]) => DateTime.now().subtract(Duration(days: days, hours: hours)).toIso8601String();

final _returnLines = [stockLine('3', 'SUATUOI', 'Sữa tươi không đường 1L', 6, 32000, 'Hộp', lot: 'ST1026', exp: '2026-11-20')];

Map<String, Object?> _return(String id, String no, String status, num total, int days, List<Map<String, Object?>> lines) => {
      'id': id, 'returnNo': no, 'status': status, 'supplierId': 'sNCC02', 'supplierName': 'Sữa & nguyên liệu Minh Châu',
      'sourceReceiptId': 'r2', 'sourceReceiptNo': 'PN000127', 'totalAmount': total, 'totalVat': 0, 'discountAmount': 0,
      'refundDue': total, 'refundReceived': status == 'Completed' ? total : 0, 'returnDate': _ago(days),
      'createdBy': 'Nguyễn Văn An', 'returnedBy': 'Nguyễn Văn An', 'lineCount': lines.length, 'lines': lines,
      'note': 'Sữa móp hộp, NCC đổi trả',
    };

final _returns = [
  _return('t1', 'TH000014', 'Draft', 192000, 0, _returnLines),
  _return('t2', 'TH000013', 'Completed', 255000, 6, const []),
];

Map<String, Object?> _issue(String id, String no, String kind, String status, String cat, String? who, int days,
        List<Map<String, Object?>> lines) {
  final total = lines.fold<num>(0, (a, l) => a + (l['lineTotal'] as num));
  return {
    'id': id, 'issueNo': no, 'kind': kind, 'status': status, 'categoryName': cat, 'recipientName': who,
    'issuedAt': _ago(days), 'createdAt': _ago(days), 'createdBy': 'Nguyễn Văn An', 'issuedBy': 'Nguyễn Văn An',
    'totalQty': lines.fold<num>(0, (a, l) => a + (l['qty'] as num)), 'totalValue': total == 0 ? 120000 : total,
    'lineCount': lines.length, 'lines': lines, 'note': kind == 'damage' ? 'Bánh quá hạn trưng bày' : 'Pha chế thử món mới',
  };
}

final _damageLines = [
  stockLine('7', 'TIRA', 'Bánh tiramisu', 2, 22000, 'Cái'),
  stockLine('3', 'SUATUOI', 'Sữa tươi không đường 1L', 1, 32000, 'Hộp'),
];
final _internalLines = [
  stockLine('1', 'HATCF', 'Hạt cà phê Robusta', 0.5, 255000, 'Kg'),
  stockLine('2', 'SUADAC', 'Sữa đặc', 2, 27500, 'Hộp'),
];

final _damage = [
  _issue('d1', 'XH000021', 'damage', 'Draft', 'Hết hạn / hư hỏng', null, 0, _damageLines),
  _issue('d2', 'XH000020', 'damage', 'Completed', 'Đổ vỡ', null, 3, const []),
];
final _internal = [
  _issue('i1', 'XD000009', 'internal-use', 'Draft', 'Pha chế thử món', 'Quầy bar — Trần Thị Mai', 0, _internalLines),
  _issue('i2', 'XD000008', 'internal-use', 'Completed', 'Nhân viên dùng', 'Bếp', 5, const []),
];

final _api = stockApi((req) {
  final p = req.url.path;
  if (p.endsWith('/api/pos/purchase/returns')) return {'items': _returns, 'total': _returns.length};
  if (p.endsWith('/api/pos/purchase/returns/t1')) return _returns.first;
  if (p.endsWith('/api/pos/stock/damage')) return {'items': _damage, 'total': _damage.length};
  if (p.endsWith('/api/pos/stock/damage/d1')) return _damage.first;
  if (p.endsWith('/api/pos/stock/internal-use')) return {'items': _internal, 'total': _internal.length};
  if (p.endsWith('/api/pos/stock/internal-use/i1')) return _internal.first;
  return null;
});

Finder _rich(String s) => find.textContaining(s, findRichText: true);

Future<void> _open(WidgetTester t, String no) async {
  await t.tap(find.text(no).first);
  await stockFrames(t, 6);
}

void main() {
  setUp(mockStockDeviceChannels);

  for (final (suffix, size) in [('', desktopSize), ('-mobile', mobileSize)]) {
    final mobile = suffix.isNotEmpty;
    testWidgets('pos-stock-docs-1$suffix: trả hàng nhập', (t) async {
      await guideShot(
        t,
        name: 'pos-stock-docs-1$suffix',
        screen: withPosPackage(const WhAdaptivePurchaseReturnList()),
        api: _api,
        crumbs: const ['POS', 'Trả hàng nhập'],
        size: size,
        act: (t) => _open(t, 'TH000014'),
        marks: mobile
            ? [
                GuideMark(1, [find.text('Phiếu tạm').first, find.text('NCC còn phải hoàn')], pad: 8),
                GuideMark(2, [find.text('Sữa tươi không đường 1L').last, _rich('SL: 6')], pad: 8),
                GuideMark(3, [GuideMark.button(find.text('Hoàn thành trả'))]),
              ]
            : [
                GuideMark(1, [find.text('TH000014').first, _rich('Phiếu nhập gốc')], pad: 8),
                GuideMark(2, [find.text('SUATUOI'), _rich('NCC cần trả: 192')], pad: 8),
                GuideMark(3, [GuideMark.button(find.text('Hoàn thành trả hàng'))]),
              ],
      );
    });

    testWidgets('pos-stock-docs-2$suffix: xuất hủy', (t) async {
      await guideShot(
        t,
        name: 'pos-stock-docs-2$suffix',
        screen: withPosPackage(const WhAdaptiveDamageIssueList()),
        api: _api,
        crumbs: const ['POS', 'Xuất hủy'],
        size: size,
        act: (t) => _open(t, 'XH000021'),
        marks: mobile
            ? [
                GuideMark(1, [find.text('Phiếu tạm').first, find.text('Hết hạn / hư hỏng')], pad: 8),
                GuideMark(2, [find.text('Bánh tiramisu'), _rich('SL: 1 Hộp')], pad: 8),
                GuideMark(3, [GuideMark.button(find.text('Hoàn thành hủy'))]),
              ]
            : [
                GuideMark(1, [find.text('XH000021').first, find.text('Phiếu tạm').first], pad: 8),
                GuideMark(2, [find.text('TIRA'), _rich('Tổng giá trị: 76')], pad: 8),
                GuideMark(3, [GuideMark.button(find.text('Hoàn thành xuất hủy'))]),
              ],
      );
    });

    testWidgets('pos-stock-docs-3$suffix: xuất dùng nội bộ', (t) async {
      await guideShot(
        t,
        name: 'pos-stock-docs-3$suffix',
        screen: withPosPackage(const WhAdaptiveInternalUseList()),
        api: _api,
        crumbs: const ['POS', 'Xuất dùng nội bộ'],
        size: size,
        act: (t) => _open(t, 'XD000009'),
        marks: mobile
            ? [
                GuideMark(1, [find.text('Phiếu tạm').first, _rich('Quầy bar')], pad: 8),
                GuideMark(2, [find.text('Hạt cà phê Robusta'), _rich('SL: 2 Hộp')], pad: 8),
                GuideMark(3, [GuideMark.button(find.textContaining('Hoàn thành').last)]),
              ]
            : [
                GuideMark(1, [find.text('XD000009').first, _rich('Người nhận: Quầy bar')], pad: 8),
                GuideMark(2, [find.text('HATCF'), _rich('Tổng giá trị: 182')], pad: 8),
                GuideMark(3, [GuideMark.button(find.text('Hoàn thành xuất'))]),
              ],
      );
    });
  }
}
