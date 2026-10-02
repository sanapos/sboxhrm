import 'dart:convert';

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

/// Bảng lương tách đoạn khi đổi lương giữa kỳ (hồ sơ lương theo ngày hiệu lực).
Map<String, dynamic> _benefit(String id, num rate) => {
      'id': id,
      'rateType': 'Monthly',
      'rate': rate,
      'completionSalary': 0,
      'socialInsuranceType': 0,
      'attendanceMode': 'both',
      'paidLeaveType': 'sunday',
      'weeklyOffDays': 'Sunday',
      'hourlyOvertimeType': 2,
      'holidayOvertimeType': 1,
      'description': 'attendanceType:both|shifts:Ca HC|shiftsPerDay:1|hoursPerWorkDay:8',
    };

final _old = _benefit('b-old', 10000000);
final _new = _benefit('b-new', 12000000);

http.Response _ok(Object? data) =>
    http.Response(jsonEncode({'isSuccess': true, 'data': data}), 200, headers: {'content-type': 'application/json; charset=utf-8'});

MockClient _client({required bool timeline}) => MockClient((req) async {
      final p = req.url.path;
      if (p.endsWith('/api/employees')) {
        return _ok({
          'items': [
            {'id': 'e1', 'employeeCode': 'NV001', 'firstName': 'An', 'lastName': 'Nguyễn Văn', 'workStatus': 'Active', 'pin': 'NV001'},
          ],
          'totalCount': 1,
        });
      }
      if (p.endsWith('/api/benefits/employees')) {
        return _ok([
          {'employeeId': 'e1', 'benefitId': 'b-new', 'benefit': _new},
        ]);
      }
      if (p.endsWith('/api/benefits/timeline')) {
        if (!timeline) return http.Response('{}', 404);
        return _ok([
          {
            'employeeId': 'e1',
            'segments': [
              {'id': 'v1', 'benefitId': 'b-old', 'benefit': _old, 'from': '2026-09-01T00:00:00', 'to': '2026-09-15T00:00:00'},
              {'id': 'v2', 'benefitId': 'b-new', 'benefit': _new, 'from': '2026-09-16T00:00:00', 'to': '2026-09-30T00:00:00'},
            ],
          },
        ]);
      }
      if (p.endsWith('/api/shifts/templates')) {
        return _ok([
          {'id': 's1', 'name': 'Ca HC', 'startTime': '08:00:00', 'endTime': '17:00:00', 'breakMinutes': 60, 'isActive': true},
        ]);
      }
      if (p.endsWith('/api/settings/insurance') || p.endsWith('/api/settings/tax')) return _ok(<String, dynamic>{});
      if (p.endsWith('/api/allowances')) return _ok({'items': []});
      if (p.endsWith('/api/settings/salary')) return _ok({'standardWorkDays': 26, 'standardWorkHours': 8});
      if (p.contains('/api/benefits/me')) return _ok(null);
      return _ok([]);
    });

List<Attendance> _month() {
  final out = <Attendance>[];
  for (var d = 1; d <= 30; d++) {
    final day = DateTime(2026, 9, d);
    if (day.weekday == DateTime.sunday) continue;
    for (final (h, m) in [(8, 0), (17, 0)]) {
      out.add(Attendance(id: '$d-$h', pin: 'NV001', employeeId: 'NV001', attendanceTime: DateTime(2026, 9, d, h, m)));
    }
  }
  return out;
}

Future<Map<String, dynamic>> _row(WidgetTester t, {required bool timeline}) async {
  SharedPreferences.setMockInitialValues({});
  final key = GlobalKey<PayrollSummaryTabState>();
  late List<Map<String, dynamic>>? rows;
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
            attendances: _month(),
            devices: const [],
            fromDate: DateTime(2026, 9, 1),
            toDate: DateTime(2026, 9, 30),
          ),
        ),
      ),
    ));
    rows = null;
    for (var i = 0; i < 40 && rows == null; i++) {
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await t.pump(const Duration(milliseconds: 50));
      rows = key.currentState?.debugPayrollRows();
    }
  }, () => _client(timeline: timeline));
  expect(rows, isNotNull, reason: 'bảng lương chưa tải xong');
  return rows!.firstWhere((r) => r['code'] == 'NV001');
}

void main() {
  testWidgets('Không có lịch sử: tính cả tháng theo hồ sơ hiện hành', (t) async {
    final r = await _row(t, timeline: false);
    expect(r['workDays'], 26);
    expect(r['standardDays'], 26);
    expect((r['workSalary'] as num).round(), 12000000);
    expect(r['salaryChanged'], isFalse);
  });

  testWidgets('Tăng lương từ 16/9: nửa đầu lương cũ, nửa sau lương mới', (t) async {
    final r = await _row(t, timeline: true);
    expect(r['workDays'], 26);
    expect(r['salaryChanged'], isTrue);
    // 10tr ÷ 26 × 13 + 12tr ÷ 26 × 13
    expect((r['workSalary'] as num).round(), 11000000);
    final segs = r['salarySegments'] as List;
    expect(segs.length, 2);
    expect((segs.first['workSalary'] as num).round(), 5000000);
    expect((segs.last['workSalary'] as num).round(), 6000000);
    expect(r['baseSalary'], 12000000);
  });
}
