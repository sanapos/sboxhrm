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
import 'package:zkteco_flutter_client/models/pos_product.dart';
import 'package:zkteco_flutter_client/providers/auth_provider.dart';
import 'package:zkteco_flutter_client/providers/permission_provider.dart';
import 'package:zkteco_flutter_client/providers/theme_provider.dart';
import 'package:zkteco_flutter_client/screens/pos/pos_material_report_screen.dart';
import 'package:zkteco_flutter_client/screens/pos/pos_topping_report_screen.dart';

/// «Nguyên vật liệu» + «Topping»: dựng với số liệu mẫu (đúng dạng JSON máy chủ trả), không lỗi giao diện,
/// có kết luận / việc nên làm / đồ thị. Đặt SBOX_SHOT_DIR để lưu ảnh duyệt giao diện.
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

Map<String, dynamic> _mat(String name, String unit, num onHand, num used, num value, num? daysLeft, String level,
        String levelText, List<(String, num, num)> dishes, {num received = 0, num wasted = 0, num wastedValue = 0}) =>
    {
      'productId': name, 'code': 'NVL', 'name': name, 'unit': unit, 'type': 'Material', 'onHand': onHand, 'minStock': 0,
      'costPrice': 0, 'usedQty': used, 'usedValue': value, 'receivedQty': received, 'wastedQty': wasted,
      'wastedValue': wastedValue, 'avgPerDay': used / 7, 'daysLeft': daysLeft, 'level': level, 'levelText': levelText,
      'dishes': [for (final (n, q, v) in dishes) {'name': n, 'qty': q, 'value': v}],
    };

final _materials = {
  'verdict': 'red',
  'verdictText': '2 nguyên liệu đã hết hoặc sắp hết trong 2 ngày — cần nhập ngay',
  'verdictDetail': 'Bột năng, Kem béo',
  'days': 7,
  'summary': {
    'materialCount': 6, 'usedCount': 5, 'usedValue': 4850000, 'usedPerDay': 692857, 'redCount': 2, 'yellowCount': 1,
    'negativeCount': 1, 'wastedValue': 320000, 'noRecipeDishCount': 2, 'recipeConfigured': true,
  },
  'materials': [
    _mat('Bột năng', 'g', 300, 4900, 245000, 0.4, 'red', 'Sắp hết (< 2 ngày)', [('Trân châu đen', 4900, 245000)]),
    _mat('Kem béo', 'ml', -200, 5600, 560000, 0, 'red', 'Đã hết', [('Trà sữa', 3500, 350000), ('Cà phê muối', 2100, 210000)]),
    _mat('Sữa tươi', 'ml', 9000, 21000, 1050000, 3, 'yellow', 'Đủ < 5 ngày',
        [('Trà sữa', 14000, 700000), ('Bạc xỉu', 7000, 350000)], received: 20000, wasted: 2000, wastedValue: 100000),
    _mat('Cà phê hạt', 'g', 6000, 4200, 1260000, 10, 'green', 'Đủ dùng', [('Cà phê đen', 2400, 720000), ('Bạc xỉu', 1800, 540000)]),
    _mat('Trà đen', 'g', 2500, 1750, 1735000, 10, 'green', 'Đủ dùng', [('Trà sữa', 1750, 1735000)], wasted: 300, wastedValue: 220000),
    _mat('Bột cacao', 'g', 800, 0, 0, null, 'none', 'Không dùng trong kỳ', []),
  ],
  'daily': [
    for (var d = 11; d <= 17; d++) {'day': '2026-10-$d', 'value': 500000 + (d % 3) * 150000},
  ],
  'topDishes': [
    {'name': 'Trà sữa', 'qty': 0, 'value': 2785000},
    {'name': 'Cà phê đen', 'qty': 0, 'value': 720000},
    {'name': 'Bạc xỉu', 'qty': 0, 'value': 890000},
    {'name': 'Trân châu đen', 'qty': 0, 'value': 245000},
    {'name': 'Cà phê muối', 'qty': 0, 'value': 210000},
  ],
  'noRecipeDishes': [
    {'productId': 'x', 'name': 'Sinh tố bơ', 'soldQty': 42, 'onHand': -42},
    {'productId': 'y', 'name': 'Matcha đá xay', 'soldQty': 18, 'onHand': -18},
  ],
  'recommendations': [
    {'level': 'red', 'title': 'Nhập ngay «Bột năng»', 'detail': 'Còn 300 g, dùng ~700 g/ngày → đủ khoảng 0,4 ngày.'},
    {'level': 'red', 'title': 'Nhập ngay «Kem béo»', 'detail': 'Đã hết (tồn -200 ml). Món dùng nhiều: Trà sữa, Cà phê muối.'},
    {'level': 'yellow', 'title': 'Lên kế hoạch nhập «Sữa tươi»', 'detail': 'Đủ dùng khoảng 3 ngày (dùng ~3.000 ml/ngày).'},
    {'level': 'yellow', 'title': 'Khai định lượng cho món pha chế / chế biến', 'detail': 'Sinh tố bơ, Matcha đá xay bán ra nhưng không trừ nguyên liệu.'},
  ],
};

