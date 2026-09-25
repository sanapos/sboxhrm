import 'package:flutter_test/flutter_test.dart';
import 'package:zkteco_flutter_client/models/attendance.dart';
import 'package:zkteco_flutter_client/utils/shift_records_calculator.dart';

Attendance _punch(int h, int m, int state, {int day = 25}) => Attendance(
      id: '$day-$h-$m',
      attendanceTime: DateTime(2026, 9, day, h, m),
      attendanceState: state,
    );

List<(DateTime?, DateTime?)> _pairs(List<Attendance> a) => [
      for (final p in buildDayAttendancePairs(a)) (p.checkIn, p.checkOut),
    ];

void main() {
  test('máy gửi ngược loại (08:10 Ra, 13:10 Vào) → ghép theo thời gian', () {
    expect(_pairs([_punch(8, 10, 1), _punch(13, 10, 0)]), [
      (DateTime(2026, 9, 25, 8, 10), DateTime(2026, 9, 25, 13, 10)),
    ]);
    expect(
        _pairs([
          _punch(8, 0, 1),
          _punch(12, 0, 0),
          _punch(13, 0, 1),
          _punch(17, 0, 0),
        ]),
        [
          (DateTime(2026, 9, 25, 8), DateTime(2026, 9, 25, 12)),
          (DateTime(2026, 9, 25, 13), DateTime(2026, 9, 25, 17)),
        ]);
  });

  test('loại đúng vẫn ghép theo loại', () {
    expect(_pairs([_punch(8, 7, 0), _punch(13, 4, 1)]), [
      (DateTime(2026, 9, 25, 8, 7), DateTime(2026, 9, 25, 13, 4)),
    ]);
  });

  test('Ra lẻ đầu ngày (ra ca đêm trước) + ca mới vẫn giữ Ra riêng', () {
    expect(
        _pairs([_punch(6, 0, 1), _punch(18, 0, 0), _punch(22, 0, 1)]),
        [
          (null, DateTime(2026, 9, 25, 6)),
          (DateTime(2026, 9, 25, 18), DateTime(2026, 9, 25, 22)),
        ]);
  });
}
