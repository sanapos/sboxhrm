import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zkteco_flutter_client/models/attendance.dart';
import 'package:zkteco_flutter_client/screens/attendance/attendance_by_shift_tab.dart';
import 'package:zkteco_flutter_client/screens/attendance/attendance_summary_tab.dart';

// Kỳ «Tuần trước» (T2 → CN): chấm đủ T2, T3; nghỉ phép (đã duyệt) T4; còn lại không chấm.
final _today = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);
final _mon = _today.subtract(Duration(days: _today.weekday - 1 + 7));
DateTime _day(int i) => DateTime(_mon.year, _mon.month, _mon.day + i);
String _label(int i) => DateFormat('dd/MM/yyyy').format(_day(i));

Attendance _punch(String id, int i, int h, int m) => Attendance(
      id: id,
      pin: '40001',
      employeeId: '40001',
      employeeName: 'Nguyễn Văn A',
      attendanceTime: DateTime(_day(i).year, _day(i).month, _day(i).day, h, m),
    );

final _attendances = [
  _punch('a1', 0, 7, 58),
  _punch('a2', 0, 17, 2),
  _punch('a3', 1, 8, 0),
  _punch('a4', 1, 17, 0),
];

final _employees = <Map<String, dynamic>>[
  {'id': 'e1', 'employeeCode': '40001', 'pin': '40001', 'fullName': 'Nguyễn Văn A'},
];

final _leaves = <dynamic>[
  <String, dynamic>{
    'employeeCode': '40001',
    'fromDate': DateFormat('yyyy-MM-dd').format(_day(2)),
    'toDate': DateFormat('yyyy-MM-dd').format(_day(2)),
    'status': 'Approved',
    'type': 'AnnualLeave',
  },
];

// Bảng desktop (thanh cuộn, tiêu đề ghim) trong môi trường test báo lỗi vẽ không liên quan dữ liệu
// — chỉ bỏ qua đúng các lỗi đó, lỗi khác vẫn làm test hỏng.
const _layoutOnlyErrors = [
  "Scrollbar's ScrollController",
  'ScrollController is attached to more than one ScrollPosition',
  'SliverGeometry is not valid',
];

Future<void> _pump(WidgetTester tester, Widget tab) async {
  final prev = FlutterError.onError;
  FlutterError.onError = (d) {
    final msg = d.exceptionAsString();
    if (_layoutOnlyErrors.any(msg.contains)) return;
    prev?.call(d);
  };
  addTearDown(() => FlutterError.onError = prev);
  tester.view.physicalSize = const Size(2200, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MaterialApp(home: Scaffold(body: tab)));
  await tester.pumpAndSettle();
  // Mở màn bộ lọc thu gọn thành một dòng — mở ra để chọn.
  await tester.tap(find.text('Bộ lọc').first);
  await tester.pumpAndSettle();
}

Future<void> _pickScope(WidgetTester tester, String label) async {
  await tester.tap(find.text('Đủ ngày trong kỳ').first);
  await tester.pumpAndSettle();
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}

