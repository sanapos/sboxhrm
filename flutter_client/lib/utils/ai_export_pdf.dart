import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'pos_pdf_fonts.dart';

/// Quá số dòng này PDF mất nhiều phút để dựng trên máy yếu — phần còn lại xem trong Excel.
const int aiExportPdfMaxRows = 1000;

/// PDF câu trả lời của Trợ lý ảo: các bảng số liệu của báo cáo (GET exports/{id}), nhận xét AI in tách riêng ở cuối.
Future<Uint8List> buildAiExportPdf(Map<String, dynamic> doc) async {
  final fonts = await loadPosPdfFonts();
  final money = NumberFormat('#,##0.##', 'en_US');
  String cell(dynamic v) {
    if (v == null) return '';
    // Kiểu Việt Nam: 1.234.567,5 — «99.9» dễ đọc nhầm thành 99 nghìn.
    if (v is num) return money.format(v).replaceAll(',', '#').replaceAll('.', ',').replaceAll('#', '.');
    return v.toString();
  }

  final pdf = pw.Document(theme: pw.ThemeData.withFont(base: fonts.regular, bold: fonts.bold));
  final content = <pw.Widget>[
    pw.Text((doc['title'] ?? 'Báo cáo').toString(), style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
    pw.SizedBox(height: 2),
    pw.Text('Xuất lúc ${DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now())} — từ Trợ lý ảo SBOX',
        style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700)),
  ];
  for (final raw in (doc['tables'] as List? ?? const [])) {
    final t = Map<String, dynamic>.from(raw as Map);
    final columns = (t['columns'] as List? ?? const []).map((e) => e.toString()).toList();
    final rows = (t['rows'] as List? ?? const []).whereType<List>().toList();
    if (columns.isEmpty) continue;
    final shown = rows.take(aiExportPdfMaxRows).toList();
    final numeric = <int, pw.Alignment>{
      for (var c = 0; c < columns.length; c++)
        if (shown.any((r) => c < r.length && r[c] is num)) c: pw.Alignment.centerRight,
    };
    final size = columns.length > 10 ? 6.5 : (columns.length > 6 ? 7.5 : 8.5);
    content.addAll([
      pw.SizedBox(height: 14),
      pw.Text((t['title'] ?? '').toString(), style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
      if ((t['period'] ?? '').toString().isNotEmpty)
        pw.Text('Kỳ dữ liệu: ${t['period']}', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700)),
      pw.SizedBox(height: 4),
      pw.TableHelper.fromTextArray(
        headers: columns,
        data: shown.map((r) => List.generate(columns.length, (c) => c < r.length ? cell(r[c]) : '')).toList(),
        headerStyle: pw.TextStyle(fontSize: size, fontWeight: pw.FontWeight.bold, color: PdfColors.white),
        headerDecoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFF6366F1)),
        cellStyle: pw.TextStyle(fontSize: size),
        cellAlignments: numeric,
        cellPadding: const pw.EdgeInsets.symmetric(horizontal: 3, vertical: 2),
        oddRowDecoration: const pw.BoxDecoration(color: PdfColors.grey100),
        border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.4),
      ),
      if (rows.length > aiExportPdfMaxRows || t['truncated'] == true)
        pw.Padding(
          padding: const pw.EdgeInsets.only(top: 3),
          child: pw.Text(
              rows.length > aiExportPdfMaxRows
                  ? 'Chỉ in $aiExportPdfMaxRows / ${rows.length} dòng — xuất Excel để xem đủ.'
                  : 'Danh sách đã bị giới hạn — muốn đủ dữ liệu, xuất từ màn báo cáo tương ứng.',
              style: const pw.TextStyle(fontSize: 8, color: PdfColors.orange800)),
        ),
    ]);
  }
  final reply = (doc['reply'] ?? '').toString().trim();
  if (reply.isNotEmpty) {
    content.addAll([
      pw.SizedBox(height: 16),
      pw.Text('Nhận xét của Trợ lý ảo (do AI viết — đối chiếu với các bảng số liệu)',
          style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
      pw.SizedBox(height: 4),
      for (final line in reply.split('\n'))
        pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 2),
          child: pw.Text(line, style: const pw.TextStyle(fontSize: 9, lineSpacing: 1.5)),
        ),
    ]);
  }
  pdf.addPage(pw.MultiPage(
    pageFormat: PdfPageFormat.a4.landscape,
    margin: const pw.EdgeInsets.all(24),
    maxPages: 200,
    footer: (ctx) => pw.Align(
      alignment: pw.Alignment.centerRight,
      child: pw.Text('Trang ${ctx.pageNumber} / ${ctx.pagesCount}', style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey600)),
    ),
    build: (_) => content,
  ));
  return pdf.save();
}
