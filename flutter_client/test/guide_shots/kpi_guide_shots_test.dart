import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:zkteco_flutter_client/screens/kpi_screen.dart';
import 'package:zkteco_flutter_client/widgets/page_top_actions.dart';

import 'guide_shot_kit.dart';

/// Ảnh cho bước hướng dẫn «KPI» (id: kpi): chu kỳ tháng 10, chỉ tiêu doanh số
/// của nhân viên bán hàng, lương KPI tính từ % hoàn thành.

final _employees = [
  {'id': 'e1', 'employeeCode': 'NV001', 'fullName': 'Nguyễn Văn An', 'firstName': 'An', 'lastName': 'Nguyễn Văn', 'departmentName': 'Kinh doanh'},
  {'id': 'e2', 'employeeCode': 'NV002', 'fullName': 'Trần Thị Bình', 'firstName': 'Bình', 'lastName': 'Trần Thị', 'departmentName': 'Kinh doanh'},
  {'id': 'e3', 'employeeCode': 'NV003', 'fullName': 'Lê Văn Cường', 'firstName': 'Cường', 'lastName': 'Lê Văn', 'departmentName': 'Kinh doanh'},
  {'id': 'e4', 'employeeCode': 'NV004', 'fullName': 'Phạm Minh Dũng', 'firstName': 'Dũng', 'lastName': 'Phạm Minh', 'departmentName': 'Chăm sóc khách hàng'},
];

Map<String, Object?> _target(String id, int i, num target, num actual, num salary) {
  final e = _employees[i];
  return {
    'id': id,
    'employeeId': e['id'],
    'employeeName': e['fullName'],
    'employeeCode': e['employeeCode'],
    'department': e['departmentName'],
    'criteriaType': 0,
    'targetValue': target,
    'actualValue': actual,
    'completionRate': (actual / target * 100),
    'completionSalary': salary,
  };
}

final _targets = [
  _target('t1', 0, 150000000, 168000000, 3000000),
  _target('t2', 1, 120000000, 102000000, 2500000),
  _target('t3', 2, 100000000, 64000000, 2000000),
  _target('t4', 3, 80000000, 81500000, 1500000),
];

Map<String, Object?> _salary(String id, int i, num base, num score, num bonus) {
  final e = _employees[i];
  return {
    'id': id,
    'employeeId': e['id'],
    'employeeName': e['fullName'],
    'employeeCode': e['employeeCode'],
    'baseSalary': base,
    'totalKpiScore': score,
    'kpiBonusAmount': bonus,
    'allowances': 500000,
    'deductions': 0,
    'grossIncome': base + bonus + 500000,
    'netIncome': base + bonus + 500000,
    'isApproved': false,
  };
}

MockClient _api({int status = 0}) => guideApi({
      '/api/kpi/gsheet-config/credentials-status': {'configured': false},
      '/api/kpi/periods': [
        {'id': 'p1', 'name': 'Tháng 10/2026', 'status': status, 'periodStart': '2026-10-01T00:00:00', 'periodEnd': '2026-10-31T00:00:00'},
        {'id': 'p0', 'name': 'Tháng 9/2026', 'status': 2, 'periodStart': '2026-09-01T00:00:00', 'periodEnd': '2026-09-30T00:00:00'},
      ],
      '/api/kpi/dashboard': {
        'totalEmployees': 4,
        'averageCompletion': 96.4,
        'aboveTarget': 2,
        'belowTarget': 2,
      },
      '/api/kpi/employee-targets': _targets,
      '/api/kpi/salary': [
        _salary('s1', 0, 8000000, 112, 3360000),
        _salary('s2', 1, 7000000, 85, 2125000),
        _salary('s3', 2, 7000000, 64, 1280000),
        _salary('s4', 3, 6500000, 102, 1530000),
      ],
      '/api/employees': {'items': _employees, 'totalCount': _employees.length},
    });

const _crumbs = ['Quản lý vận hành', 'KPI'];

