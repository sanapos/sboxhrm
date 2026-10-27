import 'package:flutter_test/flutter_test.dart';
import 'package:sbox_pos/utils/pos_print_orchestrator.dart';

void main() {
  test('Lệnh hủy / lỗi khi đang in → có thể đã in (hỏi trước khi in lại)', () {
    for (final code in ['STUCK_PRINTING', 'STUCK_NO_REQUEUE', 'MAX_ATTEMPTS', 'PRINT_TIMEOUT', 'stuck_printing']) {
      expect(PosPrintOrchestrator.isMaybePrintedCode(code), isTrue, reason: code);
    }
  });

  test('Lệnh chưa ai in / Agent chưa bắt đầu in → không hỏi, in lại luôn', () {
    for (final code in ['STALE_QUEUED', 'STUCK_CLAIMED', 'EXPIRED', 'NO_AGENT_PORT', '', null]) {
      expect(PosPrintOrchestrator.isMaybePrintedCode(code), isFalse, reason: '$code');
    }
  });
}
