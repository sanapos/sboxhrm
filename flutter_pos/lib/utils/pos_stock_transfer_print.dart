import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'pos_pdf_fonts.dart';
import 'api_datetime.dart';
import 'pos_purchase_receipt_print.dart';
import 'package:sbox_pos/l10n/app_tr.dart';

/// PDF phiếu chuyển kho (A4 dọc) — dữ liệu là JSON phiếu từ /api/branch-ops/transfers.
Future<Uint8List> buildPosStockTransferPdfBytes({
  required Map<String, dynamic> transfer,
  int copies = 1,
}) async {
  final fonts = await loadPosPdfFonts();
  final pdf = pw.Document(
    theme: pw.ThemeData.withFont(base: fonts.regular, bold: fonts.bold),
  );
  final body10 = pw.TextStyle(font: fonts.regular, fontSize: 10);
  final bold10 = pw.TextStyle(font: fonts.bold, fontSize: 10);
  final bold20 = pw.TextStyle(font: fonts.bold, fontSize: 20);
  final qtyFmt = NumberFormat('#,##0.###', 'vi_VN');
  final dateFmt = DateFormat('dd/MM/yyyy HH:mm');

  num n(Object? v) => v is num ? v : num.tryParse('$v') ?? 0;
  String date(Object? v) {
    final d = v == null ? null : parseApiUtcDateTime(v);
    return d == null ? '—' : dateFmt.format(d.toLocal());
  }

  final lines = [for (final l in (transfer['lines'] as List? ?? const [])) Map<String, dynamic>.from(l as Map)];
  final received = lines.any((l) => l['receivedQty'] != null);

  pw.Widget signature(String label) => pw.Expanded(
        child: pw.Column(children: [
          pw.Text(tr(label), style: bold10),
          pw.Text(tr('(Ký, ghi rõ họ tên)'), style: body10),
          pw.SizedBox(height: 50),
        ]),
      );

  pw.Widget pageContent() => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Center(child: pw.Text(tr('PHIẾU CHUYỂN KHO'), style: bold20)),
          pw.SizedBox(height: 10),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(tr('Mã phiếu: ${transfer['transferNo'] ?? ''}'), style: body10),
              pw.Text(tr('Trạng thái: ${transfer['statusLabel'] ?? ''}'), style: body10),
            ],
          ),
          pw.SizedBox(height: 6),
          pw.Text(tr('Kho đi: ${transfer['fromBranchName'] ?? ''}'), style: bold10),
          pw.Text(tr('Kho đến: ${transfer['toBranchName'] ?? ''}'), style: bold10),
          pw.SizedBox(height: 4),
          pw.Text(tr('Ngày tạo: ${date(transfer['createdAt'])} · ${transfer['createdByName'] ?? '—'}'), style: body10),
          if (transfer['sentAt'] != null)
            pw.Text(tr('Ngày gửi: ${date(transfer['sentAt'])} · ${transfer['sentByName'] ?? '—'}'), style: body10),
          if (transfer['receivedAt'] != null)
            pw.Text(tr('Ngày nhận: ${date(transfer['receivedAt'])} · ${transfer['receivedByName'] ?? '—'}'),
                style: body10),
          pw.SizedBox(height: 12),
          pw.TableHelper.fromTextArray(
            headers: [
              'STT',
              tr('Mã hàng'),
              tr('Tên hàng'),
              tr('ĐVT'),
              tr('SL gửi'),
              if (received) tr('SL nhận'),
            ],
            data: List.generate(lines.length, (i) {
              final l = lines[i];
              return [
                '${i + 1}',
                '${l['sku'] ?? ''}',
                '${l['productName'] ?? ''}',
                '${l['unit'] ?? ''}',
                qtyFmt.format(n(l['qty'])),
                if (received) l['receivedQty'] == null ? '—' : qtyFmt.format(n(l['receivedQty'])),
              ];
            }),
            headerStyle: bold10,
            cellStyle: body10,
            cellAlignment: pw.Alignment.centerLeft,
          ),
          pw.SizedBox(height: 8),
          pw.Align(
            alignment: pw.Alignment.centerRight,
            child: pw.Text(tr('Tổng số lượng: ${qtyFmt.format(n(transfer['totalQty']))}'), style: bold10),
          ),
          if ((transfer['note'] ?? '').toString().isNotEmpty) ...[
            pw.SizedBox(height: 6),
            pw.Text(tr('Ghi chú: ${transfer['note']}'), style: body10),
          ],
          pw.SizedBox(height: 24),
          pw.Row(children: [
            signature('Người lập phiếu'),
            signature('Người giao hàng'),
            signature('Người nhận hàng'),
          ]),
        ],
      );

  for (var c = 0; c < copies; c++) {
    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (_) => pageContent(),
      ),
    );
  }
  return Uint8List.fromList(await pdf.save());
}

Future<void> printPosStockTransfer({
  required BuildContext context,
  required Map<String, dynamic> transfer,
}) {
  return showPosPurchaseReceiptPrintDialog(
    context,
    title: 'Phiếu chuyển kho ${transfer['transferNo'] ?? ''}',
    buildPdf: (copies) => buildPosStockTransferPdfBytes(transfer: transfer, copies: copies),
  );
}
