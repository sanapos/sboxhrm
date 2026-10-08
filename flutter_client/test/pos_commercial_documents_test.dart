import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:zkteco_flutter_client/models/pos_print_template.dart';
import 'package:zkteco_flutter_client/models/pos_quote.dart';
import 'package:zkteco_flutter_client/utils/pos_print_template_defaults.dart';
import 'package:zkteco_flutter_client/utils/pos_print_template_renderer.dart';
import 'package:zkteco_flutter_client/widgets/pos/pos_quote_care_sheet.dart';

PosQuote _quote({double deposit = 0, double? pct}) => PosQuote(
      id: 'q1',
      quoteNo: 'BG0007',
      status: 'Draft',
      customerName: 'Trần Thị Bình',
      customerAddress: '12 Lê Duẩn, Đà Nẵng',
      depositAmount: deposit,
      depositPercent: pct,
      vatMode: PosQuoteVat.none,
      lines: [
        PosQuoteLine(
          productName: 'Tủ bếp',
          unitName: 'md',
          qty: 2,
          unitPrice: 1000000,
          lineTotal: 2000000,
        ),
      ],
    );

void main() {
  setUpAll(() => initializeDateFormatting('vi_VN'));

  test('IF / IFNOT lồng nhau và số 0 coi là trống', () {
    final html = applyPosPrintConditionals(
      '<!--IF:A-->a<!--IF:B-->b<!--ENDIF:B--><!--IFNOT:B-->nb<!--ENDIFNOT:B-->'
      '<!--ENDIF:A--><!--IF:Z-->z<!--ENDIF:Z-->',
      {'A': 'x', 'B': '0 đ'},
    );
    expect(html, 'anb');
  });

  test('Bảng đợt thanh toán lặp theo dữ liệu mẫu', () {
    final html = renderPosPrintTemplateHtml(
      posPrintDefaultHtml(
        documentType: PosPrintDocumentTypes.contract,
        paperSize: PosPrintPaperSizes.a4,
      ),
      data: posPrintSampleData(documentType: PosPrintDocumentTypes.contract),
      lineItems: posPrintSampleLines(),
      wrapDocument: false,
    );
    expect(html, contains('Đặt cọc ký hợp đồng'));
    expect(html, contains('Nghiệm thu bàn giao'));
    expect(html, isNot(contains('<!--IF')));
    expect(html, isNot(contains('{Dot_')));
  });

  test('Đề nghị thanh toán không tự chèn bảng hàng', () {
    final html = renderPosPrintTemplateHtml(
      posPrintDefaultHtml(
        documentType: PosPrintDocumentTypes.paymentRequest,
        paperSize: PosPrintPaperSizes.a4,
      ),
      data: posPrintSampleData(documentType: PosPrintDocumentTypes.paymentRequest),
      lineItems: posPrintSampleLines(),
      wrapDocument: false,
    );
    expect(html, isNot(contains('Trà sữa')));
  });

  test('Chứng từ thật không lọt dữ liệu mẫu, không tự gán cọc 50%', () {
    final html = bindPosCommercialPrintHtmlLocal(
      _quote(),
      documentType: PosPrintDocumentTypes.contract,
      docNo: 'HD0001',
    );
    for (final fake in [
      '4100543367',
      'Nghĩa Tín',
      '5810053610',
      'Huỳnh Lê Đại Phúc',
      '0402207773',
      '512222255555',
      'Nguyễn Hoài Sang',
      '12 tháng',
    ]) {
      expect(html, isNot(contains(fake)), reason: fake);
    }
    expect(html, contains('Trần Thị Bình'));
    expect(html, contains('HD0001'));
    expect(html, isNot(contains('1.000.000 đ</b> (')), reason: 'không có cọc');
  });

  test('Báo giá có cọc 30% in đúng số tiền cọc', () {
    final html = bindPosQuotePrintHtmlLocal(_quote(pct: 30), _quote().lines);
    expect(html, contains('600.000'));
    expect(html, isNot(contains('4100543367')));
  });
}
