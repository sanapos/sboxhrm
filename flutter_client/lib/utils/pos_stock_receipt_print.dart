import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../models/pos_product.dart';
import 'package:zkteco_flutter_client/l10n/app_tr.dart';

/// In phiếu nhập kho POS (PDF A4).
Future<void> printPosStockReceipt(PosStockReceipt receipt) async {
  final pdf = pw.Document();
  final money = NumberFormat('#,##0', 'vi_VN');
  final dateFmt = DateFormat('dd/MM/yyyy HH:mm');

  pdf.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(32),
      build: (ctx) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Center(
            child: pw.Text(tr('PHIẾU NHẬP KHO'),
                style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
          ),
          pw.SizedBox(height: 8),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(tr('Số phiếu: ${receipt.receiptNo}')),
              pw.Text(tr('Ngày: ${dateFmt.format(receipt.createdAt.toLocal())}')),
            ],
          ),
          if (receipt.supplierName != null && receipt.supplierName!.isNotEmpty)
            pw.Text(tr('Nhà cung cấp: ${receipt.supplierName}')),
          if (receipt.note != null && receipt.note!.isNotEmpty)
            pw.Text(tr('Ghi chú: ${receipt.note}')),
          pw.SizedBox(height: 16),
          pw.Table.fromTextArray(
            headers: ['STT', 'Mã hàng', 'Tên hàng', 'SL', 'Giá vốn', 'Thành tiền'],
            data: List.generate(receipt.lines.length, (i) {
              final l = receipt.lines[i];
              return [
                '${i + 1}',
                l.productCode,
                l.productName,
                money.format(l.qty),
                money.format(l.costPrice),
                money.format(l.lineTotal),
              ];
            }),
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9),
            cellStyle: const pw.TextStyle(fontSize: 9),
            cellAlignment: pw.Alignment.centerLeft,
          ),
          pw.SizedBox(height: 12),
          pw.Align(
            alignment: pw.Alignment.centerRight,
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                pw.Text(tr('Tổng SL: ${money.format(receipt.totalQty)}')),
                pw.Text(tr('Tổng tiền: ${money.format(receipt.totalCost)}'),
                    style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
              ],
            ),
          ),
          pw.Spacer(),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
            children: [
              pw.Column(children: [
                pw.Text(tr('Người lập phiếu')),
                pw.SizedBox(height: 40),
                pw.Text(receipt.createdBy ?? ''),
              ]),
              pw.Column(children: [
                pw.Text(tr('Thủ kho')),
                pw.SizedBox(height: 40),
                pw.Text(''),
              ]),
            ],
          ),
        ],
      ),
    ),
  );

  final bytes = await pdf.save();
  await Printing.sharePdf(
    bytes: Uint8List.fromList(bytes),
    filename: 'PhieuNhap_${receipt.receiptNo}.pdf',
  );
}
