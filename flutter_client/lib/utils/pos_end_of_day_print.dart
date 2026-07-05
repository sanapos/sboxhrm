import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../models/pos_end_of_day_report.dart';
import '../models/pos_store_printer.dart';
import 'pos_html_print.dart';
import 'pos_print_orchestrator.dart';
import 'pos_store_printer_mapper.dart';
import 'pos_thermal_printer_service.dart';
import 'pos_thermal_printer_settings.dart';

enum PosEndOfDayPrintFormat { bill, a4 }

String buildPosEndOfDayHtml(
  PosEndOfDayReport report, {
  PosEndOfDayPrintFormat format = PosEndOfDayPrintFormat.bill,
  bool showProductDetail = true,
}) {
  return format == PosEndOfDayPrintFormat.a4
      ? _buildA4(report, showProductDetail: showProductDetail)
      : _buildBill(report, showProductDetail: showProductDetail);
}

String _money(num v) => NumberFormat('#,##0', 'vi_VN').format(v);
String _qty(num v) => NumberFormat('#,##0.##', 'vi_VN').format(v);
String _dt(DateTime d) => DateFormat('dd/MM/yyyy HH:mm').format(d.toLocal());
String _d(DateTime d) => DateFormat('dd/MM/yyyy').format(d.toLocal());

String _buildBill(PosEndOfDayReport r, {required bool showProductDetail}) {
  final staff = r.staffName ?? r.staffEmail ?? 'Tất cả nhân viên';
  final period = '${_dt(r.from)} - ${_dt(r.to)}';
  final rows = <String>[
    _billRow('1', 'Số đơn hàng / Number of orders', '', '${r.orderCount}'),
    _billRow('2', 'Chiết khấu / Total discount', '', _money(r.orderDiscount)),
    _billSub('Other', _money(r.orderDiscount)),
    _billSub('Voucher', '0'),
    _billRow('3', 'Tổng doanh thu / Total sales', '', _money(r.totalSales)),
    _billRow('4', 'VAT', '', _money(r.vat)),
    _billRow('5', 'Tổng doanh thu ròng / Net sales', '', _money(r.netSales)),
    _billRow('6', 'Trả hàng / Refund', '', _money(r.refundTotal)),
    _billRow('', 'Doanh thu trừ trả hàng / Total after refund', '', _money(r.totalAfterRefund)),
    _billRow('7', 'Hóa đơn hủy / Invoice canceled', '', '${r.canceledCount}'),
    _billRow('8', 'Phương thức thanh toán / Payment method', '', ''),
    _billSub('Tiền mặt / Cash', _money(r.cashTotal)),
    _billSub('Ghi nợ / Debt', _money(r.debtTotal)),
    ...r.payments
        .where((p) =>
            !p.paymentMethod.toLowerCase().contains('mặt') &&
            p.paymentMethod.toLowerCase() != 'cash')
        .map((p) => _billSub(p.paymentMethod, _money(p.total))),
    _billRow('9', 'Thực thu', '', _money(r.actualReceived)),
    if (showProductDetail) ...[
      _billRow('10', 'Hàng hóa bán ra / Product sales', '', ''),
      ...r.products.map((p) => _billProduct(p.productName, _qty(p.qty), _money(p.revenue))),
      _billRow('11', 'Giảm giá trên mặt hàng / Discount on products', '', _money(r.lineDiscountTotal)),
    ],
  ];

  return '''
<!DOCTYPE html>
<html><head><meta charset="utf-8"/>
<style>
  @page { margin: 4mm; size: 80mm auto; }
  body { font-family: Arial, sans-serif; font-size: 11px; margin: 0; color: #111; }
  h1 { font-size: 14px; text-align: center; margin: 0 0 8px; }
  .meta { text-align: center; font-size: 10px; margin-bottom: 10px; line-height: 1.4; }
  table { width: 100%; border-collapse: collapse; }
  td { padding: 3px 2px; vertical-align: top; border-bottom: 1px solid #ddd; }
  .idx { width: 18px; }
  .amt { text-align: right; white-space: nowrap; width: 72px; }
  .sub td:first-child { padding-left: 18px; color: #444; }
  .sub .label { font-size: 10px; }
  .footer { margin-top: 12px; font-size: 9px; text-align: center; color: #666; }
</style></head><body>
  <h1>TỔNG KẾT CUỐI NGÀY</h1>
  <div class="meta">
    ${r.storeName != null && r.storeName!.isNotEmpty ? '<div><b>${_esc(r.storeName!)}</b></div>' : ''}
    <div>Nhân viên: ${_esc(staff)}</div>
    <div>$period</div>
  </div>
  <table>${rows.join()}</table>
  <div class="footer">In lúc ${_dt(r.generatedAt)} · SBOX POS</div>
</body></html>''';
}

