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
import 'package:zkteco_flutter_client/screens/allowance_settings_screen.dart';
import 'package:zkteco_flutter_client/screens/holiday_settings_screen.dart';
import 'package:zkteco_flutter_client/screens/insurance_settings_screen.dart';
import 'package:zkteco_flutter_client/screens/penalty_settings_screen.dart';
import 'package:zkteco_flutter_client/screens/tax_settings_screen.dart';
import 'package:zkteco_flutter_client/widgets/settings/settings_page.dart';

/// Thiết lập B2: Ngày lễ, Phụ cấp, Mức phạt, Bảo hiểm, Thuế. Đặt SBOX_SHOT_DIR để lưu ảnh duyệt.
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

final _holidays = [
  {'id': 'h1', 'name': 'Tết Dương lịch', 'date': '2026-01-01T00:00:00', 'isRecurring': true, 'isProjected': true, 'originYear': 2025, 'salaryRate': 3, 'category': 'Ngày nghỉ chính thức'},
  {'id': 'h2', 'name': 'Tết Nguyên Đán (Mùng 1)', 'date': '2026-02-17T00:00:00', 'isRecurring': false, 'salaryRate': 3, 'category': 'Ngày nghỉ chính thức'},
  {'id': 'h3', 'name': 'Ngày Quốc tế Lao động', 'date': '2026-05-01T00:00:00', 'isRecurring': true, 'salaryRate': 3, 'category': 'Ngày nghỉ chính thức'},
  {'id': 'h4', 'name': 'Ngày thành lập công ty', 'date': '2026-08-15T00:00:00', 'isRecurring': true, 'salaryRate': 2, 'category': 'Ngày đặc biệt công ty', 'employeeIds': ['e1', 'e2']},
];

final _allowances = [
  {'id': 'a1', 'name': 'Phụ cấp ăn trưa', 'type': 'Daily', 'amount': 30000, 'isTaxable': false, 'isActive': true, 'minWorkHours': 4.5},
  {'id': 'a2', 'name': 'Phụ cấp xăng xe', 'code': 'XX', 'type': 'Fixed', 'amount': 500000, 'isTaxable': true, 'isActive': true},
  {'id': 'a3', 'name': 'Phụ cấp ca đêm', 'type': 4, 'amount': 50000, 'isTaxable': true, 'isActive': true, 'shiftIds': ['s3'], 'employeeIds': ['e1', 'e2', 'e3'], 'minWorkPercent': 90},
  {'id': 'a4', 'name': 'Phụ cấp chuyên cần', 'type': 0, 'amount': 300000, 'isTaxable': true, 'isInsuranceApplicable': true, 'isActive': false},
];

http.Response _ok(Object? data) =>
    http.Response(jsonEncode({'isSuccess': true, 'data': data}), 200, headers: {'content-type': 'application/json; charset=utf-8'});

