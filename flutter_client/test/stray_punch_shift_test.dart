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

    // Số lần chấm chẵn lệch ca: quên vào sáng (11:30 ra sáng · 12:58 vào chiều) → không phải cặp «hợp lệ».
    final even = computeDailyShiftRecords(
            attendances: [_p(26, 11, 30), _p(26, 12, 58)],
            fromDate: from,
            toDate: to,
            shiftTemplates: [sang, chieu, toi],
            shiftSalaryLevels: levels)
        .single;
    expect(even.status, allOf(contains('Thiếu vào Ca sáng'), contains('Thiếu ra Ca chiều')));
    expect(even.workCount, 0);
    // Ngày bình thường số lần chấm chẵn không đổi.
    final normal = computeDailyShiftRecords(
            attendances: [_p(26, 7, 28), _p(26, 11, 31), _p(26, 12, 58), _p(26, 17, 3)],
            fromDate: from,
            toDate: to,
            shiftTemplates: [sang, chieu, toi],
            shiftSalaryLevels: levels)
        .single;
    expect((normal.status, normal.workCount), ('Hợp lệ', 1.0));

    // Chấm 2 lần đúng vai vào – ra, làm liền qua trưa (06:58 · 16:05): giữ một cặp, không tách thành hai ca thiếu.
    final longDay = computeDailyShiftRecords(
            attendances: [_p(25, 6, 58), _p(25, 16, 5)],
            fromDate: from,
            toDate: to,
            shiftTemplates: [sang, chieu, toi],
            shiftSalaryLevels: levels)
        .single;
    expect(longDay.status, isNot(contains('Thiếu')));
    expect(longDay.workCount, greaterThan(0));
  });

  test('Gán nhiều ca chồng giờ (ca để chọn): vào trễ không bị tách thành hai ca thiếu vào', () {
    Map<String, dynamic> st(String id, String s, String e) =>
        <String, dynamic>{'id': id, 'name': id, 'startTime': '$s:00', 'endTime': '$e:00'};
    final shifts = [
      st('C2', '14:00', '22:30'), st('G9C', '17:00', '22:00'), st('G9S', '10:00', '14:00'),
      st('P13', '13:00', '18:00'), st('P17', '17:00', '22:00'), st('S9', '09:00', '17:30'),
      st('P9', '09:00', '14:00'),
    ];
    final levels = [
      for (final s in shifts) <String, dynamic>{'shiftTemplateId': s['id'], 'employeeIds': ['A']},
    ];
    final rs = {
      for (final r in computeDailyShiftRecords(
          attendances: [
            _p(23, 17, 56), _p(23, 22, 39), // vào trễ 56p ca 17:00
            _p(19, 8, 59), _p(19, 14, 4), _p(19, 17, 58), _p(19, 22, 35), // ca 9h + ca tối vào trễ
            _p(16, 10, 0), _p(16, 17, 53), _p(16, 22, 31),
          ],
          fromDate: from,
          toDate: to,
          shiftTemplates: shifts,
          shiftSalaryLevels: levels))
        r.date.day: r,
    };
    final late = rs[23]!;
    expect(late.shiftNames, hasLength(1));
    expect(late.shiftNames.single, anyOf('G9C', 'P17'));
    expect(late.status, isNot(contains('Thiếu')));
    expect((late.lateMinutes, late.workCount > 0), (56, true));

    final two = rs[19]!;
    expect(two.shiftNames, hasLength(2));
    expect(two.shiftNames.first, 'P9');
    expect(two.status, isNot(contains('Thiếu')));
    expect(two.lateMinutes, 58);

    expect(rs[16]!.status, isNot(contains('Thiếu vào')));
    expect(rs[16]!.workCount, greaterThan(0));
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