String _billRow(String idx, String label, String mid, String amt) => '''
<tr>
  <td class="idx">${_esc(idx)}</td>
  <td>${_esc(label)}</td>
  <td class="mid">${_esc(mid)}</td>
  <td class="amt">${_esc(amt)}</td>
</tr>''';

String _billSub(String label, String amt) => '''
<tr class="sub">
  <td></td>
  <td class="label">${_esc(label)}</td>
  <td></td>
  <td class="amt">${_esc(amt)}</td>
</tr>''';

String _billProduct(String name, String qty, String amt) => '''
<tr class="sub">
  <td></td>
  <td class="label">${_esc(name)}</td>
  <td style="text-align:center">${_esc(qty)}</td>
  <td class="amt">${_esc(amt)}</td>
</tr>''';

String _buildA4(PosEndOfDayReport r, {required bool showProductDetail}) {
  final staff = r.staffName ?? r.staffEmail ?? 'Tất cả nhân viên';
  final summaryRows = '''
    <tr><td>Số đơn hàng</td><td class="r">${r.orderCount}</td></tr>
    <tr><td>Chiết khấu đơn</td><td class="r">${_money(r.orderDiscount)}</td></tr>
    <tr><td>Tổng doanh thu</td><td class="r">${_money(r.totalSales)}</td></tr>
    <tr><td>VAT</td><td class="r">${_money(r.vat)}</td></tr>
    <tr><td>Doanh thu ròng</td><td class="r">${_money(r.netSales)}</td></tr>
    <tr><td>Trả hàng</td><td class="r">${_money(r.refundTotal)}</td></tr>
    <tr><td>Sau trả hàng</td><td class="r">${_money(r.totalAfterRefund)}</td></tr>
    <tr><td>Hóa đơn hủy</td><td class="r">${r.canceledCount} (${_money(r.canceledTotal)})</td></tr>
    <tr><td>Tiền mặt</td><td class="r">${_money(r.cashTotal)}</td></tr>
    <tr><td>Ghi nợ</td><td class="r">${_money(r.debtTotal)}</td></tr>
    <tr><td><b>Thực thu</b></td><td class="r"><b>${_money(r.actualReceived)}</b></td></tr>
    <tr><td>Giảm giá dòng hàng</td><td class="r">${_money(r.lineDiscountTotal)}</td></tr>
  ''';

  final productTable = showProductDetail && r.products.isNotEmpty
      ? '''
<h3>Hàng hóa bán ra</h3>
<table class="grid">
  <thead><tr>
    <th>STT</th><th>Tên hàng</th><th class="r">SL</th><th class="r">Doanh thu</th><th class="r">Giảm giá</th>
  </tr></thead>
  <tbody>
    ${r.products.asMap().entries.map((e) {
      final p = e.value;
      return '<tr><td>${e.key + 1}</td><td>${_esc(p.productName)}</td>'
          '<td class="r">${_qty(p.qty)}</td><td class="r">${_money(p.revenue)}</td>'
          '<td class="r">${_money(p.lineDiscount)}</td></tr>';
    }).join()}
  </tbody>
</table>'''
      : '';

  final txTable = r.transactions.isNotEmpty
      ? '''
<h3>Chi tiết giao dịch</h3>
<table class="grid">
  <thead><tr>
    <th>Mã GD</th><th>Thời gian</th><th class="r">SL</th><th class="r">Doanh thu</th>
    <th class="r">VAT</th><th class="r">Phí trả</th><th class="r">Thực thu</th><th>HTTT</th>
  </tr></thead>
  <tbody>
    ${r.transactions.map((t) => '''
      <tr>
        <td>${_esc(t.orderNo)}</td>
        <td>${_dt(t.createdAt)}</td>
        <td class="r">${_qty(t.qty)}</td>
        <td class="r">${_money(t.revenue)}</td>
        <td class="r">${_money(t.vat)}</td>
        <td class="r">${_money(t.returnFee)}</td>
        <td class="r">${_money(t.actualReceived)}</td>
        <td>${_esc(t.paymentMethod)}</td>
      </tr>''').join()}
  </tbody>
</table>'''
      : '';

  return '''
<!DOCTYPE html>
<html><head><meta charset="utf-8"/>
<style>
  @page { size: A4; margin: 12mm; }
  body { font-family: Arial, sans-serif; font-size: 12px; color: #111; }
  h1 { text-align: center; font-size: 20px; margin: 0 0 4px; }
  h2 { font-size: 14px; margin: 16px 0 8px; color: #2563EB; }
  h3 { font-size: 13px; margin: 14px 0 6px; }
  .meta { text-align: center; margin-bottom: 16px; line-height: 1.5; }
  table.sum { width: 100%; max-width: 520px; margin: 0 auto 12px; border-collapse: collapse; }
  table.sum td { padding: 5px 8px; border-bottom: 1px solid #e5e7eb; }
  table.sum td.r { text-align: right; font-variant-numeric: tabular-nums; }
  table.grid { width: 100%; border-collapse: collapse; font-size: 11px; }
  table.grid th, table.grid td { border: 1px solid #d1d5db; padding: 5px 6px; }
  table.grid th { background: #f3f4f6; text-align: left; }
  table.grid td.r, table.grid th.r { text-align: right; }
  .footer { margin-top: 20px; text-align: center; font-size: 10px; color: #666; }
</style></head><body>
  <h1>BÁO CÁO CUỐI NGÀY VỀ BÁN HÀNG</h1>
  <div class="meta">
    ${r.storeName != null && r.storeName!.isNotEmpty ? '<div><b>${_esc(r.storeName!)}</b></div>' : ''}
    <div>Ngày bán: ${_d(r.from)} – ${_d(r.to)}</div>
    <div>Nhân viên: ${_esc(staff)}</div>
  </div>
  <h2>Tổng kết</h2>
  <table class="sum">$summaryRows</table>
  $productTable
  $txTable
  <div class="footer">In lúc ${_dt(r.generatedAt)} · SBOX POS</div>
</body></html>''';
}

