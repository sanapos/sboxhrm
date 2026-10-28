import 'package:flutter_test/flutter_test.dart';
import 'package:sbox_pos/utils/pos_cup_label_print.dart';
import 'package:sbox_pos/utils/pos_pending_print_store.dart';

void main() {
  test('Tem ly treo qua Agent: phiếu chờ giữ mã lệnh gốc khi lưu / đọc lại', () {
    final job = PendingCupLabelPrintJob(
      id: 'cup_hang_j1',
      tickets: [const CupLabelTicket(productName: 'Trà sữa', tableLabel: 'Bàn 3', orderNo: 'HD01')],
      tableLabel: 'Bàn 3',
      orderNo: 'HD01',
      sourceJobId: 'j1',
      errorMessage: 'Chưa in sau 90s (Máy tem)',
    );
    final back = PendingCupLabelPrintJob.fromJson(job.toJson());
    expect(back.sourceJobId, 'j1');
    expect(back.copyWith(attemptCount: 2).sourceJobId, 'j1');
    expect(back.tickets.single.productName, 'Trà sữa');
    expect(back.tableLabel, 'Bàn 3');
    // Phiếu cũ (chưa có trường này) vẫn đọc được.
    final legacy = Map<String, dynamic>.from(job.toJson())..remove('sourceJobId');
    expect(PendingCupLabelPrintJob.fromJson(legacy).sourceJobId, isNull);
  });
}
