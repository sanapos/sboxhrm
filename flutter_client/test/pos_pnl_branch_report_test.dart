import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zkteco_flutter_client/l10n/app_localizations.dart';
import 'package:zkteco_flutter_client/providers/auth_provider.dart';
import 'package:zkteco_flutter_client/providers/permission_provider.dart';
import 'package:zkteco_flutter_client/providers/theme_provider.dart';
import 'package:zkteco_flutter_client/screens/branch_ops/branch_report_screen.dart';
import 'package:zkteco_flutter_client/screens/pos/pos_split_report_screens.dart';

/// «Kết quả kinh doanh» và «Báo cáo chi nhánh» có các dòng phụ thu / phí giao hàng, cước hãng, khấu hao, cọc khách bỏ;
/// ô Lợi nhuận ròng ghi biên lãi RÒNG. Đặt SBOX_SHOT_DIR để lưu ảnh duyệt giao diện.
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

final _pnl = {
  'orderCount': 412, 'grossSales': 128500000, 'refunds': 1500000, 'vat': 0, 'discount': 2400000,
  'revenue': 127000000, 'saleCost': 72000000, 'returnedCost': 800000, 'cogs': 71200000, 'grossProfit': 55800000,
  'damageCost': 600000, 'internalUseCost': 0, 'otherIssueCost': 0, 'countLossCost': 400000, 'inventoryLoss': 1000000,
  'surchargeIncome': 3200000, 'deliveryFeeIncome': 1800000, 'carrierCost': 2100000, 'shippingNet': 2900000,
  'depreciation': 1500000, 'forfeitedDeposits': 600000, 'expenses': 18500000, 'otherIncome': 400000,
  'netProfit': 38700000, 'marginPct': 43.9, 'netMarginPct': 30.5,
  'expenseByCategory': [
    {'category': 'Tiền thuê mặt bằng', 'amount': 12000000, 'count': 1},
    {'category': 'Tiền điện', 'amount': 4500000, 'count': 1},
    {'category': 'Chi phí khác', 'amount': 2000000, 'count': 5},
  ],
  'otherIncomeByCategory': [{'category': 'Thu khác', 'amount': 400000, 'count': 1}],
  'lines': [
    {'code': '01', 'label': 'Tiền hàng bán (đã trừ giảm giá, chưa VAT)', 'amount': 128500000},
    {'code': '02', 'label': 'Hàng khách trả lại', 'amount': -1500000},
    {'code': '10', 'label': 'Doanh thu thuần', 'amount': 127000000},
    {'code': '11', 'label': 'Giá vốn hàng bán', 'amount': -71200000},
    {'code': '20', 'label': 'Lợi nhuận gộp', 'amount': 55800000},
    {'code': '15', 'label': 'Xuất hủy hàng', 'amount': -600000},
    {'code': '18', 'label': 'Chênh lệch kiểm kê (thiếu − thừa)', 'amount': -400000},
    {'code': '23', 'label': 'Phụ thu, phí giao hàng thu khách', 'amount': 5000000},
    {'code': '24', 'label': 'Cước hãng vận chuyển tính', 'amount': -2100000},
    {'code': '25', 'label': 'Khấu hao tài sản', 'amount': -1500000},
    {'code': '21', 'label': 'Chi phí hoạt động (sổ quỹ)', 'amount': -18500000},
    {'code': '26', 'label': 'Cọc khách bỏ', 'amount': 600000},
    {'code': '22', 'label': 'Thu nhập khác', 'amount': 400000},
    {'code': '50', 'label': 'Lợi nhuận thuần', 'amount': 38700000},
  ],
};

Map<String, dynamic> _branch(String id, String code, String name, num rev, num gross, num exp, num pay, num ship, num carrier,
        num dep, num forfeit, num net, {bool hq = false}) =>
    {
      'branchId': id, 'code': code, 'name': name, 'isHeadquarter': hq, 'revenue': rev, 'orders': 200, 'avgOrder': rev / 200,
      'refunds': 0, 'cogs': rev - gross, 'grossProfit': gross, 'grossMarginPct': gross / rev * 100, 'otherIncome': 0,
      'expenses': exp, 'payroll': pay, 'netProfit': net, 'stockValue': 25000000, 'employees': 6,
      'surchargeIncome': ship * 0.6, 'deliveryFeeIncome': ship * 0.4, 'carrierCost': carrier, 'depreciation': dep,
      'forfeitedDeposits': forfeit,
    };