String _esc(String s) =>
    s.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;');

Future<Uint8List> buildPosEndOfDayPdfBytes(
  PosEndOfDayReport r, {
  PosEndOfDayPrintFormat format = PosEndOfDayPrintFormat.bill,
  bool showProductDetail = true,
}) async {
  final pdf = pw.Document();
  final staff = r.staffName ?? r.staffEmail ?? 'Tất cả nhân viên';
  final pageFormat = format == PosEndOfDayPrintFormat.a4
      ? PdfPageFormat.a4
      : PdfPageFormat.roll80;

  pw.Widget row(String label, String value, {bool bold = false}) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 2),
        child: pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Expanded(
              child: pw.Text(label,
                  style: pw.TextStyle(
                      fontSize: 9,
                      fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal)),
            ),
            pw.SizedBox(width: 8),
            pw.Text(value,
                style: pw.TextStyle(
                    fontSize: 9,
                    fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal)),
          ],
        ),
      );

  pdf.addPage(
    pw.Page(
      pageFormat: pageFormat,
      margin: const pw.EdgeInsets.all(12),
      build: (ctx) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          pw.Center(
            child: pw.Text('TỔNG KẾT CUỐI NGÀY',
                style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold)),
          ),
          pw.SizedBox(height: 6),
          if (r.storeName != null && r.storeName!.isNotEmpty)
            pw.Center(child: pw.Text(r.storeName!, style: const pw.TextStyle(fontSize: 10))),
          pw.Center(child: pw.Text('Nhân viên: $staff', style: const pw.TextStyle(fontSize: 9))),
          pw.Center(
            child: pw.Text('${_dt(r.from)} - ${_dt(r.to)}',
                style: const pw.TextStyle(fontSize: 9)),
          ),
          pw.SizedBox(height: 10),
          row('Số đơn hàng', '${r.orderCount}'),
          row('Chiết khấu', _money(r.orderDiscount)),
          row('Tổng doanh thu', _money(r.totalSales)),
          row('VAT', _money(r.vat)),
          row('Doanh thu ròng', _money(r.netSales)),
          row('Trả hàng', _money(r.refundTotal)),
          row('Sau trả hàng', _money(r.totalAfterRefund)),
          row('Tiền mặt', _money(r.cashTotal)),
          row('Ghi nợ', _money(r.debtTotal)),
          row('Thực thu', _money(r.actualReceived), bold: true),
          if (showProductDetail && r.products.isNotEmpty) ...[
            pw.SizedBox(height: 8),
            pw.Text('Hàng hóa bán ra',
                style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
            ...r.products.take(30).map(
                  (p) => row(
                    p.productName,
                    '${_qty(p.qty)} · ${_money(p.revenue)}',
                  ),
                ),
          ],
          pw.Spacer(),
          pw.Center(
            child: pw.Text('In lúc ${_dt(r.generatedAt)} · SBOX POS',
                style: const pw.TextStyle(fontSize: 8)),
          ),
        ],
      ),
    ),
  );

  return Uint8List.fromList(await pdf.save());
}

