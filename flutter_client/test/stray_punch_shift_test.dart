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
