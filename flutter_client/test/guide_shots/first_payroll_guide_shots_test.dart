import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:zkteco_flutter_client/models/attendance.dart';
import 'package:zkteco_flutter_client/screens/attendance/payroll_summary_tab.dart';

import '../fixtures/payroll_fixture.dart';
import 'guide_shot_kit.dart';

/// Ảnh cho bước hướng dẫn «Chốt công & bảng lương tháng đầu» (id: first_payroll).
/// Dùng bộ dữ liệu bảng lương mẫu tháng 8/2026 (test/fixtures/payroll_fixture.dart) —
/// cùng số liệu với payroll_golden_test, bảng tự tính trên máy (máy chủ chưa có bảng).
/// Bỏ NV005 (mẫu cố ý chưa cài lương) để ảnh hướng dẫn không hiện cảnh báo thiết lập lương.

http.Response _ok(Object? data) => http.Response(jsonEncode({'isSuccess': true, 'data': data}), 200,
    headers: {'content-type': 'application/json; charset=utf-8'});

final _employees = [for (final e in payrollFixtureEmployees) if (e['id'] != 'e5') e];

MockClient _api() {
  final responses = payrollFixtureResponses();
  return MockClient((req) async {
    final p = req.url.path;
    if (p.endsWith('/api/payroll/summary')) return http.Response('{}', 404);
    if (p.endsWith('/api/employees')) return _ok({'items': _employees, 'totalCount': _employees.length});
    if (p.endsWith('/api/benefits/employees')) {
      return _ok([for (final b in responses['/api/benefits/employees'] as List) if ((b as Map)['employeeId'] != 'e5') b]);
    }
    for (final e in responses.entries) {
      if (p.endsWith(e.key)) return e.value == null ? http.Response('{}', 404) : _ok(e.value);
    }
    if (p.contains('/api/benefits/me')) return _ok(null);
    return _ok([]);
  });
}

Widget _screen() => Scaffold(
      body: PayrollSummaryTab(
        attendances: [
          for (final a in payrollFixtureAttendanceJson().map(Attendance.fromJson))
            if (a.employeeId != '5') a,
        ],
        devices: const [],
        fromDate: DateTime(2026, 8, 1),
        toDate: DateTime(2026, 8, 31),
      ),
    );

const _crumbs = ['Báo cáo nhân sự', 'Tổng hợp lương'];

/// Bộ lọc kỳ lương + nút «Chốt lương» nằm cuối khung «Tổng quan & bộ lọc» — cuộn tới đó.
/// Ô ngày của bộ lọc: máy tính «01/08/2026», điện thoại «01/08/26» (không lấy dòng tóm tắt bộ lọc).
Finder _date(String dm) => find.byWidgetPredicate((w) => w is Text && (w.data == '$dm/2026' || w.data == '$dm/26'));

/// Điện thoại: khung «Bộ lọc» gập sẵn — mở ra trước.
Future<void> _toFilters(WidgetTester t) async {
  // Dựa vào mũi tên của khung «Bộ lọc» (expand_more = đang gập), không dựa vào chữ «Xóa lọc»:
  // lúc màn vừa tải chữ đó có thể chưa thấy dù khung đang mở → bấm nhầm thành gập lại.
  final collapsed = find.descendant(
      of: find.ancestor(of: find.text('Bộ lọc'), matching: find.byType(ExpansionTile)),
      matching: find.byIcon(Icons.expand_more));
  if (collapsed.evaluate().isNotEmpty) {
    await guideScrollTo(t, find.text('Bộ lọc'), alignment: 0.3);
    await t.tap(find.text('Bộ lọc'));
    await t.pump(const Duration(milliseconds: 500));
  }
  await guideScrollTo(t, find.text('Xóa lọc'), alignment: 0.7);
}

void main() {
  for (final (suffix, size) in [('', desktopSize), ('-mobile', mobileSize)]) {
    final mobile = size.width < 600;

    testWidgets('first-payroll-1$suffix: chọn kỳ lương', (t) async {
      await guideShot(
        t,
        name: 'first-payroll-1$suffix',
        screen: _screen(),
        api: _api(),
        crumbs: _crumbs,
        size: size,
        act: _toFilters,
        marks: [
          GuideMark(1, [GuideMark.button(_date('01/08')), GuideMark.button(_date('31/08'))], pad: 4),
          GuideMark(2, [GuideMark.button(find.text('Phòng ban')), GuideMark.button(find.text('Tất cả NV (6)'))], pad: 4),
        ],
      );
    });

    testWidgets('first-payroll-2$suffix: rà từng nhân viên', (t) async {
      await guideShot(
        t,
        name: 'first-payroll-2$suffix',
        screen: _screen(),
        api: _api(),
        crumbs: _crumbs,
        size: size,
        act: (t) async {
          if (mobile) {
            // .last: tên cũng có trong «Thực lĩnh cao nhất» ở khung tổng quan phía trên.
            await guideScrollTo(t, find.text('Nguyễn Văn An').last, alignment: 0.1);
            await t.tap(find.text('Nguyễn Văn An').last);
            await t.pump(const Duration(milliseconds: 500));
            await guideScrollTo(t, find.text('Nguyễn Văn An').last, alignment: 0.02);
          }
        },
        marks: mobile
            ? [
                GuideMark(1, [find.text('Thu nhập').last, find.textContaining('4.369.375').last], pad: 14),
                GuideMark(2, [find.textContaining('18.493.125').last], pad: 8),
              ]
            : [
                GuideMark(1, [find.text('Nguyễn Văn An').last, find.text('2.812.500').last], pad: 6),
                GuideMark(2, [find.text('Thực nhận').last, find.text('18.493.125').last], pad: 6),
              ],
      );
    });

    testWidgets('first-payroll-3$suffix: chốt lương kỳ', (t) async {
      await guideShot(
        t,
        name: 'first-payroll-3$suffix',
        screen: _screen(),
        api: _api(),
        crumbs: _crumbs,
        size: size,
        act: _toFilters,
        marks: [
          GuideMark(1, [GuideMark.button(find.text('Chốt lương'))]),
        ],
      );
    });
  }
}
