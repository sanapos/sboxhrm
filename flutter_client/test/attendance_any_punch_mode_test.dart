import 'package:flutter_test/flutter_test.dart';
import 'package:zkteco_flutter_client/models/attendance.dart';
import 'package:zkteco_flutter_client/utils/shift_records_calculator.dart';

/// «Chấm bất kỳ trong ca» (attendanceMode = any): một lần chấm trong khung ca = đủ ca.
/// Dữ liệu theo một nhân viên thật: 5 ca, mỗi ngày chấm 1 lần ở giữa ca.
Attendance _p(int m, int d, int h, int mi) => Attendance(
      id: '$m-$d-$h-$mi', pin: 'NV01', employeeId: 'NV01', employeeName: 'NV01',
      attendanceTime: DateTime(2026, m, d, h, mi));

Map<String, dynamic> _sh(String id, String name, String s, String e, [String type = 'Hành chính']) => {
      'id': id, 'name': name, 'startTime': s, 'endTime': e, 'shiftType': type,
      'lateGraceMinutes': 5, 'earlyLeaveGraceMinutes': 5, 'earlyCheckInMinutes': 30,
      'maximumAllowedLateMinutes': 30, 'breakTimeMinutes': 30, 'isActive': true,
    };

final _shifts = [
  _sh('sang', 'Ca sáng', '07:30:00', '11:30:00'),
  _sh('chieu', 'Ca chiều', '13:00:00', '17:00:00'),
  _sh('toi', 'Ca Tối', '17:00:00', '22:00:00'),
  _sh('dem', 'Qua đêm', '22:00:00', '03:00:00', 'Qua đêm'),
  _sh('hc', 'Hành chính', '07:00:00', '16:00:00'),
];

List<DailyShiftRecord> _run(String mode, List<Attendance> atts, {int shiftsPerDay = 1}) => computeDailyShiftRecords(
      attendances: atts,
      fromDate: DateTime(2026, 9, 25),
      toDate: DateTime(2026, 10, 10),
      shiftTemplates: _shifts,
      salaryProfiles: [
        {
          'id': 'b1', 'rateType': 'Monthly', 'rate': 8000000, 'attendanceMode': mode,
          'shiftsPerDay': shiftsPerDay,
          'description': 'attendanceType:$mode|shifts:Hành chính, Qua đêm, Ca Tối, Ca chiều, Ca sáng'
              '|shiftsPerDay:$shiftsPerDay|hoursPerWorkDay:8',
          'employees': [{'id': 'e1', 'employeeCode': 'NV01'}],
        }
      ],
      employeesList: [{'id': 'e1', 'employeeCode': 'NV01', 'fullName': 'NV01'}],
    );

void main() {
  test('Một lần chấm giữa ca = đủ ca, không đi trễ (trước đây 0 công «Thiếu chấm»)', () {
    final recs = _run('any', [_p(9, 25, 9, 40), _p(9, 27, 6, 57), _p(10, 4, 9, 20)]);
    expect(recs, hasLength(3));
    for (final r in recs) {
      expect(r.workCount, 1.0, reason: '${r.date}');
      expect(r.lateMinutes, 0);
      expect(r.earlyMinutes, 0);
      expect(r.status, 'Hợp lệ');
      expect(r.shiftNames, ['Hành chính']); // ca xếp đầu trong thiết lập lương được ưu tiên
    }
  });

  test('Chấm ngoài ca đầu → ca khác chứa giờ chấm', () {
    final r = _run('any', [_p(10, 1, 16, 18)]).single; // sau 16:00 hành chính → ca chiều 13–17
    expect(r.shiftNames, ['Ca chiều']);
    expect(r.workCount, 0.5);
    expect(r.lateMinutes, 0);
  });

  test('Nhiều lần chấm trong cùng ca chỉ tính một ca; tối đa số ca / ngày', () {
    expect(_run('any', [_p(9, 26, 8, 0), _p(9, 26, 12, 0), _p(9, 26, 15, 50)]).single.workCount, 1.0);
    final two = _run('any', [_p(9, 26, 7, 35), _p(9, 26, 18, 0)], shiftsPerDay: 2).single;
    expect(two.shiftNames.toSet(), {'Hành chính', 'Ca Tối'});
  });

  test('Chấm vào: lần chấm sau giờ hết ca không đẩy giờ ra sang hôm sau / không trễ ảo', () {
    final r = _run('checkin', [_p(10, 1, 16, 18)]).firstWhere((x) => x.shiftNames.contains('Hành chính'));
    expect(r.workHours, lessThan(1)); // trước đây 23,2 giờ
    expect(r.lateMinutes, 0); // trước đây 558 phút
  });
}
