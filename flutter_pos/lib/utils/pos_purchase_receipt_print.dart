import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../models/pos_purchase.dart';
import 'package:sbox_pos/l10n/app_tr.dart';
import 'pos_pdf_fonts.dart';
import '../widgets/pos/pos_pdf_iframe_stub.dart'
    if (dart.library.js_interop) '../widgets/pos/pos_pdf_iframe_web.dart';

const _blue = Color(0xFF2563EB);

/// Tạo PDF phiếu nhập hàng kiểu KiotViet (khổ ngang A4, font tiếng Việt).
Future<Uint8List> buildPosPurchaseReceiptPdfBytes({
  required String receiptNo,
  required DateTime importDate,
  String? branchName,
  String? createdBy,
  String? supplierName,
  String? supplierAddress,
  String? inputInvoiceNo,
  String? note,
  String status = 'Draft',
  String paymentMethod = 'Tiền mặt',
  required double linesTotal,
  required double totalVat,
  required double discountAmount,
  bool discountIsPercent = false,
  double discountInput = 0,
  required double paidAmount,
  required double grandTotal,
  required List<PosPurchaseLine> lines,
  int copies = 1,
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
  final debt = grandTotal - paidAmount;
  final discLabel = discountIsPercent
      ? '${discountInput.toStringAsFixed(discountInput % 1 == 0 ? 0 : 1)}% (${money.format(discountAmount)})'
      : money.format(discountAmount);

  pw.Widget pageContent() => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Center(child: pw.Text('PHIẾU NHẬP HÀNG', style: bold20)),
          pw.SizedBox(height: 10),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text('Mã phiếu: ${receiptNo.isEmpty ? '—' : receiptNo}', style: body10),
              pw.Text('Ngày: ${dateFmt.format(importDate.toLocal())}', style: body10),
            ],
          ),
          pw.SizedBox(height: 6),
          if (branchName != null && branchName.isNotEmpty)
            pw.Text('Chi nhánh nhập: $branchName', style: body10),
          if (createdBy != null && createdBy.isNotEmpty)
            pw.Text('Người tạo: $createdBy', style: body10),
          pw.Text('Nhà cung cấp: ${supplierName ?? ''}', style: body10),
          if (supplierAddress != null && supplierAddress.isNotEmpty)
            pw.Text('Địa chỉ: $supplierAddress', style: body10),
          if (inputInvoiceNo != null && inputInvoiceNo.isNotEmpty)
            pw.Text('Số hóa đơn đầu vào: $inputInvoiceNo', style: body10),
          pw.SizedBox(height: 12),
          pw.TableHelper.fromTextArray(
            headers: const [
              'STT',
              'Mã hàng',
              'Tên hàng',
              'Đơn giá',
              'SL',
              'VAT',
              'Chiết khấu',
              'Thành tiền',
            ],
            data: List.generate(lines.length, (i) {
              final l = lines[i];
              final unitSuffix =
                  l.unitName != null && l.unitName!.isNotEmpty ? ' (${l.unitName})' : '';
              final name = '${l.productName}$unitSuffix';
              final vatLabel = l.vatRate <= 0 ? '—' : '${l.vatRate.toStringAsFixed(0)}%';
              return [
                '${i + 1}',
                l.productCode,
                name,
                money.format(l.costPrice),
                qtyFmt.format(l.qty),
                vatLabel,
                money.format(l.discountAmount),
                money.format(l.lineTotal),
              ];
            }),
            headerStyle: bold9,
            cellStyle: body9,
            cellAlignment: pw.Alignment.centerLeft,
          ),
          pw.SizedBox(height: 10),
          pw.Text('Tổng số lượng hàng: ${qtyFmt.format(totalQty)}', style: body10),
          pw.Text('Tổng tiền hàng: ${money.format(linesTotal)}', style: body10),
          pw.Text('Tổng VAT: ${money.format(totalVat)}', style: body10),
          pw.Text('Chiết khấu hóa đơn: $discLabel', style: body10),
          pw.Text('Tiền cần trả NCC: ${money.format(grandTotal)}', style: bold10),
          pw.Text('Tiền trả NCC: ${money.format(paidAmount)} ($paymentMethod)', style: body10),
          pw.Text('Tính vào công nợ: ${money.format(debt)}', style: body10),
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
                  pw.Text('Nhà cung cấp', style: bold10),
                  pw.SizedBox(height: 48),
                  pw.Text('(Ký, họ tên)', style: body10),
                ],
              ),
              pw.Column(
                children: [
                  pw.Text('Người lập', style: bold10),
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

/// Mở dialog xem trước + in / xuất PDF.
Future<void> showPosPurchaseReceiptPrintDialog(
  BuildContext context, {
  required Future<Uint8List> Function(int copies) buildPdf,
  required String title,
}) async {
  var copies = 1;
  Uint8List? bytes;
  var loading = true;
  String? error;

  Future<void> rebuild(StateSetter setDlg) async {
    setDlg(() {
      loading = true;
      error = null;
    });
    try {
      bytes = await buildPdf(copies);
    } catch (e) {
      error = '$e';
    }
    setDlg(() => loading = false);
  }

  await showDialog<void>(
    context: context,
    barrierDismissible: true,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setDlg) {
        if (loading && bytes == null && error == null) {
          rebuild(setDlg);
        }
        return Dialog(
          insetPadding: const EdgeInsets.all(16),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.sizeOf(ctx).width * 0.95,
              maxHeight: MediaQuery.sizeOf(ctx).height * 0.92,
              minWidth: 720,
              minHeight: 520,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(tr(title),
                            style: const TextStyle(
                                fontSize: 16, fontWeight: FontWeight.w600)),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(ctx),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      Text(tr('Số bản in:'), style: TextStyle(fontSize: 13)),
                      const SizedBox(width: 8),
                      DropdownButton<int>(
                        value: copies,
                        items: List.generate(
                          10,
                          (i) => DropdownMenuItem(value: i + 1, child: Text(tr('${i + 1}'))),
                        ),
                        onChanged: (v) async {
                          if (v == null) return;
                          copies = v;
                          await rebuild(setDlg);
                        },
                      ),
                      const Spacer(),
                      OutlinedButton.icon(
                        onPressed: bytes == null
                            ? null
                            : () async {
                                await Printing.layoutPdf(
                                  onLayout: (_) async => bytes!,
                                  name: title,
                                );
                              },
                        icon: const Icon(Icons.print, size: 18),
                        label: Text(tr('In trực tiếp')),
                      ),
                      const SizedBox(width: 8),
                      FilledButton.icon(
                        onPressed: bytes == null
                            ? null
                            : () async {
                                await Printing.sharePdf(
                                  bytes: bytes!,
                                  filename: '$title.pdf',
                                );
                              },
                        style: FilledButton.styleFrom(backgroundColor: _blue),
                        icon: const Icon(Icons.download, size: 18),
                        label: Text(tr('Xuất PDF')),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 16),
                Expanded(
                  child: loading
                      ? const Center(child: CircularProgressIndicator())
                      : error != null
                          ? Center(child: Text(tr('Lỗi: $error')))
                          : bytes == null
                              ? Center(child: Text(tr('Không tạo được PDF')))
                              : Padding(
                                  padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                                  child: buildPosPdfPreview(bytes!),
                                ),
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
}

/// In phiếu nhập hàng NCC — mở dialog xem trước.
Future<void> printPosPurchaseReceipt({
  required BuildContext context,
  required String receiptNo,
  required DateTime importDate,
  String? branchName,
  String? createdBy,
  String? supplierName,
  String? supplierAddress,
  String? inputInvoiceNo,
  String? note,
  String status = 'Draft',
  String paymentMethod = 'Tiền mặt',
  required double linesTotal,
  required double totalVat,
  required double discountAmount,
  bool discountIsPercent = false,
  double discountInput = 0,
  required double paidAmount,
  required double grandTotal,
  required List<PosPurchaseLine> lines,
}) async {
  await showPosPurchaseReceiptPrintDialog(
    context,
    title: 'Phiếu nhập ${receiptNo.isEmpty ? 'tạm' : receiptNo}',
    buildPdf: (copies) => buildPosPurchaseReceiptPdfBytes(
      receiptNo: receiptNo,
      importDate: importDate,
      branchName: branchName,
      createdBy: createdBy,
      supplierName: supplierName,
      supplierAddress: supplierAddress,
      inputInvoiceNo: inputInvoiceNo,
      note: note,
      status: status,
      paymentMethod: paymentMethod,
      linesTotal: linesTotal,
      totalVat: totalVat,
      discountAmount: discountAmount,
      discountIsPercent: discountIsPercent,
      discountInput: discountInput,
      paidAmount: paidAmount,
      grandTotal: grandTotal,
      lines: lines,
      copies: copies,
    ),
  );
}
