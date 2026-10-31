import 'dart:typed_data';

import 'package:barcode/barcode.dart';
import 'package:excel/excel.dart' as excel_lib;
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../l10n/app_tr.dart';
import 'excel_download_helper.dart';
import 'excel_report_builder.dart';
import 'pos_pdf_fonts.dart';

/// Một dòng bảng liên kết Zalo (GET /api/zalo-bot/employee-links).
class ZaloLinkRow {
  ZaloLinkRow(Map<String, dynamic> m)
      : employeeId = m['employeeId']?.toString(),
        userId = m['userId']?.toString(),
        name = (m['name'] ?? '').toString(),
        employeeCode = m['employeeCode']?.toString(),
        department = m['department']?.toString(),
        phone = m['phone']?.toString(),
        hasAccount = m['hasAccount'] == true,
        linked = m['linked'] == true,
        zaloName = m['zaloName']?.toString(),
        linkedAt = DateTime.tryParse('${m['linkedAt'] ?? ''}')?.toLocal(),
        code = m['code']?.toString(),
        codeExpiresAt = DateTime.tryParse('${m['codeExpiresAt'] ?? ''}')?.toLocal();

  final String? employeeId;
  final String? userId;
  final String name;
  final String? employeeCode;
  final String? department;
  final String? phone;
  final bool hasAccount;
  final bool linked;
  final String? zaloName;
  final DateTime? linkedAt;
  final String? code;
  final DateTime? codeExpiresAt;

  /// «482 915» — dễ đọc / gõ.
  String? get codeDisplay => code == null || code!.length != 6 ? code : '${code!.substring(0, 3)} ${code!.substring(3)}';
}

final _date = DateFormat('dd/MM/yyyy');

/// Phiếu cắt — mỗi người một ô (tên, mã, QR mở bot, các bước), 2 cột × 5 hàng / trang A4.
/// Phát riêng tay từng người: ai cầm mã là liên kết được Zalo của mình với hồ sơ đó.
Future<void> printZaloLinkSlips({
  required List<ZaloLinkRow> rows,
  required String storeName,
  String? botName,
  String? botLink,
}) async {
  final bytes = await buildZaloLinkSlipsPdf(rows: rows, storeName: storeName, botName: botName, botLink: botLink);
  await Printing.layoutPdf(name: 'Ma-lien-ket-Zalo', onLayout: (_) async => bytes);
}

