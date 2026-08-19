import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../models/pos_end_of_day_report.dart';
import '../models/pos_store_printer.dart';
import '../widgets/notification_overlay.dart';
import 'pos_html_print.dart';
import 'pos_print_orchestrator.dart';
import 'pos_printer_transport.dart';
import 'pos_store_printer_mapper.dart';
import 'pos_sunmi_native_print.dart';
import 'pos_thermal_printer_service.dart';
import 'pos_thermal_printer_settings.dart';
import 'package:zkteco_flutter_client/l10n/app_tr.dart';

enum PosEndOfDayPrintFormat {
  /// Bill nhiệt 58mm (Sunmi V2s / K58).
  bill58,

  /// Bill nhiệt 80mm.
  bill80,

  /// Báo cáo A4.
  a4;

  bool get isThermalBill => this == bill58 || this == bill80;

  int get paperWidthMm => switch (this) {
        bill58 => 58,
        bill80 => 80,
        a4 => 210,
      };

  int get thermalChars => paperWidthMm <= 58 ? 32 : 48;

  String get label => switch (this) {
        bill58 => 'Bill K58',
        bill80 => 'Bill K80',
        a4 => 'Khổ A4',
      };
}

String buildPosEndOfDayHtml(
  PosEndOfDayReport report, {
  PosEndOfDayPrintFormat format = PosEndOfDayPrintFormat.bill58,
  bool showProductDetail = true,
}) {
  return format == PosEndOfDayPrintFormat.a4
      ? _buildA4(report, showProductDetail: showProductDetail)
      : _buildBillHtml(
          report,
          showProductDetail: showProductDetail,
          paperWidthMm: format.paperWidthMm,
        );
}

String _money(num v) => NumberFormat('#,##0', 'vi_VN').format(v);
String _qty(num v) => NumberFormat('#,##0.##', 'vi_VN').format(v);
String _dt(DateTime d) => DateFormat('dd/MM/yyyy HH:mm').format(d.toLocal());
String _d(DateTime d) => DateFormat('dd/MM/yyyy').format(d.toLocal());
String _dtShort(DateTime d) => DateFormat('dd/MM HH:mm').format(d.toLocal());

String _lr(String left, String right, int width) {
  final r = right.trim();
  final gap = 1;
  final maxL = (width - r.length - gap).clamp(4, width);
  var l = left.trim();
  if (l.length > maxL) l = '${l.substring(0, maxL - 1)}…';
  return '${l.padRight(maxL)}${' ' * gap}$r';
}

String _rule(int width, [String ch = '-']) =>
    List.filled(width.clamp(8, 64), ch).join();

/// Dòng thermal đã căn trái/phải theo khổ giấy.
class _EodThermalLayout {
  _EodThermalLayout(this.report, {required this.chars, required this.showProductDetail});

  final PosEndOfDayReport report;
  final int chars;
  final bool showProductDetail;

  String get staff =>
      report.staffName ?? report.staffEmail ?? 'Tất cả nhân viên';

