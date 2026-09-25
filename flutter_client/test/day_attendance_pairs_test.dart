import 'package:flutter_test/flutter_test.dart';
import 'package:zkteco_flutter_client/models/attendance.dart';
import 'package:zkteco_flutter_client/utils/shift_records_calculator.dart';

Attendance _punch(int h, int m, int state) => Attendance(
      id: '$h-$m',
      attendanceTime: DateTime(2026, 9, 25, h, m),
      attendanceState: state,
    );

DateTime _t(int h, [int m = 0]) => DateTime(2026, 9, 25, h, m);

List<(DateTime?, DateTime?)> _pairs(List<Attendance> a) => [
      for (final p in buildDayAttendancePairs(a)) (p.checkIn, p.checkOut),
    ];

/// Ghép chỉ theo giờ chấm (1–2, 3–4…), bỏ qua loại Vào/Ra máy gửi.
void main() {
  test('máy gửi ngược loại (08:10 Ra, 13:10 Vào) vẫn là vào 08:10 – ra 13:10', () {
    expect(_pairs([_punch(13, 10, 0), _punch(8, 10, 1)]), [(_t(8, 10), _t(13, 10))]);
  });

  test('loại lộn xộn không ảnh hưởng: 4 lần chấm → 2 cặp theo giờ', () {
    expect(
        _pairs([_punch(8, 0, 0), _punch(12, 0, 0), _punch(13, 0, 1), _punch(17, 0, 1)]),
        [(_t(8), _t(12)), (_t(13), _t(17))]);
  });

  test('số lần chấm lẻ → lần cuối là vào thiếu ra; 1 lần «Ra» duy nhất = vào', () {
    expect(_pairs([_punch(6, 0, 1), _punch(18, 0, 0), _punch(22, 0, 1)]),
        [(_t(6), _t(18)), (_t(22), null)]);
    expect(_pairs([_punch(17, 0, 1)]), [(_t(17), null)]);
  });
}