Future<Uint8List> buildZaloLinkSlipsPdf({
  required List<ZaloLinkRow> rows,
  required String storeName,
  String? botName,
  String? botLink,
}) async {
  final fonts = await loadPosPdfFonts();
  final theme = pw.ThemeData.withFont(base: fonts.regular, bold: fonts.bold);
  final doc = pw.Document(theme: theme);
  final bot = (botName ?? '').trim().isEmpty ? tr('bot của cửa hàng') : '«${botName!.trim()}»';
  final hasQr = (botLink ?? '').trim().startsWith('http');

  pw.Widget slip(ZaloLinkRow r) => pw.Container(
        padding: const pw.EdgeInsets.all(10),
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: PdfColors.grey600, width: 0.6, style: pw.BorderStyle.dashed),
        ),
        child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Expanded(
            child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
              pw.Text(tr('Nhận thông báo qua Zalo'), style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700)),
              pw.SizedBox(height: 2),
              pw.Text(r.name, maxLines: 1, style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
              pw.Text(
                [if ((r.employeeCode ?? '').isNotEmpty) r.employeeCode!, if ((r.department ?? '').isNotEmpty) r.department!]
                    .join(' · '),
                maxLines: 1,
                style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
              ),
              pw.SizedBox(height: 6),
              pw.Text(r.codeDisplay ?? '', style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold, letterSpacing: 2)),
              pw.SizedBox(height: 4),
              pw.Text(
                tr('1. Mở Zalo, quét QR (hoặc tìm {bot})\n2. Gửi mã 6 số ở trên cho bot\n3. Bot trả lời «Đã liên kết» là xong')
                    .replaceAll('{bot}', bot),
                style: const pw.TextStyle(fontSize: 7.5, lineSpacing: 1.5),
              ),
              if (r.codeExpiresAt != null)
                pw.Padding(
                  padding: const pw.EdgeInsets.only(top: 3),
                  child: pw.Text(tr('Mã dùng đến {d} · chỉ dành cho bạn').replaceAll('{d}', _date.format(r.codeExpiresAt!)),
                      style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey700)),
                ),
            ]),
          ),
          if (hasQr) ...[
            pw.SizedBox(width: 6),
            pw.BarcodeWidget(barcode: Barcode.qrCode(), data: botLink!.trim(), width: 70, height: 70),
          ],
        ]),
      );

  final slips = rows.where((r) => (r.code ?? '').isNotEmpty).toList();
  const perPage = 10;
  const margin = 20.0;
  // Ô cố định 2 cột × 5 hàng (≈ 277 × 148 pt): GridView trong Expanded kéo giãn ô cho đầy trang
  // khi ít người (3 người → ô cao nửa trang, trống trơn, cắt ra phí giấy).
  final slipW = (PdfPageFormat.a4.width - margin * 2) / 2;
  const slipH = 148.0;
  for (var start = 0; start < slips.length; start += perPage) {
    final page = slips.sublist(start, (start + perPage).clamp(0, slips.length));
    doc.addPage(pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(margin),
      build: (_) => pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: [
        pw.Text('${tr('Mã liên kết Zalo')} — $storeName', style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
        pw.Text(tr('Cắt theo đường chấm, phát riêng cho từng người. Không dán công khai.'),
            style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700)),
        pw.SizedBox(height: 8),
        pw.Wrap(children: [
          for (final r in page) pw.SizedBox(width: slipW, height: slipH, child: slip(r)),
        ]),
      ]),
    ));
  }
  return doc.save();
}

/// Bảng liên kết cả cửa hàng ra Excel (quản lý theo dõi ai đã / chưa liên kết).
Future<void> exportZaloLinksExcel(List<ZaloLinkRow> rows, {required String storeName}) async {
  final wb = excel_lib.Excel.createExcel();
  final sheet = wb['Liên kết Zalo'];
  sheet.appendRow([excel_lib.TextCellValue('${tr('LIÊN KẾT ZALO NHẬN THÔNG BÁO')} — $storeName')]);
  sheet.appendRow([excel_lib.TextCellValue('${tr('Xuất lúc')} ${DateFormat('HH:mm dd/MM/yyyy').format(DateTime.now())}')]);
  sheet.appendRow([]);
  final headers = ['STT', 'Họ tên', 'Mã NV', 'Phòng ban', 'Số điện thoại', 'Tài khoản app', 'Trạng thái', 'Tên Zalo', 'Mã liên kết', 'Mã dùng đến'];
  sheet.appendRow([for (final h in headers) excel_lib.TextCellValue(tr(h))]);
  var i = 0;
  for (final r in rows) {
    i++;
    sheet.appendRow([
      excel_lib.IntCellValue(i),
      excel_lib.TextCellValue(r.name),
      excel_lib.TextCellValue(r.employeeCode ?? ''),
      excel_lib.TextCellValue(r.department ?? ''),
      excel_lib.TextCellValue(r.phone ?? ''),
      excel_lib.TextCellValue(tr(r.hasAccount ? 'Có' : 'Không')),
      excel_lib.TextCellValue(tr(r.linked ? 'Đã liên kết' : 'Chưa liên kết')),
      excel_lib.TextCellValue(r.zaloName ?? ''),
      excel_lib.TextCellValue(r.codeDisplay ?? ''),
      excel_lib.TextCellValue(r.codeExpiresAt == null ? '' : _date.format(r.codeExpiresAt!)),
    ]);
  }
  wb.delete('Sheet1');
  final bytes = ExcelReportBuilder.encodeReport(wb);
  if (bytes == null) return;
  await ExcelDownloadHelper.saveExcelBytes(bytes, 'lien-ket-zalo-${DateFormat('yyyyMMdd').format(DateTime.now())}.xlsx');
}