  List<String> buildLines() {
    final r = report;
    final lines = <String>[
      if (r.storeName != null && r.storeName!.trim().isNotEmpty) r.storeName!.trim(),
      _rule(chars, '='),
      'NV: $staff',
      'Từ: ${_dtShort(r.from)}',
      'Đến: ${_dtShort(r.to)}',
      _rule(chars),
      '>> BÁN HÀNG',
      _lr('Số đơn', '${r.orderCount}', chars),
      _lr('Doanh thu', _money(r.totalSales), chars),
      _lr('Chiết khấu', _money(r.orderDiscount), chars),
      _lr('VAT', _money(r.vat), chars),
      _lr('DT ròng', _money(r.netSales), chars),
      if (r.closedOffDayOrders.isNotEmpty) ...[
        _rule(chars),
        '>> CHỐT NGÀY KHÁC',
        _lr('Số HĐ', '${r.closedOffDayCount}', chars),
        for (final o in r.closedOffDayOrders.take(chars <= 32 ? 8 : 15))
          _lr(o.orderNo, o.draftDayLabel, chars),
      ],
      _rule(chars),
      '>> TRẢ / HỦY',
      _lr('Trả hàng', _money(r.refundTotal), chars),
      _lr('Sau trả', _money(r.totalAfterRefund), chars),
      _lr('Hủy đơn', '${r.canceledCount}', chars),
      if (r.canceledTotal > 0) _lr('GT hủy', _money(r.canceledTotal), chars),
      _rule(chars),
      '>> THANH TOÁN BÁN HÀNG',
      _lr('Tiền mặt HĐ', _money(r.cashTotal), chars),
      _lr('Ghi nợ', _money(r.debtTotal), chars),
    ];

    for (final p in r.payments) {
      final m = p.paymentMethod.toLowerCase();
      if (m.contains('mặt') || m == 'cash' || m.contains('ghi nợ') || m.contains('debt')) {
        continue;
      }
      lines.add(_lr(p.paymentMethod, _money(p.total), chars));
    }
    lines.addAll([
      _lr('Thực thu HĐ', _money(r.actualReceived), chars),
      _rule(chars),
      '>> CỌC ĐẶT BÀN',
      _lr('Thu cọc hôm nay', _money(r.depositCollected), chars),
      for (final p in r.depositByPayment)
        _lr(p.paymentMethod, _money(p.total), chars),
      _lr('Hoàn cọc', _money(r.depositRefunded), chars),
      _lr('Mất cọc', _money(r.depositForfeited), chars),
      _lr('Đang giữ', _money(r.depositHeld), chars),
      _lr('Đã trừ HĐ', _money(r.depositApplied), chars),
      _rule(chars),
      _lr('TIỀN MẶT KÉT', _money(r.drawerCash), chars),
      _lr('QUỸ VÀO HÔM NAY', _money(r.fundInToday), chars),
    ]);

    if (showProductDetail && r.products.isNotEmpty) {
      lines.add('>> HÀNG BÁN');
      lines.add(_rule(chars));
      final take = chars <= 32 ? 15 : 25;
      for (final p in r.products.take(take)) {
        var name = p.productName.trim();
        if (name.length > chars) name = '${name.substring(0, chars - 1)}…';
        lines.add(name);
        lines.add(_lr('  SL ${_qty(p.qty)}', _money(p.revenue), chars));
      }
      if (r.products.length > take) {
        lines.add('... +${r.products.length - take} mặt hàng');
      }
      if (r.lineDiscountTotal > 0) {
        lines.add(_lr('CK mặt hàng', _money(r.lineDiscountTotal), chars));
      }
      lines.add(_rule(chars));
    }

    return lines;
  }

  /// Nội dung tiếng Việt đầy đủ cho Sunmi native / PDF (không ASCII hóa).
  List<({String left, String right, bool bold})> salesRows() => [
        (left: 'Số đơn', right: '${report.orderCount}', bold: false),
        (left: 'Doanh thu', right: _money(report.totalSales), bold: false),
        (left: 'Chiết khấu', right: _money(report.orderDiscount), bold: false),
        (left: 'VAT', right: _money(report.vat), bold: false),
        (left: 'DT ròng', right: _money(report.netSales), bold: true),
        if (report.closedOffDayOrders.isNotEmpty)
          (left: 'Chốt ngày khác', right: '${report.closedOffDayCount}', bold: false),
      ];

  List<({String left, String right, bool bold})> offDayRows() =>
      report.closedOffDayOrders
          .take(15)
          .map((o) => (left: o.orderNo, right: o.draftDayLabel, bold: false))
          .toList();

  List<({String left, String right, bool bold})> refundRows() => [
        (left: 'Trả hàng', right: _money(report.refundTotal), bold: false),
        (left: 'Sau trả', right: _money(report.totalAfterRefund), bold: false),
        (left: 'Hủy đơn', right: '${report.canceledCount}', bold: false),
        if (report.canceledTotal > 0)
          (left: 'GT hủy', right: _money(report.canceledTotal), bold: false),
      ];

