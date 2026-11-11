import 'package:flutter_test/flutter_test.dart';
import 'package:zkteco_flutter_client/models/attendance.dart';
import 'package:zkteco_flutter_client/utils/shift_records_calculator.dart';

Attendance _punch(int day, int h, int m) => Attendance(
      id: '$day-$h-$m',
      pin: '07',
      employeeId: '07',
      employeeName: 'Dung',
      attendanceTime: DateTime(2026, 11, day, h, m),
    );

/// Vào trễ quá «Giới hạn đi trễ» (maximumAllowedLateMinutes) vẫn khớp ca và tính trễ đủ phút.
/// Trước đây lượt đó bị bỏ qua hẳn: người trễ 19 phút không bị tính, người trễ 14 phút lại bị tính.
void main() {
  final shift = <String, dynamic>{
    'id': 'hc',
    'name': 'Ca hành chính',
    'startTime': '08:00:00',
    'endTime': '17:00:00',
    'lateGraceMinutes': 5,
    'earlyLeaveGraceMinutes': 5,
    'maximumAllowedLateMinutes': 15,
  };
  final levels = [
    <String, dynamic>{'shiftTemplateId': 'hc', 'employeeIds': ['07']},
  ];
  final atts = [
    _punch(4, 8, 14), _punch(4, 17, 2), // trễ 14P (trong giới hạn)
    _punch(6, 8, 19), _punch(6, 16, 53), // trễ 19P (quá giới hạn 15P), về sớm 7P
    _punch(7, 10, 30), _punch(7, 17, 0), // trễ 150P — vẫn trong 180P từ giờ vào ca
  ];

  test('Trễ quá giới hạn vẫn tính đủ phút, giữ cả về sớm', () {
    final from = DateTime(2026, 11, 1), to = DateTime(2026, 11, 30);
    final entries = computeDailyShiftLateEntries(
        attendances: atts, fromDate: from, toDate: to, shiftTemplates: [shift], shiftSalaryLevels: levels);
    final byDay = {for (final e in entries) e.date.day: (e.lateMinutes, e.earlyMinutes)};
    expect(byDay[4], (14, 0));
    expect(byDay[6], (19, 7));
    expect(byDay[7], (150, 0));

    final records = computeDailyShiftRecords(
        attendances: atts, fromDate: from, toDate: to, shiftTemplates: [shift], shiftSalaryLevels: levels);
    final rec6 = records.firstWhere((r) => r.date.day == 6);
    expect(rec6.lateMinutes, 19);
    expect(rec6.earlyMinutes, 7);
  });
}