final _client = MockClient((req) async {
  final p = req.url.path;
  if (p.endsWith('/settings/insurance')) return _ok({'baseSalary': 2340000, 'minSalaryRegion1': 4960000, 'minSalaryRegion2': 4410000, 'minSalaryRegion3': 3860000, 'minSalaryRegion4': 3450000, 'maxInsuranceSalary': 46800000, 'defaultRegion': 1});
  if (p.endsWith('/settings/tax')) return _ok({});
  if (p.endsWith('/tax/employee-deductions')) {
    return _ok([
      {'employeeId': 'e1', 'employeeName': 'Nguyễn Văn An', 'employeeCode': 'NV001', 'numberOfDependents': 2, 'dependentRegistrationFormUrl': '/uploads/a.pdf'},
      {'employeeId': 'e2', 'employeeName': 'Trần Thị Bình', 'employeeCode': 'NV002', 'numberOfDependents': 0},
    ]);
  }
  if (p.endsWith('/settings/holidays')) return _ok(_holidays);
  if (p.endsWith('/allowances')) return _ok({'items': _allowances});
  if (p.endsWith('/shifts/templates')) return _ok([{'id': 's3', 'name': 'Ca đêm'}]);
  if (p.endsWith('/settings/penalty')) return _ok({'collectionMethod': 'Salary'});
  if (p.endsWith('/employees')) return _ok({'items': []});
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
    for (var i = 0; i < 10; i++) {
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
  setUp(() => SharedPreferences.setMockInitialValues({}));
  tearDown(() => SettingsLeaveGuard.set(null));

  test('Thuế: tính lũy tiến 5 bậc', () {
    final t = TaxParams();
    final ins = InsParams();
    // 30tr, đóng BH trên 10tr (10,5% = 1.050.000), 1 người phụ thuộc
    final r = t.compute(gross: 30000000, insuranceSalary: 10000000, dependents: 1, ins: ins);
    expect(r.insurance, 1050000);
    expect(r.taxable, 30000000 - 1050000 - 15500000 - 6200000);
    // 7.250.000 trong bậc 1 (5%)
    expect(r.tax, closeTo(362500, 0.01));
    expect(t.copy().toJson()['taxRate7'], t.rates[4]);
    expect((t.copy()..caps[2] = 1000).validate(), isNotNull);
  });

  test('Bảo hiểm: chặn trần', () {
    final r = InsParams().compute(60000000);
    expect(r.capped, 46800000);
    expect(r.employee, closeTo(46800000 * 0.105, 0.01));
  });

  test('Phạt: bậc theo phút và tái phạm', () {
    final p = PenaltyParams();
    expect(p.lateTicket(10, 1).tier, 0);
    final t = p.lateTicket(35, 4); // bậc 2 + tái phạm từ lần 3
    expect(t.tier, 2);
    expect(t.base, 100000);
    expect(t.surcharge, 100000);
    expect(p.lateTicket(90, 12).surcharge, 500000);
    final back = PenaltyParams.fromJson(p.toJson()..['violationPenalty'] = 123);
    expect(back.violation, 123); // giữ nguyên khoản không dùng
  });

  test('Ngày lễ âm lịch quy đổi đúng năm', () {
    final tet = HolidayPreset.all.firstWhere((p) => p.name.contains('Mùng 1'));
    expect(tet.dateIn(2026), DateTime(2026, 2, 17));
    expect(tet.dateIn(2025), DateTime(2025, 1, 29));
    final gioTo = HolidayPreset.all.firstWhere((p) => p.name.contains('Giỗ Tổ'));
    expect(gioTo.dateIn(2026), DateTime(2026, 4, 26));
  });

  testWidgets('Ngày lễ', (t) async {
    await _pump(t, const HolidaySettingsScreen(canEditOverride: true, initialYear: 2026), const Size(1200, 1500), 'b2_holidays');
    expect(find.textContaining('Hằng năm (từ 2025)'), findsOneWidget);
    expect(find.textContaining('còn thiếu'), findsOneWidget);
  });

  testWidgets('Phụ cấp', (t) async {
    await _pump(t, const AllowanceSettingsScreen(canEditOverride: true), const Size(1200, 1100), 'b2_allowances');
    expect(find.textContaining('Ca: Ca đêm'), findsOneWidget);
    expect(find.text('Làm từ 90% ca'), findsOneWidget);
    expect(find.text('Làm từ 4 giờ 30 phút'), findsOneWidget);
  });

  testWidgets('Phụ cấp — điều kiện nhận', (t) async {
    await _pump(t, const AllowanceSettingsScreen(canEditOverride: true), const Size(1200, 1300), 'b2_allowance_rule',
        before: () => t.tap(find.text('Phụ cấp ca đêm')));
    expect(find.text('Điều kiện nhận'), findsOneWidget);
    expect(find.textContaining('ca 5 tiếng cần từ 4 giờ 30 phút'), findsOneWidget);
  });

  testWidgets('Mức phạt', (t) async {
    await _pump(t, const PenaltySettingsScreen(canEditOverride: true), const Size(1200, 2100), 'b2_penalty');
    expect(find.textContaining('Phiếu phạt bậc 1'), findsOneWidget);
  });

  testWidgets('Bảo hiểm', (t) async {
    await _pump(t, const InsuranceSettingsScreen(canEditOverride: true), const Size(1200, 2000), 'b2_insurance');
    expect(find.text('Dùng mức 2026'), findsOneWidget);
  });

  testWidgets('Thuế TNCN — điện thoại', (t) async {
    await _pump(t, const TaxSettingsScreen(canEditOverride: true), const Size(390, 3000), 'b2_tax_mobile');
    expect(find.textContaining('1/2 nhân viên'), findsOneWidget);
  });
}
