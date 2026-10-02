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
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zkteco_flutter_client/providers/theme_provider.dart';
import 'package:zkteco_flutter_client/screens/payroll_pay/payroll_pay_page.dart';

/// Trả lương: tiền mặt / chuyển khoản / kết hợp, chuyển từng người. SBOX_SHOT_DIR để lưu ảnh.
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


Map<String, dynamic> _line(String id, String code, String name, double net, {double paid = 0, bool ready = true, String? bank = 'Vietcombank', String? acc = '0011002345678'}) => {
      'payslipId': id, 'employeeCode': code, 'employeeName': name, 'month': 9, 'year': 2026,
      'netSalary': net, 'paidAmount': paid, 'remaining': net - paid,
      'bankText': bank, 'bankRecognized': ready, 'bankBin': ready ? '970436' : null, 'bankShortName': ready ? bank : null,
      'accountNumber': acc, 'accountName': name.toUpperCase(), 'transferContent': 'LUONG T09 2026 $code', 'ready': ready,
    };

final _info = {
  'items': [
    _line('p1', 'NV001', 'Nguyễn Văn An', 12500000),
    _line('p2', 'NV002', 'Trần Thị Bình', 9800000, paid: 3000000),
    _line('p3', 'NV003', 'Lê Minh Châu', 7200000, ready: false, bank: 'Ngân hàng X', acc: null),
    _line('p4', 'NV004', 'Phạm Thu Dung', 15000000),
  ],
  'sourceAccounts': [
    {'id': 'b1', 'bankName': 'Techcombank', 'accountNumber': '19033456789', 'bin': '970407', 'appId': 'tcb', 'isDefault': true},
  ],
};

final List<Map<String, dynamic>> _paid = [];

http.Response _ok(Object data) =>
    http.Response(jsonEncode({'isSuccess': true, 'data': data}), 200, headers: {'content-type': 'application/json; charset=utf-8'});

final _client = MockClient((req) async {
  final p = req.url.path;
  if (p.endsWith('/payslips/payment-info')) return _ok(_info);
  if (p.endsWith('/payslips/pay')) {
    final b = jsonDecode(req.body) as Map;
    _paid.add(Map<String, dynamic>.from(b));
    return _ok({'paid': (b['items'] as List).length, 'errors': []});
  }
  if (p.contains('img.vietqr.io')) return http.Response('', 404);
  return http.Response(jsonEncode({'isSuccess': false, 'message': 'not mocked $p'}), 200);
});

Future<void> _pump(WidgetTester tester, Widget home, Size size, String name, {bool tall = true}) async {
  final key = GlobalKey();
  Widget app(Size s) => RepaintBoundary(
        key: key,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: ThemeProvider().lightTheme,
                    home: MediaQuery(data: MediaQueryData(size: s), child: home),
        ),
      );
  Future<void> setSize(Size s) async {
    await tester.binding.setSurfaceSize(s);
    tester.view.physicalSize = s;
    tester.view.devicePixelRatio = 1;
  }

  await http.runWithClient(() async {
    await setSize(size);
    await tester.pumpWidget(app(size));
    for (var i = 0; i < 10; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(tester.takeException(), isNull);
    if (tall) {
      var extent = 0.0;
      for (final e in find.byType(Scrollable).evaluate()) {
        final st = (e as StatefulElement).state as ScrollableState;
        if (st.position.axis == Axis.vertical && st.position.maxScrollExtent > extent) extent = st.position.maxScrollExtent;
      }
      if (extent > 0) {
        final t = Size(size.width, size.height + extent);
        await setSize(t);
        await tester.pumpWidget(app(t));
        for (var i = 0; i < 4; i++) {
          await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
          await tester.pump(const Duration(milliseconds: 100));
        }
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
  setUpAll(() async {
    await _loadFonts();
    await initializeDateFormatting('vi_VN');
  });
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    _paid.clear();
  });

  testWidgets('Trả lương — máy tính, chuyển khoản', (t) async {
    await _pump(t, const PayrollPayPage(payslipIds: ['p1', 'p2', 'p3', 'p4']), const Size(1280, 900), 'pay_desktop');
    expect(find.text('Chuyển từng người'), findsOneWidget);
    expect(find.text('Xuất file ngân hàng'), findsOneWidget);
    expect(find.textContaining('thiếu số tài khoản'), findsOneWidget);
    expect(find.textContaining('đã trả 3.000.000đ'), findsOneWidget);
  });

  testWidgets('Trả lương — điện thoại, kết hợp', (t) async {
    await _pump(t, const PayrollPayPage(payslipIds: ['p1', 'p2']), const Size(390, 844), 'pay_mobile_mixed', tall: false);
    await http.runWithClient(() async {
      await t.tap(find.descendant(of: find.byType(SegmentedButton<PayMethod>), matching: find.text('Kết hợp')));
      await t.pump();
    }, () => _client);
    expect(find.text('Tiền mặt'), findsWidgets);
    final dir = Platform.environment['SBOX_SHOT_DIR'];
    if (dir != null) {
      await _pump(t, const PayrollPayPage(payslipIds: ['p1', 'p2']), const Size(390, 844), 'pay_mobile', tall: false);
    }
  });

  testWidgets('Tiền mặt: xác nhận gửi đúng số', (t) async {
    await _pump(t, const PayrollPayPage(payslipIds: ['p1', 'p2', 'p3', 'p4']), const Size(1280, 1100), 'pay_cash', tall: false);
    await http.runWithClient(() async {
      await t.tap(find.descendant(of: find.byType(SegmentedButton<PayMethod>), matching: find.text('Tiền mặt')));
      await t.pump();
      await t.tap(find.textContaining('Xác nhận đã trả tiền mặt'));
      await t.pump();
      await t.tap(find.text('Ghi nhận đã trả'));
      for (var i = 0; i < 5; i++) {
        await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
        await t.pump(const Duration(milliseconds: 50));
      }
    }, () => _client);
    expect(_paid, hasLength(1));
    final items = (_paid.single['items'] as List).cast<Map>();
    expect(items, hasLength(4)); // tiền mặt: người thiếu STK vẫn trả được
    expect(items.firstWhere((i) => i['payslipId'] == 'p2')['cashAmount'], 6800000);
    expect(items.every((i) => i['bankAmount'] == 0), isTrue);
    expect(_paid.single.containsKey('bankAccountId'), isFalse);
  });

  testWidgets('Chuyển từng người — điện thoại', (t) async {
    final l = PayLine.fromJson(_line('p1', 'NV001', 'Nguyễn Văn An', 12500000))..cash = 2500000;
    final src = PaySource.fromJson((_info['sourceAccounts'] as List).first as Map<String, dynamic>);
    await _pump(t, PayrollTransferStepper(lines: [l], method: PayMethod.mixed, source: src, onPaid: (_) async => true),
        const Size(390, 844), 'pay_transfer_mobile');
    expect(find.text('10.000.000đ'), findsOneWidget); // phần chuyển khoản
    expect(find.textContaining('Trả tiền mặt: 2.500.000đ'), findsOneWidget);
    expect(find.text('LUONG T09 2026 NV001'), findsOneWidget);
    expect(find.text('Đã chuyển xong'), findsOneWidget);
  });
}