Map<String, dynamic> _top(String name, num qty, num rev, num cost, num share, String level, String? note,
        {num onHand = 40, bool tracks = true}) =>
    {
      'productId': name, 'name': name, 'qty': qty, 'revenue': rev, 'cost': cost, 'profit': rev - cost, 'sharePct': share,
      'onHand': onHand, 'tracksStock': tracks, 'level': level, 'note': note,
    };

final _toppings = {
  'verdict': 'red',
  'verdictText': '1 topping đang bán lỗ — cần chỉnh giá hoặc định lượng',
  'verdictDetail': 'Kem cheese',
  'summary': {
    'cups': 620, 'cupsWithTopping': 233, 'ratePct': 37.6, 'rateLevel': 'green', 'toppingRevenue': 1935000,
    'toppingCost': 812000, 'toppingProfit': 1123000, 'marginPct': 58.0, 'portions': 318, 'avgPerCup': 1.36,
    'revenuePerCup': 3121, 'toppingKinds': 6, 'groupCount': 2,
  },
  'toppings': [
    _top('Trân châu đen', 142, 710000, 213000, 36.7, 'green', null, tracks: false),
    _top('Thạch phô mai', 66, 396000, 132000, 20.5, 'green', null),
    _top('Kem cheese', 48, 384000, 432000, 19.8, 'red', 'Bán lỗ: giá vốn cao hơn giá bán'),
    _top('Pudding trứng', 31, 217000, 35000, 11.2, 'yellow', 'Chưa có giá vốn — lãi đang tính 100%'),
    _top('Trân châu trắng', 22, 132000, 0, 6.8, 'red', 'Hết hàng trong kho', onHand: 0),
    _top('Shot espresso', 9, 96000, 0, 5.0, 'green', null),
  ],
  'dishes': [
    {'productId': 'a', 'name': 'Trà sữa truyền thống', 'cups': 260, 'cupsWithTopping': 148, 'ratePct': 56.9, 'toppingRevenue': 1120000, 'toppingsPerCup': 1.5},
    {'productId': 'b', 'name': 'Trà đào cam sả', 'cups': 150, 'cupsWithTopping': 40, 'ratePct': 26.7, 'toppingRevenue': 330000, 'toppingsPerCup': 1.1},
    {'productId': 'c', 'name': 'Cà phê sữa đá', 'cups': 130, 'cupsWithTopping': 9, 'ratePct': 6.9, 'toppingRevenue': 96000, 'toppingsPerCup': 1},
    {'productId': 'd', 'name': 'Sữa chua dâu', 'cups': 80, 'cupsWithTopping': 36, 'ratePct': 45, 'toppingRevenue': 389000, 'toppingsPerCup': 1.4},
  ],
  'daily': [
    for (var d = 11; d <= 17; d++)
      {'day': '2026-10-$d', 'cups': 90, 'cupsWithTopping': 20 + d * 1.0, 'ratePct': [28.0, 31.5, 44.2, 25.0, 12.0, 39.0, 41.3][d - 11], 'revenue': 270000},
  ],
  'recommendations': [
    {'level': 'red', 'title': 'Chỉnh giá «Kem cheese»', 'detail': 'Bán 384.000đ nhưng giá vốn 432.000đ (lỗ 48.000đ). Tăng giá thêm hoặc giảm định lượng.'},
    {'level': 'red', 'title': 'Nhập thêm «Trân châu trắng»', 'detail': 'Topping hết hàng trong kho — thu ngân bán sẽ bị báo hết.'},
    {'level': 'info', 'title': 'Món bán chạy nhưng ít khi thêm topping', 'detail': 'Cà phê sữa đá (6,9%) — kiểm tra món đã gắn đúng nhóm topping chưa.'},
  ],
};