final _compare = {
  'from': '2026-10-01T00:00:00.000', 'to': '2026-10-17T00:00:00.000',
  'branches': [
    _branch('b1', 'HQ', 'Trụ sở Cầu Giấy', 80e6, 35e6, 9e6, 12e6, 3e6, 1.2e6, 1e6, 0.6e6, 15.4e6, hq: true),
    _branch('b2', 'HD', 'Chi nhánh Hà Đông', 47e6, 20e6, 9.5e6, 10e6, 2e6, 0.9e6, 0.5e6, 0, 1.1e6),
  ],
  'totals': {
    'revenue': 127e6, 'orders': 400, 'avgOrder': 317500, 'grossProfit': 55e6, 'grossMarginPct': 43.3, 'expenses': 18.5e6,
    'payroll': 22e6, 'carrierCost': 2.1e6, 'depreciation': 1.5e6, 'netProfit': 16.5e6, 'stockValue': 50e6, 'employees': 12,
  },
  'daily': {'labels': ['2026-10-15', '2026-10-16', '2026-10-17'], 'series': []},
};

final _client = MockClient((req) async {
  final path = req.url.path;
  final data = path.endsWith('/pnl/summary')
      ? _pnl
      : path.contains('reports/compare')
          ? _compare
          : <String, dynamic>{'items': [], 'total': 0};
  return http.Response(jsonEncode({'isSuccess': true, 'data': data}), 200,
      headers: {'content-type': 'application/json; charset=utf-8'});
});

Future<void> _pump(WidgetTester tester, Widget home, Size size, String name) async {
  final key = GlobalKey();
  await tester.binding.setSurfaceSize(size);
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  await http.runWithClient(() async {
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => PermissionProvider()..loadPermissions(role: 'Admin')),
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
      ],
      child: RepaintBoundary(
        key: key,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: ThemeProvider().lightTheme,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            DefaultMaterialLocalizations.delegate,
            DefaultWidgetsLocalizations.delegate,
          ],
          home: MediaQuery(data: MediaQueryData(size: size), child: home),
        ),
      ),
    ));
    for (var i = 0; i < 12; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
      await tester.pump(const Duration(milliseconds: 100));
    }
  }, () => _client);
  expect(tester.takeException(), isNull, reason: name);
  final dir = Platform.environment['SBOX_SHOT_DIR'];
  if (dir != null) {
    await tester.runAsync(() async {
      final b = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final img = await b.toImage(pixelRatio: size.width < 600 ? 1.5 : 1);
      final data = await img.toByteData(format: ui.ImageByteFormat.png);
      File('$dir/$name.png').writeAsBytesSync(data!.buffer.asUint8List());
    });
  }
  tester.view.resetPhysicalSize();
  tester.view.resetDevicePixelRatio();
}

void main() {
  setUpAll(() async {
    await _loadFonts();
    await initializeDateFormatting('vi_VN');
  });
  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final size in const [Size(390, 3400), Size(1100, 2600)]) {
    testWidgets('Kết quả kinh doanh ${size.width.toInt()}', (t) async {
      await _pump(t, const PosPnlReportScreen(), size, 'pnl_${size.width.toInt()}');
      expect(find.text('Phụ thu, phí giao hàng thu khách'), findsOneWidget);
      expect(find.text('Cước hãng vận chuyển tính'), findsOneWidget);
      expect(find.text('Khấu hao tài sản'), findsOneWidget);
      expect(find.text('Cọc khách bỏ'), findsWidgets);
      expect(find.textContaining('Biên lãi ròng 30,5'), findsOneWidget, reason: 'ô Lợi nhuận ròng ghi biên lãi ròng');
      expect(find.textContaining('biên lãi ròng 30,5%'), findsOneWidget);
    });
    testWidgets('Báo cáo chi nhánh ${size.width.toInt()}', (t) async {
      await _pump(t, const BranchReportScreen(), size, 'branch_${size.width.toInt()}');
      expect(find.text('Trụ sở Cầu Giấy'), findsWidgets);
      expect(find.textContaining('khấu hao'), findsWidgets);
      if (size.width > 600) {
        expect(find.text('Cước hãng'), findsOneWidget);
        expect(find.text('Cọc khách bỏ'), findsOneWidget);
      }
    });
  }
}
