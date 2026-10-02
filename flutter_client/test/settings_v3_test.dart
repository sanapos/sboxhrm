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
import 'package:zkteco_flutter_client/l10n/app_localizations.dart';
import 'package:zkteco_flutter_client/screens/pos/pos_printers_tabs_screen.dart';
import 'package:zkteco_flutter_client/screens/settings_screen.dart';
import 'package:zkteco_flutter_client/utils/settings_hub_catalog.dart';

/// Làm lại Cài đặt / Thiết lập SBOX: máy in 2 tab, mở mục theo mã, trang Cài đặt cá nhân. Đặt SBOX_SHOT_DIR để lưu ảnh duyệt giao diện.
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

final _client = MockClient((req) async =>
    http.Response(jsonEncode({'isSuccess': true, 'data': []}), 200, headers: {'content-type': 'application/json; charset=utf-8'}));

Future<void> _pump(WidgetTester tester, Widget home, Size size, String name, {Future<void> Function()? before}) async {
  final key = GlobalKey();
  await tester.binding.setSurfaceSize(size);
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  await http.runWithClient(() async {
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => PermissionProvider()),
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
      ],
      child: RepaintBoundary(
        key: key,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: ThemeProvider().lightTheme,
          localizationsDelegates: const [AppLocalizations.delegate, DefaultMaterialLocalizations.delegate, DefaultWidgetsLocalizations.delegate],
          home: MediaQuery(data: MediaQueryData(size: size), child: home),
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
    SharedPreferences.setMockInitialValues({});
    SettingsHubScreen.debugPermittedItems = SettingsHubCatalog.allItems;
  });
  tearDown(() => SettingsHubScreen.debugPermittedItems = null);

  testWidgets('Máy in: một mục, hai tab (trên máy này / cloud)', (t) async {
    await _pump(t, const Scaffold(body: PosPrintersTabsScreen(debugTabs: (device: true, cloud: true))), const Size(900, 700), 'v3_printers_tabs');
    expect(find.text('Trên máy này'), findsOneWidget);
    expect(find.text('Máy in cloud'), findsOneWidget);
  });

  testWidgets('Máy in: chỉ có quyền cloud thì không hiện tab', (t) async {
    await _pump(t, const Scaffold(body: PosPrintersTabsScreen(debugTabs: (device: false, cloud: true))), const Size(900, 700), 'v3_printers_cloud_only');
    expect(find.byType(TabBar), findsNothing);
  });

  testWidgets('Mở thẳng mục theo mã; lối tắt cũ «Máy in cloud» mở mục Máy in', (t) async {
    expect(SettingsHubScreen.openCode('khong-co'), isFalse);
    SettingsHubScreen.pendingSubIndex.value = 29;
    await _pump(t, const SettingsHubScreen(), const Size(1280, 800), 'v3_hub_printers');
    expect(find.text('Máy in'), findsWidgets); // tiêu đề trang con + menu trái
    expect(find.byWidgetPredicate((w) => w is PosPrintersTabsScreen && w.cloudFirst), findsOneWidget);
  });

  testWidgets('Cài đặt (cá nhân) — không còn dữ liệu mẫu / đồng bộ', (t) async {
    await _pump(t, const SettingsScreen(showAppBar: true), const Size(390, 1500), 'v3_personal_settings');
    expect(find.text('Cài đặt'), findsOneWidget);
    expect(find.text('Đổi mật khẩu'), findsWidgets);
    expect(find.text('Cài dữ liệu mẫu'), findsNothing);
    expect(find.textContaining('5 phút'), findsNothing);
    expect(find.text('Xóa tài khoản'), findsOneWidget);
  });
}
