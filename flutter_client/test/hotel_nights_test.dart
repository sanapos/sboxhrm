import 'package:flutter_test/flutter_test.dart';
import 'package:zkteco_flutter_client/models/pos_sell_industry.dart';

/// Giờ Việt Nam → UTC (cùng bộ ca với PosHotelNightMathTests bên C#).
DateTime vn(int day, int h, [int m = 0]) =>
    DateTime.utc(2026, 9, day, h, m).subtract(const Duration(hours: 7));

void main() {
  const p = PosHotelStayPolicy();
  final cases = <(DateTime, DateTime, double)>[
    (vn(1, 14), vn(2, 11), 1.0),
    (vn(1, 22), vn(2, 12, 20), 1.0),
    (vn(1, 14), vn(2, 15), 1.5),
    (vn(1, 14), vn(2, 19), 2.0),
    (vn(1, 10), vn(2, 12), 1.5),
    (vn(1, 1), vn(1, 12), 1.0),
    (vn(1, 14), vn(4, 11), 3.0),
    (vn(1, 14), vn(1, 16), 1.0),
  ];
  test('Số đêm khách sạn khớp máy chủ', () {
    for (final (s, e, n) in cases) {
      expect(p.nights(s, e), n, reason: '$s → $e');
    }
  });
  test('Đọc giờ nhận / trả của cửa hàng', () {
    final c = PosHotelStayPolicy.parse(
        '{"hotel":{"checkIn":"13:00","checkOut":"11:00","lateHalfUntil":"17:00","graceMinutes":0}}');
    expect(c.nights(vn(1, 13), vn(2, 11, 30)), 1.5);
    expect(PosHotelStayPolicy.parse('{"hotel":{"nightMode":false}}').nightMode, isFalse);
  });
}
