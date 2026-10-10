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
import 'package:zkteco_flutter_client/screens/pos/pos_loyalty_settings_screen.dart';

/// Thiết lập tích điểm có mục «Hạng thành viên»: hiện hạng đã lưu, thêm hạng, lưu gửi đúng dữ liệu.
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

Map<String, dynamic>? _saved;

MockClient _client() => MockClient((req) async {
      Map<String, dynamic> data;
      if (req.url.path.endsWith('/customers/tiers')) {
        if (req.method == 'PUT') _saved = jsonDecode(req.body) as Map<String, dynamic>;
        data = {
          'noTierCount': 3,
          'tiers': [
            {'name': 'Bạc', 'minSpend': 2000000, 'color': '#64748B', 'customerCount': 12},
            {'name': 'Vàng', 'minSpend': 10000000, 'color': '#F59E0B', 'benefit': 'Giảm 5% ngày sinh nhật', 'customerCount': 4},
          ],
        };
      } else {
        data = {'loyaltyEnabled': true, 'loyaltyEarnPerAmount': 10000, 'loyaltyRedeemValue': 100, 'loyaltyMaxRedeemPercent': 100};
      }
      return http.Response(jsonEncode({'isSuccess': true, 'data': data}), 200,
          headers: {'content-type': 'application/json; charset=utf-8'});
    });

Future<void> _pump(WidgetTester t, Size size, String shot) async {
  SharedPreferences.setMockInitialValues({});
  await t.binding.setSurfaceSize(size);
  t.view.physicalSize = size;
  t.view.devicePixelRatio = 1;
  final key = GlobalKey();
  await http.runWithClient(() async {
    await t.pumpWidget(RepaintBoundary(
      key: key,
      child: const MaterialApp(debugShowCheckedModeBanner: false, home: PosLoyaltySettingsScreen()),
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
  expect(errors, isEmpty, reason: errors.join('\n'));
}

void main() {
  setUpAll(_fonts);

  testWidgets('Máy tính: hiện hạng đã lưu, thêm hạng rồi lưu', (t) async {
    await _pump(t, const Size(1280, 1400), 'pos_loyalty_tiers_desk');
    expect(find.text('Hạng thành viên'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Vàng'), findsOneWidget);
    expect(find.widgetWithText(TextField, '10.000.000'), findsOneWidget);

    await t.tap(find.text('Thêm hạng'));
    await t.pump();
    await t.enterText(
        find.byWidgetPredicate((w) => w is TextField && w.decoration?.labelText == 'Tên hạng').last, 'Kim cương');
    // Thanh Lưu trượt lên khi có thay đổi.
    for (var i = 0; i < 10; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    _saved = null;
    await http.runWithClient(() async {
      await t.tap(find.text('Lưu').last);
      for (var i = 0; i < 6; i++) {
        await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
        await t.pump(const Duration(milliseconds: 100));
      }
    }, _client);
    final tiers = (_saved?['tiers'] as List?) ?? const [];
    expect(tiers.map((x) => x['name']), ['Bạc', 'Vàng', 'Kim cương']);
    expect(tiers.last['minSpend'], 20000000);
    // Thông báo «Đã lưu» tự ẩn bằng Timer — chờ hết trước khi kết thúc test.
    await t.pump(const Duration(seconds: 10));
    t.view.resetPhysicalSize();
  });

  testWidgets('Điện thoại: không tràn', (t) async {
    await _pump(t, const Size(390, 1800), 'pos_loyalty_tiers_phone');
    t.view.resetPhysicalSize();
  });
}
