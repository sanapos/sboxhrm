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
import 'package:zkteco_flutter_client/screens/salary_v2/sl_common.dart';
import 'package:zkteco_flutter_client/screens/salary_v2/sl_editor.dart';
import 'package:zkteco_flutter_client/screens/salary_v2/sl_model.dart';
import 'package:zkteco_flutter_client/screens/salary_v2/sl_screen.dart';
import 'package:zkteco_flutter_client/services/api_service.dart';

/// Thiết lập lương. Đặt SBOX_SHOT_DIR để lưu ảnh duyệt.
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

final _benefitMonthly = {
  'id': 'b1', 'name': 'Lương Nguyễn Văn An (NV001)', 'rateType': 'Monthly', 'rate': 12000000, 'completionSalary': 3000000,
  'socialInsuranceType': 1, 'insuranceSalary': 12000000, 'attendanceMode': 'both', 'paidLeaveType': 'sunday',
  'description': 'attendanceType:both|shifts:Ca sáng, Ca chiều|shiftsPerDay:1|hoursPerWorkDay:8',
  'hourlyOvertimeType': 1, 'holidayOvertimeType': 1, 'paidLeaveDays': 12, 'overtimeMultiplier': 1.8, 'transportAllowance': 300000,
};
final _benefitDaily = {
  'id': 'b2', 'rateType': 'Daily', 'rate': 350000, 'dailyFixedRate': 350000, 'socialInsuranceType': 0,
  'attendanceMode': 'any', 'paidLeaveType': 'off-4', 'description': 'attendanceType:any|shiftsPerDay:1|hoursPerWorkDay:8',
};
final _benefitShift = {
  'id': 'b3', 'rateType': 'Shift', 'rate': 1, 'shiftSalaryType': 1, 'socialInsuranceType': 3,
  'attendanceMode': 'checkin', 'description': 'attendanceType:checkin|shifts:Ca tối|shiftsPerDay:1|hoursPerWorkDay:6',
};

http.Response _ok(Object? data) =>
    http.Response(jsonEncode({'isSuccess': true, 'data': data}), 200, headers: {'content-type': 'application/json; charset=utf-8'});

