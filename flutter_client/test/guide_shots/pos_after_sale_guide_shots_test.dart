import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zkteco_flutter_client/screens/pos/pos_cancel_return_history_screen.dart';
import 'package:zkteco_flutter_client/screens/pos_sale_order_list_screen.dart';

import 'guide_shot_kit.dart';
import 'pos_guide_common.dart';

/// Ảnh cho bước «Sau bán: đơn hàng, in lại, hủy, trả hàng» (id: pos_after_sale) — quán cà phê.

final _today = DateTime.now();
String _at(int h, int m) => DateTime(_today.year, _today.month, _today.day, h, m).toUtc().toIso8601String();

Map<String, Object?> _line(String id, String code, String name, int qty, num price, {String unit = 'Ly'}) => {
      'id': 'l-$id', 'lineId': 'l-$id', 'productId': id, 'productCode': code, 'productName': name,
      'qty': qty, 'unitPrice': price, 'unitName': unit, 'discountAmount': 0, 'lineTotal': qty * price,
    };

Map<String, Object?> _order(String id, String no, String time, List<Map<String, Object?>> lines,
    {String? customer, String pay = 'Cash', String status = 'Completed', String? returnStatus, num returned = 0, int printCount = 1}) {
  final total = lines.fold<num>(0, (s, l) => s + (l['lineTotal'] as num));
  return {
    'id': id, 'orderNo': no, 'status': status, 'saleDate': time, 'createdAt': time,
    'subTotal': total, 'discount': 0, 'total': total, 'paidAmount': total, 'balanceDue': 0,
    'paymentMethod': pay, 'customerName': customer, 'customerPhone': customer == null ? null : '0901234567',
    'createdByName': 'Trần Thị Mai', 'soldByName': 'Trần Thị Mai', 'lines': lines,
    'returnStatus': returnStatus, 'returnedAmount': returned, 'printCount': printCount,
  };
}

final _orders = [
  _order('o5', 'HD000125', _at(14, 32), [
    _line('p2', 'CFS', 'Cà phê sữa đá', 2, 29000),
    _line('p5', 'TDCS', 'Trà đào cam sả', 1, 39000),
    _line('p7', 'TIRA', 'Bánh tiramisu', 1, 45000, unit: 'Cái'),
  ], customer: 'Chị Lan'),
  _order('o4', 'HD000124', _at(14, 5), [_line('p3', 'BX', 'Bạc xỉu', 2, 32000)], pay: 'Transfer'),
  _order('o3', 'HD000123', _at(13, 40), [_line('p1', 'CFD', 'Cà phê đen đá', 3, 25000)], returnStatus: 'Partial', returned: 25000),
  _order('o2', 'HD000122', _at(11, 18), [_line('p4', 'CFM', 'Cà phê muối', 2, 35000), _line('p6', 'NECAM', 'Nước ép cam', 1, 35000)]),
  _order('o1', 'HD000121', _at(9, 2), [_line('p2', 'CFS', 'Cà phê sữa đá', 1, 29000)], status: 'Cancelled', printCount: 0),
];

final _audits = [
  {'actionType': 'SaleCancel', 'occurredAt': _at(9, 20), 'orderNo': 'HD000121', 'amount': 29000, 'reason': 'Khách đổi ý, không lấy nữa',
    'actorName': 'Trần Thị Mai', 'afterProvisionalBill': true, 'deviceName': 'Quầy 1'},
  {'actionType': 'SaleReturn', 'occurredAt': _at(13, 55), 'orderNo': 'HD000123', 'productName': 'Cà phê đen đá', 'qty': 1, 'amount': 25000,
    'reason': 'Pha nhầm, khách trả lại 1 ly', 'actorName': 'Nguyễn Văn An', 'afterProvisionalBill': true, 'deviceName': 'Quầy 1'},
  {'actionType': 'KitchenVoid', 'occurredAt': _at(12, 10), 'orderNo': 'HD000122', 'productName': 'Nước ép cam', 'qty': 1, 'amount': 35000,
    'reason': 'Hết cam', 'actorName': 'Lê Hoàng Phúc', 'afterProvisionalBill': false, 'deviceName': 'Quầy 1'},
];

