import 'package:flutter_test/flutter_test.dart';
import 'package:zkteco_flutter_client/models/attendance.dart';
import 'package:zkteco_flutter_client/utils/shift_records_calculator.dart';

Attendance _punch(int day, int h, int m) => Attendance(
      id: '$day-$h-$m',
      pin: '036',
      employeeId: '036',
      employeeName: 'Võ Thị Thiêng',
      attendanceTime: DateTime(2026, 9, day, h, m),
    );

void main() {
  final shift = <String, dynamic>{
    'id': 'p8',
    'name': 'CA P8',
    'startTime': '08:00:00',
    'endTime': '13:00:00',
    'lateGraceMinutes': 5,
    'earlyLeaveGraceMinutes': 5,
  };
  final levels = [
    <String, dynamic>{'shiftTemplateId': 'p8', 'employeeIds': ['036']},
  ];
  final atts = [
    _punch(22, 8, 7), _punch(22, 13, 4), // trễ 7P
    _punch(25, 8, 10), _punch(25, 12, 40), // trễ 10P, về sớm 20P
    _punch(24, 8, 3), _punch(24, 13, 5), // trong ân hạn
  ];

  test('Đi trễ / về sớm lấy đúng số của Tổng hợp theo ca', () {
    final from = DateTime(2026, 9, 1), to = DateTime(2026, 9, 30);
    final records = computeDailyShiftRecords(
        attendances: atts, fromDate: from, toDate: to, shiftTemplates: [shift], shiftSalaryLevels: levels);
    final entries = computeDailyShiftLateEntries(
        attendances: atts, fromDate: from, toDate: to, shiftTemplates: [shift], shiftSalaryLevels: levels);

    expect(entries.map((e) => (e.date.day, e.shiftName, e.lateMinutes, e.earlyMinutes)),
        [(25, 'CA P8', 10, 20), (22, 'CA P8', 7, 0)]);
    for (final r in records) {
      final mine = entries.where((e) => e.date == r.date);
      expect(mine.fold<int>(0, (s, e) => s + e.lateMinutes), r.lateMinutes);
      expect(mine.fold<int>(0, (s, e) => s + e.earlyMinutes), r.earlyMinutes);
    }
  });
}
