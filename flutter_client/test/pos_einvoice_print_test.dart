import 'package:flutter_test/flutter_test.dart';
import 'package:zkteco_flutter_client/models/pos_print_template.dart';
import 'package:zkteco_flutter_client/models/pos_print_template_v2.dart';
import 'package:zkteco_flutter_client/models/pos_sale_order.dart';
import 'package:zkteco_flutter_client/utils/pos_einvoice_qr.dart';
import 'package:zkteco_flutter_client/utils/pos_print_template_compiler.dart';
import 'package:zkteco_flutter_client/utils/pos_print_template_renderer.dart';
import 'package:zkteco_flutter_client/utils/pos_print_template_v2_presets.dart';

PosSaleOrder _order({
  String status = 'Issued',
  String? no = '00000123',
  bool printOnReceipt = true,
}) =>
    PosSaleOrder.fromJson({
      'id': 'o1',
      'orderNo': 'HD270920260001',
      'status': 'Completed',
      'total': 110000,
      'subTotal': 110000,
      'paidAmount': 110000,
      'paymentMethod': 'Tiền mặt',
      'lines': [],
      'eInvoiceStatus': status,
      'eInvoiceProvider': 'Misa',
      'eInvoiceNo': no,
      'eInvoiceSeries': '1C25TAA',
      'eInvoiceCode': 'M1-25-ABC',
      'eInvoiceReservationCode': 'L4CXU6X0W0',
      'eInvoiceLookupUrl': 'https://www.meinvoice.vn/tra-cuu/?sc=L4CXU6X0W0',
      'eInvoiceSellerTaxCode': '0101243150',
      'eInvoicePrintOnReceipt': printOnReceipt,
    });

PosPrintCompiledOutput _compile(PosSaleOrder order) {
  final template = PosPrintTemplateV2Presets.build(
    documentType: PosPrintDocumentTypes.saleInvoice,
    paperSize: PosPrintPaperSizes.k80,
    printerProfile: PosPrintPrinterProfiles.sunmiK80,
  );
  return PosPrintTemplateCompiler.compile(
    template: template,
    data: buildSaleOrderPrintData(order),
    lineItems: const [],
  );
}

void main() {
  test('Bill đã xuất HĐĐT in ký hiệu, số, mã CQT, mã tra cứu và QR tra cứu', () {
    final out = _compile(_order());
    final texts = out.steps.whereType<PosPrintCompiledLine>().map((l) => l.text).join('\n');
    expect(texts, contains('Ký hiệu: 1C25TAA - Số: 00000123'));
    expect(texts, contains('Mã CQT: M1-25-ABC'));
    expect(texts, contains('Mã tra cứu: L4CXU6X0W0'));
    final qr = out.steps.whereType<PosPrintCompiledQr>().single;
    expect(posInlineQrData(qr.imageUrl), 'https://www.meinvoice.vn/tra-cuu/?sc=L4CXU6X0W0');
    expect(out.html, contains('<svg'));
  });

  test('Không in khối HĐĐT khi chưa phát hành hoặc cửa hàng tắt', () {
    for (final o in [
      _order(status: 'Failed'),
      _order(no: null),
      _order(printOnReceipt: false),
    ]) {
      final out = _compile(o);
      expect(out.steps.whereType<PosPrintCompiledQr>(), isEmpty);
      expect(buildSaleOrderPrintData(o).containsKey('HDDT_So'), isFalse);
    }
  });

  test('Mẫu tự đặt biến {HDDT_So} → không lặp chữ, vẫn thêm QR', () {
    final base = PosPrintTemplateV2Presets.build(
      documentType: PosPrintDocumentTypes.saleInvoice,
      paperSize: PosPrintPaperSizes.k80,
      printerProfile: PosPrintPrinterProfiles.sunmiK80,
    );
    final custom = base.copyWith(blocks: [
      ...base.blocks,
      const PosPrintBlock(type: PosPrintBlockType.text, text: 'Số HĐĐT: {HDDT_So}'),
    ]);
    final out = PosPrintTemplateCompiler.compile(
      template: custom,
      data: buildSaleOrderPrintData(_order()),
      lineItems: const [],
    );
    final texts = out.steps.whereType<PosPrintCompiledLine>().map((l) => l.text).toList();
    expect(texts, contains('Số HĐĐT: 00000123'));
    expect(texts.where((t) => t.startsWith('Ký hiệu:')), isEmpty);
    expect(out.steps.whereType<PosPrintCompiledQr>(), hasLength(1));
  });

  test('Ảnh QR sinh tại máy là PNG hợp lệ (dùng cho Sunmi / ESC-POS)', () async {
    final png = await posQrPngBytes('https://www.meinvoice.vn/tra-cuu/?sc=L4CXU6X0W0');
    expect(png, isNotNull);
    expect(png!.sublist(0, 4), [0x89, 0x50, 0x4E, 0x47]);
  });
}