  List<({String left, String right, bool bold})> paymentRows() {
    final rows = <({String left, String right, bool bold})>[
      (left: 'Tiền mặt HĐ', right: _money(report.cashTotal), bold: false),
      (left: 'Ghi nợ', right: _money(report.debtTotal), bold: false),
    ];
    for (final p in report.payments) {
      final m = p.paymentMethod.toLowerCase();
      if (m.contains('mặt') || m == 'cash' || m.contains('ghi nợ') || m.contains('debt')) {
        continue;
      }
      rows.add((left: p.paymentMethod, right: _money(p.total), bold: false));
    }
    rows.add((left: 'Thực thu HĐ', right: _money(report.actualReceived), bold: false));
    rows.add((left: 'Thu cọc hôm nay', right: _money(report.depositCollected), bold: false));
    for (final p in report.depositByPayment) {
      rows.add((left: 'Cọc ${p.paymentMethod}', right: _money(p.total), bold: false));
    }
    rows.add((left: 'Hoàn cọc', right: _money(report.depositRefunded), bold: false));
    rows.add((left: 'Mất cọc', right: _money(report.depositForfeited), bold: false));
    rows.add((left: 'Đang giữ', right: _money(report.depositHeld), bold: false));
    rows.add((left: 'TIỀN MẶT KÉT', right: _money(report.drawerCash), bold: true));
    rows.add((left: 'QUỸ VÀO HÔM NAY', right: _money(report.fundInToday), bold: true));
    return rows;
  }

  List<({String name, String qty, String amount})> productRows() {
    if (!showProductDetail) return const [];
    final take = chars <= 32 ? 15 : 25;
    return report.products
        .take(take)
        .map((p) => (
              name: p.productName,
              qty: _qty(p.qty),
              amount: _money(p.revenue),
            ))
        .toList();
  }
}

