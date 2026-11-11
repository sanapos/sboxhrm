import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zkteco_flutter_client/models/attendance.dart';
import 'package:zkteco_flutter_client/screens/attendance/attendance_by_shift_tab.dart';

// Ca sáng 07:00–11:00 + ca chiều 13:00–17:00. T2 chỉ làm chiều, T3 làm cả ngày.
final _today = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);
final _mon = _today.subtract(Duration(days: _today.weekday - 1 + 7));
DateTime _day(int i) => DateTime(_mon.year, _mon.month, _mon.day + i);

Attendance _punch(String id, int i, int h, int m) => Attendance(
      id: id,
      pin: '40001',
      employeeId: 'e1', // GUID nhân viên như dữ liệu thật
      employeeName: 'Nguyễn Văn A',
      attendanceTime: DateTime(_day(i).year, _day(i).month, _day(i).day, h, m),
    );

final _shifts = <Map<String, dynamic>>[
  {'id': 'sang', 'name': 'Ca sáng', 'startTime': '07:00:00', 'endTime': '11:00:00'},
  {'id': 'chieu', 'name': 'Ca chiều', 'startTime': '13:00:00', 'endTime': '17:00:00'},
];

const _layoutOnlyErrors = [
  "Scrollbar's ScrollController",
  'ScrollController is attached to more than one ScrollPosition',
  'SliverGeometry is not valid',
];

Future<void> _pump(
  WidgetTester tester, {
  Map<String, List<int>>? punchSlots,
  List<String> assignedShiftIds = const ['sang', 'chieu'],
  List<Map<String, dynamic>>? shifts,
  List<Map<String, dynamic>> salaryProfiles = const [],
}) async {
  final prev = FlutterError.onError;
  FlutterError.onError = (d) {
    if (_layoutOnlyErrors.any(d.exceptionAsString().contains)) return;
    prev?.call(d);
  };
  addTearDown(() => FlutterError.onError = prev);
  tester.view.physicalSize = const Size(2400, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: AttendanceByShiftTab(
        attendances: [
          _punch('c1', 0, 13, 2), _punch('c2', 0, 17, 1),
          _punch('c3', 1, 6, 58), _punch('c4', 1, 11, 3),
          _punch('c5', 1, 12, 57), _punch('c6', 1, 17, 4),
        ],
        devices: const [],
        fromDate: _day(0),
        toDate: _day(6),
        dateRangePreset: 'lastWeek',
        employeesList: const [
          {'id': 'e1', 'employeeCode': '40001', 'pin': '40001', 'fullName': 'Nguyễn Văn A'},
        ],
        shiftTemplates: shifts ?? _shifts,
        salaryProfiles: salaryProfiles,
        initialPunchSlots: punchSlots ?? const {},
        shiftSalaryLevels: [
          for (final id in assignedShiftIds) <String, dynamic>{'shiftTemplateId': id, 'employeeIds': ['e1']},
        ],
      ),
    ),
  ));
  await tester.pumpAndSettle();
  // Mở màn bộ lọc thu gọn thành một dòng — mở ra để chọn cách xếp giờ chấm.
  await tester.tap(find.text('Bộ lọc').first);
  await tester.pumpAndSettle();
}

/// Cột «Lần n» chứa giờ [hm] (so tâm ngang ô giờ với tiêu đề cột).
int _columnOf(WidgetTester tester, String hm) {
  final x = tester.getCenter(find.text(hm).first).dx;
  for (var n = 1; n <= 8; n++) {
    final h = find.text('Lần $n');
    if (h.evaluate().isEmpty) break;
    if ((tester.getCenter(h.first).dx - x).abs() < 30) return n;
  }
  return -1;
}

