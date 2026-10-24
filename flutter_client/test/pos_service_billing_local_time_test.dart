import 'package:flutter_test/flutter_test.dart';
import 'package:zkteco_flutter_client/models/pos_sell_industry.dart';

void main() {
  test('giờ mở phòng dạng giờ máy (không UTC) vẫn tính đúng phút', () {
    // Phòng mở 2 giờ trước, giờ bắt đầu ở dạng giờ máy (như khi đọc từ sơ đồ phòng).
    final startLocal = DateTime.now().subtract(const Duration(minutes: 120));
    expect(startLocal.isUtc, isFalse);
    final elapsed = PosServiceBillingCalc.elapsedMinutes(startLocal, null);
    expect(elapsed, inInclusiveRange(120, 121));

    final billable = PosServiceBillingCalc.billableMinutes(
      elapsed: 120,
      mode: PosServiceBillingMode.perHour,
      billRoundMinutes: 5,
    );
    final charge = PosServiceBillingCalc.timedLineCharge(
      mode: PosServiceBillingMode.perHour,
      billableMinutes: billable,
      unitPrice: 60000,
      openingFee: 30000,
      openingMinutes: 30,
      billRoundMinutes: 5,
    );
    // 30 phút đầu 30.000 + 90 phút × 60.000 / giờ = 120.000.
    expect(charge.round(), 120000);
  });

  test('85 phút × 60.000 / giờ ra đúng 85.000', () {
    final charge = PosServiceBillingCalc.timedLineCharge(
      mode: PosServiceBillingMode.perHour,
      billableMinutes: 85,
      unitPrice: 60000,
      billRoundMinutes: 5,
    );
    expect(charge.round(), 85000);
  });
}