String _buildBillHtml(
  PosEndOfDayReport r, {
  required bool showProductDetail,
  required int paperWidthMm,
}) {
  final staff = r.staffName ?? r.staffEmail ?? 'Tất cả nhân viên';
  final k58 = paperWidthMm <= 58;
  final pageW = k58 ? '58mm' : '80mm';
  final font = k58 ? '10px' : '11px';
  final title = k58 ? '13px' : '15px';

  String row(String label, String amt, {bool bold = false, bool sub = false}) {
    final weight = bold ? 'font-weight:700;' : '';
    final pad = sub ? 'padding-left:10px;color:#444;' : '';
    return '<tr style="$weight">'
        '<td style="$pad">${_esc(label)}</td>'
        '<td class="amt">${_esc(amt)}</td></tr>';
  }

  String section(String name) =>
      '<tr class="sec"><td colspan="2">${_esc(name)}</td></tr>';

  final rows = StringBuffer()
    ..write(section('BÁN HÀNG'))
    ..write(row('Số đơn hàng', '${r.orderCount}'))
    ..write(row('Tổng doanh thu', _money(r.totalSales)))
    ..write(row('Chiết khấu', _money(r.orderDiscount)))
    ..write(row('VAT', _money(r.vat)))
    ..write(row('Doanh thu ròng', _money(r.netSales), bold: true));
  if (r.closedOffDayOrders.isNotEmpty) {
    rows.write(section('CHỐT NGÀY KHÁC'));
    rows.write(row('Số HĐ', '${r.closedOffDayCount}'));
    for (final o in r.closedOffDayOrders.take(k58 ? 8 : 15)) {
      rows.write(row(o.orderNo, o.draftDayLabel, sub: true));
    }
  }
  rows
    ..write(section('TRẢ / HỦY'))
    ..write(row('Trả hàng', _money(r.refundTotal)))
    ..write(row('Sau trả hàng', _money(r.totalAfterRefund)))
    ..write(row('Hóa đơn hủy', '${r.canceledCount}'))
    ..write(section('THANH TOÁN BÁN HÀNG'))
    ..write(row('Tiền mặt HĐ', _money(r.cashTotal), sub: true))
    ..write(row('Ghi nợ', _money(r.debtTotal), sub: true));

  for (final p in r.payments) {
    final m = p.paymentMethod.toLowerCase();
    if (m.contains('mặt') || m == 'cash') continue;
    rows.write(row(p.paymentMethod, _money(p.total), sub: true));
  }
  rows
    ..write(row('Thực thu HĐ', _money(r.actualReceived)))
    ..write(section('CỌC ĐẶT BÀN'))
    ..write(row('Thu cọc hôm nay', _money(r.depositCollected), sub: true));
  for (final p in r.depositByPayment) {
    rows.write(row(p.paymentMethod, _money(p.total), sub: true));
  }
  rows
    ..write(row('Hoàn cọc', _money(r.depositRefunded), sub: true))
    ..write(row('Mất cọc', _money(r.depositForfeited), sub: true))
    ..write(row('Đang giữ', _money(r.depositHeld), sub: true))
    ..write(row('TIỀN MẶT KÉT', _money(r.drawerCash), bold: true))
    ..write(row('QUỸ VÀO HÔM NAY', _money(r.fundInToday), bold: true));

  if (showProductDetail && r.products.isNotEmpty) {
    rows.write(section('HÀNG BÁN'));
    for (final p in r.products.take(k58 ? 15 : 30)) {
      rows.write(row(p.productName, '${_qty(p.qty)} · ${_money(p.revenue)}', sub: true));
    }
    if (r.lineDiscountTotal > 0) {
      rows.write(row('CK mặt hàng', _money(r.lineDiscountTotal)));
    }
  }

  return '''
<!DOCTYPE html>
<html><head><meta charset="utf-8"/>
<style>
  @page { margin: 3mm; size: $pageW auto; }
  body { font-family: Arial, sans-serif; font-size: $font; margin: 0; color: #111; }
  h1 { font-size: $title; text-align: center; margin: 0 0 2px; letter-spacing: 0.3px; }
  .badge { text-align: center; font-size: 9px; color: #555; margin-bottom: 6px; }
  .meta { text-align: center; font-size: 9px; margin-bottom: 8px; line-height: 1.35; }
  table { width: 100%; border-collapse: collapse; }
  td { padding: 3px 1px; vertical-align: top; border-bottom: 1px dotted #ccc; }
  td.amt { text-align: right; white-space: nowrap; font-variant-numeric: tabular-nums; }
  tr.sec td { border-bottom: 1px solid #111; font-weight: 700; padding-top: 8px;
    letter-spacing: 0.4px; font-size: 9px; }
  .footer { margin-top: 10px; font-size: 8px; text-align: center; color: #666; }
</style></head><body>
  ${r.storeName != null && r.storeName!.isNotEmpty ? '<div class="meta"><b>${_esc(r.storeName!)}</b></div>' : ''}
  <h1>TỔNG KẾT CUỐI NGÀY</h1>
  <div class="badge">Bill ${k58 ? 'K58' : 'K80'}</div>
  <div class="meta">
    <div>NV: ${_esc(staff)}</div>
    <div>${_dt(r.from)} – ${_dt(r.to)}</div>
  </div>
  <table>${rows.toString()}</table>
  <div class="footer">In lúc ${_dt(r.generatedAt)} · SBOX POS</div>
</body></html>''';
}

