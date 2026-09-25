import 'package:flutter_test/flutter_test.dart';
import 'package:zkteco_flutter_client/models/attendance.dart';
import 'package:zkteco_flutter_client/utils/schedule_compliance.dart';
import 'package:zkteco_flutter_client/utils/shift_records_calculator.dart';

Attendance _punch(int day, int h, int m) => Attendance(
      id: '$day-$h-$m',
      pin: '036',
      employeeId: '036',
      employeeName: 'Võ Thị Thiêng',
      attendanceTime: DateTime(2026, 9, day, h, m),
    );

Map<String, dynamic> _sched(int day, {String? shift = 'p8', bool off = false}) => {
      'employeeUserId': 'g1',
      'employeeCode': '036',
      'date': '2026-09-${day.toString().padLeft(2, '0')}T00:00:00',
      'shiftId': shift,
      'shiftName': shift == 'p8' ? 'CA P8' : 'CA P2',
      'isDayOff': off,
    };

void main() {
  test('Đối chiếu lịch với chấm công: đủ các trạng thái và tỷ lệ tuân thủ', () {
    final shifts = [
      {'id': 'p8', 'name': 'CA P8', 'startTime': '08:00:00', 'endTime': '13:00:00'},
      {'id': 'p2', 'name': 'CA P2', 'startTime': '14:00:00', 'endTime': '18:00:00'},
    ];
    final levels = [
      {'shiftTemplateId': 'p8', 'employeeIds': ['036']},
      {'shiftTemplateId': 'p2', 'employeeIds': ['036']},
    ];
    final atts = [
      _punch(21, 8, 0), _punch(21, 13, 0), // đúng lịch
      _punch(22, 8, 20), _punch(22, 13, 0), // trễ 20P
      _punch(23, 14, 0), _punch(23, 18, 0), // lịch P8 nhưng làm P2 → sai ca
      _punch(26, 8, 0), _punch(26, 13, 0), // không có lịch → ngoài lịch
      _punch(27, 8, 0), // thiếu giờ ra
    ];
    final from = DateTime(2026, 9, 21), to = DateTime(2026, 9, 27);
    final records = computeDailyShiftRecords(
      attendances: atts,
      fromDate: from,
      toDate: to,
      shiftTemplates: shifts,
      shiftSalaryLevels: levels,
    );
    final result = computeScheduleCompliance(
      schedules: [for (final d in [21, 22, 23, 24, 25, 27]) _sched(d)],
      records: records,
      employees: [
        {'id': 'g1', 'employeeCode': '036', 'pin': '036', 'lastName': 'Võ Thị', 'firstName': 'Thiêng', 'department': 'Bếp'},
      ],
      fromDate: from,
      toDate: to,
      isOnApprovedLeave: (guid, day) => guid == 'g1' && day.day == 25,
    );

    final byDay = {for (final r in result.rows) r.date.day: r};
    expect(byDay[21]!.status, ScheduleComplianceStatus.onTime);
    expect((byDay[22]!.status, byDay[22]!.lateMinutes), (ScheduleComplianceStatus.lateEarly, 20));
    expect((byDay[23]!.status, byDay[23]!.actualShift), (ScheduleComplianceStatus.wrongShift, 'CA P2'));
    expect(byDay[24]!.status, ScheduleComplianceStatus.absent);
    expect(byDay[25]!.status, ScheduleComplianceStatus.onLeave);
    expect(byDay[26]!.status, ScheduleComplianceStatus.offSchedule);
    expect(byDay[27]!.status, ScheduleComplianceStatus.missingOut);
    expect(result.rows.length, 7);

    final t = result.total;
    expect((t.scheduled, t.expected), (6, 5));
    expect(t.complianceRate, closeTo(0.2, 1e-9)); // 1 đúng lịch / 5 ca cần có mặt
    expect(t.attendanceRate, closeTo(0.8, 1e-9)); // 1 vắng / 5
    expect(result.byEmployee.single.label, 'Võ Thị Thiêng');
    expect(result.byDepartment.single.label, 'Bếp');
  });

  test('Nhân viên không có lịch trong kỳ → không báo đi làm ngoài lịch', () {
    final records = computeDailyShiftRecords(
      attendances: [_punch(21, 8, 0), _punch(21, 13, 0)],
      fromDate: DateTime(2026, 9, 21),
      toDate: DateTime(2026, 9, 21),
    );
    final result = computeScheduleCompliance(
      schedules: const [],
      records: records,
      employees: [{'id': 'g1', 'employeeCode': '036'}],
      fromDate: DateTime(2026, 9, 21),
      toDate: DateTime(2026, 9, 21),
    );
    expect(result.rows, isEmpty);
  });
}