final _desktop = TargetPlatformVariant.only(TargetPlatform.windows);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('Theo ca: đủ ngày trong kỳ ↔ chỉ ngày có chấm', variant: _desktop, (tester) async {
    await _pump(
      tester,
      AttendanceByShiftTab(
        attendances: _attendances,
        devices: const [],
        fromDate: _day(0),
        toDate: _day(6),
        dateRangePreset: 'lastWeek',
        employeesList: _employees,
        approvedLeaves: _leaves,
      ),
    );

    // Mặc định đủ ngày: 7 ngày, ngày nghỉ phép có dòng «Nghỉ phép», ngày thường không chấm là «Vắng».
    for (var i = 0; i < 7; i++) {
      expect(find.text(_label(i)), findsOneWidget, reason: _label(i));
    }
    expect(find.text('Nghỉ phép'), findsWidgets);
    expect(find.text('Vắng'), findsWidgets);
    // NV chưa đặt ngày nghỉ tuần: Chủ nhật không chấm là Vắng, không phải Nghỉ tuần.
    expect(find.text('Nghỉ tuần'), findsNothing);

    await _pickScope(tester, 'Chỉ ngày có chấm');
    expect(find.text(_label(0)), findsOneWidget);
    expect(find.text(_label(1)), findsOneWidget);
    for (var i = 2; i < 7; i++) {
      expect(find.text(_label(i)), findsNothing, reason: _label(i));
    }
    // Nhớ lựa chọn theo máy.
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('attendance_by_shift_day_scope_v1'), 'punchedOnly');
  });

  testWidgets('Theo ca: lọc «Thiếu chấm» khi đủ ngày không kéo dòng nghỉ phép vào', variant: _desktop, (tester) async {
    await _pump(
      tester,
      AttendanceByShiftTab(
        attendances: _attendances,
        devices: const [],
        fromDate: _day(0),
        toDate: _day(6),
        dateRangePreset: 'lastWeek',
        employeesList: _employees,
        approvedLeaves: _leaves,
      ),
    );
    await tester.tap(find.text('Tất cả trạng thái').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Thiếu chấm').last);
    await tester.pumpAndSettle();
    expect(find.text(_label(2)), findsNothing); // nghỉ phép
    expect(find.text(_label(0)), findsNothing); // chấm đủ
    expect(find.text(_label(3)), findsOneWidget); // vắng
  });

  testWidgets('Tổng hợp chấm công: đủ ngày trong kỳ ↔ chỉ ngày có chấm', variant: _desktop, (tester) async {
    await _pump(
      tester,
      AttendanceSummaryTab(
        attendances: _attendances,
        devices: const [],
        fromDate: _day(0),
        toDate: _day(6),
        dateRangePreset: 'lastWeek',
        employeesList: _employees,
        approvedLeaves: _leaves,
      ),
    );

    for (var i = 0; i < 7; i++) {
      expect(find.text(_label(i)), findsOneWidget, reason: _label(i));
    }
    // Ngày không chấm ghi rõ loại ở cột «Số công».
    expect(find.text('Nghỉ phép'), findsOneWidget);
    expect(find.text('Vắng'), findsWidgets);
    expect(find.text('Nghỉ tuần'), findsNothing);

    await _pickScope(tester, 'Chỉ ngày có chấm');
    expect(find.text(_label(0)), findsOneWidget);
    expect(find.text(_label(1)), findsOneWidget);
    for (var i = 2; i < 7; i++) {
      expect(find.text(_label(i)), findsNothing, reason: _label(i));
    }
    expect(find.text('Nghỉ phép'), findsNothing);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('attendance_summary_day_scope_v1'), 'punchedOnly');
  });

  testWidgets('Tổng hợp chấm công: giờ = ra − vào, không trừ nghỉ trưa, Tổng giờ = cộng Giờ ca', variant: _desktop,
      (tester) async {
    final shifts = <Map<String, dynamic>>[
      {'id': 'p9', 'name': 'P9', 'startTime': '09:00:00', 'endTime': '14:00:00'},
      {'id': 'g9c', 'name': 'G9C', 'startTime': '17:00:00', 'endTime': '22:00:00'},
    ];
    await _pump(
      tester,
      AttendanceSummaryTab(
        attendances: [
          _punch('b1', 0, 16, 59), _punch('b2', 0, 22, 24), // 5h25 (trước: Giờ ca 4h25 · Tổng 5h01)
          _punch('b3', 1, 8, 57), _punch('b4', 1, 14, 6), // 5h09
          _punch('b5', 1, 16, 58), _punch('b6', 1, 21, 11), // 4h13
        ],
        devices: const [],
        fromDate: _day(0),
        toDate: _day(6),
        dateRangePreset: 'lastWeek',
        employeesList: _employees,
        shiftTemplates: shifts,
        shiftSalaryLevels: [
          for (final s in shifts) <String, dynamic>{'shiftTemplateId': s['id'], 'employeeIds': ['e1']},
        ],
      ),
    );
    expect(find.text('5h25'), findsNWidgets(2)); // Giờ ca 1 + Tổng giờ
    expect(find.text('5h09'), findsOneWidget);
    expect(find.text('4h13'), findsNWidgets(2)); // Giờ ca 2 ngày 2 + dòng cộng NV
    expect(find.text('9h22'), findsOneWidget);
    expect(find.text('10h34'), findsOneWidget); // dòng cộng: Giờ ca 1
    expect(find.text('14h47'), findsOneWidget); // dòng cộng: Tổng giờ = 10h34 + 4h13
    expect(find.text('4h25'), findsNothing);
    expect(find.text('4h09'), findsNothing);
  });
}
