import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zkteco_flutter_client/providers/permission_provider.dart';
import 'package:zkteco_flutter_client/screens/pos/pos_customers_screen.dart';

/// Màn khách hàng: bộ lọc sinh nhật / mua hàng / trạng thái / sắp xếp gửi lên máy chủ;
/// điện thoại & máy tính không tràn chữ. SBOX_SHOT_DIR = lưu ảnh.
Future<void> _fonts() async {
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

final _queries = <Map<String, String>>[];

Map<String, dynamic> _cust(String code, String name, {String? birthday, double debt = 0, int orders = 0, String? last}) => {
      'id': 'id-$code', 'customerCode': code, 'name': name, 'phone': '0912 000 ${code.substring(2)}',
      'birthday': birthday, 'totalPurchase': orders * 250000, 'currentDebt': debt, 'pointBalance': orders * 25,
      'isActive': true, 'orderCount': orders, 'lastPurchaseAt': last, 'province': 'Hà Nội',
      'tier': orders >= 12 ? 'Kim cương' : (orders >= 1 ? 'Bạc' : null),
    };

MockClient _client() => MockClient((req) async {
      if (req.url.path.endsWith('/customers/tiers')) {
        return http.Response(
            jsonEncode({
              'isSuccess': true,
              'data': {
                'noTierCount': 1,
                'tiers': [
                  {'name': 'Bạc', 'minSpend': 200000, 'color': '#64748B', 'customerCount': 1},
                  {'name': 'Kim cương', 'minSpend': 3000000, 'color': '#8B5CF6', 'benefit': 'Giảm 5% mỗi đơn', 'customerCount': 1},
                ],
              },
            }),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'});
      }
      if (req.url.path == '/api/pos/customers') _queries.add(req.url.queryParameters);
      final now = DateTime.now();
      final bd = '1990-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}T00:00:00';
      return http.Response(
          jsonEncode({
            'isSuccess': true,
            'data': {
              'total': 3, 'page': 1, 'pageSize': 50, 'sumDebt': 1500000, 'sumPurchase': 9000000, 'sumPoints': 875,
              'birthdaysThisMonth': 1,
              'items': [
                _cust('KH000001', 'Nguyễn Thị Hồng Nhung (Công ty TNHH Thương mại Dịch vụ Ánh Dương)',
                    birthday: bd, debt: 1500000, orders: 12, last: now.toUtc().subtract(const Duration(days: 3)).toIso8601String()),
                _cust('KH000002', 'Trần Văn Bình', orders: 1, last: now.toUtc().subtract(const Duration(days: 120)).toIso8601String()),
                _cust('KH000003', 'Lê Minh'),
              ],
            },
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'});
    });

Future<void> _pump(WidgetTester t, Size size, String shot) async {
  SharedPreferences.setMockInitialValues({});
  _queries.clear();
  await t.binding.setSurfaceSize(size);
  t.view.physicalSize = size;
  t.view.devicePixelRatio = 1;
  final key = GlobalKey();
  await http.runWithClient(() async {
    await t.pumpWidget(RepaintBoundary(
      key: key,
      child: ChangeNotifierProvider(
        create: (_) => PermissionProvider()..loadPermissions(role: 'Admin'),
        child: const MaterialApp(debugShowCheckedModeBanner: false, home: PosCustomersScreen()),
      ),
    ));
    for (var i = 0; i < 8; i++) {
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
      await t.pump(const Duration(milliseconds: 100));
    }
  }, _client);
  final errors = <Object>[];
  Object? e;
  while ((e = t.takeException()) != null) {
    errors.add(e!);
  }
  final dir = Platform.environment['SBOX_SHOT_DIR'];
  if (dir != null) {
    await t.runAsync(() async {
      final b = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final img = await b.toImage(pixelRatio: size.width < 600 ? 1.5 : 1);
      final data = await img.toByteData(format: ui.ImageByteFormat.png);
      File('$dir/$shot.png').writeAsBytesSync(data!.buffer.asUint8List());
    });
  }
  t.view.resetPhysicalSize();
  expect(errors, isEmpty, reason: errors.join('\n'));
}

void main() {
  setUpAll(_fonts);

  testWidgets('Điện thoại: không tràn, có sinh nhật / mua gần nhất, gửi sắp xếp mặc định', (t) async {
    await _pump(t, const Size(390, 1500), 'pos_customers_phone');
    expect(_queries.single['sort'], 'debt');
    expect(_queries.single['status'], 'active');
    expect(find.textContaining('Sinh nhật tháng này'), findsOneWidget);
  });

  testWidgets('Máy tính: cột sinh nhật, mua gần nhất', (t) async {
    await _pump(t, const Size(1440, 1000), 'pos_customers_desk');
    expect(find.text('Mua gần nhất'), findsOneWidget);
    expect(find.textContaining('3 ngày trước · 12 đơn'), findsOneWidget);
    expect(find.text('Chưa mua'), findsWidgets);
    expect(find.text('Kim cương'), findsOneWidget);
    expect(find.textContaining('Hạng'), findsWidgets);
  });
}
