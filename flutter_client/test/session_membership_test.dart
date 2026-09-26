import 'package:flutter_test/flutter_test.dart';
import 'package:zkteco_flutter_client/models/pos_sell_industry.dart';

void main() {
  test('Thẻ tập theo thời gian: không giới hạn buổi, đếm lượt, hết hạn thì không trừ được', () {
    final active = PosSessionBalanceDto.fromJson({
      'id': 'a', 'customerId': 'c', 'packageName': 'Thẻ tháng',
      'totalSessions': 9999, 'remainingSessions': 9987,
      'expiresAt': DateTime.now().add(const Duration(days: 3)).toUtc().toIso8601String(),
    });
    expect(active.isUnlimited, isTrue);
    expect(active.canRedeem, isTrue);
    expect(active.remainLabel, 'Không giới hạn buổi · đã tập 12 lượt');
    expect(active.daysLeft, 3);

    final expired = PosSessionBalanceDto.fromJson({
      'id': 'b', 'customerId': 'c', 'packageName': 'Gói 10 buổi',
      'totalSessions': 10, 'remainingSessions': 4,
      'expiresAt': DateTime.now().subtract(const Duration(days: 1)).toUtc().toIso8601String(),
    });
    expect(expired.isUnlimited, isFalse);
    expect(expired.canRedeem, isFalse);
    expect(expired.remainLabel, 'Còn 4/10 · đã dùng 6');
  });
}
