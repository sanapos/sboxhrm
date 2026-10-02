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
import 'package:zkteco_flutter_client/screens/annual_leave/al_policy.dart';
import 'package:zkteco_flutter_client/screens/annual_leave/al_screen.dart';
import 'package:zkteco_flutter_client/services/api_service.dart';

/// Phép năm. Đặt SBOX_SHOT_DIR để lưu ảnh duyệt.
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

Map<String, dynamic> _row(String id, String code, String name, Map<String, dynamic> extra) => {
      'employeeId': id,
      'code': code,
      'name': name,
      'department': 'Kinh doanh',
      'hasSalaryProfile': true,
      'eligible': true,
      'baseDays': 12,
      'seniorityDays': 0,
      'months': 12,
      'entitled': 12,
      'carry': 0,
      'carryExpired': 0,
      'adjust': 0,
      'used': 0,
      'pending': 0,
      'paidOutDays': 0,
      'paidOutAmount': 0,
      'remaining': 12,
      'available': 12,
      'dailyRate': 500000,
      ...extra,
    };

final _summary = [
  _row('e1', 'NV001', 'Nguyễn Văn An', {'seniorityDays': 1, 'entitled': 13, 'used': 5, 'remaining': 8, 'available': 6, 'pending': 2, 'joinDate': '2019-03-01T00:00:00'}),
  _row('e2', 'NV002', 'Trần Thị Bình', {'carry': 3, 'carryExpiresOn': '2026-03-31T00:00:00', 'used': 3, 'remaining': 12, 'available': 12}),
  _row('e3', 'NV003', 'Lê Minh Châu', {'months': 6, 'entitled': 6, 'used': 1, 'remaining': 5, 'available': 5, 'joinDate': '2026-07-01T00:00:00'}),
  _row('e4', 'NV004', 'Phạm Thu Dung', {'months': 8, 'entitled': 8, 'used': 2, 'remaining': 6, 'available': 6, 'resignationDate': '2026-08-31T00:00:00'}),
  _row('e5', 'NV005', 'Hoàng Văn Em', {'eligible': false, 'baseDays': 0, 'entitled': 0, 'remaining': 0, 'available': 0}),
];

http.Response _ok(Object? data) =>
    http.Response(jsonEncode({'isSuccess': true, 'data': data}), 200, headers: {'content-type': 'application/json; charset=utf-8'});

final _client = MockClient((req) async {
  final p = req.url.path;
  if (p.endsWith('/api/annual-leave/summary')) return _ok(_summary);
  if (p.endsWith('/api/annual-leave/policy')) return _ok({'defaultDays': 12, 'yearEndMode': 'carry_payout', 'carryMaxDays': 5, 'carryExpireMonth': 3});
  if (p.contains('/api/annual-leave/employees/')) {
    return _ok({
      'summary': _summary.first,
      'leaves': [
        {'id': 'l1', 'startDate': '2026-04-29T00:00:00', 'endDate': '2026-05-04T00:00:00', 'halfShift': false, 'days': 3, 'status': 'Approved', 'type': 'AnnualLeave', 'reason': 'Về quê'},
        {'id': 'l2', 'startDate': '2026-08-10T00:00:00', 'endDate': '2026-08-11T00:00:00', 'halfShift': false, 'days': 2, 'status': 'Approved', 'type': 'AnnualLeave'},
        {'id': 'l3', 'startDate': '2026-12-24T00:00:00', 'endDate': '2026-12-25T00:00:00', 'halfShift': false, 'days': 2, 'status': 'Pending', 'type': 'AnnualLeave'},
      ],
      'entries': [],
      'policy': {},
    });
  }
  return _ok([]);
});

Future<void> _pump(WidgetTester tester, Size size, String name, {Future<void> Function()? before, Widget? home}) async {
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
          child: home!,
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

  testWidgets('Phép năm — máy tính', (t) async {
    await _pump(t, const Size(1280, 900), 'al_summary', home: const AnnualLeaveScreen(managerOverride: true, initialYear: 2026));
    expect(find.text('Nghỉ việc chưa trả tiền phép'), findsOneWidget);
    expect(find.text('+1 thâm niên'), findsOneWidget);
    expect(find.textContaining('Trả tiền phép nghỉ việc (1)'), findsOneWidget);
  });

  testWidgets('Chi tiết một nhân viên', (t) async {
    await _pump(t, const Size(430, 1100), 'al_detail',
        home: Scaffold(body: AnnualLeaveDetail(employeeId: 'e1', year: 2026, api: ApiService())));
    expect(find.text('Còn lại'), findsOneWidget);
    expect(find.text('Thâm niên'), findsOneWidget);
  });

  testWidgets('Phép năm — điện thoại', (t) async {
    await _pump(t, const Size(390, 1400), 'al_summary_mobile', home: const AnnualLeaveScreen(managerOverride: true, initialYear: 2026));
    expect(find.text('Chốt phép năm 2026'), findsOneWidget);
  });

  testWidgets('Chính sách phép năm', (t) async {
    await _pump(t, const Size(1100, 1500), 'al_policy', home: const Scaffold(body: AnnualLeavePolicyScreen(canEditOverride: true)));
    expect(find.text('Chuyển tối đa, trả tiền phần dư'), findsOneWidget);
    expect(find.text('Hết tháng 3'), findsOneWidget);
  });
}