final _api = posGuideApi((req) {
  final p = req.url.path;
  if (p.endsWith('/api/pos/sales')) {
    final completed = _orders.where((o) => o['status'] == 'Completed').fold<num>(0, (s, o) => s + (o['total'] as num));
    return {'items': _orders, 'total': _orders.length, 'completedTotal': completed};
  }
  final m = RegExp(r'/api/pos/sales/([^/]+)$').firstMatch(p);
  if (m != null) return _orders.firstWhere((o) => o['id'] == m.group(1), orElse: () => _orders.first);
  if (p.endsWith('/payments')) return const [];
  if (p.contains('cancel-return')) {
    return {
      'items': _audits, 'total': _audits.length, 'totalAmount': 89000,
      'types': [
        {'actionType': 'KitchenVoid', 'count': 1, 'amount': 35000},
        {'actionType': 'SaleCancel', 'count': 1, 'amount': 29000},
        {'actionType': 'SaleReturn', 'count': 1, 'amount': 25000},
      ],
      'afterBillCount': 2, 'afterBillAmount': 54000,
    };
  }
  return null;
});

Future<void> _settle(WidgetTester t, [int ms = 600]) async {
  await t.pump(Duration(milliseconds: ms));
  for (var i = 0; i < 5; i++) {
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 60)));
    await t.pump(const Duration(milliseconds: 200));
  }
}

/// Ảnh / cache ảnh dùng thư mục máy — trong test trả thư mục tạm.
void _mockPathProvider() {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (_) async => Directory.systemTemp.createTempSync('sbox_guide').path);
}

void main() {
  setUp(_mockPathProvider);
  for (final (suffix, size) in [('', desktopSize), ('-mobile', mobileSize)]) {
    final mobile = suffix.isNotEmpty;
    testWidgets('pos-after-sale-1$suffix: danh sách đơn hàng', (t) async {
      await guideShot(
        t,
        name: 'pos-after-sale-1$suffix',
        screen: withPosPackage(const PosSaleOrderListScreen()),
        api: _api,
        crumbs: const ['POS', 'Đơn hàng'],
        size: size,
        marks: [
          GuideMark(1, mobile
              ? [GuideMark.button(find.text('Lọc').first), find.text('Tháng này').first]
              : [find.text('Trạng thái: ').first, find.text('Thanh toán: ').first], pad: 8),
          GuideMark(2, [mobile ? GuideMark.button(find.text('HD000125')) : find.textContaining('HD000125').first], pad: mobile ? 2 : 10),
        ],
      );
    }, timeout: const Timeout(Duration(seconds: 120)));

    testWidgets('pos-after-sale-2$suffix: thao tác trên đơn', (t) async {
      await guideShot(
        t,
        name: 'pos-after-sale-2$suffix',
        screen: withPosPackage(const PosSaleOrderListScreen()),
        api: _api,
        crumbs: const ['POS', 'Đơn hàng'],
        size: size,
        act: (t) async {
          await t.tap(find.textContaining('HD000125').hitTestable().first);
          await _settle(t);
          // Máy tính: hàng nút thao tác nằm cuối phần chi tiết — cuộn lên cho thấy trọn.
          if (!mobile) await guideScrollTo(t, find.text('Sao chép'), alignment: 0.8);
        },
        marks: [
          GuideMark(1, [GuideMark.button(find.textContaining('In (').last)]),
          GuideMark(2, [GuideMark.button(find.text('Hủy đơn').last)]),
          GuideMark(3, [GuideMark.button(find.text('Trả hàng').last)]),
        ],
      );
    }, timeout: const Timeout(Duration(seconds: 120)));

    testWidgets('pos-after-sale-3$suffix: lịch sử hủy / trả', (t) async {
      await guideShot(
        t,
        name: 'pos-after-sale-3$suffix',
        screen: withPosPackage(const PosCancelReturnHistoryScreen()),
        api: _api,
        crumbs: const ['POS', 'Báo cáo', 'Lịch sử hủy / trả'],
        size: size,
        act: (t) async {
          // Ẩn biểu đồ tổng quan → danh sách từng lượt hủy / trả lên đầu.
          await _settle(t);
          if (find.text('Ẩn biểu đồ').evaluate().isNotEmpty) {
            await t.tap(find.text('Ẩn biểu đồ').first);
            await _settle(t, 300);
          }
          if (mobile) await guideScrollTo(t, find.textContaining('Lý do: Khách đổi ý'), alignment: 0.55);
        },
        marks: [
          GuideMark(1, mobile
              ? [find.textContaining('Hủy đơn').hitTestable().first, find.textContaining('Trả hàng').hitTestable().first]
              : [find.text('Hủy món bếp').first, find.text('Trả hàng').first], pad: 8),
          GuideMark(2, [find.textContaining('Lý do: Khách đổi ý').first], pad: 8),
        ],
      );
    }, timeout: const Timeout(Duration(seconds: 120)));
  }
}
