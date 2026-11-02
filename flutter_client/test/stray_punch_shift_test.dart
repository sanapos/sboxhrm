import 'package:flutter_test/flutter_test.dart';
import 'package:zkteco_flutter_client/models/attendance.dart';
import 'package:zkteco_flutter_client/utils/shift_records_calculator.dart';

Attendance _p(int d, int h, int m) => Attendance(
      id: '$d-$h-$m',
      pin: 'A',
      employeeId: 'A',
      employeeName: 'A',
      attendanceTime: DateTime(2026, 10, d, h, m),
    );

void main() {
  final from = DateTime(2026, 10, 1), to = DateTime(2026, 10, 31);

  test('Ca sáng + ca chiều: một lần chấm lẻ / bấm trùng không làm lệch các cặp sau', () {
    final sang = <String, dynamic>{'id': 's', 'name': 'Ca sáng', 'startTime': '08:00:00', 'endTime': '11:30:00'};
    final chieu = <String, dynamic>{'id': 'c', 'name': 'Ca chiều', 'startTime': '13:00:00', 'endTime': '17:00:00'};
    final levels = [
      <String, dynamic>{'shiftTemplateId': 's', 'employeeIds': ['A']},
      <String, dynamic>{'shiftTemplateId': 'c', 'employeeIds': ['A']},
    ];
    final atts = [
      _p(20, 8, 8), _p(20, 11, 31), _p(20, 12, 38), _p(20, 17, 11), _p(20, 18, 2), // chấm thêm 18:02
      _p(19, 8, 5), _p(19, 11, 33), _p(19, 13, 0), _p(19, 17, 17), _p(19, 17, 19), // bấm trùng 17:17 / 17:19
      _p(17, 8, 2), _p(17, 11, 1), _p(17, 12, 17), _p(17, 12, 58), _p(17, 17, 0), // chấm thêm 12:17
      _p(9, 8, 0), _p(9, 11, 30), _p(9, 17, 0), // thiếu vào chiều → vẫn báo thiếu
    ];
    final rs = {
      for (final r in computeDailyShiftRecords(
          attendances: atts, fromDate: from, toDate: to, shiftTemplates: [sang, chieu], shiftSalaryLevels: levels))
        r.date.day: r,
    };
    for (final d in [17, 19, 20]) {
      expect(rs[d]!.status, isNot(contains('Thiếu')), reason: 'ngày $d');
      expect(rs[d]!.workCount, 1.0, reason: 'ngày $d');
    }
    expect(rs[17]!.earlyMinutes, 29);
    expect(rs[20]!.lateMinutes, 8);
    expect(rs[9]!.status, contains('Thiếu'));

    // Gán kèm ca qua đêm (bậc lương ca «Qua đêm» 22:00–03:00) — vẫn ghép theo ca sáng / chiều.
    final qd = <String, dynamic>{'id': 'q', 'name': 'Qua đêm', 'startTime': '22:00:00', 'endTime': '03:00:00'};
    final withNight = {
      for (final r in computeDailyShiftRecords(
          attendances: atts,
          fromDate: from,
          toDate: to,
          shiftTemplates: [sang, chieu, qd],
          shiftSalaryLevels: [...levels, <String, dynamic>{'shiftTemplateId': 'q', 'employeeIds': ['A']}]))
        r.date.day: r,
    };
    expect((withNight[17]!.workCount, withNight[17]!.earlyMinutes), (1.0, 29));
    expect(withNight[19]!.status, isNot(contains('Thiếu')));
  });

  test('Ca sáng + ca chiều thiếu lần ra sáng: không tính 07:26–12:59 là tăng ca đủ công', () {
    final sang = <String, dynamic>{'id': 's', 'name': 'Ca sáng', 'startTime': '07:30:00', 'endTime': '11:30:00'};
    final chieu = <String, dynamic>{'id': 'c', 'name': 'Ca chiều', 'startTime': '13:00:00', 'endTime': '17:00:00'};
    final levels = [
      <String, dynamic>{'shiftTemplateId': 's', 'employeeIds': ['A']},
      <String, dynamic>{'shiftTemplateId': 'c', 'employeeIds': ['A']},
    ];
    final r = computeDailyShiftRecords(
            attendances: [_p(28, 7, 26), _p(28, 12, 59), _p(28, 17, 4)],
            fromDate: from,
            toDate: to,
            shiftTemplates: [sang, chieu],
            shiftSalaryLevels: levels)
        .single;
    expect((r.overtimeMinutes, r.workCount), (0, 0.5));
    expect(r.workHours, closeTo(4.0, 0.01));
    expect(r.status, contains('Thiếu ra'));
  });

  test('Gán 3 ca (sáng, chiều, tối) thiếu vào chiều: 17:05 là ra ca chiều, không phải vào Ca Tối', () {
    final sang = <String, dynamic>{'id': 's', 'name': 'Ca sáng', 'startTime': '07:30:00', 'endTime': '11:30:00'};
    final chieu = <String, dynamic>{'id': 'c', 'name': 'Ca chiều', 'startTime': '13:00:00', 'endTime': '17:00:00'};
    final toi = <String, dynamic>{'id': 't', 'name': 'Ca Tối', 'startTime': '17:00:00', 'endTime': '22:00:00'};
    final levels = [
      for (final id in ['s', 'c', 't']) <String, dynamic>{'shiftTemplateId': id, 'employeeIds': ['A']},
    ];
    final atts = [_p(27, 7, 30), _p(27, 11, 30), _p(27, 17, 5)];
    final r = computeDailyShiftRecords(
            attendances: atts, fromDate: from, toDate: to, shiftTemplates: [sang, chieu, toi], shiftSalaryLevels: levels)
        .single;
    expect(r.shiftNames, ['Ca sáng', 'Ca chiều']);
    expect(r.status, contains('Thiếu vào Ca chiều'));
    expect((r.workCount, r.overtimeMinutes), (0.5, 0));
    // Bảng lương theo ca: ca chiều chỉ có giờ ra → không tính giờ.
    final ps = computeDailyShiftPairs(
        attendances: atts, fromDate: from, toDate: to, shiftTemplates: [sang, chieu, toi], shiftSalaryLevels: levels);
    expect(ps.fold<double>(0, (t, p) => t + dailyShiftPairWorkHours(p)), closeTo(4.0, 0.01));

    // 2 ca/ngày đã đủ sáng + chiều, 18:02 rơi vào Ca Tối gán kèm → chấm thừa, không «thiếu ra Ca Tối».
    final perDay2 = computeDailyShiftRecords(
      attendances: [_p(30, 7, 35), _p(30, 11, 31), _p(30, 12, 38), _p(30, 17, 11), _p(30, 18, 2)],
      fromDate: from,
      toDate: to,
      shiftTemplates: [sang, chieu, toi],
      shiftSalaryLevels: levels,
      salaryProfiles: [
        {
          'shiftsPerDay': 2,
          'employees': [{'id': 'A', 'employeeCode': 'A'}],
        }
      ],
    ).single;
    expect(perDay2.status, isNot(contains('Thiếu')));
    expect(perDay2.workCount, 1.0);
    expect(perDay2.shiftNames, ['Ca sáng', 'Ca chiều']);
  });

  test('Ca có nghỉ trưa chấm 5 lần: bỏ lần chấm lẻ giữa trưa', () {
    final hc = <String, dynamic>{
      'id': 'hc', 'name': 'HC', 'startTime': '08:00:00', 'endTime': '17:00:00',
      'lunchBreakStartTime': '12:00:00', 'lunchBreakEndTime': '13:00:00',
    };
    final levels = [<String, dynamic>{'shiftTemplateId': 'hc', 'employeeIds': ['A']}];
    final atts = [_p(5, 7, 56), _p(5, 12, 2), _p(5, 12, 30), _p(5, 12, 58), _p(5, 17, 3)];
    final r = computeDailyShiftRecords(
            attendances: atts, fromDate: from, toDate: to, shiftTemplates: [hc], shiftSalaryLevels: levels)
        .single;
    expect((r.lateMinutes, r.earlyMinutes, r.workHours, r.workCount), (0, 0, 8.0, 1.0));
    expect(r.status, isNot(contains('Thiếu')));
  });
}