final _client = MockClient((req) async {
  final path = req.url.path;
  final data = path.contains('/materials/summary')
      ? _materials
      : path.contains('/toppings/summary')
          ? _toppings
          : <String, dynamic>{};
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

  for (final size in const [Size(390, 3600), Size(1100, 2600)]) {
    testWidgets('Nguyên vật liệu ${size.width.toInt()}', (t) async {
      await _pump(t, const PosMaterialReportScreen(), size, 'materials_${size.width.toInt()}');
      expect(find.textContaining('2 nguyên liệu đã hết hoặc sắp hết'), findsOneWidget);
      expect(find.text('Việc nên làm'), findsOneWidget);
      expect(find.text('Nhập ngay «Bột năng»'), findsOneWidget);
      expect(find.text('Còn đủ dùng bao nhiêu ngày'), findsOneWidget);
      expect(find.text('Món tốn nguyên liệu nhất'), findsOneWidget);
      expect(find.text('Tiền nguyên liệu dùng theo ngày'), findsOneWidget);
      expect(find.text('Món bán ra mà chưa khai định lượng'), findsOneWidget);
      expect(find.text('Sinh tố bơ'), findsOneWidget);
      // Lọc «Cần nhập» chỉ còn đỏ / vàng.
      await t.tap(find.text('Cần nhập'));
      await t.pump();
      expect(find.text('Bột cacao'), findsNothing);
    });

    testWidgets('Topping ${size.width.toInt()}', (t) async {
      await _pump(t, const PosToppingReportScreen(), size, 'toppings_${size.width.toInt()}');
      expect(find.text('1 topping đang bán lỗ — cần chỉnh giá hoặc định lượng'), findsOneWidget);
      expect(find.text('Ly có topping'), findsOneWidget);
      expect(find.text('37,6%'), findsOneWidget);
      expect(find.text('Bao nhiêu ly có thêm topping'), findsOneWidget);
      expect(find.text('Topping bán chạy'), findsOneWidget);
      expect(find.text('Theo món'), findsOneWidget);
      expect(find.text('Tỷ lệ ly có topping theo ngày'), findsOneWidget);
      expect(find.text('Bán lỗ: giá vốn cao hơn giá bán'), findsOneWidget);
      expect(find.text('Chỉnh giá «Kem cheese»'), findsOneWidget);
    });
  }

  group('Định lượng theo size', () {
    final product = PosProduct.fromJson({
      'id': 'p1', 'productCode': 'HH1', 'name': 'Trà sữa', 'productType': 'Goods',
      'recipeLines': [
        {'componentProductId': 'milk', 'qty': 30},
        {'componentProductId': 'pearl', 'qty': 20},
        {'componentProductId': 'milk', 'qty': 50, 'variantId': 'L'},
      ],
    });

    test('size khai riêng dùng dòng riêng, size khác dùng «mọi size»', () {
      expect(product.recipeLinesFor('L').map((l) => l.qty), [50]);
      expect(product.recipeLinesFor('M').map((l) => l.qty), [30, 20]);
      expect(product.recipeLinesFor(null).map((l) => l.qty), [30, 20]);
    });

    test('lưu bộ nhớ đệm giữ size của dòng định lượng', () {
      final again = PosProduct.fromJson(product.toSellCacheJson());
      expect(again.recipeLinesFor('L').single.qty, 50);
      expect(again.recipeLinesFor(null).length, 2);
    });

    test('size khai bằng đơn vị bán («L») dùng định lượng của đơn vị', () {
      final p = PosProduct.fromJson({
        'id': 'p2', 'productCode': 'DV1', 'name': 'Trà sữa', 'productType': 'Service',
        'recipeLines': [
          {'componentProductId': 'milk', 'qty': 100},
          {'componentProductId': 'milk', 'qty': 150, 'unitId': 'uL'},
        ],
      });
      expect(p.recipeLinesFor(null, 'uL').map((l) => l.qty), [150]);
      expect(p.recipeLinesFor(null, 'uM').map((l) => l.qty), [100]);
      expect(p.recipeLinesFor(null).map((l) => l.qty), [100]);
      expect(p.recipeLinesFor(null, 'uL').single.sizeKey, 'u:uL');
      expect(PosProduct.fromJson(p.toSellCacheJson()).recipeLinesFor(null, 'uL').single.qty, 150);
    });

    test('nhóm topping đọc số món đang gắn', () {
      final g = PosProductToppingGroup.fromJson({'id': 'g', 'name': 'Topping', 'linkedProductCount': 7, 'items': []});
      expect(g.linkedProductCount, 7);
    });
  });
}
