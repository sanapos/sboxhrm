import 'package:flutter_test/flutter_test.dart';
import 'package:zkteco_flutter_client/models/cash_transaction.dart';
import 'package:zkteco_flutter_client/models/pos_print_template.dart';
import 'package:zkteco_flutter_client/models/pos_print_template_v2.dart';
import 'package:zkteco_flutter_client/utils/pos_print_template_compiler.dart';
import 'package:zkteco_flutter_client/utils/pos_print_template_v2_presets.dart';
import 'package:zkteco_flutter_client/utils/pos_vietqr_helper.dart';

/// Tách TLV EMVCo: id(2) + độ dài(2) + giá trị.
Map<String, String> _tlv(String s) {
  final out = <String, String>{};
  var i = 0;
  while (i + 4 <= s.length) {
    final id = s.substring(i, i + 2);
    final len = int.parse(s.substring(i + 2, i + 4));
    out[id] = s.substring(i + 4, i + 4 + len);
    i += 4 + len;
  }
  return out;
}

BankAccount _acc({String bankCode = '970436', String number = '0071000123456'}) =>
    BankAccount(
      id: 'b1',
      accountName: 'CUA HANG QA',
      accountNumber: number,
      bankCode: bankCode,
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
  test('CRC-16/CCITT-FALSE đúng mẫu chuẩn', () {
    expect(PosVietQrHelper.crc16('123456789'), 0x29B1);
  });

  test('chuỗi VietQR đúng cấu trúc NAPAS + CRC', () {
    final s = PosVietQrHelper.emvPayload(
      bankBin: '970436',
      accountNumber: '0071000123456',
      amount: 150000,
      description: 'POS HĐ020112260001',
    )!;
    final top = _tlv(s);
    expect(top['00'], '01');
    expect(top['01'], '12'); // có số tiền → QR động
    expect(top['53'], '704');
    expect(top['54'], '150000');
    expect(top['58'], 'VN');
    final mai = _tlv(top['38']!);
    expect(mai['00'], 'A000000727');
    expect(mai['02'], 'QRIBFTTA');
    final bene = _tlv(mai['01']!);
    expect(bene['00'], '970436');
    expect(bene['01'], '0071000123456');
    expect(_tlv(top['62']!)['08'], 'POS HD020112260001'); // bỏ dấu
    final body = s.substring(0, s.length - 4);
    expect(body.endsWith('6304'), isTrue);
    expect(s.substring(s.length - 4),
        PosVietQrHelper.crc16(body).toRadixString(16).toUpperCase().padLeft(4, '0'));
  });

  test('mẫu NAPAS công bố: phần trước CRC trùng khớp', () {
    final s = PosVietQrHelper.emvPayload(bankBin: '970403', accountNumber: '0011012345678')!;
    expect(
      s.startsWith('00020101021138570010A00000072701270006970403011300110123456780208QRIBFTTA53037045802VN6304'),
      isTrue,
    );
  });

  test('URL img.vietqr.io → chuỗi sinh tại máy; mã NH không phải BIN → null (dùng ảnh mạng)', () {
    final url = _acc().generateVietQRUrl(amount: 150000, description: 'POS HD1');
    final s = PosVietQrHelper.emvPayloadFromImageUrl(url)!;
    expect(_tlv(s)['54'], '150000');
    expect(_tlv(_tlv(_tlv(s)['38']!)['01']!)['01'], '0071000123456');
    final vcb = _acc(bankCode: 'VCB').generateVietQRUrl(amount: 1000);
    expect(PosVietQrHelper.emvPayloadFromImageUrl(vcb), isNull);
    // VA Tingee có chữ (TGE…) vẫn sinh được.
    final va = _acc(number: 'TGE123456VCB').generateVietQRUrl(amount: 1000);
    expect(PosVietQrHelper.emvPayloadFromImageUrl(va), isNotNull);
  });

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
