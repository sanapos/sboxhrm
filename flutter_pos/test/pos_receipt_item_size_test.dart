import 'package:flutter_test/flutter_test.dart';
import 'package:sbox_pos/models/pos_print_template.dart';
import 'package:sbox_pos/models/pos_print_template_v2.dart';
import 'package:sbox_pos/models/pos_sale_order.dart';
import 'package:sbox_pos/utils/pos_print_template_compiler.dart';
import 'package:sbox_pos/utils/pos_print_template_renderer.dart';
import 'package:sbox_pos/utils/pos_print_template_runtime.dart';

/// Hóa đơn nhiệt: dòng hàng đủ to trên K58, giờ karaoke in «1h55» + giờ vào–ra dưới dòng.
void main() {
  final start = DateTime(2026, 10, 28, 12, 22);
  final timed = PosSaleOrderLine(
    productId: 'room',
    productName: 'Phòng VIP 2',
    unitName: 'Giờ',
    qty: 115 / 60,
    unitPrice: 150000,
    lineTotal: 317500,
    durationMinutes: 115,
    billableMinutes: 115,
    serviceStartedAt: start,
    serviceEndedAt: start.add(const Duration(minutes: 115)),
  );
  final beer = PosSaleOrderLine(
    productId: 'beer',
    productName: 'Bia Tiger lon',
    qty: 12,
    unitPrice: 25000,
    lineTotal: 300000,
  );

  test('dòng tiền giờ: SL «1h55», ghi chú giờ vào–ra', () {
    final lines = buildSaleOrderPrintLines([timed, beer]);
    expect(lines[0]['So_Luong'], '1h55');
    expect(lines[0]['Ghi_Chu'], startsWith('12:22–14:17'));
    expect(lines[0]['Ghi_Chu'], contains('phí mở phòng'));
    expect(lines[1]['So_Luong'], '12');
    expect(lines[1]['Ghi_Chu'], isEmpty);
  });

  for (final paper in [PosPrintPaperSizes.k58, PosPrintPaperSizes.k80]) {
    test('$paper: dòng hàng và ghi chú dòng không bị thu nhỏ', () {
      final k58 = paper == PosPrintPaperSizes.k58;
      final tpl = PosPrintTemplateRuntime.resolveOrPreset(
        documentType: PosPrintDocumentTypes.saleInvoice,
        paperSize: paper,
        printerProfile: k58 ? PosPrintPrinterProfiles.sunmiK58 : PosPrintPrinterProfiles.sunmiK80,
      );
      final out = PosPrintTemplateCompiler.compile(
        template: tpl,
        data: posPrintSampleData(),
        lineItems: buildSaleOrderPrintLines([timed, beer]),
      );
      final rows = out.steps.whereType<PosPrintCompiledSaleRow>().toList();
      expect(rows, isNotEmpty);
      for (final r in rows) {
        expect(r.fontSize, greaterThanOrEqualTo(k58 ? 18 : 22), reason: r.name);
      }
      final note = out.steps
          .whereType<PosPrintCompiledLine>()
          .firstWhere((l) => l.text.contains('12:22'));
      expect(note.fontSize, greaterThanOrEqualTo(15));
    });
  }
}
