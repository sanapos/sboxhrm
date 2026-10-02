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
import 'package:zkteco_flutter_client/providers/auth_provider.dart';
import 'package:zkteco_flutter_client/providers/permission_provider.dart';
import 'package:zkteco_flutter_client/providers/theme_provider.dart';
import 'package:zkteco_flutter_client/screens/settings_hub_screen.dart';
import 'package:zkteco_flutter_client/utils/settings_hub_catalog.dart';

/// Thiết lập SBOX với dữ liệu mẫu. Đặt SBOX_SHOT_DIR để lưu ảnh duyệt giao diện.
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

final _health = [
  {'key': 'shift', 'status': 'ok', 'text': '4 ca đang dùng'},
  {'key': 'holiday', 'status': 'warn', 'text': 'Chưa có ngày lễ năm 2027'},
  {'key': 'device', 'status': 'warn', 'text': '1/3 máy mất kết nối'},
  {'key': 'mobile', 'status': 'ok', 'text': '2 vị trí chấm công'},
  {'key': 'insurance', 'status': 'info', 'text': 'Đang dùng mức mặc định'},
  {'key': 'tax', 'status': 'info', 'text': 'Đang dùng biểu thuế mặc định'},
  {'key': 'penalty', 'status': 'ok', 'text': '3 mức phạt'},
  {'key': 'allowance', 'status': 'ok', 'text': '5 phụ cấp'},
  {'key': 'branch', 'status': 'ok', 'text': '3 chi nhánh'},
  {'key': 'payment', 'status': 'todo', 'text': 'Chưa có tài khoản nhận tiền'},
  {'key': 'einvoice', 'status': 'info', 'text': 'Chưa kết nối'},
  {'key': 'shipping', 'status': 'info', 'text': 'Chưa bật đơn vị giao hàng'},
  {'key': 'cloudPrinter', 'status': 'info', 'text': 'Chưa có máy in cloud'},
];

final _client = MockClient((req) async {
  if (req.url.path.endsWith('/settings-health')) {
    return http.Response(jsonEncode({'isSuccess': true, 'data': _health}), 200,
        headers: {'content-type': 'application/json; charset=utf-8'});
  }
  return http.Response(jsonEncode({'isSuccess': false}), 200, headers: {'content-type': 'application/json'});
});

Future<void> _pump(WidgetTester tester, Size size, String name, {Future<void> Function()? before}) async {
  final key = GlobalKey();
  await tester.binding.setSurfaceSize(size);
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  await http.runWithClient(() async {
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => PermissionProvider()),
      ],
      child: RepaintBoundary(
        key: key,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: ThemeProvider().lightTheme,
          home: MediaQuery(data: MediaQueryData(size: size), child: const SettingsHubScreen()),
        ),
      ),
    ));
    for (var i = 0; i < 10; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
      await tester.pump(const Duration(milliseconds: 100));
    }
    if (before != null) {
      await before();
      for (var i = 0; i < 4; i++) {
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
  setUp(() {
    SharedPreferences.setMockInitialValues({
      'settings_hub_recent': ['28', '15', '0'],
    });
    SettingsHubScreen.debugPermittedItems = SettingsHubCatalog.allItems;
  });
  tearDown(() => SettingsHubScreen.debugPermittedItems = null);

  test('Danh mục: mã không trùng, đủ nhóm, đã bỏ Khách hàng POS / Thiết lập lương, tìm kiếm', () {
    final ids = SettingsHubCatalog.allItems.map((e) => e.index).toList();
    expect(ids.toSet().length, ids.length);
    expect(ids, isNot(contains(20)));
    expect(ids, isNot(contains(24)));
    for (final i in SettingsHubCatalog.allItems) {
      expect(SettingsHubCatalog.groups.map((g) => g.title), contains(i.groupTitle));
    }
    expect(SettingsHubCatalog.search(SettingsHubCatalog.allItems, 'bhxh').map((e) => e.label), ['Bảo hiểm']);
    expect(SettingsHubCatalog.search(SettingsHubCatalog.allItems, 'vat').map((e) => e.label), ['Thông tin cửa hàng']);
    expect(SettingsHubCatalog.search(SettingsHubCatalog.allItems, 'ca đêm').first.label, 'Ca làm việc');
    expect(SettingsHubCatalog.byIndex(28)!.moduleCode, 'BankAccount');
  });

  testWidgets('Thiết lập — máy tính', (t) async {
    await _pump(t, const Size(1440, 1500), 'settings_desktop');
    expect(find.text('Việc cần làm (3)'), findsOneWidget);
    expect(find.text('Chưa có tài khoản nhận tiền'), findsWidgets);
    expect(find.text('Mở gần đây'), findsOneWidget);
  });

  testWidgets('Thiết lập — điện thoại', (t) async {
    await _pump(t, const Size(390, 2400), 'settings_mobile');
  });

  testWidgets('Tìm kiếm', (t) async {
    await _pump(t, const Size(390, 900), 'settings_search', before: () async {
      await t.enterText(find.byType(TextField).first, 'máy in');
    });
    expect(find.text('Máy in'), findsWidgets);
    expect(find.text('Bảo hiểm'), findsNothing);
  });
}