Future<void> printPosEndOfDayReport(
  BuildContext context,
  PosEndOfDayReport report, {
  PosEndOfDayPrintFormat format = PosEndOfDayPrintFormat.bill,
  bool showProductDetail = true,
}) async {
  if (!kIsWeb && format == PosEndOfDayPrintFormat.bill) {
    await PosPrintOrchestrator.instance.refreshConfig();
    final printers = PosPrintOrchestrator.instance
        .resolvePrinters(PosCloudDocumentTypes.endOfDayReport);
    final local = await PosThermalPrinterSettings.load();
    final lines =
        _buildEodThermalLines(report, showProductDetail: showProductDetail);

    if (printers.isNotEmpty) {
      final ok = await PosPrintOrchestrator.instance.dispatchEscPosToAll(
        documentType: PosCloudDocumentTypes.endOfDayReport,
        referenceNo: 'EOD-${_d(report.from)}',
        showFeedback: true,
        successTitle: 'In cuối ngày',
        buildBytes: (printer) async {
          final settings = toThermalSettings(printer);
          return PosThermalPrinterService.buildTextEscPosBytes(
            settings: settings,
            title: 'TỔNG KẾT CUỐI NGÀY',
            lines: lines,
            footer: 'In lúc ${_dt(report.generatedAt)} · SBOX POS',
          );
        },
      );
      if (ok) return;
    }

    if (local.enabled) {
      final bytes = await PosThermalPrinterService.buildTextEscPosBytes(
        settings: local,
        title: 'TỔNG KẾT CUỐI NGÀY',
        lines: lines,
        footer: 'In lúc ${_dt(report.generatedAt)} · SBOX POS',
      );
      final ok = await PosPrintOrchestrator.instance.dispatchLocalEscPos(
        bytes: bytes,
        showFeedback: true,
        successTitle: 'In cuối ngày',
        settingsOverride: local,
      );
      if (ok) return;
    }
  }

  final bytes = await buildPosEndOfDayPdfBytes(
    report,
    format: format,
    showProductDetail: showProductDetail,
  );
  final title = format == PosEndOfDayPrintFormat.a4
      ? 'TongKetCuoiNgay_A4'
      : 'TongKetCuoiNgay_Bill';

  if (!context.mounted) return;

  if (kIsWeb) {
    final html = buildPosEndOfDayHtml(
      report,
      format: format,
      showProductDetail: showProductDetail,
    );
    await showPosHtmlPrintDialog(context, title: title, htmlDocument: html);
    return;
  }

  await showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('In tổng kết cuối ngày'),
      content: const Text('Chọn cách in hoặc xuất PDF.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Đóng')),
        OutlinedButton(
          onPressed: () async {
            Navigator.pop(ctx);
            await Printing.layoutPdf(
              onLayout: (_) async => bytes,
              name: title,
            );
          },
          child: const Text('In'),
        ),
        FilledButton(
          onPressed: () async {
            Navigator.pop(ctx);
            await Printing.sharePdf(bytes: bytes, filename: '$title.pdf');
          },
          child: const Text('Xuất PDF'),
        ),
      ],
    ),
  );
}

List<String> _buildEodThermalLines(
  PosEndOfDayReport r, {
  required bool showProductDetail,
}) {
  final staff = r.staffName ?? r.staffEmail ?? 'Tất cả';
  final lines = <String>[
    if (r.storeName != null && r.storeName!.isNotEmpty) r.storeName!,
    'Nhân viên: $staff',
    '${_dt(r.from)} - ${_dt(r.to)}',
    '────────────────',
    'Số đơn: ${r.orderCount}',
    'Chiết khấu: ${_money(r.orderDiscount)}',
    'Doanh thu: ${_money(r.totalSales)}',
    'VAT: ${_money(r.vat)}',
    'Doanh thu ròng: ${_money(r.netSales)}',
    'Trả hàng: ${_money(r.refundTotal)}',
    'Sau trả hàng: ${_money(r.totalAfterRefund)}',
    'Hủy đơn: ${r.canceledCount}',
    'Tiền mặt: ${_money(r.cashTotal)}',
    'Ghi nợ: ${_money(r.debtTotal)}',
    'Thực thu: ${_money(r.actualReceived)}',
  ];
  if (showProductDetail && r.products.isNotEmpty) {
    lines.add('── Hàng bán ──');
    for (final p in r.products.take(20)) {
      lines.add('${p.productName}: ${_qty(p.qty)} · ${_money(p.revenue)}');
    }
    if (r.products.length > 20) {
      lines.add('... và ${r.products.length - 20} mặt hàng');
    }
    lines.add('CK mặt hàng: ${_money(r.lineDiscountTotal)}');
  }
  return lines;
}
