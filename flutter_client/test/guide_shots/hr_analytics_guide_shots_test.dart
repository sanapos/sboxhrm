import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zkteco_flutter_client/models/user.dart';
import 'package:zkteco_flutter_client/providers/auth_provider.dart';
import 'package:zkteco_flutter_client/screens/analytics_reports_screen.dart';
import 'package:zkteco_flutter_client/screens/travel_hours_report_screen.dart';

import 'guide_shot_kit.dart';
import 'hrm_extras_common.dart';

/// Ảnh cho bước hướng dẫn «Báo cáo phân tích & báo cáo đi đường» (id: hr_analytics).

Widget _withReports(Widget child) {
  SharedPreferences.setMockInitialValues({});
  final auth = AuthProvider()
    ..debugSetUser(User(
      id: 'u1', employeeId: 'e1', email: 'admin@comganam.vn', fullName: 'Nguyễn Văn Hùng', role: 'Admin', storeId: 's1',
      allowedModules: const [
        'HrAnalyticsReport', 'AttendanceReport', 'AttendanceSummary', 'Attendance', 'LeaveReport', 'WorkSchedule', 'KPI',
        'Report', 'Meal', 'TravelHoursReport', 'MobileAttendance', 'Employee',
      ],
    ));
  return ChangeNotifierProvider<AuthProvider>.value(value: auth, child: child);
}

Map<String, Object?> _c(String id, String code, String name, String dept, int present, int late, int leave, int absent) => {
      'employeeId': id, 'employeeCode': code, 'employeeName': name, 'department': dept, 'standardDays': 26,
      'presentDays': present, 'lateDays': late, 'leaveDays': leave, 'absentDays': absent,
      'complianceRate': ((present / 26) * 1000).round() / 10,
    };

final _now = DateTime.now();

final _compliance = {
  'year': _now.year, 'month': _now.month, 'standardDays': 26, 'totalEmployees': 6, 'avgComplianceRate': 88.5,
  'items': [
    _c('e1', '1', 'Nguyễn Văn Hùng', 'Ban quản lý', 26, 0, 0, 0),
    _c('e2', '2', 'Trần Thị Lan', 'Phục vụ', 25, 2, 1, 0),
    _c('e3', '3', 'Lê Văn Minh', 'Bếp', 24, 1, 0, 2),
    _c('e4', '4', 'Phạm Thị Hoa', 'Thu ngân', 23, 3, 1, 2),
    _c('e5', '5', 'Võ Minh Tuấn', 'Phục vụ', 21, 4, 0, 5),
    _c('e8', '8', 'Hồ Ngọc Ánh', 'Kế toán', 19, 0, 2, 5),
  ],
};

String _t(int day, int h, int m) =>
    '${isoDay(DateTime(_now.year, _now.month, day))}T${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:00';

/// Đi đường: bắt đầu (2) / đến điểm (3).
final _travel = [
  {'id': 't1', 'odooEmployeeId': '5', 'employeeName': 'Võ Minh Tuấn', 'punchTime': _t(1, 8, 10), 'punchType': 2, 'status': 'approved'},
  {'id': 't2', 'odooEmployeeId': '5', 'employeeName': 'Võ Minh Tuấn', 'punchTime': _t(1, 9, 5), 'punchType': 3, 'status': 'approved'},
  {'id': 't3', 'odooEmployeeId': '5', 'employeeName': 'Võ Minh Tuấn', 'punchTime': _t(1, 14, 0), 'punchType': 2, 'status': 'approved'},
  {'id': 't4', 'odooEmployeeId': '5', 'employeeName': 'Võ Minh Tuấn', 'punchTime': _t(1, 14, 40), 'punchType': 3, 'status': 'pending'},
  {'id': 't5', 'odooEmployeeId': '3', 'employeeName': 'Lê Văn Minh', 'punchTime': _t(1, 6, 30), 'punchType': 2, 'status': 'approved'},
  {'id': 't6', 'odooEmployeeId': '3', 'employeeName': 'Lê Văn Minh', 'punchTime': _t(1, 7, 15), 'punchType': 3, 'status': 'approved'},
];

MockClient get _api => guideApi({
      '/api/reports/attendance-analytics/compliance': _compliance,
      '/api/mobile-attendance/history': _travel,
      '/api/employees': {'items': extrasEmployees, 'totalCount': extrasEmployees.length},
    });

void main() {
  for (final (suffix, size) in [('', desktopSize), ('-mobile', mobileSize)]) {
    testWidgets('hr-analytics-1$suffix: danh sách báo cáo phân tích', (t) async {
      await guideShot(
        t,
        name: 'hr-analytics-1$suffix',
        screen: _withReports(const AnalyticsReportsScreen()),
        api: _api,
        crumbs: const ['Báo cáo nhân sự', 'Báo cáo phân tích'],
        size: size,
        marks: [
          GuideMark(1, [find.byType(TextField).first], pad: 4),
          GuideMark(2, [find.text('Chấm công').first, cardOf(find.text('Tỷ lệ chuyên cần'))], pad: 4),
          if (size.width >= 600) GuideMark(3, [cardOf(find.text('Báo cáo điều hành tháng'))], pad: 2),
        ],
      );
    });

    testWidgets('hr-analytics-2$suffix: tỷ lệ chuyên cần', (t) async {
      await guideShot(
        t,
        name: 'hr-analytics-2$suffix',
        screen: _withReports(const AnalyticsReportsScreen()),
        api: _api,
        crumbs: const ['Báo cáo nhân sự', 'Báo cáo phân tích', 'Tỷ lệ chuyên cần'],
        size: size,
        act: (t) async {
          await t.tap(find.text('Tỷ lệ chuyên cần').first);
          await extrasSettle(t, 10);
        },
        marks: [
          GuideMark(1, [GuideMark.button(find.textContaining('Tháng ${_now.month}/'))], pad: 2),
          GuideMark(2, [find.text('Xếp hạng tỷ lệ chuyên cần'), find.text('Trần Thị Lan').first], pad: 10),
          if (size.width >= 600) GuideMark(3, [find.textContaining('Chi tiết ('), find.text('Ngày vắng')], pad: 8),
        ],
      );
    });

    testWidgets('hr-analytics-3$suffix: báo cáo đi đường', (t) async {
      await guideShot(
        t,
        name: 'hr-analytics-3$suffix',
        screen: _withReports(const TravelHoursReportScreen()),
        api: _api,
        crumbs: const ['Báo cáo nhân sự', 'Báo cáo đi đường'],
        size: size,
        act: (t) async => extrasSettle(t, 8),
        marks: [
          GuideMark(1, [GuideMark.button(find.text('Hôm nay')), GuideMark.button(find.text('Tùy chọn khác'))], pad: 4),
          GuideMark(2, [find.text('Tổng giờ'), find.textContaining('Tính lương')], pad: 14),
          GuideMark(3, [GuideMark.button(find.text('Thêm đi đường'))], pad: 2),
        ],
      );
    });
  }
}
