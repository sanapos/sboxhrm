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
import 'package:zkteco_flutter_client/screens/pos/pos_hkd_books_screen.dart';
import 'package:zkteco_flutter_client/widgets/pos/reports/hkd_tax_overview.dart';

/// «Thuế hộ kinh doanh»: tổng quan dễ hiểu (kết luận màu, thanh ngưỡng 1 tỷ / 3 tỷ, cột theo tháng, việc nên làm),
/// đổi «Tất cả đơn bán» ↔ «Hóa đơn VAT đã xuất» gửi basis lên máy chủ. Đặt SBOX_SHOT_DIR để lưu ảnh duyệt giao diện.
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

const _all = [62e6, 70e6, 85e6, 90e6, 96e6, 101e6, 110e6, 118e6, 125e6, 72e6, 0, 0];
const _inv = [20e6, 25e6, 31e6, 40e6, 44e6, 52e6, 60e6, 61e6, 70e6, 41e6, 0, 0];

Map<String, dynamic> _overview(String basis) {
  final m = basis == 'invoice' ? _inv : _all;
  final ytd = m.fold<double>(0, (a, b) => a + b);
  return {
    'year': 2026, 'basis': basis, 'isCurrentYear': true, 'daysElapsed': 290,
    'exemptBelow': 1e9, 'incomeMethodAbove': 3e9,
    'months': [for (var i = 0; i < 12; i++) {'month': i + 1, 'all': _all[i], 'invoiced': _inv[i]}],
    'ytd': ytd, 'ytdAll': 929e6, 'ytdInvoiced': 444e6, 'priorYear': 780e6,
    'projected': ytd * 365 / 290, 'annualEstimate': ytd * 365 / 290,
    'invoiceCoveragePct': 47.8, 'configuredGroup': 1, 'suggestedGroup': basis == 'invoice' ? 1 : 2,
    'vatPercent': 0, 'pitPercent': 0, 'hasTaxCode': false,
    'tax': {'vat': 0, 'pit': 0, 'total': 0},
    'quarter': {'number': 4, 'revenue': 72e6, 'vat': 0, 'pit': 0, 'total': 0},
    'verdict': basis == 'invoice' ? 'yellow' : 'red',
    'verdictText': basis == 'invoice' ? 'Hồ sơ thuế ổn, có việc cần chú ý' : 'Hồ sơ thuế đang khai thấp hơn doanh thu thật',
    'verdictDetail': 'Năm 2026: đã bán 929 triệu, dự kiến cả năm 1,17 tỷ, thuộc nhóm 2 (1–3 tỷ/năm). Thuế ước tính từ đầu năm: 0 đ.',
    'actions': [
      {'level': 'high', 'title': 'Doanh thu thật đã ở nhóm 2 (1–3 tỷ/năm), hồ sơ đang khai nhóm 1',
       'detail': 'Dự kiến cả năm 1,17 tỷ. Khai thấp hơn doanh thu thật có thể bị truy thu và phạt.',
       'howTo': 'Mở «Hồ sơ hộ kinh doanh» bên dưới, chọn nhóm 2, bấm «Lưu hồ sơ».'},
      {'level': 'high', 'title': 'Chưa nhập tỷ lệ % thuế — thuế ước tính đang là 0 đồng',
       'detail': 'Hộ doanh thu từ 1 tỷ phải nộp GTGT và TNCN theo tỷ lệ % của ngành nghề.',
       'howTo': 'Bấm ngành nghề phù hợp để điền tỷ lệ gợi ý, rồi «Lưu hồ sơ».'},
      {'level': 'medium', 'title': 'Còn 52,2% doanh thu chưa xuất hóa đơn điện tử',
       'detail': 'Đã xuất 444 triệu / tổng bán 929 triệu.', 'howTo': 'Bật «Hóa đơn điện tử» trong Thiết lập SBOX.'},
    ],
    'ratePresets': [
      {'industry': 'Phân phối, bán lẻ hàng hóa', 'vat': 1, 'pit': 0.5},
      {'industry': 'Ăn uống, sản xuất, vận tải, dịch vụ kèm hàng hóa', 'vat': 3, 'pit': 1.5},
    ],
  };
}

