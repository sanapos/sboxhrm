import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../models/pos_print_template.dart';
import '../models/pos_sale_order.dart';
import '../models/pos_store_printer.dart';
import '../services/api_service.dart';
import 'pos_html_print.dart';
import 'pos_pdf_fonts.dart';
import 'pos_print_orchestrator.dart';
import 'pos_print_template_renderer.dart';
import 'pos_purchase_receipt_print.dart';
import 'pos_store_printer_mapper.dart';
import 'pos_thermal_printer_settings.dart';
import 'pos_thermal_printer_service.dart';

/// Tạo PDF hóa đơn bán hàng kiểu KiotViet (khổ ngang A4, font tiếng Việt).
Future<Uint8List> buildPosSaleOrderPdfBytes({
  required String orderNo,
  required DateTime saleDate,
  String? branchName,
  String? createdBy,
  String? soldBy,
  String? customerName,
  String? salesChannel,
  String? priceListName,
  String? note,
  String paymentMethod = 'Tiền mặt',
  required double subTotal,
  required double discount,
  required double total,
  required double paidAmount,
  required double balanceDue,
  required double returnedAmount,
  required List<PosSaleOrderLine> lines,
  int copies = 1,
  bool mergeSameItems = false,
  int printCount = 0,
  int dailyOrderIndex = 0,
  double dailySalesTotal = 0,
}) async {
  final fonts = await loadPosPdfFonts();
  final pdf = pw.Document(
    theme: pw.ThemeData.withFont(base: fonts.regular, bold: fonts.bold),
  );
  final body9 = pw.TextStyle(font: fonts.regular, fontSize: 9);
  final bold9 = pw.TextStyle(font: fonts.bold, fontSize: 9);
  final bold20 = pw.TextStyle(font: fonts.bold, fontSize: 20);
  final body10 = pw.TextStyle(font: fonts.regular, fontSize: 10);
  final bold10 = pw.TextStyle(font: fonts.bold, fontSize: 10);

  final money = NumberFormat('#,##0', 'vi_VN');
  final qtyFmt = NumberFormat('#,##0.##', 'vi_VN');
  final dateFmt = DateFormat('dd/MM/yyyy HH:mm');
  final totalQty = lines.fold<double>(0, (a, l) => a + l.qty);

  final printLines = mergeSameItems ? _mergeSaleLines(lines) : lines;
  final printQty = mergeSameItems
      ? printLines.fold<double>(0, (a, l) => a + l.qty)
      : totalQty;

  pw.Widget pageContent() => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Center(
            child: pw.Text(
              printCount > 1 ? 'HÓA ĐƠN BÁN HÀNG IN LẠI' : 'HÓA ĐƠN BÁN HÀNG',
              style: bold20,
            ),
          ),
          if (printCount > 1) ...[
            pw.SizedBox(height: 6),
            pw.Center(
              child: pw.Text(
                '*** Bản in lại — thông báo chủ cửa hàng ***',
                style: pw.TextStyle(
                  font: fonts.bold,
                  fontSize: 11,
                  color: PdfColors.red800,
                ),
              ),
            ),
          ],
          pw.SizedBox(height: 10),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text('Mã đơn: ${orderNo.isEmpty ? '—' : orderNo}', style: body10),
              pw.Text('Ngày bán: ${dateFmt.format(saleDate.toLocal())}', style: body10),
            ],
          ),
          pw.SizedBox(height: 6),
          if (branchName != null && branchName.isNotEmpty)
            pw.Text('Chi nhánh: $branchName', style: body10),
          if (createdBy != null && createdBy.isNotEmpty)
            pw.Text('Người tạo: $createdBy', style: body10),
          if (soldBy != null && soldBy.isNotEmpty)
            pw.Text('Người bán: $soldBy', style: body10),
          pw.Text('Khách hàng: ${customerName ?? 'Khách lẻ'}', style: body10),
          if (salesChannel != null && salesChannel.isNotEmpty)
            pw.Text('Kênh bán: $salesChannel', style: body10),
          if (priceListName != null && priceListName.isNotEmpty)
            pw.Text('Bảng giá: $priceListName', style: body10),
          pw.SizedBox(height: 12),
          pw.TableHelper.fromTextArray(
            headers: const [
              'STT',
              'Tên hàng',
              'Đơn giá',
              'SL',
              'CK',
              'Thành tiền',
            ],
            data: List.generate(printLines.length, (i) {
              final l = printLines[i];
              final unitSuffix =
                  l.unitName != null && l.unitName!.isNotEmpty ? ' (${l.unitName})' : '';
              var name = '${l.productName}$unitSuffix';
              if (l.lineNote != null && l.lineNote!.isNotEmpty) {
                name = '$name\n↳ ${l.lineNote}';
              }
              return [
                '${i + 1}',
                name,
                money.format(l.unitPrice),
                qtyFmt.format(l.qty),
                l.discountAmount > 0 ? money.format(l.discountAmount) : '—',
                money.format(l.lineTotal),
              ];
            }),
            headerStyle: bold9,
            cellStyle: body9,
            cellAlignment: pw.Alignment.centerLeft,
          ),
          pw.SizedBox(height: 10),
          pw.Text('Tổng số lượng: ${qtyFmt.format(printQty)}', style: body10),
          pw.Text('Tổng tiền hàng: ${money.format(subTotal)}', style: body10),
          pw.Text('Giảm giá: ${money.format(discount)}', style: body10),
          pw.Text('Tổng cộng: ${money.format(total)}', style: bold10),
          pw.Text('Đã thanh toán: ${money.format(paidAmount)} ($paymentMethod)', style: body10),
          pw.Text('Còn lại: ${money.format(balanceDue)}', style: body10),
          if (returnedAmount > 0)
            pw.Text('Đã trả hàng: ${money.format(returnedAmount)}', style: body10),
          if (note != null && note.isNotEmpty) ...[
            pw.SizedBox(height: 8),
            pw.Text('Ghi chú: $note', style: body10),
          ],
          pw.Spacer(),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
            children: [
              pw.Column(
                children: [
                  pw.Text('Khách hàng', style: bold10),
                  pw.SizedBox(height: 48),
                  pw.Text('(Ký, họ tên)', style: body10),
                ],
              ),
              pw.Column(
                children: [
                  pw.Text('Người bán', style: bold10),
                  pw.SizedBox(height: 48),
                  pw.Text('(Ký, họ tên)', style: body10),
                ],
              ),
            ],
          ),
        ],
      );

  final copyCount = copies.clamp(1, 20);
  for (var c = 0; c < copyCount; c++) {
    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.all(28),
        theme: pw.ThemeData.withFont(base: fonts.regular, bold: fonts.bold),
        build: (_) => pageContent(),
      ),
    );
  }

  return Uint8List.fromList(await pdf.save());
}

