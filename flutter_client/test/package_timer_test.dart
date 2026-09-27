import 'package:flutter_test/flutter_test.dart';
import 'package:zkteco_flutter_client/widgets/pos/pos_package_timer.dart';

void main() {
  final start = DateTime.utc(2026, 9, 27, 20, 0);
  PosPackageTimerCalc calc({int total = 60, int pause = 0}) =>
      PosPackageTimerCalc(startedAt: start, totalMinutes: total, pauseMinutes: pause, alertBeforeMinutes: 5);

  test('Gói 1 giờ: đang chạy → sắp hết (5 phút cuối) → hết giờ, đếm quá giờ', () {
    expect(calc().stage(DateTime.utc(2026, 9, 27, 20, 30)), PosPackageTimerStage.running);
    expect(calc().stage(DateTime.utc(2026, 9, 27, 20, 56)), PosPackageTimerStage.soon);
    expect(calc().stage(DateTime.utc(2026, 9, 27, 21, 0)), PosPackageTimerStage.over);
    final over = calc().remaining(DateTime.utc(2026, 9, 27, 21, 5, 12))!;
    expect(PosPackageTimerCalc.fmt(over), '05:12');
    expect(over.isNegative, isTrue);
  });

  test('2 gói = 120 phút; phút tạm dừng cộng vào giờ hết', () {
    expect(calc(total: 120).endsAt, DateTime.utc(2026, 9, 27, 22, 0));
    expect(calc(pause: 10).endsAt, DateTime.utc(2026, 9, 27, 21, 10));
    expect(PosPackageTimerCalc.fmt(const Duration(hours: 1, minutes: 2, seconds: 3)), '1:02:03');
  });

  test('Chưa bấm bắt đầu', () {
    const c = PosPackageTimerCalc(startedAt: null, totalMinutes: 60);
    expect(c.stage(), PosPackageTimerStage.notStarted);
    expect(c.endsAt, isNull);
  });
}