final _client = MockClient((req) async {
  final p = req.url.path;
  if (p.endsWith('/api/employees')) {
    return _ok({
      'items': [
        {'id': 'e1', 'employeeCode': 'NV001', 'lastName': 'Nguyễn Văn', 'firstName': 'An', 'department': 'Kinh doanh', 'position': 'Trưởng nhóm'},
        {'id': 'e2', 'employeeCode': 'NV002', 'lastName': 'Trần Thị', 'firstName': 'Bình', 'department': 'Bếp'},
        {'id': 'e3', 'employeeCode': 'NV003', 'lastName': 'Lê Minh', 'firstName': 'Châu', 'department': 'Phục vụ'},
        {'id': 'e4', 'employeeCode': 'NV004', 'lastName': 'Phạm Thu', 'firstName': 'Dung', 'department': 'Thu ngân'},
      ],
    });
  }
  if (p.endsWith('/api/benefits/employees')) {
    return _ok([
      {'employeeId': 'e1', 'benefitId': 'b1', 'benefit': _benefitMonthly, 'upcoming': {'id': 'v9', 'effectiveDate': '2026-11-01T00:00:00'}},
      {'employeeId': 'e2', 'benefitId': 'b2', 'benefit': _benefitDaily},
      {'employeeId': 'e3', 'benefitId': 'b3', 'benefit': _benefitShift},
    ]);
  }
  if (p.endsWith('/api/shifts/templates')) {
    return _ok([
      {'id': 's1', 'name': 'Ca sáng'},
      {'id': 's2', 'name': 'Ca chiều'},
      {'id': 's3', 'name': 'Ca tối'},
    ]);
  }
  if (p.endsWith('/api/allowances')) {
    return _ok({
      'items': [
        {'id': 'a1', 'name': 'Phụ cấp ăn trưa', 'type': 'Daily', 'amount': 30000, 'isActive': true, 'employeeIds': ['e1', 'e2']},
        {'id': 'a2', 'name': 'Phụ cấp xăng xe', 'type': 'Fixed', 'amount': 500000, 'isActive': true, 'employeeIds': ['e1']},
      ],
    });
  }
  if (p.endsWith('/api/settings/insurance')) return _ok({'maxInsuranceSalary': 46800000, 'defaultRegion': 1, 'minSalaryRegion1': 4960000});
  if (p.endsWith('/api/settings/salary')) return _ok({'standardWorkDays': 26, 'overtimeRate': 1.5, 'weekendRate': 2, 'holidayRate': 3});
  return http.Response(jsonEncode({'isSuccess': false}), 200, headers: {'content-type': 'application/json'});
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
          child: home ?? const SalaryV2Screen(canEditOverride: true),
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

  test('Lưu giữ nguyên trường không có trên form; phép năm lưu cho lương tháng', () {
    final d = SalaryDraft.fromBenefit(_benefitMonthly);
    expect(d.kind, SalaryKind.monthly);
    expect(d.shifts, ['Ca sáng', 'Ca chiều']);
    d.paidLeaveDays = 14;
    final out = d.toBenefit(name: 'X', fixedAllowanceTotal: 500000, dailyAllowanceTotal: 30000, insuranceSettings: const {}, storeWeekendRate: 2);
    expect(out['overtimeMultiplier'], 1.8);
    expect(out['transportAllowance'], 300000);
    expect(out['paidLeaveDays'], 14);
    expect(out.containsKey('id'), isFalse);
    expect(out['description'], contains('shifts:Ca sáng, Ca chiều'));
  });

  test('BHXH áp trần; lương ngày không có «theo lương cơ bản»', () {
    final d = SalaryDraft.fromBenefit({..._benefitMonthly, 'rate': 60000000});
    expect(d.insuranceSalary({'maxInsuranceSalary': 46800000}), 46800000);
    final daily = SalaryDraft.fromBenefit({..._benefitDaily, 'socialInsuranceType': 1});
    expect(daily.insurance, InsuranceKind.none);
    expect(daily.insuranceChoices.contains(InsuranceKind.base), isFalse);
  });

  test('Tên hồ sơ có mã nhân viên', () {
    expect(salaryProfileName('Nguyễn Văn An', 'NV001'), isNot(salaryProfileName('Nguyễn Văn An', 'NV009')));
  });

  test('Kiểm tra thiếu mức lương', () {
    final d = SalaryDraft()..kind = SalaryKind.daily;
    expect(d.validate(), isNotNull);
    d.daily = 300000;
    expect(d.validate(), isNull);
  });

  testWidgets('Danh sách — máy tính', (t) async {
    await _pump(t, const Size(1200, 900), 'sl_list');
    expect(find.text('Chưa thiết lập'), findsWidgets);
    expect(find.text('12.000.000đ/tháng'), findsOneWidget);
    expect(find.text('Lương ca theo bậc'), findsOneWidget);
    expect(find.text('Đổi lương 01/11'), findsOneWidget);
  });

  testWidgets('Sửa thiết lập — máy tính', (t) async {
    final emp = SlEmployee(
      {'id': 'e1', 'employeeCode': 'NV001', 'lastName': 'Nguyễn Văn', 'firstName': 'An', 'department': 'Kinh doanh'},
      {'benefitId': 'b1', 'benefit': _benefitMonthly, 'upcoming': {'id': 'v9', 'effectiveDate': '2026-11-01T00:00:00'}},
    );
    final ctx = SlContext(
      api: ApiService(),
      shifts: [
        {'name': 'Ca sáng'},
        {'name': 'Ca chiều'},
        {'name': 'Ca tối'},
      ],
      allowances: [
        {'id': 'a2', 'name': 'Phụ cấp xăng xe', 'type': 'Fixed', 'amount': 500000, 'isActive': true, 'employeeIds': ['e1']},
        {'id': 'a1', 'name': 'Phụ cấp ăn trưa', 'type': 'Daily', 'amount': 30000, 'isActive': true, 'employeeIds': ['e1']},
      ],
      insurance: const {'maxInsuranceSalary': 46800000},
      store: {'standardWorkDays': 26},
    );
    await _pump(t, const Size(1280, 2700), 'sl_editor', home: SalaryEditor(ctx: ctx, employee: emp));
    expect(find.text('Thực nhận ước tính'), findsOneWidget);
    expect(find.text('Nghỉ phép'), findsOneWidget);
    expect(find.text('Sửa hồ sơ hiện tại'), findsOneWidget);
  });

  testWidgets('Đổi lương từ ngày', (t) async {
    final emp = SlEmployee(
      {'id': 'e1', 'employeeCode': 'NV001', 'lastName': 'Nguyễn Văn', 'firstName': 'An', 'department': 'Kinh doanh'},
      {'benefitId': 'b1', 'benefit': _benefitMonthly},
    );
    final ctx = SlContext(api: ApiService(), insurance: const {'maxInsuranceSalary': 46800000}, store: {'standardWorkDays': 26});
    await _pump(t, const Size(1280, 1000), 'sl_editor_from_date', home: SalaryEditor(ctx: ctx, employee: emp), before: () async {
      await t.tap(find.text('Đổi lương từ ngày'));
    });
    expect(find.textContaining('tách hai đoạn'), findsOneWidget);
  });

  testWidgets('Danh sách — điện thoại', (t) async {
    await _pump(t, const Size(390, 1500), 'sl_list_mobile');
    expect(find.text('Thiết lập lương'), findsOneWidget);
  });
}