List<PosSaleOrderLine> _mergeSaleLines(List<PosSaleOrderLine> lines) {
  final map = <String, PosSaleOrderLine>{};
  for (final l in lines) {
    final key = '${l.productId}|${l.variantId ?? ''}|${l.unitPrice}|${l.unitName ?? ''}';
    final existing = map[key];
    if (existing == null) {
      map[key] = l;
    } else {
      map[key] = PosSaleOrderLine(
        id: existing.id,
        productId: existing.productId,
        variantId: existing.variantId,
        productName: existing.productName,
        unitName: existing.unitName,
        qty: existing.qty + l.qty,
        unitPrice: existing.unitPrice,
        discountAmount: existing.discountAmount + l.discountAmount,
        lineTotal: existing.lineTotal + l.lineTotal,
        lineNote: [existing.lineNote, l.lineNote]
            .where((n) => n != null && n.isNotEmpty)
            .join('; '),
      );
    }
  }
  return map.values.toList();
}

/// In hóa đơn bán hàng — mở dialog xem trước.
Future<PosPrintTemplate?> _resolveSalePrintTemplate(String? templateId) async {
  if (templateId != null && templateId.isNotEmpty) {
    final res = await ApiService().getPosPrintTemplate(templateId);
    if (res['isSuccess'] == true && res['data'] is Map) {
      return PosPrintTemplate.fromJson(res['data'] as Map<String, dynamic>);
    }
  }
  final listRes = await ApiService().getPosPrintTemplates(
    documentType: PosPrintDocumentTypes.saleInvoice,
  );
  if (listRes['isSuccess'] == true && listRes['data'] is List) {
    final list = (listRes['data'] as List)
        .map((e) => PosPrintTemplate.fromJson(e as Map<String, dynamic>))
        .toList();
    return list.where((t) => t.isDefault).firstOrNull ?? list.firstOrNull;
  }
  return null;
}

PosThermalPrinterSettings _thermalSettingsForTemplate(
  PosThermalPrinterSettings settings,
  PosPrintTemplate? template,
) {
  if (template != null && PosPrintPaperSizes.isThermal(template.paperSize)) {
    return settings.copyWith(paperSize: template.paperSize);
  }
  return settings;
}

