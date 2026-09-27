import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zkteco_flutter_client/providers/theme_provider.dart';
import 'package:zkteco_flutter_client/screens/design_system_showcase_screen.dart';

/// Dựng trang mẫu giao diện ở khổ máy tính và điện thoại — không lỗi, không tràn.
/// Đặt biến môi trường SBOX_SHOT_DIR để lưu ảnh chụp PNG (duyệt giao diện).
Future<void> _loadFonts() async {
  final fl = FontLoader('BeVietnamPro');
  for (final f in ['Regular', 'Medium', 'SemiBold', 'Bold', 'ExtraBold']) {
    final bytes = File('assets/fonts/BeVietnamPro-$f.ttf').readAsBytesSync();
    fl.addFont(Future.value(ByteData.view(bytes.buffer)));
  }
  await fl.load();
  final flutterRoot = Platform.environment['FLUTTER_ROOT'];
  if (flutterRoot != null) {
    final icons = File('$flutterRoot/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
    if (icons.existsSync()) {
      final il = FontLoader('MaterialIcons')..addFont(Future.value(ByteData.view(icons.readAsBytesSync().buffer)));
      await il.load();
    }
  }
}

Future<void> _shot(WidgetTester tester, GlobalKey key, String name) async {
  final dir = Platform.environment['SBOX_SHOT_DIR'];
  if (dir == null) return;
  await tester.runAsync(() async {
    final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final img = await boundary.toImage(pixelRatio: 1.5);
    final data = await img.toByteData(format: ui.ImageByteFormat.png);
    File('$dir/$name.png').writeAsBytesSync(data!.buffer.asUint8List());
  });
}

Future<void> _pumpShowcase(WidgetTester tester, Size size, String name) async {
  await tester.binding.setSurfaceSize(size);
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  final key = GlobalKey();
  await tester.pumpWidget(RepaintBoundary(
    key: key,
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeProvider().lightTheme,
      home: MediaQuery(
        data: MediaQueryData(size: size),
        child: const DesignSystemShowcaseScreen(),
      ),
    ),
  ));
  await tester.pump(const Duration(milliseconds: 500));
  expect(tester.takeException(), isNull);
  // Cuộn cả trang vào khung chụp: phóng to chiều cao tới hết nội dung.
  final scrollable = tester.state<ScrollableState>(find.byType(Scrollable).first);
  final full = scrollable.position.maxScrollExtent + size.height;
  final tall = Size(size.width, full);
  await tester.binding.setSurfaceSize(tall);
  tester.view.physicalSize = tall;
  await tester.pumpWidget(RepaintBoundary(
    key: key,
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeProvider().lightTheme,
      home: MediaQuery(data: MediaQueryData(size: tall), child: const DesignSystemShowcaseScreen()),
    ),
  ));
  await tester.pump(const Duration(milliseconds: 500));
  expect(tester.takeException(), isNull);
  await _shot(tester, key, name);
  tester.view.resetPhysicalSize();
  tester.view.resetDevicePixelRatio();
}

void main() {
  setUpAll(_loadFonts);
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('Trang mẫu giao diện — máy tính 1440', (tester) async {
    await _pumpShowcase(tester, const Size(1440, 900), 'sbox_design_desktop');
    expect(find.text('Đơn hàng'), findsWidgets);
    expect(find.text('1–20 / 57'), findsOneWidget);
  });

  testWidgets('Trang mẫu giao diện — điện thoại 390 (bảng chuyển dạng thẻ)', (tester) async {
    await _pumpShowcase(tester, const Size(390, 844), 'sbox_design_mobile');
    expect(find.text('Trang 1 / 3'), findsOneWidget);
  });
}
