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
  final shift = <String, dynamic>{
    'id': 'hc',
    'name': 'HC',
    'startTime': '08:00:00',
    'endTime': '17:00:00',
    'lunchBreakStartTime': '12:00:00',
    'lunchBreakEndTime': '13:00:00',
  };
  final levels = [
    <String, dynamic>{'shiftTemplateId': 'hc', 'employeeIds': ['A']},
  ];
  final atts = [
    _p(5, 7, 56), _p(5, 12, 2), _p(5, 12, 58), _p(5, 17, 3), // đủ 4 lần
    _p(13, 7, 58), _p(13, 11, 40), _p(13, 13, 30), _p(13, 17, 0), // ra trưa sớm 20P, vào lại trễ 30P
    _p(10, 8, 0), _p(10, 11, 30), // chỉ làm sáng
    _p(7, 7, 45), _p(7, 12, 55), _p(7, 17, 1), // thiếu 1 lần chấm trưa
    _p(8, 8, 2), _p(8, 11, 30), _p(8, 17, 10), // ra trưa sớm 30P, thiếu vào lại
    _p(6, 12, 57), _p(6, 17, 5), // chỉ làm chiều
    _p(9, 13, 20), _p(9, 17, 0), // chỉ làm chiều, vào trễ 20P
  ];
  final from = DateTime(2026, 10, 1), to = DateTime(2026, 10, 31);

  test('Ca có nghỉ trưa chấm 4 lần: một ca, không «về sớm» từ giờ ra trưa', () {
    final rs = {
      for (final r in computeDailyShiftRecords(
          attendances: atts, fromDate: from, toDate: to, shiftTemplates: [shift], shiftSalaryLevels: levels))
        r.date.day: r,
    };
    expect((rs[5]!.lateMinutes, rs[5]!.earlyMinutes, rs[5]!.workHours, rs[5]!.workCount), (0, 0, 8.0, 1.0));
    expect((rs[13]!.lateMinutes, rs[13]!.earlyMinutes), (30, 20));
    expect(rs[13]!.workHours, closeTo(7.2, 0.01));
    expect(rs[10]!.earlyMinutes, 330);
    // Chấm 3 lần: không «về sớm» tới hết ca, giữ công nửa ngày và báo thiếu chấm như cũ.
    expect((rs[7]!.earlyMinutes, rs[7]!.workCount), (0, 0.5));
    expect(rs[7]!.workHours, closeTo(4.25, 0.01));
    expect(rs[7]!.status, contains('Thiếu'));
    expect((rs[8]!.earlyMinutes, rs[8]!.workCount), (30, 0.5));
    // Chỉ làm chiều: nhận đúng ca, đi trễ tính từ hết giờ nghỉ trưa, nửa công.
    expect(rs[6]!.shiftNames, ['HC']);
    expect((rs[6]!.lateMinutes, rs[6]!.earlyMinutes, rs[6]!.workCount), (0, 0, 0.5));
    expect(rs[6]!.workHours, closeTo(4.08, 0.01));
    expect((rs[9]!.lateMinutes, rs[9]!.workCount), (20, 0.5));
  });

  test('Cặp ca (bảng lương theo ca) gộp sáng – chiều, giờ làm trừ thời gian ra ngoài', () {
    final ps = computeDailyShiftPairs(
        attendances: atts, fromDate: from, toDate: to, shiftTemplates: [shift], shiftSalaryLevels: levels);
    final d5 = ps.where((p) => p.date.day == 5).toList();
    expect(d5, hasLength(1));
    expect((d5.single.lateMinutes, d5.single.earlyMinutes), (0, 0));
    expect(dailyShiftPairWorkHours(d5.single), closeTo(8.18, 0.01));
    final d13 = ps.singleWhere((p) => p.date.day == 13);
    expect((d13.lateMinutes, d13.earlyMinutes), (30, 20));
  });
}
