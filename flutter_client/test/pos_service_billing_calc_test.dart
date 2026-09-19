import 'package:flutter_test/flutter_test.dart';
import 'package:zkteco_flutter_client/models/pos_sell_industry.dart';

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
    expect(charge(elapsed: 59, mode: mode, price: price, min: 60, round: 15), 200000);
    expect(charge(elapsed: 60, mode: mode, price: price, min: 60, round: 15), 200000);
    expect(charge(elapsed: 61, mode: mode, price: price, min: 60, round: 15), 250000);
    expect(charge(elapsed: 90, mode: mode, price: price, min: 60, round: 15), 300000);
    expect(charge(elapsed: 180, mode: mode, price: price, min: 60, round: 15), 600000);
    expect(charge(elapsed: 420, mode: mode, price: price, min: 60, round: 15), 1400000);
    expect(charge(elapsed: 480, mode: mode, price: price, min: 60, round: 15), 1600000);
  });

  test('karaoke giờ: phí mở 30p + min 1h', () {
    expect(
      charge(
        elapsed: 1,
        mode: PosServiceBillingMode.perHour,
        price: 200000,
        min: 60,
        round: 15,
        openingFee: 80000,
        openingMinutes: 30,
      ),
      180000,
    );
  });

  test('theo giờ prorata không min không round', () {
    final billable = PosServiceBillingCalc.billableMinutes(
      elapsed: 31,
      mode: PosServiceBillingMode.perHour,
    );
    final qty = PosServiceBillingCalc.billableQty(
      mode: PosServiceBillingMode.perHour,
      billableMinutes: billable,
      fallbackQty: 0,
    );
    expect(billable, 31);
    expect(qty, 0.5167);
    expect(
      PosServiceBillingCalc.timedLineCharge(
        mode: PosServiceBillingMode.perHour,
        billableMinutes: billable,
        unitPrice: 120000,
      ),
      62004,
    );
  });

  test('karaoke block 5p + phí mở gồm 30p', () {
    const mode = PosServiceBillingMode.perBlock;
    expect(
      charge(
        elapsed: 0,
        mode: mode,
        price: 10000,
        round: 5,
        openingFee: 50000,
        openingMinutes: 30,
      ),
      50000,
    );
    expect(
      charge(
        elapsed: 30,
        mode: mode,
        price: 10000,
        round: 5,
        openingFee: 50000,
        openingMinutes: 30,
      ),
      50000,
    );
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
    expect(
      charge(
        elapsed: 36,
        mode: mode,
        price: 10000,
        round: 5,
        openingFee: 50000,
        openingMinutes: 30,
      ),
      70000,
    );
  });

  test('block lẻ sau phút mở — làm tròn lên nguyên block', () {
    final billable = PosServiceBillingCalc.billableMinutes(
      elapsed: 45,
      mode: PosServiceBillingMode.perBlock,
      billRoundMinutes: 15,
    );
    final qty = PosServiceBillingCalc.extraQty(
      mode: PosServiceBillingMode.perBlock,
      billableMinutes: billable,
      openingMinutes: 20,
      billRoundMinutes: 15,
    );
    expect(qty, 2);
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
    expect(
      charge(
        elapsed: 11,
        mode: PosServiceBillingMode.perHour,
        price: 200000,
        min: 60,
        round: 15,
        grace: 10,
      ),
      200000,
    );
  });

  test('elapsed 7 giờ + pause đang mở', () {
    final start = DateTime.utc(2026, 9, 18, 20);
    final end = DateTime.utc(2026, 9, 19, 3);
    expect(PosServiceBillingCalc.elapsedMinutes(start, end), 420);

    final sessionStart = DateTime.utc(2026, 9, 18, 10);
    final sessionEnd = sessionStart.add(const Duration(hours: 1, seconds: 1));
    final paused = sessionEnd.subtract(const Duration(minutes: 10, seconds: 30));
    expect(
      PosServiceBillingCalc.elapsedMinutes(
        sessionStart,
        sessionEnd,
        pausedAt: paused,
      ),
      50,
    );
  });

  test('KS theo ngày', () {
    expect(
      PosServiceBillingCalc.billableQty(
        mode: PosServiceBillingMode.perDay,
        billableMinutes: PosServiceBillingCalc.billableMinutes(
          elapsed: 1441,
          mode: PosServiceBillingMode.perDay,
        ),
        fallbackQty: 1,
      ),
      2,
    );
  });
}
