import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zkteco_flutter_client/models/attendance.dart';
import 'package:zkteco_flutter_client/models/user.dart';
import 'package:zkteco_flutter_client/providers/auth_provider.dart';
import 'package:zkteco_flutter_client/screens/attendance/attendance_by_shift_tab.dart';
import 'package:zkteco_flutter_client/features/boss/boss_staff_today_screen.dart';
import 'package:zkteco_flutter_client/screens/attendance/attendance_summary_tab.dart';
import 'package:zkteco_flutter_client/services/api_service.dart';
import 'package:zkteco_flutter_client/widgets/attendance/attendance_employee_list.dart';

// Tổng hợp chấm công trên điện thoại (chủ nhiều NV): ô số bấm ra danh sách người,
// NV lương theo giờ hiện giờ (không tính công), không bị tính vắng ngày không có lịch.
//
// Kỳ «Tuần trước» (T2 → CN, đều đã qua):
// - An (lương tháng): chấm đủ 7 ngày 08:00–17:00.
// - Bình (lương GIỜ): ca tối 18:00–22:00 thứ 2 và thứ 4, không xếp lịch → 8 giờ, 0 vắng.
// - Cường (lương tháng): chỉ đi T2–T4 → vắng 4 ngày.
final _today = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);
final _mon = _today.subtract(Duration(days: _today.weekday - 1 + 7));
DateTime _day(int i) => DateTime(_mon.year, _mon.month, _mon.day + i);

var _n = 0;
Attendance _p(String code, String name, int day, int h, int m) => Attendance(
      id: 'a${_n++}',
      pin: code,
      employeeId: code,
      employeeName: name,
      attendanceTime: DateTime(_day(day).year, _day(day).month, _day(day).day, h, m),
    );

final _logs = [
  for (var d = 0; d < 7; d++) ...[_p('1', 'Nguyễn Văn An', d, 8, 0), _p('1', 'Nguyễn Văn An', d, 17, 0)],
  for (final d in [0, 2]) ...[_p('2', 'Trần Thị Bình', d, 18, 0), _p('2', 'Trần Thị Bình', d, 22, 0)],
  for (var d = 0; d < 3; d++) ...[_p('3', 'Lê Văn Cường', d, 8, 0), _p('3', 'Lê Văn Cường', d, 17, 0)],
];

final _employees = <Map<String, dynamic>>[
  {'id': 'g1', 'employeeCode': '1', 'pin': '1', 'fullName': 'Nguyễn Văn An'},
  {'id': 'g2', 'employeeCode': '2', 'pin': '2', 'fullName': 'Trần Thị Bình'},
  {'id': 'g3', 'employeeCode': '3', 'pin': '3', 'fullName': 'Lê Văn Cường'},
];

final _profiles = <Map<String, dynamic>>[
  {
    'rateType': 'Monthly',
    'employees': [
      {'employeeCode': '1', 'id': 'g1'},
      {'employeeCode': '3', 'id': 'g3'},
    ],
  },
  {
    'rateType': 'Hourly',
    'employees': [
      {'employeeCode': '2', 'id': 'g2'},
    ],
  },
];

Future<void> _pump(WidgetTester t, Widget tab) async {
  SharedPreferences.setMockInitialValues({});
  t.view.physicalSize = const Size(390, 844);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.resetPhysicalSize);
  addTearDown(t.view.resetDevicePixelRatio);
  final auth = AuthProvider()
    ..debugSetUser(User(id: 'u1', employeeId: 'e1', email: 'chu@shop.vn', fullName: 'Chủ', role: 'Admin', storeId: 's1'));
  await t.pumpWidget(ChangeNotifierProvider<AuthProvider>.value(
    value: auth,
    child: MaterialApp(home: Scaffold(body: tab)),
  ));
  for (var i = 0; i < 10; i++) {
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await t.pump(const Duration(milliseconds: 100));
  }
}