String _buildA4(PosEndOfDayReport r, {required bool showProductDetail}) {
  final staff = r.staffName ?? r.staffEmail ?? 'Tất cả nhân viên';
  final summaryRows = '''
    <tr><td>Số đơn hàng</td><td class="r">${r.orderCount}</td></tr>
    <tr><td>Chiết khấu đơn</td><td class="r">${_money(r.orderDiscount)}</td></tr>
    <tr><td>Tổng doanh thu</td><td class="r">${_money(r.totalSales)}</td></tr>
    <tr><td>VAT</td><td class="r">${_money(r.vat)}</td></tr>
    <tr><td>Doanh thu ròng</td><td class="r">${_money(r.netSales)}</td></tr>
    ${r.closedOffDayOrders.isNotEmpty ? '<tr><td>Chốt ngày khác</td><td class="r">${r.closedOffDayCount}</td></tr>' : ''}
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
        <td>${_esc(t.closedOffDay ? '${t.orderNo} · ${t.note ?? 'Chốt ngày khác'}' : t.orderNo)}</td>
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
  ${r.closedOffDayOrders.isNotEmpty ? '''
<h3>Hóa đơn chốt ngày khác</h3>
<table class="grid">
  <thead><tr><th>Mã HĐ</th><th>Nháp</th><th class="r">Thành tiền</th></tr></thead>
  <tbody>
    ${r.closedOffDayOrders.map((o) => '<tr><td>${_esc(o.orderNo)}</td><td>${_esc(o.draftDayLabel)}</td><td class="r">${_money(o.total)}</td></tr>').join()}
  </tbody>
</table>''' : ''}
  $productTable
  $txTable
  <div class="footer">In lúc ${_dt(r.generatedAt)} · SBOX POS</div>
</body></html>''';
}

String _esc(String s) =>
    s.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;');

