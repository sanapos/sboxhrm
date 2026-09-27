import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sbox_pos/screens/pos/pos_shipping_report_screen.dart';
import 'package:sbox_pos/widgets/pos/pos_shipping_compare_sheet.dart';

/// Giao diện vận chuyển với dữ liệu giả (không gọi server thật).
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  http.Response json(Object body) =>
      http.Response(jsonEncode(body), 200, headers: {'content-type': 'application/json; charset=utf-8'});

  testWidgets('So sánh cước: nhiều gói, thời gian giao, nhãn, chọn sẵn gói Đề xuất', (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 1400));
    final client = MockClient((req) async => json({
          'isSuccess': true,
          'data': {
            'orderId': 'o1',
            'package': {'weightGrams': 800, 'lengthCm': 20, 'widthCm': 15, 'heightCm': 10, 'chargeableWeightGrams': 800},
            'quotes': [
              {'carrierCode': 'Ghn', 'carrierName': 'GHN', 'success': true, 'fee': 32000, 'serviceName': 'GHN Chuẩn', 'serviceCode': '2', 'etaMinutes': 2880, 'badges': ['cheapest', 'recommended']},
              {'carrierCode': 'Ghn', 'carrierName': 'GHN', 'success': true, 'fee': 45000, 'serviceName': 'GHN Nhanh', 'serviceCode': '1', 'etaMinutes': 1440, 'badges': ['fastest']},
              {'carrierCode': 'Ghtk', 'carrierName': 'GHTK', 'success': false, 'fee': 0, 'message': 'Thiếu token'},
              {'carrierCode': 'Internal', 'carrierName': 'Giao hàng nội bộ', 'success': true, 'fee': 0, 'serviceName': 'Tự giao', 'serviceCode': 'internal'},
            ],
          },
        }));
    ShippingCarrierPick? picked;
    await http.runWithClient(() async {
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (ctx) => TextButton(
            onPressed: () async => picked = await showShippingCompareDialog(context: ctx, orderId: 'o1', orderNo: 'HD1'),
            child: const Text('open'),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }, () => client);

    expect(find.text('Rẻ nhất'), findsOneWidget);
    expect(find.text('Nhanh nhất'), findsOneWidget);
    expect(find.text('Đề xuất'), findsOneWidget);
    expect(find.textContaining('Giao dự kiến ~2 ngày'), findsOneWidget);
    expect(find.textContaining('Giao dự kiến ~24 giờ'), findsOneWidget);
    expect(find.text('Thiếu token'), findsOneWidget);

    await tester.tap(find.text('Tạo vận đơn'));
    await tester.pumpAndSettle();
    expect(picked, isNotNull);
    expect(picked!.serviceName, 'GHN Chuẩn');
    expect(picked!.fee, 32000);
  });

  testWidgets('Báo cáo vận chuyển: tổng hợp và các tab', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1100, 1600));
    final row = {
      'orderId': 'o1', 'orderNo': 'HD9', 'customerName': 'An', 'carrierCode': 'Ghn', 'carrierName': 'GHN',
      'trackingCode': 'GHN123', 'statusCode': 'returning', 'statusLabel': 'Đang hoàn hàng', 'deliveryFee': 30000,
      'codAmount': 250000, 'failCount': 2, 'reason': 'Khách không nghe máy',
    };
    final client = MockClient((req) async => json({
          'isSuccess': true,
          'data': {
            'total': {'shipments': 12, 'delivered': 9, 'successRate': 90.0, 'failedOrders': 2, 'failedAttempts': 3,
              'returning': 1, 'returned': 1, 'cancelled': 1, 'avgDeliveryHours': 30.5, 'feeCharged': 360000,
              'carrierCost': 300000, 'shipProfit': 60000, 'codPending': 450000},
            'byCarrier': [
              {'carrierCode': 'Ghn', 'carrierName': 'GHN', 'shipments': 12, 'delivered': 9, 'successRate': 90.0,
                'failedOrders': 2, 'returning': 1, 'returned': 1, 'cancelled': 1, 'shipProfit': 60000, 'codPending': 450000},
            ],
            'failed': [row],
            'returns': [row],
            'cancelled': [],
            'cod': [],
          },
        }));
    await http.runWithClient(() async {
      await tester.pumpWidget(const MaterialApp(home: PosShippingReportScreen()));
      await tester.pumpAndSettle();
    }, () => client);

    expect(find.text('12'), findsWidgets);
    expect(find.textContaining('90'), findsWidgets);
    expect(find.textContaining('Giao thất bại (1)'), findsOneWidget);
    expect(find.textContaining('Hoàn hàng (1)'), findsOneWidget);

    await tester.tap(find.textContaining('Hoàn hàng (1)'));
    await tester.pumpAndSettle();
    expect(find.textContaining('shop CHƯA xác nhận'), findsOneWidget);
    expect(find.text('Đã nhận hàng'), findsOneWidget);
  });
}
