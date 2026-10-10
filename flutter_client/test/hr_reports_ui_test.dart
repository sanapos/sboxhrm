import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zkteco_flutter_client/l10n/app_localizations.dart';
import 'package:zkteco_flutter_client/models/user.dart';
import 'package:zkteco_flutter_client/providers/auth_provider.dart';
import 'package:zkteco_flutter_client/providers/permission_provider.dart';
import 'package:zkteco_flutter_client/providers/theme_provider.dart';
import 'package:zkteco_flutter_client/screens/advance_report_screen.dart';
import 'package:zkteco_flutter_client/screens/analytics_reports_screen.dart';
import 'package:zkteco_flutter_client/screens/business_trip_report_screen.dart';
import 'package:zkteco_flutter_client/screens/late_early_report_screen.dart';
import 'package:zkteco_flutter_client/screens/leave_report_screen.dart';
import 'package:zkteco_flutter_client/screens/penalty_report_screen.dart';
import 'package:zkteco_flutter_client/screens/travel_hours_report_screen.dart';

import 'fixtures/hr_reports_fixture.dart';

/// Báo cáo nhân sự trên điện thoại / máy tính với dữ liệu mẫu: không lỗi vẽ (tràn chữ, ngoại lệ),
/// số tổng khớp dữ liệu. SBOX_SHOT_DIR = lưu ảnh để duyệt giao diện. HR_REPORT_LOG_PATHS=1 in API gọi.
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

final _seen = <String>{};

MockClient _client() => MockClient((req) async {
      final p = req.url.path;
      _seen.add('${req.method} $p${req.url.query.isEmpty ? '' : '?${req.url.query}'}');
      final body = hrReportsResponse(req.method, p, req.url.queryParameters);
      if (body == null) {
        return http.Response(jsonEncode({'isSuccess': true, 'data': []}), 200, headers: {'content-type': 'application/json; charset=utf-8'});
      }
      return http.Response(jsonEncode(body), 200, headers: {'content-type': 'application/json; charset=utf-8'});
    });

Future<void> _pump(WidgetTester t, Widget screen, Size size, String shot,
    {String role = 'Manager', List<String> expectTexts = const []}) async {
  SharedPreferences.setMockInitialValues({});
  _seen.clear();
  await t.binding.setSurfaceSize(size);
  t.view.physicalSize = size;
  t.view.devicePixelRatio = 1;
  final auth = AuthProvider()
    ..debugSetUser(User(id: 'u1', employeeId: 'e1', email: 'ql@shop.vn', fullName: 'Quản Lý', role: role, storeId: 's1'));
  final key = GlobalKey();
  await http.runWithClient(() async {
    await t.pumpWidget(RepaintBoundary(
      key: key,
      child: MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthProvider>.value(value: auth),
          ChangeNotifierProvider(create: (_) => PermissionProvider()..loadPermissions(role: 'Admin')),
        ],
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: ThemeProvider().lightTheme,
          localizationsDelegates: const [AppLocalizations.delegate, GlobalMaterialLocalizations.delegate, GlobalWidgetsLocalizations.delegate, GlobalCupertinoLocalizations.delegate],
          supportedLocales: const [Locale('vi')],
          locale: const Locale('vi'),
          home: MediaQuery(data: MediaQueryData(size: size), child: Scaffold(body: screen)),
        ),
      ),
    ));
    for (var i = 0; i < 12; i++) {
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 40)));
      await t.pump(const Duration(milliseconds: 100));
    }
  }, _client);
  final errors = <Object>[];
  Object? e;
  while ((e = t.takeException()) != null) {
    errors.add(e!);
  }
  final missing = [
    for (final s in expectTexts)
      if (find.textContaining(s, findRichText: true).evaluate().isEmpty) s,
  ];
  if (Platform.environment['HR_REPORT_LOG_PATHS'] == '1') {
    // ignore: avoid_print
    print('[$shot] ${(_seen.toList()..sort()).join('\n  ')}');
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
  // Hẹn giờ nền của AuthProvider (kiểm tra vị trí, thử lại 2 giây) — chạy hết trước khi gỡ cây.
  await http.runWithClient(() async {
    await t.pumpWidget(const SizedBox());
    for (var i = 0; i < 4; i++) {
      await t.pump(const Duration(seconds: 3));
    }
  }, _client);
  t.view.resetPhysicalSize();
  expect(errors, isEmpty, reason: '$shot: ${errors.join('\n')}');
  expect(missing, isEmpty, reason: '$shot: thiếu chữ trên màn');
}

const _phone = Size(390, 1600);
const _desk = Size(1440, 1100);

void main() {
  setUpAll(_fonts);

  // Số mong đợi theo test/fixtures/hr_reports_fixture.dart (khớp cách bảng lương trừ / tính).
  const expects = <String, List<String>>{
    'penalty': ['Trừ lương 50.000đ · Thu tiền mặt 100.000đ'],
    'advance': ['Đã chi 1.000.000đ · Chờ chi 1.500.000đ'],
    'business_trip': ['Đã chi 3.000.000đ · Chờ chi 2.000.000đ'],
    'leave': ['2,5 ngày'],
    'travel': ['2h30p', 'Tính lương 1h30p (đã duyệt)'],
  };
  final screens = <String, Widget Function()>{
    'late_early': () => const LateEarlyReportScreen(),
    'penalty': () => const PenaltyReportScreen(),
    'advance': () => const AdvanceReportScreen(),
    'business_trip': () => const BusinessTripReportScreen(),
    'leave': () => const LeaveReportScreen(),
    'travel': () => const TravelHoursReportScreen(),
    'analytics': () => const AnalyticsReportsScreen(),
  };
  for (final e in screens.entries) {
    final ex = expects[e.key] ?? const <String>[];
    testWidgets('${e.key} — điện thoại (quản lý)', (t) async => _pump(t, e.value(), _phone, 'hr_${e.key}_phone', expectTexts: ex));
    testWidgets('${e.key} — máy tính (quản lý)', (t) async => _pump(t, e.value(), _desk, 'hr_${e.key}_desk', expectTexts: ex));
    testWidgets('${e.key} — điện thoại (nhân viên)', (t) async =>
        _pump(t, e.value(), _phone, 'hr_${e.key}_phone_emp', role: 'Employee'));
  }
}
