import 'package:flutter_test/flutter_test.dart';
import 'package:sbox_pos/models/pos_sell_industry.dart';

void main() {
  double charge({
    required int elapsed,
    required PosServiceBillingMode mode,
    required double price,
    int? min,
    int? round,
    int? grace,
    int? roundAfter,
    double openingFee = 0,
    int? openingMinutes,
  }) {
    final billable = PosServiceBillingCalc.billableMinutes(
      elapsed: elapsed,
      mode: mode,
      minBillMinutes: min,
      billRoundMinutes: round,
      graceMinutes: grace,
      roundAfterMinutes: roundAfter,
    );
    return PosServiceBillingCalc.timedLineCharge(
      mode: mode,
      billableMinutes: billable,
      unitPrice: price,
      openingFee: openingFee,
      openingMinutes: openingMinutes,
      billRoundMinutes: round,
    );
  }

  test('karaoke theo giờ: min 1h, làm tròn 15p, ca 1p–7h', () {
    const price = 200000.0;
    const mode = PosServiceBillingMode.perHour;
    expect(charge(elapsed: 0, mode: mode, price: price, min: 60, round: 15), 0);
    expect(charge(elapsed: 1, mode: mode, price: price, min: 60, round: 15), 200000);
    expect(charge(elapsed: 61, mode: mode, price: price, min: 60, round: 15), 250000);
    expect(charge(elapsed: 420, mode: mode, price: price, min: 60, round: 15), 1400000);
    expect(charge(elapsed: 480, mode: mode, price: price, min: 60, round: 15), 1600000);
  });

  test('karaoke block 5p + phí mở gồm 30p', () {
    const mode = PosServiceBillingMode.perBlock;
    expect(
      charge(
        elapsed: 31,
        mode: mode,
        price: 10000,
        round: 5,
        openingFee: 50000,
        openingMinutes: 30,
      ),
      60000,
    );
  });

  test('grace không bị phút tối thiểu nuốt', () {
    expect(
      PosServiceBillingCalc.billableMinutes(
        elapsed: 8,
        mode: PosServiceBillingMode.perHour,
        minBillMinutes: 60,
        billRoundMinutes: 15,
        graceMinutes: 10,
      ),
      0,
    );
  });

  test('elapsed 7 giờ', () {
    final start = DateTime.utc(2026, 9, 18, 20);
    final end = DateTime.utc(2026, 9, 19, 3);
    expect(PosServiceBillingCalc.elapsedMinutes(start, end), 420);
  });
}
