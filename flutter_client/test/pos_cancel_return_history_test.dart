import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zkteco_flutter_client/providers/theme_provider.dart';
import 'package:zkteco_flutter_client/screens/pos/pos_cancel_return_history_screen.dart';

/// Lịch sử hủy / trả: thẻ tổng lấy theo máy chủ (cả kỳ), đủ loại mới, tên nhân viên thay email.
Future<void> _loadFonts() async {
  final fl = FontLoader('BeVietnamPro');
  for (final f in ['Regular', 'Medium', 'SemiBold', 'Bold', 'ExtraBold']) {
    fl.addFont(Future.value(ByteData.view(File('assets/fonts/BeVietnamPro-$f.ttf').readAsBytesSync().buffer)));
  }
  await fl.load();
}

final _now = DateTime.now().toUtc();
String _at(int h) => _now.subtract(Duration(hours: h)).toIso8601String();

Map<String, dynamic> _data() => {
      'items': [
        {'id': '1', 'actionType': 'DraftCancel', 'afterProvisionalBill': true, 'orderNo': 'HD0012', 'resourceName': 'Bàn 5',
          'productName': 'Cà phê sữa, Trà đào +2 món', 'qty': 5, 'amount': 185000, 'occurredAt': _at(1),
          'actor': 'thu.ngan@shop.vn', 'actorName': 'Nguyễn Thu Ngân'},
        {'id': '2', 'actionType': 'KitchenVoid', 'afterProvisionalBill': false, 'orderNo': 'HD0011', 'resourceName': 'Bàn 2',
          'productName': 'Bò lúc lắc', 'qty': 1, 'amount': 120000, 'reason': 'Khách đổi món', 'occurredAt': _at(3),
          'actor': 'bep@shop.vn'},
        {'id': '3', 'actionType': 'ReturnCancel', 'afterProvisionalBill': true, 'orderNo': 'HD0009', 'amount': 50000,
          'detailNote': 'Hủy phiếu trả TH0003', 'occurredAt': _at(5), 'actor': 'ql@shop.vn', 'actorName': 'Trần Quản Lý'},
      ],
      'total': 1250,
      'truncated': true,
      'scope': 'store',
      'totalCount': 1250,
      'totalAmount': 98500000,
      'afterBillCount': 37,
      'afterBillAmount': 4200000,
      'types': [
        {'actionType': 'KitchenVoid', 'count': 900, 'amount': 61000000},
        {'actionType': 'SaleCancel', 'count': 120, 'amount': 20000000},
        {'actionType': 'SaleReturn', 'count': 80, 'amount': 9000000},
        {'actionType': 'DraftCancel', 'count': 140, 'amount': 8000000},
        {'actionType': 'OrderDelete', 'count': 0, 'amount': 0},
        {'actionType': 'ReturnCancel', 'count': 10, 'amount': 500000},
      ],
    };

final _client = MockClient((req) async {
  if (req.url.path.endsWith('/api/pos/cancel-return-audits')) {
    return http.Response(jsonEncode({'isSuccess': true, 'data': _data()}), 200,
        headers: {'content-type': 'application/json; charset=utf-8'});
  }
  return http.Response(jsonEncode({'isSuccess': false, 'message': 'not mocked'}), 200);
});

void main() {
  setUpAll(_loadFonts);
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('Lịch sử hủy / trả — điện thoại', (tester) async {
    const size = Size(390, 1800);
    await tester.binding.setSurfaceSize(size);
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    final key = GlobalKey();
    await http.runWithClient(() async {
      await tester.pumpWidget(RepaintBoundary(
        key: key,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: ThemeProvider().lightTheme,
          home: const MediaQuery(data: MediaQueryData(size: size), child: PosCancelReturnHistoryScreen()),
        ),
      ));
      for (var i = 0; i < 6; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
        await tester.pump(const Duration(milliseconds: 100));
      }
    }, () => _client);
    expect(tester.takeException(), isNull);
    // Tổng cả kỳ từ máy chủ, không phải 3 dòng tải về.
    expect(find.text('1250'), findsOneWidget);
    expect(find.text('140'), findsOneWidget); // Hủy đơn tạm
    expect(find.textContaining('Hủy phiếu trả'), findsWidgets);
    expect(find.textContaining('Nguyễn Thu Ngân'), findsWidgets);
    expect(find.textContaining('3/1250'), findsOneWidget);
    final dir = Platform.environment['SBOX_SHOT_DIR'];
    if (dir != null) {
      await tester.runAsync(() async {
        final b = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        final img = await b.toImage(pixelRatio: 1.5);
        final data = await img.toByteData(format: ui.ImageByteFormat.png);
        File('$dir/cancel_return_history_mobile.png').writeAsBytesSync(data!.buffer.asUint8List());
      });
    }
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}