Future<Uint8List> buildPosEndOfDayPdfBytes(
  PosEndOfDayReport r, {
  PosEndOfDayPrintFormat format = PosEndOfDayPrintFormat.bill58,
  bool showProductDetail = true,
}) async {
  final pdf = pw.Document();
  final staff = r.staffName ?? r.staffEmail ?? 'Tất cả nhân viên';
  final pageFormat = switch (format) {
    PosEndOfDayPrintFormat.a4 => PdfPageFormat.a4,
    PosEndOfDayPrintFormat.bill58 => PdfPageFormat.roll57,
    PosEndOfDayPrintFormat.bill80 => PdfPageFormat.roll80,
  };
  final layout = _EodThermalLayout(
    r,
    chars: format.thermalChars,
    showProductDetail: showProductDetail,
  );
  final fs = format == PosEndOfDayPrintFormat.bill58 ? 8.5 : 9.5;

  pw.Widget pair(String label, String value, {bool bold = false}) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 1.5),
        child: pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Expanded(
              child: pw.Text(
                label,
                style: pw.TextStyle(
                  fontSize: fs,
                  fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
                ),
              ),
            ),
            pw.Text(
              value,
              style: pw.TextStyle(
                fontSize: fs,
                fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
              ),
            ),
          ],
        ),
      );

  pw.Widget section(String title) => pw.Padding(
        padding: const pw.EdgeInsets.only(top: 6, bottom: 2),
        child: pw.Text(
          title,
          style: pw.TextStyle(fontSize: fs, fontWeight: pw.FontWeight.bold),
          textAlign: pw.TextAlign.center,
        ),
      );

  pdf.addPage(
    pw.Page(
      pageFormat: pageFormat,
      margin: pw.EdgeInsets.all(format == PosEndOfDayPrintFormat.a4 ? 12 : 8),
      build: (ctx) {
        if (format == PosEndOfDayPrintFormat.a4) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [
              pw.Center(
                child: pw.Text(tr('BÁO CÁO CUỐI NGÀY VỀ BÁN HÀNG'),
                  style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
                ),
              ),
              pw.SizedBox(height: 8),
              if (r.storeName != null && r.storeName!.isNotEmpty)
                pw.Center(child: pw.Text(r.storeName!, style: const pw.TextStyle(fontSize: 10))),
              pw.Center(child: pw.Text(tr('Nhân viên: $staff'), style: const pw.TextStyle(fontSize: 9))),
              pw.Center(
                child: pw.Text('${_dt(r.from)} - ${_dt(r.to)}',
                    style: const pw.TextStyle(fontSize: 9)),
              ),
              pw.SizedBox(height: 12),
              ...layout.salesRows().map((e) => pair(e.left, e.right, bold: e.bold)),
              ...layout.refundRows().map((e) => pair(e.left, e.right, bold: e.bold)),
              ...layout.paymentRows().map((e) => pair(e.left, e.right, bold: e.bold)),
              pair('Thực thu', _money(r.actualReceived), bold: true),
              if (showProductDetail && r.products.isNotEmpty) ...[
                pw.SizedBox(height: 10),
                pw.Text(tr('Hàng hóa bán ra'),
                    style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
                ...r.products.take(40).map(
                      (p) => pair(p.productName, '${_qty(p.qty)} · ${_money(p.revenue)}'),
                    ),
              ],
              pw.Spacer(),
              pw.Center(
                child: pw.Text(tr('In lúc ${_dt(r.generatedAt)} · SBOX POS'),
                    style: const pw.TextStyle(fontSize: 8)),
              ),
            ],
          );
        }

        return pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            if (r.storeName != null && r.storeName!.trim().isNotEmpty)
              pw.Center(
                child: pw.Text(
                  r.storeName!.trim(),
                  style: pw.TextStyle(fontSize: fs + 1, fontWeight: pw.FontWeight.bold),
                  textAlign: pw.TextAlign.center,
                ),
              ),
            pw.Center(
              child: pw.Text(tr('TỔNG KẾT CUỐI NGÀY'),
                style: pw.TextStyle(fontSize: fs + 2, fontWeight: pw.FontWeight.bold),
              ),
            ),
            pw.Center(
              child: pw.Text(
                'Bill ${format == PosEndOfDayPrintFormat.bill58 ? 'K58' : 'K80'}',
                style: pw.TextStyle(fontSize: fs - 1),
              ),
            ),
            pw.SizedBox(height: 4),
            pw.Text('NV: $staff', style: pw.TextStyle(fontSize: fs)),
            pw.Text(tr('Từ: ${_dtShort(r.from)}'), style: pw.TextStyle(fontSize: fs - 0.5)),
            pw.Text(tr('Đến: ${_dtShort(r.to)}'), style: pw.TextStyle(fontSize: fs - 0.5)),
            pw.Divider(thickness: 0.6),
            section('BÁN HÀNG'),
            ...layout.salesRows().map((e) => pair(e.left, e.right, bold: e.bold)),
            if (layout.offDayRows().isNotEmpty) ...[
              pw.Divider(thickness: 0.4),
              section('CHỐT NGÀY KHÁC'),
              ...layout.offDayRows().map((e) => pair(e.left, e.right)),
            ],
            pw.Divider(thickness: 0.4),
            section('TRẢ / HỦY'),
            ...layout.refundRows().map((e) => pair(e.left, e.right, bold: e.bold)),
            pw.Divider(thickness: 0.4),
            section('THANH TOÁN / CỌC'),
            ...layout.paymentRows().map((e) => pair(e.left, e.right, bold: e.bold)),
            pw.Divider(thickness: 0.8),
            pair('TIỀN MẶT KÉT', _money(r.drawerCash), bold: true),
            pw.Divider(thickness: 0.8),
            if (layout.productRows().isNotEmpty) ...[
              section('HÀNG BÁN'),
              ...layout.productRows().map((p) => pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                    children: [
                      pw.Text(p.name,
                          style: pw.TextStyle(
                              fontSize: fs, fontWeight: pw.FontWeight.bold)),
                      pair('  SL ${p.qty}', p.amount),
                    ],
                  )),
            ],
            pw.SizedBox(height: 8),
            pw.Center(
              child: pw.Text(tr('In lúc ${_dt(r.generatedAt)} · SBOX POS'),
                style: pw.TextStyle(fontSize: fs - 1),
              ),
            ),
          ],
        );
      },
    ),
  );

  return Uint8List.fromList(await pdf.save());
}