Future<void> _tab(WidgetTester t, String label) async {
  await t.tap(find.descendant(of: find.byType(TabBar), matching: find.text(label)).first);
  for (var i = 0; i < 6; i++) {
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await t.pump(const Duration(milliseconds: 100));
  }
}

/// Điện thoại: thao tác phụ gom trong nút «Thao tác khác» cạnh FAB.
Future<void> _action(WidgetTester t, String label, bool mobile) async {
  if (mobile) {
    // Gọi thẳng thao tác đã đăng ký (giống chọn trong bảng «Thao tác khác»): bấm qua bảng
    // trượt rồi mở hộp thoại ngay lúc bảng đang đóng làm flutter_test lỗi cây semantics.
    PageTopActions.instance.actions.whereType<HrmTopBarAction>().firstWhere((a) => a.label == label).onPressed!();
  } else {
    await t.tap(find.byTooltip(label));
  }
  for (var i = 0; i < 10; i++) {
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await t.pump(const Duration(milliseconds: 100));
  }
}

Finder _tabLabel(String label) => find.descendant(of: find.byType(TabBar), matching: find.text(label)).first;

void main() {
  for (final (suffix, size) in [('', desktopSize), ('-mobile', mobileSize)]) {
    final mobile = size.width < 600;

    testWidgets('kpi-1$suffix: giao chỉ tiêu theo nhân viên', (t) async {
      await guideShot(
        t,
        name: 'kpi-1$suffix',
        screen: const KpiScreen(),
        api: _api(),
        crumbs: _crumbs,
        size: size,
        act: (t) => _tab(t, 'Chỉ tiêu'),
        marks: [
          GuideMark(1, [_tabLabel('Chỉ tiêu')]),
          GuideMark(2, [if (mobile) GuideMark.button(find.text('Giao chỉ tiêu')) else find.byTooltip('Giao chỉ tiêu')]),
          GuideMark(3, [find.text('Nguyễn Văn An'), find.text('150.000.000'), find.text('168.000.000')], pad: 10),
        ],
      );
    });

    testWidgets('kpi-2$suffix: cập nhật doanh số thực tế', (t) async {
      await guideShot(
        t,
        name: 'kpi-2$suffix',
        screen: const KpiScreen(),
        api: _api(),
        crumbs: _crumbs,
        size: size,
        act: (t) async {
          await _tab(t, 'Chỉ tiêu');
          await _action(t, 'Cập nhật doanh số', mobile);
          // Điện thoại: chờ bảng thao tác đóng hẳn rồi mới gõ (đang đóng thì cây widget còn dở).
          for (var i = 0; i < 10; i++) {
            await t.pump(const Duration(milliseconds: 100));
          }
          await t.enterText(find.widgetWithText(TextField, 'Thực tế').first, '172000000');
          await t.pump(const Duration(milliseconds: 200));
        },
        marks: [
          GuideMark(1, [find.text('Mục tiêu: 150.000.000'), find.widgetWithText(TextField, 'Thực tế').first]),
          GuideMark(2, [GuideMark.button(find.text('Lưu tất cả'))]),
        ],
      );
    });

    testWidgets('kpi-3$suffix: lương KPI, duyệt', (t) async {
      await guideShot(
        t,
        name: 'kpi-3$suffix',
        screen: const KpiScreen(),
        api: _api(status: 2),
        crumbs: _crumbs,
        size: size,
        act: (t) => _tab(t, mobile ? 'Lương' : 'Lương KPI'),
        marks: [
          GuideMark(1, [_tabLabel(mobile ? 'Lương' : 'Lương KPI')]),
          GuideMark(2, [if (mobile) find.text('% KPI').first else find.text('112.0%'), find.text('3.360.000')], pad: mobile ? 6 : 10),
          GuideMark(3, [GuideMark.button(find.textContaining('Duyệt ('))]),
        ],
      );
    });
  }
}
