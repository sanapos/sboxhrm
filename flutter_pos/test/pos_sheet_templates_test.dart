import 'package:flutter_test/flutter_test.dart';
import 'package:sbox_pos/models/pos_print_template.dart';
import 'package:sbox_pos/models/pos_sale_order.dart';
import 'package:sbox_pos/models/pos_stock_issue_doc.dart';
import 'package:sbox_pos/utils/pos_sheet_document_print.dart';
import 'package:sbox_pos/utils/pos_commercial_templates.g.dart';
import 'package:sbox_pos/utils/pos_print_template_defaults.dart';
import 'package:sbox_pos/utils/pos_print_template_renderer.dart';

/// Mẫu A4/A5 từng loại chứng từ (PrintTemplates/Sheet) — dựng với dữ liệu mẫu không còn sót mã trường.
void main() {
  const docs = [
    PosPrintDocumentTypes.saleInvoice,
    PosPrintDocumentTypes.saleOrder,
    PosPrintDocumentTypes.delivery,
    PosPrintDocumentTypes.saleReturn,
    PosPrintDocumentTypes.saleExchange,
    PosPrintDocumentTypes.purchaseOrder,
    PosPrintDocumentTypes.purchaseReceipt,
    PosPrintDocumentTypes.purchaseReturn,
    PosPrintDocumentTypes.stockTransfer,
    PosPrintDocumentTypes.stockIssue,
    PosPrintDocumentTypes.cashReceipt,
    PosPrintDocumentTypes.cashPayment,
  ];

  test('đủ 24 mẫu A4/A5', () {
    for (final d in docs) {
      for (final p in [PosPrintPaperSizes.a4, PosPrintPaperSizes.a5]) {
        expect(posSheetTemplateHtml['$d.$p'], isNotNull, reason: '$d.$p');
        expect(posPrintDefaultHtml(documentType: d, paperSize: p), posSheetTemplateHtml['$d.$p']);
      }
    }
  });

  for (final d in docs) {
    for (final p in [PosPrintPaperSizes.a4, PosPrintPaperSizes.a5]) {
      test('$d $p dựng đủ dữ liệu mẫu', () {
        final tpl = posPrintDefaultHtml(documentType: d, paperSize: p);
        final data = posPrintSampleData(documentType: d, storeName: 'Cửa hàng A');
        final lines = [
          for (final l in posPrintSampleLines(count: 3))
            {...l, 'SL_Nhan': l['So_Luong']!, 'Loai_Dong': 'Đổi mới'},
        ];
        final html = renderPosPrintTemplateHtml(
          tpl,
          data: data,
          lineItems: lines,
          wrapDocument: false,
          paperSize: p,
        );
        expect(RegExp(r'\{[A-Z][A-Za-z_]+\}').allMatches(html).map((m) => m.group(0)).toSet(),
            isEmpty,
            reason: 'Còn mã trường chưa có dữ liệu mẫu');
        expect(html.contains('<!--IF'), isFalse);
        final isCash = d == PosPrintDocumentTypes.cashReceipt || d == PosPrintDocumentTypes.cashPayment;
        if (!isCash) {
          expect(html, contains('Laptop văn phòng'), reason: 'Bảng hàng phải lặp đủ dòng');
        } else {
          expect(html.contains('Laptop văn phòng'), isFalse, reason: 'Phiếu thu/chi không có bảng hàng');
        }
      });
    }
  }

  test('phiếu thu A5 in ngang', () {
    final html = posPrintDefaultHtml(
        documentType: PosPrintDocumentTypes.cashReceipt, paperSize: PosPrintPaperSizes.a5);
    final setup = PosCommercialPageSetup.parse(html);
    expect(setup.isA5, isTrue);
    expect(setup.landscape, isTrue);
    expect(setup.cssWidth > setup.cssHeight, isTrue);
    final page = wrapPosCommercialPrintHtml(html, setup);
    expect(page, contains('size: A5 landscape'));
    // Lưu lại khổ/lề không mất hướng giấy.
    expect(PosCommercialPageSetup.parse(setup.applyToHtml(html)).landscape, isTrue);
  });

  test('mẫu nhập hàng không còn «Khách lẻ»', () {
    final html = posPrintDefaultHtml(
        documentType: PosPrintDocumentTypes.purchaseReceipt, paperSize: PosPrintPaperSizes.a4);
    expect(html, contains('{Nha_Cung_Cap}'));
    expect(html.contains('Khách lẻ'), isFalse);
  });

  PosSaleOrder order({String status = 'Completed'}) => PosSaleOrder(
        id: 'o1',
        orderNo: 'HD000123',
        status: status,
        subTotal: 500000,
        total: 530000,
        deliveryFee: 30000,
        paidAmount: 100000,
        customerName: 'Chị Lan',
        deliveryAddress: '12 Nguyễn Huệ, Q.1',
        deliveryPhone: '0912345678',
        deliveryPartner: 'GHN',
        deliveryTrackingCode: 'GHN123',
        saleDate: DateTime(2026, 10, 28, 9),
        lines: [
          PosSaleOrderLine(
              productId: 'p1', productName: 'Áo thun', qty: 2, unitPrice: 250000, lineTotal: 500000),
        ],
      );

  test('phiếu giao hàng A4 từ đơn bán: địa chỉ giao, vận đơn, COD', () {
    final html = renderSaleOrderTemplate(
      posPrintDefaultHtml(documentType: PosPrintDocumentTypes.delivery, paperSize: PosPrintPaperSizes.a4),
      order(),
      storeName: 'Cửa hàng A',
      paperSize: PosPrintPaperSizes.a4,
    );
    expect(html, contains('PHIẾU GIAO HÀNG'));
    expect(html, contains('12 Nguyễn Huệ, Q.1'));
    expect(html, contains('GHN123'));
    expect(html, contains('THU HỘ (COD)'));
    expect(html, contains('Áo thun'));
  });

  test('phiếu trả hàng ghi số hóa đơn gốc', () {
    final html = renderSaleOrderTemplate(
      posPrintDefaultHtml(documentType: PosPrintDocumentTypes.saleReturn, paperSize: PosPrintPaperSizes.a5),
      order(status: 'Return'),
      paperSize: PosPrintPaperSizes.a5,
    );
    expect(html, contains('Hóa đơn gốc:</b> HD000123'));
  });

  test('phiếu xuất kho: người nhận, lý do, tổng bằng chữ', () {
    final doc = PosStockIssueDoc(
      id: 'x1',
      issueNo: 'XH0001',
      recipientName: 'Bếp',
      categoryName: 'Hư hỏng',
      totalQty: 3,
      totalValue: 150000,
      lines: [
        PosStockIssueLine(
            id: 'l1', productId: 'p1', productName: 'Sữa tươi', qty: 3, costPrice: 50000, lineTotal: 150000),
      ],
    );
    final data = posStockIssuePrintData(doc, 'Xuất hủy');
    expect(data['Ly_Do'], 'Xuất hủy — Hư hỏng');
    final html = renderPosPrintTemplateHtml(
      posPrintDefaultHtml(documentType: PosPrintDocumentTypes.stockIssue, paperSize: PosPrintPaperSizes.a4),
      data: {...data, 'Ten_Cua_Hang': 'Cửa hàng A'},
      lineItems: [for (final l in posStockIssueLinesPrintData(doc.lines)) {'STT': '1', ...l}],
      wrapDocument: false,
    );
    expect(html, contains('Sữa tươi'));
    expect(html, contains('Một trăm năm mươi nghìn'));
    expect(RegExp(r'\{[A-Z][A-Za-z_]+\}').allMatches(html).map((m) => m.group(0)).toList(), isEmpty);
  });
}