Future<void> printPosEndOfDayReport(
  BuildContext context,
  PosEndOfDayReport report, {
  PosEndOfDayPrintFormat format = PosEndOfDayPrintFormat.bill58,
  bool showProductDetail = true,
}) async {
  if (!kIsWeb && format.isThermalBill) {
    await PosPrintOrchestrator.instance.refreshConfig();
    final printers = PosPrintOrchestrator.instance
        .resolvePrinters(PosCloudDocumentTypes.endOfDayReport);
    final local = await PosThermalPrinterSettings.load();
    final paperSize = format == PosEndOfDayPrintFormat.bill58 ? 'K58' : 'K80';
    final layout = _EodThermalLayout(
      report,
      chars: format.thermalChars,
      showProductDetail: showProductDetail,
    );
    final lines = layout.buildLines();
    final footer = 'In lúc ${_dt(report.generatedAt)} · SBOX POS';
    final title = 'TỔNG KẾT CUỐI NGÀY';

    if (local.enabled) {
      var settings = await PosPrinterTransport.prepareLocalSettings(local);
      settings = settings.copyWith(paperSize: paperSize);
      var printed = false;

      if (settings.connectionType == PosThermalConnectionType.sunmi ||
          await PosPrinterTransport.isSunmiDevice()) {
        try {
          printed = await PosSunmiNativePrint.printEndOfDayReport(
            storeName: report.storeName?.trim() ?? '',
            staffLabel: layout.staff,
            periodFrom: _dtShort(report.from),
            periodTo: _dtShort(report.to),
            salesRows: [...layout.salesRows(), ...layout.offDayRows()],
            refundRows: layout.refundRows(),
            paymentRows: layout.paymentRows(),
            actualReceived: '${_money(report.actualReceived)} đ',
            products: layout.productRows(),
            footer: footer,
            paperBadge: format == PosEndOfDayPrintFormat.bill58 ? 'K58' : 'K80',
            settings: settings.copyWith(
              connectionType: PosThermalConnectionType.sunmi,
              printerBrand: PosThermalPrinterBrand.sunmi,
              paperSize: paperSize,
            ),
          );
        } catch (e) {
          debugPrint('Sunmi EOD native print failed: $e');
        }
      }

      if (!printed) {
        try {
          final bytes = await PosThermalPrinterService.buildTextEscPosBytes(
            settings: settings,
            title: title,
            lines: lines,
            footer: footer,
          );
          printed = await PosPrintOrchestrator.instance.dispatchLocalEscPos(
            bytes: bytes,
            showFeedback: false,
            successTitle: 'In cuối ngày',
            settingsOverride: settings,
          );
        } catch (e) {
          debugPrint('Local EOD ESC/POS failed: $e');
        }
      }

      if (printed) {
        NotificationOverlayManager().showSuccess(
          title: 'In cuối ngày',
          message: tr('Máy in cục bộ · ${format.label}'),
        );
        return;
      }
    }

    if (printers.isNotEmpty) {
      final ok = await PosPrintOrchestrator.instance.dispatchEscPosToAll(
        documentType: PosCloudDocumentTypes.endOfDayReport,
        referenceNo: 'EOD-${_d(report.from)}',
        showFeedback: true,
        successTitle: 'In cuối ngày',
        buildBytes: (printer) async {
          var settings = toThermalSettings(printer);
          settings = settings.copyWith(paperSize: paperSize);
          return PosThermalPrinterService.buildTextEscPosBytes(
            settings: settings,
            title: title,
            lines: lines,
            footer: footer,
          );
        },
      );
      if (ok) return;
    }
  }

  final bytes = await buildPosEndOfDayPdfBytes(
    report,
    format: format,
    showProductDetail: showProductDetail,
  );
  final title = switch (format) {
    PosEndOfDayPrintFormat.a4 => 'TongKetCuoiNgay_A4',
    PosEndOfDayPrintFormat.bill58 => 'TongKetCuoiNgay_K58',
    PosEndOfDayPrintFormat.bill80 => 'TongKetCuoiNgay_K80',
  };

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
      title: Text(tr('In tổng kết · ${format.label}')),
      content: Text(tr('Chọn cách in hoặc xuất PDF.')),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr('Đóng'))),
        OutlinedButton(
          onPressed: () async {
            Navigator.pop(ctx);
            await Printing.layoutPdf(
              onLayout: (_) async => bytes,
              name: title,
            );
          },
          child: Text(tr('In')),
        ),
        FilledButton(
          onPressed: () async {
            Navigator.pop(ctx);
            await Printing.sharePdf(bytes: bytes, filename: '$title.pdf');
          },
          child: Text(tr('Xuất PDF')),
        ),
      ],
    ),
  );
}
