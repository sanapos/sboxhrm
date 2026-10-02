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
import 'package:zkteco_flutter_client/models/customer_display_models.dart';
import 'package:zkteco_flutter_client/providers/theme_provider.dart';
import 'package:zkteco_flutter_client/screens/pos/pos_einvoice_settings_screen.dart';
import 'package:zkteco_flutter_client/screens/pos/pos_store_settings_hub_screen.dart';
import 'package:zkteco_flutter_client/utils/pos_sell_store_settings.dart';
import 'package:zkteco_flutter_client/widgets/settings/settings_page.dart';

/// Thiết lập B3: Thông tin cửa hàng, Hóa đơn điện tử. Đặt SBOX_SHOT_DIR để lưu ảnh duyệt.
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

final _extra = jsonEncode({
  'sellTax': {'mode': 'per_item', 'vatRate': 10},
  'receiptStore': {'name': 'SBOX Coffee Quận 1', 'address': '12 Nguyễn Huệ, Q.1', 'phone': '0909 123 456'},
});

http.Response _ok(Object? data) =>
    http.Response(jsonEncode({'isSuccess': true, 'data': data}), 200, headers: {'content-type': 'application/json; charset=utf-8'});

final _client = MockClient((req) async {
  final p = req.url.path;
  if (p.endsWith('/pos/sell-settings')) return _ok({'sellProfile': 'Retail', 'extraJson': _extra});
  if (p.endsWith('/pos/commercial-profile')) {
    return _ok({'companyName': 'Công ty TNHH SBOX', 'taxCode': '0312345678', 'legalRepresentative': 'Nguyễn Văn An', 'legalTitle': 'Giám đốc'});
  }
  if (p.endsWith('/pos/einvoice/settings')) {
    return _ok({'enabled': true, 'provider': 'Misa', 'apiBaseUrl': 'https://api.meinvoice.vn/api/integration', 'username': 'ketoan@sbox.vn', 'hasPassword': true, 'supplierTaxCode': '0312345678', 'invoiceSeries': '1C26MAA', 'signType': 5, 'askAtCheckout': true, 'taxMode': 'included', 'defaultTaxPercent': 8});
  }
  return http.Response(jsonEncode({'isSuccess': false}), 200, headers: {'content-type': 'application/json'});
});

Future<void> _pump(WidgetTester tester, Widget home, Size size, String name, {Future<void> Function()? before}) async {
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
        home: MediaQuery(data: MediaQueryData(size: size), child: Scaffold(body: home)),
      ),
    ));
    for (var i = 0; i < 12; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
      await tester.pump(const Duration(milliseconds: 100));
    }
    if (before != null) {
      await before();
      await tester.pumpAndSettle();
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
    SharedPreferences.setMockInitialValues({'pos_sell_default_vat_rate': 5.0, 'pos_sell_tax_mode': 'included'});
    PosSellStoreSettings.invalidateServerCache();
  });
  tearDown(() => SettingsLeaveGuard.set(null));

  test('Thuế cửa hàng lấy theo server, không theo bộ nhớ máy', () async {
    final s = await PosSellStoreSettings.load(extraJson: _extra);
    expect(s.taxMode, PosSellTaxMode.perItem);
    expect(s.defaultVatRate, 10);
  });

  test('Mã xem màn hình phụ ngẫu nhiên, 10 ký tự', () {
    final codes = {for (var i = 0; i < 50; i++) CustomerDisplayConfig.newViewerCode()};
    expect(codes.length, 50);
    expect(codes.every((c) => c.length == 10), isTrue);
  });

  testWidgets('Thông tin cửa hàng', (t) async {
    await _pump(t, const PosStoreSettingsHubScreen(canEditOverride: true), const Size(1200, 2600), 'b3_store', before: () async {
      await t.enterText(find.widgetWithText(TextField, 'SBOX Coffee Quận 1'), 'SBOX Coffee Q1');
    });
    expect(SettingsLeaveGuard.active, isTrue);
    expect(find.text('Thuế theo từng mặt hàng'), findsOneWidget);
  });

  testWidgets('Hóa đơn điện tử', (t) async {
    await _pump(t, const PosEInvoiceSettingsScreen(), const Size(1200, 2000), 'b3_einvoice');
    expect(find.text('Lấy theo cửa hàng'), findsOneWidget);
    expect(SettingsLeaveGuard.active, isFalse); // mới mở, chưa sửa gì
  });
}
