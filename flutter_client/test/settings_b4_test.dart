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
import 'package:zkteco_flutter_client/screens/store_access_devices_screen.dart';

/// Thiết bị truy cập (B4). Đặt SBOX_SHOT_DIR để lưu ảnh duyệt.
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

final _now = DateTime.now().toUtc();
String _ago(int h) => _now.subtract(Duration(hours: h)).toIso8601String();

http.Response _ok(Object? data) =>
    http.Response(jsonEncode({'isSuccess': true, 'data': data}), 200, headers: {'content-type': 'application/json; charset=utf-8'});

final _client = MockClient((req) async {
  if (req.url.path.endsWith('/api/store/access-devices')) {
    return _ok({
      'used': 5,
      'max': 6,
      'unlimited': false,
      'items': [
        {'id': 'd1', 'deviceKey': '…a1b2c3', 'platform': 'web', 'deviceName': 'Web', 'userName': 'Nguyễn Văn An', 'lastSeenAt': _ago(0), 'isThisDevice': true},
        {'id': 'd2', 'deviceKey': '…9f8e7d', 'platform': 'pos', 'deviceName': 'POS', 'userName': 'Phạm Thu Dung', 'lastSeenAt': _ago(3)},
        {'id': 'd3', 'deviceKey': '…44aa10', 'platform': 'android', 'deviceName': 'HRM', 'userName': 'Võ Thị Giang', 'lastSeenAt': _ago(26)},
        {'id': 'd4', 'deviceKey': '…77bc21', 'platform': 'ios', 'deviceName': 'HRM', 'userName': 'Trần Thị Bình', 'lastSeenAt': _ago(24 * 45)},
        {'id': 'd5', 'deviceKey': '…0c0d0e', 'platform': 'android', 'deviceName': 'HRM', 'userName': null, 'lastSeenAt': _ago(24 * 70)},
      ],
    });
  }
  return http.Response(jsonEncode({'isSuccess': false}), 200, headers: {'content-type': 'application/json'});
});

Future<void> _pump(WidgetTester tester, Size size, String name, {Future<void> Function()? before}) async {
  final key = GlobalKey();
  await tester.binding.setSurfaceSize(size);
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  await http.runWithClient(() async {
    await tester.pumpWidget(RepaintBoundary(
      key: key,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeProvider().lightTheme,
        home: MediaQuery(
          data: MediaQueryData(size: size),
          child: const Scaffold(body: StoreAccessDevicesScreen(canEditOverride: true)),
        ),
      ),
    ));
    for (var i = 0; i < 12; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
      await tester.pump(const Duration(milliseconds: 100));
    }
    if (before != null) {
      await before();
      for (var i = 0; i < 8; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
        await tester.pump(const Duration(milliseconds: 100));
      }
    }
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

  testWidgets('Thiết bị truy cập — máy tính', (t) async {
    await _pump(t, const Size(1100, 950), 'b4_access_devices');
    expect(find.text('Máy này'), findsOneWidget);
    expect(find.text('Lâu không dùng'), findsNWidgets(2));
    expect(find.text('Còn 1 chỗ cho máy mới.'), findsOneWidget);
  });

  testWidgets('Thiết bị truy cập — điện thoại', (t) async {
    await _pump(t, const Size(390, 1300), 'b4_access_devices_mobile');
    expect(find.text('Gỡ tất cả'), findsOneWidget);
  });
}
