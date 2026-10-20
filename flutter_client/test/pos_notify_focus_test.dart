import 'package:flutter_test/flutter_test.dart';
import 'package:zkteco_flutter_client/utils/pos_notify_focus.dart';

void main() {
  test('đang bán: chấm công / nhân sự bị chặn, đơn QR / online / thanh toán được hiện', () {
    expect(PosNotifyFocus.isRelevant(relatedEntityType: 'Attendance', categoryCode: 'attendance'), isFalse);
    expect(PosNotifyFocus.isRelevant(relatedEntityType: 'Device'), isFalse);
    expect(PosNotifyFocus.isRelevant(relatedEntityType: 'PosSaleOrder', categoryCode: 'pos'), isFalse);
    expect(PosNotifyFocus.isRelevant(relatedEntityType: 'PosProduct', categoryCode: 'pos'), isFalse);
    expect(PosNotifyFocus.isRelevant(relatedEntityType: 'PosQrTableOrder', categoryCode: 'pos'), isTrue);
    expect(PosNotifyFocus.isRelevant(relatedEntityType: 'PosOnlineOrder'), isTrue);
  });

  test('enter / leave đếm lồng nhau', () {
    expect(PosNotifyFocus.active, isFalse);
    PosNotifyFocus.enter();
    PosNotifyFocus.enter();
    PosNotifyFocus.leave();
    expect(PosNotifyFocus.active, isTrue);
    PosNotifyFocus.leave();
    PosNotifyFocus.leave();
    expect(PosNotifyFocus.active, isFalse);
  });

  test('clip rút gọn nội dung dài', () {
    final long = 'Bàn 5 · DH000123 · ${'Cà phê sữa đá ' * 30}';
    final c = PosNotifyFocus.clip(long, max: 100);
    expect(c.length, lessThanOrEqualTo(100));
    expect(c.endsWith('…'), isTrue);
    expect(PosNotifyFocus.clip('ngắn'), 'ngắn');
  });
}