final _desktop = TargetPlatformVariant.only(TargetPlatform.windows);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('Giờ chấm theo ca: chỉ làm chiều → Lần 3–4; làm cả ngày giữ Lần 1–4', variant: _desktop, (tester) async {
    await _pump(tester);

    // Mặc định theo thứ tự: giờ đầu tiên của ngày ở Lần 1.
    expect(_columnOf(tester, '13:02'), 1);
    expect(_columnOf(tester, '17:01'), 2);

    await tester.tap(find.text('Giờ chấm theo thứ tự').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Giờ chấm theo ca').last);
    await tester.pumpAndSettle();

    expect(_columnOf(tester, '13:02'), 3);
    expect(_columnOf(tester, '17:01'), 4);
    expect(_columnOf(tester, '06:58'), 1);
    expect(_columnOf(tester, '11:03'), 2);
    expect(_columnOf(tester, '12:57'), 3);
    expect(_columnOf(tester, '17:04'), 4);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('attendance_by_shift_punch_layout_v1'), 'byShift');
  });

  testWidgets('Nhớ lựa chọn «Giờ chấm theo ca» khi mở lại', variant: _desktop, (tester) async {
    SharedPreferences.setMockInitialValues({'attendance_by_shift_punch_layout_v1': 'byShift'});
    await _pump(tester);
    expect(find.text('Giờ chấm theo ca'), findsWidgets);
    expect(_columnOf(tester, '13:02'), 3);
  });

  testWidgets('Chưa thiết lập: NV chỉ gán ca chiều → ca chiều là ca thứ nhất của NV, nằm ở Lần 1–2', variant: _desktop, (tester) async {
    SharedPreferences.setMockInitialValues({'attendance_by_shift_punch_layout_v1': 'byShift'});
    await _pump(tester, assignedShiftIds: const ['chieu']);
    expect(_columnOf(tester, '13:02'), 1);
    expect(_columnOf(tester, '17:01'), 2);
  });

  testWidgets('Có thiết lập: ca chiều luôn ở Lần 3–4, kể cả NV chỉ gán ca chiều', variant: _desktop, (tester) async {
    SharedPreferences.setMockInitialValues({'attendance_by_shift_punch_layout_v1': 'byShift'});
    await _pump(
      tester,
      assignedShiftIds: const ['chieu'],
      punchSlots: const {'sang': [1, 2], 'chieu': [3, 4]},
    );
    expect(_columnOf(tester, '13:02'), 3);
    expect(_columnOf(tester, '17:01'), 4);
  });

  testWidgets('Có thiết lập: ca sáng vào Lần 1, ra Lần 4; ca chiều Lần 5–6', variant: _desktop, (tester) async {
    SharedPreferences.setMockInitialValues({'attendance_by_shift_punch_layout_v1': 'byShift'});
    await _pump(tester, punchSlots: const {'sang': [1, 4], 'chieu': [5, 6]});
    expect(_columnOf(tester, '06:58'), 1);
    expect(_columnOf(tester, '11:03'), 4);
    expect(_columnOf(tester, '12:57'), 5);
    expect(_columnOf(tester, '17:04'), 6);
    expect(_columnOf(tester, '13:02'), 5);
    expect(_columnOf(tester, '17:01'), 6);
  });

  testWidgets('Có thiết lập: làm ca không được gán vẫn vào đúng lần của ca khớp giờ', variant: _desktop, (tester) async {
    SharedPreferences.setMockInitialValues({'attendance_by_shift_punch_layout_v1': 'byShift'});
    // Chỉ gán ca sáng nhưng T2 làm chiều 13:02–17:01, T3 làm cả hai ca.
    await _pump(tester, assignedShiftIds: const ['sang'], punchSlots: const {'sang': [1, 2], 'chieu': [5, 6]});
    expect(_columnOf(tester, '06:58'), 1);
    expect(_columnOf(tester, '11:03'), 2);
    expect(_columnOf(tester, '12:57'), 5);
    expect(_columnOf(tester, '17:04'), 6);
  });

  testWidgets('Có thiết lập: 1 ca/ngày, đi trễ quá mức cho phép nên sáng là «ca khác» → vẫn đủ Lần 1–4', variant: _desktop, (tester) async {
    SharedPreferences.setMockInitialValues({'attendance_by_shift_punch_layout_v1': 'byShift'});
    await _pump(
      tester,
      shifts: const [
        // Vào 06:50, cho trễ tối đa 1 phút: 06:58 không khớp ca sáng, hệ thống chỉ nhận ca chiều.
        {'id': 'sang', 'name': 'Ca sáng', 'startTime': '06:50:00', 'endTime': '11:00:00', 'maximumAllowedLateMinutes': 1},
        {'id': 'chieu', 'name': 'Ca chiều', 'startTime': '13:00:00', 'endTime': '17:00:00', 'maximumAllowedLateMinutes': 1},
      ],
      salaryProfiles: const [
        {
          'shiftsPerDay': 1,
          'employees': [
            {'id': 'e1', 'employeeCode': '40001'},
          ],
        },
      ],
      punchSlots: const {'sang': [1, 2], 'chieu': [3, 4]},
    );
    expect(_columnOf(tester, '06:58'), 1);
    expect(_columnOf(tester, '11:03'), 2);
    expect(_columnOf(tester, '12:57'), 3);
    expect(_columnOf(tester, '17:04'), 4);
  });

  testWidgets('Thiết lập chỉ áp dụng khi chọn «Giờ chấm theo ca»', variant: _desktop, (tester) async {
    await _pump(tester, punchSlots: const {'sang': [1, 2], 'chieu': [5, 6]});
    expect(_columnOf(tester, '13:02'), 1);
    expect(_columnOf(tester, '17:01'), 2);
  });
}
