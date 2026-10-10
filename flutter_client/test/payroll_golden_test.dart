import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zkteco_flutter_client/l10n/app_localizations.dart';
import 'package:zkteco_flutter_client/models/attendance.dart';
import 'package:zkteco_flutter_client/providers/auth_provider.dart';
import 'package:zkteco_flutter_client/providers/permission_provider.dart';
import 'package:zkteco_flutter_client/screens/attendance/payroll_summary_tab.dart';

import 'fixtures/payroll_fixture.dart';

/// «Đáp án chuẩn» bảng lương tháng 8/2026 (dữ liệu mẫu nhiều loại lương).
/// Bảng lương trên app và bộ tính lương máy chủ phải ra đúng các số này.
/// Cập nhật đáp án (khi CỐ Ý đổi công thức): UPDATE_PAYROLL_GOLDEN=1 flutter test test/payroll_golden_test.dart
http.Response _ok(Object? data) =>
    http.Response(jsonEncode({'isSuccess': true, 'data': data}), 200, headers: {'content-type': 'application/json; charset=utf-8'});

MockClient payrollFixtureClient({required bool serverAdjustments, List<Map<String, dynamic>>? serverRows}) {
  final responses = payrollFixtureResponses(serverAdjustments: serverAdjustments);
  return MockClient((req) async {
    final p = req.url.path;
    if (p.endsWith('/api/payroll/summary')) {
      if (serverRows == null) return http.Response('{}', 404);
      return _ok({'rows': serverRows, 'notConfiguredSalaryCount': 1, 'engine': 'server'});
    }
    if (p.endsWith('/api/employees')) {
      return _ok({'items': payrollFixtureEmployees, 'totalCount': payrollFixtureEmployees.length});
    }
    if (p.endsWith('/api/attendances')) {
      final items = payrollFixtureAttendanceJson();
      return _ok({'items': items, 'totalCount': items.length});
    }
    for (final e in responses.entries) {
      if (p.endsWith(e.key)) {
        if (e.value == null) return http.Response('{}', 404);
        return _ok(e.value);
      }
    }
    if (p.contains('/api/benefits/me')) return _ok(null);
    return _ok([]);
  });
}

Future<List<Map<String, dynamic>>> _rows(WidgetTester t, {required bool serverAdjustments, List<Map<String, dynamic>>? serverRows}) async {
  SharedPreferences.setMockInitialValues({});
  final key = GlobalKey<PayrollSummaryTabState>();
  List<Map<String, dynamic>>? rows;
  final atts = payrollFixtureAttendanceJson().map(Attendance.fromJson).toList();
  await http.runWithClient(() async {
    await t.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => PermissionProvider()),
      ],
      child: MaterialApp(
        localizationsDelegates: const [AppLocalizations.delegate, GlobalMaterialLocalizations.delegate, GlobalWidgetsLocalizations.delegate, GlobalCupertinoLocalizations.delegate],
        supportedLocales: const [Locale('vi')],
        locale: const Locale('vi'),
        home: Scaffold(
          body: PayrollSummaryTab(
            key: key,
            attendances: atts,
            devices: const [],
            fromDate: DateTime(2026, 8, 1),
            toDate: DateTime(2026, 8, 31),
          ),
        ),
      ),
    ));
    for (var i = 0; i < 80 && rows == null; i++) {
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await t.pump(const Duration(milliseconds: 50));
      rows = key.currentState?.debugPayrollRows();
    }
  }, () => payrollFixtureClient(serverAdjustments: serverAdjustments, serverRows: serverRows));
  expect(rows, isNotNull, reason: 'bảng lương chưa tải xong');
  return normalizePayrollRows(rows!);
}

/// Chuẩn hóa để so: qua JSON (số nguyên / thực như nhau), sắp theo mã NV.
List<Map<String, dynamic>> normalizePayrollRows(List<Map<String, dynamic>> rows) {
  final list = (jsonDecode(jsonEncode(rows)) as List).cast<Map<String, dynamic>>();
  list.sort((a, b) => '${a['code']}'.compareTo('${b['code']}'));
  return list;
}

/// So sâu, số thực lệch tối đa 0,001đ.
void expectSameRows(List<Map<String, dynamic>> actual, List<Map<String, dynamic>> expected) {
  expect(actual.length, expected.length, reason: 'số dòng');
  void cmp(Object? a, Object? e, String path) {
    if (e is num && a is num) {
      expect((a - e).abs() < 0.001, isTrue, reason: '$path: $a ≠ $e');
    } else if (e is Map && a is Map) {
      expect(a.keys.toSet(), e.keys.toSet(), reason: '$path: khóa khác nhau');
      for (final k in e.keys) {
        cmp(a[k], e[k], '$path.$k');
      }
    } else if (e is List && a is List) {
      expect(a.length, e.length, reason: '$path: độ dài');
      for (var i = 0; i < e.length; i++) {
        cmp(a[i], e[i], '$path[$i]');
      }
    } else {
      expect(a, e, reason: path);
    }
  }

  for (var i = 0; i < expected.length; i++) {
    cmp(actual[i], expected[i], expected[i]['code'] as String);
  }
}

Future<void> _check(WidgetTester t, String name, {required bool serverAdjustments}) async {
  final rows = await _rows(t, serverAdjustments: serverAdjustments);
  final file = File('test/goldens/$name.json');
  if (Platform.environment['UPDATE_PAYROLL_GOLDEN'] == '1' || !file.existsSync()) {
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(const JsonEncoder.withIndent(' ').convert(rows));
  }
  final golden = (jsonDecode(file.readAsStringSync()) as List).cast<Map<String, dynamic>>();
  expectSameRows(rows, golden);
}

void main() {
  testWidgets('Bảng lương mẫu — tính khoản cộng / trừ trên máy', (t) async {
    await _check(t, 'payroll_rows_local', serverAdjustments: false);
  });

  testWidgets('Bảng lương mẫu — khoản cộng / trừ do máy chủ tính sẵn', (t) async {
    await _check(t, 'payroll_rows_server_adj', serverAdjustments: true);
  });

  testWidgets('Máy chủ có bảng lương → màn hình dùng số máy chủ (số chính thức)', (t) async {
    final golden = (jsonDecode(File('test/goldens/payroll_rows_local.json').readAsStringSync()) as List).cast<Map<String, dynamic>>();
    final server = [for (final r in golden) {...r, 'netSalary': 123456789}];
    final rows = await _rows(t, serverAdjustments: false, serverRows: server);
    expect(rows, hasLength(golden.length));
    expect(rows.every((r) => r['netSalary'] == 123456789), isTrue);
  });
}