Future<void> printPosSaleOrder({
  required BuildContext context,
  required PosSaleOrder order,
  String? branchName,
  String? storeAddress,
  String? storePhone,
  bool mergeSameItems = false,
  int copies = 1,
  String? templateId,
  String? vietQrImageUrl,
  bool skipDedup = false,
}) async {
  final printOrder = await _resolvePrintOrder(order);
  final template = await _resolveSalePrintTemplate(templateId);

  final thermal = await PosThermalPrinterSettings.load();
  if (!kIsWeb) {
    await PosPrintOrchestrator.instance.refreshConfig();
    final cloudPrinters = PosPrintOrchestrator.instance
        .resolvePrinters(PosCloudDocumentTypes.saleInvoice);

    if (cloudPrinters.isNotEmpty) {
      final printed =
          await PosPrintOrchestrator.instance.dispatchEscPosToAll(
        documentType: PosCloudDocumentTypes.saleInvoice,
        copies: copies,
        referenceNo: printOrder.orderNo.isEmpty ? null : printOrder.orderNo,
        referenceId: printOrder.id,
        showFeedback: true,
        successTitle: printOrder.isReprint ? 'In lại hóa đơn' : 'In hóa đơn',
        skipDedup: skipDedup,
        buildBytes: (printer) async {
          var settings = toThermalSettings(printer);
          settings = _thermalSettingsForTemplate(settings, template);
          return PosThermalPrinterService.buildSaleOrderEscPosBytes(
            printOrder,
            settings: settings,
            storeName: branchName,
            storeAddress: storeAddress,
            storePhone: storePhone,
            mergeSameItems: mergeSameItems,
            vietQrImageUrl: vietQrImageUrl,
          );
        },
      );
      if (printed) {
        return;
      }
    }

    if (thermal.enabled) {
      var settings = _thermalSettingsForTemplate(thermal, template);
      final bytes = await PosThermalPrinterService.buildSaleOrderEscPosBytes(
        printOrder,
        settings: settings,
        storeName: branchName,
        storeAddress: storeAddress,
        storePhone: storePhone,
        mergeSameItems: mergeSameItems,
        vietQrImageUrl: vietQrImageUrl,
      );
      final printed = await PosPrintOrchestrator.instance.dispatchLocalEscPos(
        bytes: bytes,
        copies: copies,
        showFeedback: true,
        successTitle: printOrder.isReprint ? 'In lại hóa đơn' : 'In hóa đơn',
        settingsOverride: settings,
        documentType: PosPrintDocumentTypes.saleInvoice,
        referenceId: printOrder.id,
        referenceNo: printOrder.orderNo.isEmpty ? null : printOrder.orderNo,
        skipDedup: skipDedup,
      );
      if (printed) {
        return;
      }
    }
  }

  final saleDate =
      printOrder.saleDate?.toLocal() ?? printOrder.createdAt?.toLocal() ?? DateTime.now();

  if (template != null && template.htmlContent.trim().isNotEmpty) {
    final html = renderSaleOrderTemplate(
      template.htmlContent,
      printOrder,
      storeName: branchName,
      storeAddress: storeAddress,
      storePhone: storePhone,
      paperSize: template.paperSize,
      mergeSameItems: mergeSameItems,
    );
    await showPosHtmlPrintDialog(
      context,
      title: 'Hóa đơn ${printOrder.orderNo.isEmpty ? 'tạm' : printOrder.orderNo}'
          '${printOrder.isReprint ? ' (IN LẠI)' : ''}',
      htmlDocument: html,
      initialCopies: copies,
    );
    return;
  }

  await showPosPurchaseReceiptPrintDialog(
    context,
    title: 'Hóa đơn ${printOrder.orderNo.isEmpty ? 'tạm' : printOrder.orderNo}'
        '${printOrder.isReprint ? ' (IN LẠI)' : ''}',
    buildPdf: (c) => buildPosSaleOrderPdfBytes(
      orderNo: printOrder.orderNo,
      saleDate: saleDate,
      branchName: branchName,
      createdBy: printOrder.createdBy,
      soldBy: printOrder.soldBy,
      customerName: printOrder.customerName,
      salesChannel: printOrder.salesChannel,
      priceListName: printOrder.priceListName,
      note: printOrder.note,
      paymentMethod: printOrder.paymentMethod,
      subTotal: printOrder.subTotal,
      discount: printOrder.discount,
      total: printOrder.total,
      paidAmount: printOrder.paidAmount,
      balanceDue: printOrder.balanceDue,
      returnedAmount: printOrder.returnedAmount,
      lines: printOrder.lines,
      copies: c,
      mergeSameItems: mergeSameItems,
      printCount: printOrder.printCount,
      dailyOrderIndex: printOrder.dailyOrderIndex,
      dailySalesTotal: printOrder.dailySalesTotal,
    ),
  );
}

Future<PosSaleOrder> _resolvePrintOrder(PosSaleOrder order) async {
  if (order.id.isEmpty || order.status != 'Completed') return order;
  try {
    final res = await ApiService().recordPosSalePrint(order.id);
    if (res['isSuccess'] == true && res['data'] is Map<String, dynamic>) {
      final fromApi = PosSaleOrder.fromJson(res['data'] as Map<String, dynamic>);
      if (fromApi.lines.isEmpty && order.lines.isNotEmpty) {
        return order.copyWithPrintContext(
          printCount: fromApi.printCount,
          dailyOrderIndex: fromApi.dailyOrderIndex,
          dailySalesTotal: fromApi.dailySalesTotal,
        );
      }
      return fromApi;
    }
  } catch (_) {}
  return order.copyWithPrintContext(printCount: order.printCount + 1);
}
