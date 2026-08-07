import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../models/pos_stock_count.dart';
import '../widgets/pos/pos_stock_count_helpers.dart';
import 'pos_pdf_fonts.dart';
import 'pos_purchase_receipt_print.dart';
import 'package:sbox_pos/l10n/app_tr.dart';

/// PDF phiếu kiểm kho kiểu KiotViet (A4 ngang, font tiếng Việt).
Future<Uint8List> buildPosStockCountPdfBytes({
  required PosStockCount count,
  String? branchName,
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
  final created = count.createdAt?.toLocal() ?? DateTime.now();
  final balanced = count.completedAt?.toLocal();

  final increaseValue = count.lines
      .where((l) => l.diffQty > 0)
      .fold<double>(0, (a, l) => a + l.diffValue);
  final decreaseValue = count.lines
      .where((l) => l.diffQty < 0)
      .fold<double>(0, (a, l) => a + l.diffValue.abs());

  pw.Widget pageContent() => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Center(child: pw.Text(tr('PHIẾU KIỂM KHO'), style: bold20)),
          pw.SizedBox(height: 10),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(tr('Mã phiếu: ${count.countNo}'), style: body10),
              pw.Text(tr('Trạng thái: ${stockCountStatusLabel(count.status)}'), style: body10),
            ],
          ),
          pw.SizedBox(height: 6),
          if (branchName != null && branchName.isNotEmpty)
            pw.Text(tr('Chi nhánh kiểm: $branchName'), style: body10),
          pw.Text('${tr('Người tạo: ')}${count.createdBy ?? '—'} · Ngày tạo: ${dateFmt.format(created)}',
              style: body10),
          if (balanced != null)
            pw.Text('${tr('Người cân bằng: ')}${count.balancedBy ?? '—'} · Ngày cân bằng: ${dateFmt.format(balanced)}',
                style: body10),
          pw.SizedBox(height: 12),
          pw.TableHelper.fromTextArray(
            headers: const [
              'STT',
              'Mã hàng',
              'Tên hàng',
              'Tồn kho',
              'Kiểm thực tế',
              'SL lệch',
              'Giá trị lệch',
            ],
            data: List.generate(count.lines.length, (i) {
              final l = count.lines[i];
              final unitSuffix =
                  l.unitName != null && l.unitName!.isNotEmpty ? ' (${l.unitName})' : '';
              final name = '${l.productName}$unitSuffix';
              final actual = l.countedQty != null ? qtyFmt.format(l.countedQty) : '—';
              final diffStr = l.countedQty != null
                  ? '${l.diffQty >= 0 ? '+' : ''}${qtyFmt.format(l.diffQty)}'
                  : '—';
              final diffVal = l.countedQty != null ? money.format(l.diffValue) : '—';
              return [
                '${i + 1}',
                l.productCode,
                name,
                qtyFmt.format(l.systemQty),
                actual,
                diffStr,
                diffVal,
              ];
            }),
            headerStyle: bold9,
            cellStyle: body9,
            cellAlignment: pw.Alignment.centerLeft,
          ),
          pw.SizedBox(height: 10),
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(
                child: count.note != null && count.note!.isNotEmpty
                    ? pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text(tr('Ghi chú:'), style: bold10),
                          pw.Text(count.note!, style: body10),
                        ],
                      )
                    : pw.SizedBox(),
              ),
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Text(tr('Tổng thực tế (${qtyFmt.format(count.totalActualQty)}): ${money.format(count.totalActualValue)}'),
                      style: body10),
                  pw.Text(tr('Tổng lệch tăng (${qtyFmt.format(count.qtyIncrease)}): ${money.format(increaseValue)}'),
                      style: body10),
                  pw.Text(tr('Tổng lệch giảm (${qtyFmt.format(count.qtyDecrease)}): ${money.format(decreaseValue)}'),
                      style: body10),
                  pw.Text(tr('Tổng chênh lệch (${qtyFmt.format(count.totalDiffQty)}): ${money.format(count.totalDiffValue)}'),
                      style: bold10),
                ],
              ),
            ],
          ),
        ],
      );

  for (var c = 0; c < copies; c++) {
    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.all(28),
        build: (_) => pageContent(),
      ),
    );
  }

  return Uint8List.fromList(await pdf.save());
}

Future<void> printPosStockCount({
  required BuildContext context,
  required PosStockCount count,
  String? branchName,
}) async {
  await showPosPurchaseReceiptPrintDialog(
    context,
    title: 'Phiếu kiểm kho ${count.countNo}',
    buildPdf: (copies) => buildPosStockCountPdfBytes(
      count: count,
      branchName: branchName,
      copies: copies,
    ),
  );
}