/// Hẹn giờ nền của AuthProvider chạy hết trước khi gỡ cây.
Future<void> _drain(WidgetTester t) async {
  await t.pumpWidget(const SizedBox());
  for (var i = 0; i < 4; i++) {
    await t.pump(const Duration(seconds: 3));
  }
}

final _vertical = find.byWidgetPredicate((w) => w is Scrollable && w.axisDirection == AxisDirection.down);

void main() {
  testWidgets('Tổng hợp chấm công mobile: lương giờ hiện giờ, ô «Có ngày vắng» bấm ra danh sách', (t) async {
    await _pump(
      t,
      AttendanceSummaryTab(
        attendances: _logs,
        devices: const [],
        fromDate: _day(0),
        toDate: _day(6),
        dateRangePreset: 'lastWeek',
        employeesList: _employees,
        salaryProfiles: _profiles,
      ),
    );

    // Tổng số công không cộng công của NV lương giờ.
    expect(find.text('Không gồm 1 NV lương giờ'), findsOneWidget);
    // Bình không có lịch → không vắng; chỉ Cường vắng.
    expect(find.text('1 người'), findsWidgets);

    await t.tap(find.text('Có ngày vắng'));
    await t.pumpAndSettle();
    expect(find.text('Nhân viên có ngày vắng (1)'), findsOneWidget);
    expect(find.text('Lê Văn Cường'), findsWidgets);
    expect(find.text('4 ngày'), findsOneWidget);
    await t.tap(find.byIcon(Icons.close));
    await t.pumpAndSettle();

    // Danh sách NV: tách nhóm, Bình hiện giờ thay cho công.
    // (Tên còn xuất hiện ở bảng xếp hạng phía trên — cuộn tới tiêu đề nhóm của danh sách.)
    await t.scrollUntilVisible(find.text('Lương theo giờ (1) — chỉ tính giờ'), 300, scrollable: _vertical.first);
    await t.drag(_vertical.first, const Offset(0, -200));
    await t.pumpAndSettle();
    expect(find.text('8 giờ'), findsWidgets);
    expect(find.textContaining('vắng'), findsWidgets); // dòng Cường «4 vắng»

    // Chip lọc «Có vắng» chỉ còn Cường.
    await t.scrollUntilVisible(find.textContaining('Có vắng'), -300, scrollable: _vertical.first);
    await t.tap(find.textContaining('Có vắng'));
    await t.pumpAndSettle();
    expect(find.byType(AttendanceEmployeeRow), findsOneWidget);
    expect(find.text('Lương theo giờ (1) — chỉ tính giờ'), findsNothing);
    await _drain(t);
  });

  testWidgets('Theo ca mobile: ô số đếm người, bấm ra danh sách; lương giờ tách nhóm', (t) async {
    await _pump(
      t,
      AttendanceByShiftTab(
        attendances: _logs,
        devices: const [],
        fromDate: _day(0),
        toDate: _day(6),
        dateRangePreset: 'lastWeek',
        employeesList: _employees,
        salaryProfiles: _profiles,
      ),
    );
    await t.scrollUntilVisible(find.text('Nhân viên đi làm'), 300, scrollable: _vertical.first);
    await t.tap(find.text('Nhân viên đi làm'));
    await t.pumpAndSettle();
    expect(find.text('Nhân viên đi làm (3)'), findsOneWidget);
    await t.tap(find.byIcon(Icons.close));
    await t.pumpAndSettle();

    await t.scrollUntilVisible(find.text('Lương theo giờ (1) — chỉ tính giờ'), 300, scrollable: _vertical.first);
    await _drain(t);
  });

  testWidgets('Theo ngày (mobile): chọn ngày, chip «Vắng» chỉ còn người vắng; lương giờ không lịch không vắng', (t) async {
    await _pump(
      t,
      AttendanceSummaryTab(
        attendances: _logs,
        devices: const [],
        fromDate: _day(0),
        toDate: _day(6),
        dateRangePreset: 'lastWeek',
        employeesList: _employees,
        salaryProfiles: _profiles,
      ),
    );
    await t.scrollUntilVisible(find.text('Theo ngày'), 300, scrollable: _vertical.first);
    await t.tap(find.text('Theo ngày'));
    await t.pumpAndSettle();

    // Mặc định ngày cuối kỳ (CN): An có mặt, Cường vắng, Bình (lương giờ, không lịch) nghỉ.
    await t.scrollUntilVisible(find.text('Vắng 1'), 200, scrollable: _vertical.first);
    expect(find.text('Có mặt 1'), findsOneWidget);
    await t.tap(find.text('Vắng 1'));
    await t.pumpAndSettle();
    expect(find.byType(AttendanceEmployeeRow), findsOneWidget);
    expect(find.text('Lê Văn Cường'), findsWidgets);

    // Chọn thứ 2 đầu kỳ: cả 3 người có mặt, không ai vắng (chip Vắng biến mất → về Tất cả).
    final mon = '${_day(0).day}/${_day(0).month}';
    await t.scrollUntilVisible(find.text(mon), -200, scrollable: find.byWidgetPredicate(
        (w) => w is Scrollable && w.axisDirection == AxisDirection.right).first);
    await t.tap(find.text(mon));
    await t.pumpAndSettle();
    expect(find.text('Có mặt 3'), findsOneWidget);
    expect(find.text('Vắng 1'), findsNothing);
    await _drain(t);
  });

  testWidgets('BOSS «Nhân viên hôm nay»: nhóm đã tới ca chưa chấm / chưa tới ca / nghỉ phép / đi trễ', (t) async {
    SharedPreferences.setMockInitialValues({});
    t.view.physicalSize = const Size(390, 844);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    final now = DateTime.now();
    String at(int h, int m) => DateTime(now.year, now.month, now.day, h, m).toIso8601String();
    final api = _FakeBossApi({
      'hasSchedules': true,
      'now': at(10, 0),
      'staff': [
        {'name': 'An', 'code': '1', 'firstPunch': at(8, 20), 'lastPunch': at(8, 20), 'hasShift': true, 'shiftStart': '08:00', 'shiftEnd': '17:00', 'lateMinutes': 20},
        {'name': 'Bình', 'code': '2', 'firstPunch': at(7, 55), 'lastPunch': at(7, 55), 'hasShift': true, 'shiftStart': '08:00', 'lateMinutes': 0},
        {'name': 'Cường', 'code': '3', 'hasShift': true, 'shiftStart': '09:00'},
        {'name': 'Dung', 'code': '4', 'hasShift': true, 'shiftStart': '14:00'},
        {'name': 'Em', 'code': '5', 'onLeave': true},
        {'name': 'Giang', 'code': '6', 'hasShift': false},
      ],
    });
    await t.pumpWidget(MaterialApp(home: BossStaffTodayScreen(api: api)));
    await t.pumpAndSettle();

    expect(find.text('Tới ca, chưa chấm'), findsOneWidget); // thẻ số
    expect(find.text('Đi trễ 1'), findsOneWidget);
    expect(find.text('Chưa tới ca 1'), findsOneWidget);
    expect(find.text('Nghỉ phép 1'), findsOneWidget);
    expect(find.text('Không có ca 1'), findsOneWidget);
    expect(find.text('Trễ 20 phút'), findsOneWidget);

    await t.tap(find.text('Đi trễ 1'));
    await t.pumpAndSettle();
    expect(find.text('An'), findsOneWidget);
    expect(find.text('Bình'), findsNothing);
    expect(find.text('Cường'), findsNothing);

    await t.tap(find.text('Xem tất cả'));
    await t.pumpAndSettle();
    expect(find.text('Cường'), findsOneWidget);
  });
}

/// API giả cho màn BOSS: chỉ trả «Nhân viên hôm nay».
class _FakeBossApi implements ApiService {
  _FakeBossApi(this.data);
  final Map<String, dynamic> data;

  @override
  Future<Map<String, dynamic>> getBossStaffToday() async => {'isSuccess': true, 'data': data};

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