final _preview = {
  'book': 'S1a', 'title': 'SỔ DOANH THU BÁN HÀNG HÓA, DỊCH VỤ — Mẫu số S1a-HKD', 'periodLabel': '01/10/2026 - 17/10/2026 (UTC+7)',
  'taxGroup': 1, 'summary': [{'label': 'Tổng doanh thu', 'value': 72000000}, {'label': 'Số chứng từ', 'value': 2}],
  'columns': [{'key': 'stt', 'label': 'STT'}, {'key': 'date', 'label': 'Ngày tháng'}, {'key': 'description', 'label': 'Diễn giải'},
    {'key': 'amount', 'label': 'Số tiền', 'money': true}],
  'rows': [{'stt': 1, 'date': '01/10/2026', 'description': 'Bán hàng — Tiền mặt', 'amount': 128000}],
  'rowCount': 1, 'truncated': false,
};

final requests = <Uri>[];
final _client = MockClient((req) async {
  requests.add(req.url);
  final path = req.url.path;
  final data = path.endsWith('/hkd/settings')
      ? {'taxGroup': 1, 'taxCode': '', 'businessName': 'Quán Bún Chả Hà', 'industry': '', 'vatPercent': 0, 'pitPercent': 0,
         'recommendedBooks': ['S1a-HKD']}
      : path.endsWith('/hkd/overview')
          ? _overview(req.url.queryParameters['basis'] ?? 'all')
          : path.contains('/hkd/') ? _preview : <String, dynamic>{};
  return http.Response(jsonEncode({'isSuccess': true, 'data': data}), 200,
      headers: {'content-type': 'application/json; charset=utf-8'});
});

Future<void> _settle(WidgetTester t) async {
  for (var i = 0; i < 12; i++) {
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
    await t.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _pump(WidgetTester tester, Size size, String name, {Future<void> Function()? before}) async {
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
          home: MediaQuery(data: MediaQueryData(size: size), child: const PosHkdBooksScreen()),
        ),
      ),
    ));
    await _settle(tester);
    if (before != null) {
      await before();
      await _settle(tester);
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
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    requests.clear();
  });

  test('tiền dễ đọc', () {
    expect(hkdMoneyShort(1.5e9), '1,5 tỷ');
    expect(hkdMoneyShort(640e6), '640 triệu');
    expect(hkdMoneyShort(850000), '850.000đ');
  });

  for (final size in const [Size(390, 3600), Size(1100, 2900)]) {
    testWidgets('Thuế HKD tổng quan ${size.width.toInt()}', (t) async {
      await _pump(t, size, 'hkd_${size.width.toInt()}');
      expect(find.text('Hồ sơ thuế đang khai thấp hơn doanh thu thật'), findsOneWidget);
      expect(find.textContaining('trước đây 500 triệu'), findsWidgets);
      expect(find.text('Doanh thu năm 2026 so với ngưỡng thuế'), findsOneWidget);
      expect(find.text('Doanh thu theo tháng'), findsOneWidget);
      expect(find.text('Việc nên làm'), findsOneWidget);
      expect(find.text('Nhóm 2 · 1–3 tỷ'), findsOneWidget);
      expect(find.textContaining('Chưa nhập tỷ lệ % thuế'), findsOneWidget);
    });
  }

  testWidgets('Đổi sang «Hóa đơn VAT đã xuất» gửi basis=invoice cho tổng quan và sổ', (t) async {
    await _pump(t, const Size(1100, 2900), 'hkd_invoice_1100', before: () async {
      await t.tap(find.text('Hóa đơn VAT đã xuất'));
    });
    expect(requests.any((u) => u.path.endsWith('/hkd/overview') && u.queryParameters['basis'] == 'invoice'), isTrue);
    expect(requests.any((u) => u.path.contains('preview') && u.queryParameters['basis'] == 'invoice'), isTrue);
    expect(find.text('Hồ sơ thuế ổn, có việc cần chú ý'), findsOneWidget);
    expect(find.text('Chỉ tính đơn đã xuất hóa đơn điện tử, theo ngày lập hóa đơn.'), findsOneWidget);
  });
}
