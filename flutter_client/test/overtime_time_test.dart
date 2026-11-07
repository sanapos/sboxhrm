import 'package:flutter_test/flutter_test.dart';
import 'package:zkteco_flutter_client/utils/overtime_time.dart';

void main() {
  test('giờ hợp lệ ra dạng HH:mm:ss', () {
    expect(normalizeOvertimeTime('18:00'), '18:00:00');
    expect(normalizeOvertimeTime(' 8:30 '), '08:30:00');
    expect(normalizeOvertimeTime('23:59:30'), '23:59:30');
  });

  test('giờ sai dạng trả null', () {
    for (final s in ['', '18', '24:00', '18:60', '1800', 'abc']) {
      expect(normalizeOvertimeTime(s), isNull, reason: s);
    }
  });
}
