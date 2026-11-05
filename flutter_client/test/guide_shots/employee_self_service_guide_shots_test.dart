import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zkteco_flutter_client/models/user.dart';
import 'package:zkteco_flutter_client/providers/auth_provider.dart';
import 'package:zkteco_flutter_client/screens/payslip_screen.dart';
import 'package:zkteco_flutter_client/screens/shift_hub/shift_hub_screen.dart';
import 'package:zkteco_flutter_client/screens/shift_hub/shift_hub_ui.dart';

import 'guide_shot_kit.dart';
import 'hrm_extras_common.dart';

/// Ảnh cho bước hướng dẫn «Dành cho nhân viên: dùng app» (id: employee_self_service).
/// Đăng nhập bằng tài khoản vai trò Nhân viên — chỉ thấy dữ liệu của mình.

Widget _asEmployee(Widget child) {
  SharedPreferences.setMockInitialValues({});
  final auth = AuthProvider()
    ..debugSetUser(User(
      id: 'u2',
      employeeId: 'e2',
      email: 'lan@comganam.vn',
      fullName: 'Trần Thị Lan',
      role: 'Employee',
      storeId: 's1',
      allowedModules: const ['Payslip', 'WorkSchedule', 'Leave', 'ShiftSwap'],
    ));
  return ChangeNotifierProvider<AuthProvider>.value(value: auth, child: child);
}

Map<String, Object?> _slip(int month, {required bool paid, required num net, num bonus = 0, num ot = 0}) => {
      'id': 'p$month', 'month': month, 'year': 2026, 'employeeName': 'Trần Thị Lan', 'employeeCode': '2',
      'department': 'Phục vụ', 'employeeUserId': 'u2', 'status': paid ? 'Paid' : 'Approved', 'isPaid': paid,
      'paymentStatus': paid ? 'Đã thanh toán' : 'Chưa thanh toán', 'paidAmount': paid ? net : 0, 'remainingAmount': paid ? 0 : net,
      'periodStart': '2026-${month.toString().padLeft(2, '0')}-01T00:00:00',
      'periodEnd': '2026-${month.toString().padLeft(2, '0')}-${month == 9 ? 30 : 31}T00:00:00',
      'baseSalary': 7500000, 'allowances': 1400000, 'bonus': bonus, 'overtimePay': ot, 'deductions': 50000,
      'socialInsurance': 600000, 'healthInsurance': 112500, 'unemploymentInsurance': 75000, 'tax': 0,
      'grossSalary': 7500000 + 1400000 + bonus + ot, 'netSalary': net,
    };

final _payslips = [
  _slip(10, paid: false, net: 8862500, bonus: 300000, ot: 400000),
  _slip(9, paid: true, net: 8312500),
  _slip(8, paid: true, net: 8512500, bonus: 200000),
];

const _templates = [
  {'id': 't1', 'name': 'Ca sáng', 'start': '06:00', 'end': '14:00', 'colorIndex': 0, 'active': true},
  {'id': 't2', 'name': 'Ca chiều', 'start': '14:00', 'end': '22:00', 'colorIndex': 1, 'active': true},
];

DateTime get _today => DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);
DateTime get _mon => ShiftUi.monday(DateTime.now());

Map<String, Object?> _my() {
  const plan = ['t2', 't2', 'off', 't1', 't1', 't2', 't2'];
  final days = <Map<String, Object?>>[];
  for (var i = 0; i < 7; i++) {
    final date = _mon.add(Duration(days: i));
    // Hôm nay luôn có ca, để ô «Hôm nay: …» không phụ thuộc thứ trong tuần lúc chạy test.
    final p = date == _today && plan[i] == 'off' ? 't1' : plan[i];
    final tpl = _templates.where((t) => t['id'] == p).firstOrNull;
    days.add({
      'date': ShiftUi.key(date),
      'isToday': date == _today,
      'isPast': date.isBefore(_today),
      if (p == 'off') 'schedule': {'scheduleId': 'm$i', 'isDayOff': true, 'note': 'Nghỉ tuần'},
      if (tpl != null) 'schedule': {'scheduleId': 'm$i', 'shiftId': p, 'start': tpl['start'], 'end': tpl['end']},
      'leaves': const [],
      'swaps': const [],
      'schedules': const [],
    });
  }
  return {
    'days': days,
    'templates': _templates,
    'incomingSwaps': const [],
    'summary': {'shifts': 6, 'hours': 48, 'dayOff': 1, 'pendingRegistrations': 0, 'pendingLeaves': 0, 'pendingSwaps': 0},
  };
}

MockClient get _api => guideApi({
      '/api/payslips/my-payslips': _payslips,
      '/api/shift-hub/my': _my(),
      '/api/shift-hub/counts': {'total': 0, 'swapsForMe': 0},
      '/api/employees': {'items': extrasEmployees, 'totalCount': extrasEmployees.length},
    });

void main() {
  for (final (suffix, size) in [('', desktopSize), ('-mobile', mobileSize)]) {
    testWidgets('employee-self-service-1$suffix: phiếu lương của tôi', (t) async {
      await guideShot(
        t,
        name: 'employee-self-service-1$suffix',
        screen: _asEmployee(const PayslipScreen()),
        api: _api,
        crumbs: const ['Phiếu lương'],
        size: size,
        act: (t) async => extrasSettle(t),
        marks: [
          GuideMark(1, [find.text('Thực lĩnh kỳ gần nhất'), find.text('Kỳ T10/2026').first], pad: 16),
          GuideMark(2, [find.text('Chưa thanh toán').first, find.text('8.862.500 đ').at(1)], pad: 16),
          GuideMark(3, [find.text('Trần Thị Lan').first, find.text('Chưa thanh toán').last, find.text('8.862.500 đ').last], pad: 10),
        ],
      );
    });

    testWidgets('employee-self-service-2$suffix: chi tiết phiếu lương', (t) async {
      await guideShot(
        t,
        name: 'employee-self-service-2$suffix',
        screen: _asEmployee(const PayslipScreen()),
        api: _api,
        crumbs: const ['Phiếu lương', 'T10/2026'],
        size: size,
        act: (t) async {
          await extrasSettle(t);
          final hide = find.textContaining('Ẩn biểu đồ');
          if (hide.evaluate().isNotEmpty) {
            await t.tap(hide.first);
            await extrasSettle(t, 3);
          }
          await t.tap(find.text('Kỳ T10/2026').last);
          await extrasSettle(t);
          await scrollInto(t, find.text('Kỳ T10/2026').last, alignment: 0.15);
          await extrasSettle(t, 3);
        },
        marks: [
          GuideMark(1, [find.text('Thu nhập'), find.text('9.600.000 đ')], pad: 10),
          GuideMark(2, [find.text('Khấu trừ'), find.text('Khấu trừ khác'), find.text('50.000 đ').last], pad: 10),
          if (size.width >= 600) GuideMark(3, [GuideMark.button(find.text('Xem bảng chấm công kỳ lương'))], pad: 2),
        ],
      );
    });

    testWidgets('employee-self-service-3$suffix: lịch ca của tôi', (t) async {
      await guideShot(
        t,
        name: 'employee-self-service-3$suffix',
        screen: _asEmployee(const ShiftHubScreen(initialTab: 'my')),
        api: _api,
        crumbs: const ['Ca làm việc'],
        size: size,
        marks: [
          GuideMark(1, [find.textContaining('Hôm nay:')], pad: 10),
          GuideMark(2, [find.textContaining('ca · ')], pad: 6),
          GuideMark(3, [GuideMark.button(find.byTooltip('Thao tác').first)], pad: 2),
        ],
      );
    });
  }
}
