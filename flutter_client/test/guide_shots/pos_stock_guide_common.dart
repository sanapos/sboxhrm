import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'pos_guide_common.dart';

/// Dữ liệu mẫu quán cà phê cho ảnh hướng dẫn kho: nhà cung cấp, phiếu nhập / trả / xuất, thẻ kho.

Map<String, Object?> stockLine(String id, String code, String name, num qty, num cost, String unit,
        {String? lot, String? exp}) =>
    {
      'id': id, 'productId': 'p$id', 'productCode': code, 'productName': name, 'qty': qty,
      'costPrice': cost, 'unitCost': cost, 'lineTotal': qty * cost, 'unitName': unit, 'vatRate': 0, 'vatAmount': 0,
      'lotNo': lot, 'expiryDate': exp, 'trackExpiry': exp != null,
    };

final receiptLines = [
  stockLine('1', 'HATCF', 'Hạt cà phê Robusta', 10, 255000, 'Kg'),
  stockLine('2', 'SUADAC', 'Sữa đặc', 48, 27500, 'Hộp', lot: 'L2410', exp: '2027-04-30'),
  stockLine('3', 'SUATUOI', 'Sữa tươi không đường 1L', 24, 32000, 'Hộp', lot: 'ST1026', exp: '2026-11-20'),
];

String _ago(int days, [int hours = 2]) => DateTime.now().subtract(Duration(days: days, hours: hours)).toIso8601String();

Map<String, Object?> receipt(String id, String no, String status, String supCode, String sup, num total,
        {num paid = 0, int days = 0, List<Map<String, Object?>> lines = const []}) =>
    {
      'id': id, 'receiptNo': no, 'status': status, 'supplierId': 's$supCode', 'supplierCode': supCode,
      'supplierName': sup, 'totalCost': total, 'grandTotal': total, 'paidAmount': paid, 'balanceDue': total - paid,
      'createdAt': _ago(days), 'importDate': status == 'Completed' ? _ago(days, 0) : null,
      'createdBy': 'Nguyễn Văn An', 'lineCount': lines.length,
      'totalQty': lines.fold<num>(0, (a, l) => a + (l['qty'] as num)), 'lines': lines,
    };

final receipts = [
  receipt('r1', 'PN000128', 'Draft', 'NCC01', 'Đại lý cà phê Tây Nguyên', 4638000, lines: receiptLines),
  receipt('r2', 'PN000127', 'Completed', 'NCC02', 'Sữa & nguyên liệu Minh Châu', 2860000, paid: 2860000, days: 2),
  receipt('r3', 'PN000126', 'Completed', 'NCC03', 'Bánh ngọt Hương Quê', 1350000, paid: 500000, days: 4),
];

Map<String, Object?> supplier(String code, String name, String phone, num purchase, num debt) => {
      'id': 's$code', 'supplierCode': code, 'name': name, 'phone': phone, 'totalPurchase': purchase,
      'currentDebt': debt, 'isActive': true, 'address': 'TP. Hồ Chí Minh',
    };

final suppliers = [
  supplier('NCC01', 'Đại lý cà phê Tây Nguyên', '0905 112 233', 48600000, 4638000),
  supplier('NCC02', 'Sữa & nguyên liệu Minh Châu', '0938 456 789', 22400000, 0),
  supplier('NCC03', 'Bánh ngọt Hương Quê', '0912 345 678', 9800000, 850000),
  supplier('NCC04', 'Ly nhựa & bao bì Phú Thịnh', '0977 888 111', 6200000, 0),
];

/// API giả chung cho các màn kho; [extra] trả trước (null = để mặc định xử lý).
MockClient stockApi([Object? Function(http.Request req)? extra]) => posGuideApi((req) {
      final hit = extra?.call(req);
      if (hit != null) return hit;
      final p = req.url.path;
      if (p.endsWith('/api/pos/purchase/suppliers')) {
        return {'items': suppliers, 'total': suppliers.length, 'sumDebt': 5488000, 'sumPurchase': 87000000};
      }
      if (p.endsWith('/api/pos/purchase/receipts')) return {'items': receipts, 'total': receipts.length};
      if (p.endsWith('/api/pos/purchase/receipts/r1')) return receipts.first;
      return null;
    });

/// Kênh máy thật (máy quét Sunmi, thư mục app) không có trong test — trả rỗng.
void mockStockDeviceChannels() {
  final m = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  m.setMockStreamHandler(const EventChannel('com.sboxhrm/sunmi_scanner'), MockStreamHandler.inline(onListen: (_, __) {}));
  m.setMockMethodCallHandler(const MethodChannel('plugins.flutter.io/path_provider'),
      (_) async => Directory.systemTemp.createTempSync('sbox_guide').path);
}

/// Chờ vài khung hình có thời gian thật (API giả trả về bất đồng bộ).
Future<void> stockFrames(WidgetTester t, [int n = 6]) async {
  for (var i = 0; i < n; i++) {
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
    await t.pump(const Duration(milliseconds: 100));
  }
}
