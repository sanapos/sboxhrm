import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:zkteco_flutter_client/models/pos_print_template.dart';
import 'package:zkteco_flutter_client/models/pos_quote.dart';
import 'package:zkteco_flutter_client/utils/pos_print_template_defaults.dart';
import 'package:zkteco_flutter_client/utils/pos_quote_export.dart';
import 'package:zkteco_flutter_client/widgets/pos/pos_html_preview_stub.dart';
import 'package:zkteco_flutter_client/widgets/pos/pos_quote_care_sheet.dart';

/// Bản in báo giá / hợp đồng A4: chỗ ký, căn cột — giống nhau ở PDF, Word và khung xem trước của app.
void main() {
  setUpAll(() => initializeDateFormatting('vi_VN'));

  final quote = PosQuote(
    id: 'q1',
    quoteNo: 'BG0007',
    status: 'Draft',
    customerName: 'Trần Thị Bình',
    vatMode: PosQuoteVat.included,
    vatPercent: 8,
    lines: [
      PosQuoteLine(productName: 'Tủ bếp', unitName: 'md', qty: 2, unitPrice: 1000000, lineTotal: 2000000),
    ],
  );

  test('5 mẫu A4: chỗ ký là hàng riêng, hai ô cao 116px (Word bỏ qua chiều cao <div> trống)', () {
    for (final type in [
      PosPrintDocumentTypes.quote,
      PosPrintDocumentTypes.contract,
      PosPrintDocumentTypes.handover,
      PosPrintDocumentTypes.acceptance,
      PosPrintDocumentTypes.paymentRequest,
    ]) {
      final html = posPrintDefaultHtml(documentType: type, paperSize: PosPrintPaperSizes.a4);
      expect(RegExp(r'<td height="116" style="height:116px').allMatches(html).length, 2, reason: type);
      expect(html, isNot(contains('<div style="height:116px"></div>')), reason: type);
    }
  });

  test('Báo giá: tiêu đề cột căn giữa, bảng tổng nằm bên phải không cần margin-left:auto', () {
    final html = posPrintDefaultHtml(documentType: PosPrintDocumentTypes.quote, paperSize: PosPrintPaperSizes.a4);
    final head = html.substring(html.indexOf('<thead>'), html.indexOf('</thead>'));
    expect(RegExp(r'<th ').allMatches(head).length, RegExp(r'text-align:center;vertical-align:middle').allMatches(head).length);
    expect(html, isNot(contains('0 0 auto')));
    expect(html, contains('<td width="48%" style="width:48%;padding:0"></td><td style="padding:3px 6px">Tổng tiền hàng'));
  });

  test('File .doc: khổ A4 và lề của mẫu theo kiểu Word, bỏ @page của bản in', () {
    final html = bindPosQuotePrintHtmlLocal(quote, quote.lines);
    final doc = posWordHtmlDocument(html);
    expect(doc, contains('@page WordSection1{size:595.3pt 841.9pt;margin:34.0pt 34.0pt 34.0pt 34.0pt;}'));
    expect(doc, contains('<div class="WordSection1">'));
    expect(RegExp(r'@page\s*\{').hasMatch(doc), isFalse);
    expect(doc, contains('Tủ bếp'));
    expect(RegExp('<html', caseSensitive: false).allMatches(doc).length, 1);
  });

  testWidgets('Xem trước trong app giữ ô ký cao 116px', (t) async {
    t.view.physicalSize = const Size(900, 2400);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final html = bindPosQuotePrintHtmlLocal(quote, quote.lines);
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: buildPosRenderedHtml(
            stripPosHtmlDocumentShell(html),
            a4Width: true,
            shrinkWrap: true,
          ),
        ),
      ),
    ));
    await t.pumpAndSettle();
    final cells = find.byWidgetPredicate((w) => w is ConstrainedBox && w.constraints.minHeight == 116);
    expect(cells, findsNWidgets(2));
    for (final e in cells.evaluate()) {
      expect(t.getSize(find.byWidget(e.widget)).height, greaterThanOrEqualTo(116));
    }
  });
}
