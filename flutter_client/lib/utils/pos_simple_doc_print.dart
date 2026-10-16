import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:zkteco_flutter_client/l10n/app_tr.dart';

import 'pos_pdf_fonts.dart';
import 'pos_purchase_receipt_print.dart';

/// In phiếu kho đơn giản (trả hàng nhập, xuất hủy, xuất dùng nội bộ): tiêu đề, vài dòng thông tin,
/// bảng hàng, tổng + ghi chú. Dùng chung hộp thoại xem trước / in của phiếu nhập.
Future<Uint8List> buildPosSimpleDocPdfBytes({
  required String title,
  required String docNo,
  required String statusLabel,
  required List<String> infoLines,
  required List<String> headers,
  required List<List<String>> rows,
  required List<String> totalLines,
  String? note,
  int copies = 1,
}) async {
  final fonts = await loadPosPdfFonts();
  final pdf = pw.Document(theme: pw.ThemeData.withFont(base: fonts.regular, bold: fonts.bold));
  final body9 = pw.TextStyle(font: fonts.regular, fontSize: 9);
  final bold9 = pw.TextStyle(font: fonts.bold, fontSize: 9);
  final body10 = pw.TextStyle(font: fonts.regular, fontSize: 10);
  final bold10 = pw.TextStyle(font: fonts.bold, fontSize: 10);
  final bold18 = pw.TextStyle(font: fonts.bold, fontSize: 18);

  pw.Widget content() => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Center(child: pw.Text(tr(title), style: bold18)),
          pw.SizedBox(height: 10),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(tr('Mã phiếu: $docNo'), style: body10),
              pw.Text(tr('Trạng thái: $statusLabel'), style: body10),
            ],
          ),
          pw.SizedBox(height: 4),
          for (final l in infoLines) pw.Text(l, style: body10),
          pw.SizedBox(height: 10),
          pw.TableHelper.fromTextArray(
            headers: headers.map(tr).toList(),
            data: rows,
            headerStyle: bold9,
            cellStyle: body9,
            cellAlignment: pw.Alignment.centerLeft,
          ),
          pw.SizedBox(height: 10),
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(
                child: note != null && note.isNotEmpty
                    ? pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                        pw.Text(tr('Ghi chú:'), style: bold10),
                        pw.Text(note, style: body10),
                      ])
                    : pw.SizedBox(),
              ),
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  for (var i = 0; i < totalLines.length; i++)
                    pw.Text(totalLines[i], style: i == totalLines.length - 1 ? bold10 : body10),
                ],
              ),
            ],
          ),
        ],
      );

  for (var c = 0; c < copies; c++) {
    pdf.addPage(pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(28),
      build: (_) => content(),
    ));
  }
  return Uint8List.fromList(await pdf.save());
}

Future<void> printPosSimpleDoc(
  BuildContext context, {
  required String title,
  required String docNo,
  required String statusLabel,
  required List<String> infoLines,
  required List<String> headers,
  required List<List<String>> rows,
  required List<String> totalLines,
  String? note,
}) {
  return showPosPurchaseReceiptPrintDialog(
    context,
    title: '$title $docNo',
    buildPdf: (copies) => buildPosSimpleDocPdfBytes(
      title: title,
      docNo: docNo,
      statusLabel: statusLabel,
      infoLines: infoLines,
      headers: headers,
      rows: rows,
      totalLines: totalLines,
      note: note,
      copies: copies,
    ),
  );
}
