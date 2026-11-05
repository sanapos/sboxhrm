import 'package:flutter_test/flutter_test.dart';
import 'package:sbox_pos/models/cash_transaction.dart';
import 'package:sbox_pos/models/pos_print_template.dart';
import 'package:sbox_pos/models/pos_print_template_v2.dart';
import 'package:sbox_pos/utils/pos_print_template_compiler.dart';
import 'package:sbox_pos/utils/pos_print_template_v2_presets.dart';

BankAccount _acc() => BankAccount(
      id: 'b1',
      accountName: 'CUA HANG QA',
      accountNumber: '0071000123456',
      bankCode: '970436',
      bankName: 'Vietcombank',
    );

List<Object> _compile(PosPrintTemplateV2 template, String? qrUrl) =>
    PosPrintTemplateCompiler.compile(
      template: template,
      data: const {'Ma_Don_Hang': 'HD020112260001', 'Tong_Cong': '150.000'},
      lineItems: const [],
      vietQrImageUrl: qrUrl,
    ).steps;

void main() {
  group('in VietQR trên hóa đơn', () {
    final preset = PosPrintTemplateV2Presets.build(
      documentType: PosPrintDocumentTypes.saleInvoice,
      paperSize: PosPrintPaperSizes.k80,
      printerProfile: PosPrintPrinterProfiles.sunmiK80,
    );
    final url = _acc().generateVietQRUrl(amount: 150000, description: 'POS HD1');

    test('mẫu mặc định (không có khối QR) + bật In mã VietQR → vẫn in QR', () {
      final qrs = _compile(preset, url).whereType<PosPrintCompiledQr>().toList();
      expect(qrs, hasLength(1));
      expect(qrs.single.imageUrl, url);
      expect(qrs.single.amountText, '150.000');
      expect(qrs.single.size, 300);
    });

    test('tắt In mã VietQR (không URL) → không có QR', () {
      expect(_compile(preset, null).whereType<PosPrintCompiledQr>(), isEmpty);
    });

    test('mẫu đã có khối VietQR → không in 2 lần', () {
      final withBlock = preset.copyWith(blocks: [
        ...preset.blocks,
        const PosPrintBlock(type: PosPrintBlockType.vietQr),
      ]);
      expect(_compile(withBlock, url).whereType<PosPrintCompiledQr>(), hasLength(1));
    });

    test('xem trước mẫu (sample) giữ nguyên — không tự thêm QR', () {
      expect(_compile(preset, 'sample').whereType<PosPrintCompiledQr>(), isEmpty);
    });

    test('phiếu trả hàng không in QR thanh toán', () {
      final ret = PosPrintTemplateV2Presets.build(
        documentType: PosPrintDocumentTypes.saleReturn,
        paperSize: PosPrintPaperSizes.k80,
        printerProfile: PosPrintPrinterProfiles.sunmiK80,
      );
      expect(_compile(ret, url).whereType<PosPrintCompiledQr>(), isEmpty);
    });
  });
}
