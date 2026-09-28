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
import 'package:zkteco_flutter_client/screens/pos/pos_profit_report_screen.dart';
import 'package:zkteco_flutter_client/screens/pos/pos_split_report_screens.dart';
import 'package:zkteco_flutter_client/widgets/sbox/sbox_ui.dart';

/// Báo cáo POS: khối KPI + biểu đồ đầu trang với dữ liệu giả (không tràn, không lỗi).
/// Đặt SBOX_SHOT_DIR để lưu ảnh PNG duyệt giao diện.
Future<void> _loadFonts() async {
  final fl = FontLoader('BeVietnamPro');
  for (final f in ['Regular', 'Medium', 'SemiBold', 'Bold', 'ExtraBold']) {
    fl.addFont(Future.value(ByteData.view(File('assets/fonts/BeVietnamPro-$f.ttf').readAsBytesSync().buffer)));
  }
  await fl.load();
  final root = Platform.environment['FLUTTER_ROOT'];
  if (root != null) {
    final icons = File('$root/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
    if (icons.existsSync()) {
      await (FontLoader('MaterialIcons')..addFont(Future.value(ByteData.view(icons.readAsBytesSync().buffer)))).load();
    }
  }
}

http.Response _json(Object data) => http.Response(jsonEncode({'isSuccess': true, 'data': data}), 200,
    headers: {'content-type': 'application/json; charset=utf-8'});

String _d(int back) => DateTime(2026, 9, 27).subtract(Duration(days: back)).toIso8601String();

Map<String, dynamic> _sales(double k) => {
      'storeName': 'SBOX Coffee',
      'totalRevenue': 48250000 * k,
      'totalVat': 3860000 * k,
      'totalRevenueInclVat': 52110000 * k,
      'totalRefund': 650000 * k,
      'totalPaid': 47100000 * k,
      'totalDiscount': 1200000 * k,
      'totalCogs': 30350000 * k,
      'totalProfit': 17900000 * k,
      'profitMarginPct': 37.1,
      'orderCount': (186 * k).round(),
      'byPayment': [
        {'paymentMethod': 'Tiền mặt', 'total': 21500000 * k, 'count': 90},
        {'paymentMethod': 'Chuyển khoản', 'total': 17800000 * k, 'count': 60},
        {'paymentMethod': 'Thẻ', 'total': 5200000 * k, 'count': 20},
        {'paymentMethod': 'Ví điện tử', 'total': 2600000 * k, 'count': 16},
      ],
      'profitByDay': [
        for (var i = 6; i >= 0; i--)
          {
            'date': _d(i),
            'revenue': (5200000 + (i * 917000) % 3100000) * k,
            'cogs': (3300000 + (i * 511000) % 1900000) * k,
            'profit': (1900000 + (i * 406000) % 1200000) * k,
            'count': 20 + i,
          },
      ],
      'topEmployees': [
        {'soldBy': 'Nguyễn Thị Lan', 'revenue': 18400000 * k, 'orderCount': 71},
        {'soldBy': 'Trần Văn Minh', 'revenue': 15250000 * k, 'orderCount': 58},
        {'soldBy': 'Lê Hoàng Anh', 'revenue': 9800000 * k, 'orderCount': 39},
        {'soldBy': 'Phạm Thu Hà', 'revenue': 4800000 * k, 'orderCount': 18},
      ],
    };

Map<String, dynamic> _debt(String nameKey) => {
      'sumDebt': 38500000,
      'sumDebt0To30': 21000000,
      'sumDebt31To60': 9500000,
      'sumDebt61To90': 5000000,
      'sumDebtOver90': 3000000,
      'totalSuppliers': 3,
      'items': [
        {'name': 'Công ty An Phát', 'currentDebt': 15000000, 'debt0To30': 9000000, 'debtOver90': 3000000},
        {'name': 'Cửa hàng Minh Tâm', 'currentDebt': 12500000, 'debt0To30': 8000000},
        {'name': 'Chị Hạnh', 'currentDebt': 7000000, 'debt31To60': 7000000},
        {'name': 'Anh Quân', 'currentDebt': 4000000, 'debt61To90': 4000000},
      ],
    };

final _client = MockClient((req) async {
  final p = req.url.path;
  if (p.endsWith('/sales/summary')) {
    final from = DateTime.tryParse(req.url.queryParameters['from'] ?? '');
    final prev = from != null && from.isBefore(DateTime.now().subtract(const Duration(days: 8)));
    return _json(_sales(prev ? 0.86 : 1));
  }
  if (p.contains('/sales/orders')) return _json({'items': [], 'total': 0});
  if (p.endsWith('/customer-debt')) return _json(_debt('name'));
  if (p.endsWith('/supplier-debt')) return _json(_debt('name'));
  if (p.endsWith('/profit/by-product')) {
    return _json({
      'totalRevenue': 48250000,
      'totalCogs': 30350000,
      'totalProfit': 17900000,
      'items': [
        {'productName': 'Cà phê sữa đá', 'qty': 412, 'revenue': 11536000, 'cogs': 4200000, 'profit': 7336000, 'marginPct': 63.6},
        {'productName': 'Trà đào cam sả', 'qty': 268, 'revenue': 9380000, 'cogs': 3900000, 'profit': 5480000, 'marginPct': 58.4},
        {'productName': 'Bánh mì thịt nướng', 'qty': 150, 'revenue': 4200000, 'cogs': 3100000, 'profit': 1100000, 'marginPct': 26.2},
        {'productName': 'Nước ép cam', 'qty': 88, 'revenue': 3080000, 'cogs': 3300000, 'profit': -220000, 'marginPct': -7.1},
      ],
    });
  }
  return http.Response(jsonEncode({'isSuccess': false, 'message': 'not mocked'}), 200);
});

Future<void> _pump(WidgetTester tester, Widget screen, Size size, String name) async {
  final key = GlobalKey();
  Widget app(Size s) => RepaintBoundary(
        key: key,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: ThemeProvider().lightTheme,
          home: MediaQuery(data: MediaQueryData(size: s), child: Scaffold(body: screen)),
        ),
      );
  Future<void> setSize(Size s) async {
    await tester.binding.setSurfaceSize(s);
    tester.view.physicalSize = s;
    tester.view.devicePixelRatio = 1;
  }

  await http.runWithClient(() async {
    await setSize(size);
    await tester.pumpWidget(app(size));
    for (var i = 0; i < 8; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(tester.takeException(), isNull);
    final list = find.byType(Scrollable);
    var extent = 0.0;
    for (final e in list.evaluate()) {
      final st = (e as StatefulElement).state as ScrollableState;
      if (st.position.axis == Axis.vertical) extent = st.position.maxScrollExtent > extent ? st.position.maxScrollExtent : extent;
    }
    final tall = Size(size.width, extent + size.height);
    await setSize(tall);
    await tester.pumpWidget(app(tall));
    await tester.pump(const Duration(milliseconds: 600));
    expect(tester.takeException(), isNull);
  }, () => _client);
  final dir = Platform.environment['SBOX_SHOT_DIR'];
  if (dir != null) {
    await tester.runAsync(() async {
      final b = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final img = await b.toImage(pixelRatio: size.width < 600 ? 2 : 1.25);
      final data = await img.toByteData(format: ui.ImageByteFormat.png);
      File('$dir/$name.png').writeAsBytesSync(data!.buffer.asUint8List());
    });
  }
  tester.view.resetPhysicalSize();
  tester.view.resetDevicePixelRatio();
}

void main() {
  setUpAll(_loadFonts);
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('Kỳ trước cùng độ dài', () {
    final (f, t) = sboxPreviousRange(DateTime(2026, 9, 21), DateTime(2026, 9, 27, 23, 59))!;
    expect(f, DateTime(2026, 9, 14));
    expect(t.day, 20);
    final (mf, mt) = sboxPreviousRange(DateTime(2026, 8, 1), DateTime(2026, 8, 31, 23, 59))!;
    expect(mf, DateTime(2026, 7, 1));
    expect(mt.day, 31);
    expect(sboxPreviousRange(null, DateTime(2026)), isNull);
  });

  final screens = <(String, Widget, String)>[
    ('revenue', const PosRevenueReportScreen(), 'Doanh thu theo ngày'),
    ('profit', const PosProfitReportScreen(), 'Lãi nhiều nhất'),
    ('payment', const PosPaymentMethodReportScreen(), 'Cơ cấu đã thu'),
    ('debt', const PosDebtCombinedReportScreen(), 'Tuổi nợ'),
    ('staff', const PosStaffRevenueReportScreen(), 'Tỷ trọng doanh thu'),
  ];
  for (final (tag, screen, title) in screens) {
    testWidgets('Báo cáo $tag — máy tính', (tester) async {
      await _pump(tester, screen, const Size(1440, 900), 'report_${tag}_desktop');
      expect(find.text(title), findsWidgets);
    });
    testWidgets('Báo cáo $tag — điện thoại', (tester) async {
      await _pump(tester, screen, const Size(390, 844), 'report_${tag}_mobile');
      expect(find.text(title), findsWidgets);
    });
  }
}
