import 'package:barcode/barcode.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../l10n/app_tr.dart';
import '../models/pos_store_printer.dart';
import '../widgets/notification_overlay.dart';
import 'pos_label_printer_service.dart';
import 'pos_label_printer_settings.dart';
import 'pos_label_renderer.dart';
import 'pos_local_printers_store.dart';
import 'pos_pdf_fonts.dart';
import 'pos_print_orchestrator.dart';
import 'pos_store_printer_mapper.dart';

/// Khổ tem QR bàn mặc định (mm).
const double kPosTableQrLabelWidthMm = 60;
const double kPosTableQrLabelHeightMm = 40;

/// Khung PDF mặc định (cm).
const double kPosTableQrPdfCellCm = 6;

const _kPdfCellCm = 'pos_qr_table_pdf_cell_cm';

const kPosTableQrSboxIntro = 'SBOX POS · Quét để gọi món tại bàn';

class PosQrTablePrintItem {
  const PosQrTablePrintItem({
    required this.label,
    required this.url,
  });

  final String label;
  final String url;
}

Future<double> loadPosQrTablePdfCellCm() async {
  final prefs = await SharedPreferences.getInstance();
  final v = prefs.getDouble(_kPdfCellCm);
  if (v == null || v < 3 || v > 12) return kPosTableQrPdfCellCm;
  return v;
}

Future<void> savePosQrTablePdfCellCm(double cm) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setDouble(_kPdfCellCm, cm.clamp(3, 12));
}

Future<Uint8List> buildPosQrTablePdfBytes({
  required List<PosQrTablePrintItem> tables,
  required String storeName,
  double cellCm = kPosTableQrPdfCellCm,
  String intro = kPosTableQrSboxIntro,
}) async {
  final fonts = await loadPosPdfFonts();
  final doc = pw.Document(
    theme: pw.ThemeData.withFont(base: fonts.regular, bold: fonts.bold),
  );
  final cellPt = cellCm * PdfPageFormat.cm;
  final storeStyle = pw.TextStyle(font: fonts.bold, fontSize: 11);
  final titleStyle = pw.TextStyle(font: fonts.bold, fontSize: 13);
  final hintStyle = pw.TextStyle(font: fonts.regular, fontSize: 9);
  final introStyle = pw.TextStyle(
    font: fonts.regular,
    fontSize: 8,
    color: PdfColors.grey700,
  );
  final badge = pw.TextStyle(
    font: fonts.bold,
    fontSize: 8,
    color: PdfColors.white,
  );

  final perPage = cellCm >= 8 ? 4 : (cellCm >= 6 ? 6 : 9);
  for (var i = 0; i < tables.length; i += perPage) {
    final chunk = tables.skip(i).take(perPage).toList();
    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(18),
        theme: pw.ThemeData.withFont(base: fonts.regular, bold: fonts.bold),
        build: (_) => pw.Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final t in chunk)
              pw.Container(
                width: cellPt,
                height: cellPt,
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: PdfColors.orange200),
                  borderRadius: pw.BorderRadius.circular(10),
                ),
                child: pw.Column(
                  children: [
                    pw.Container(
                      width: double.infinity,
                      padding: const pw.EdgeInsets.symmetric(vertical: 5),
                      decoration: const pw.BoxDecoration(
                        color: PdfColors.orange800,
                        borderRadius: pw.BorderRadius.vertical(
                          top: pw.Radius.circular(9),
                        ),
                      ),
                      child: pw.Text(
                        tr('GỌI MÓN TẠI BÀN'),
                        style: badge,
                        textAlign: pw.TextAlign.center,
                      ),
                    ),
                    pw.Expanded(
                      child: pw.Padding(
                        padding: const pw.EdgeInsets.fromLTRB(6, 4, 6, 4),
                        child: pw.Column(
                          mainAxisAlignment: pw.MainAxisAlignment.center,
                          children: [
                            if (storeName.trim().isNotEmpty)
                              pw.Text(
                                storeName.trim(),
                                style: storeStyle,
                                textAlign: pw.TextAlign.center,
                                maxLines: 1,
                              ),
                            pw.Text(
                              t.label,
                              style: titleStyle,
                              textAlign: pw.TextAlign.center,
                              maxLines: 1,
                            ),
                            pw.SizedBox(height: 2),
                            pw.Expanded(
                              child: pw.Center(
                                child: pw.BarcodeWidget(
                                  barcode: Barcode.qrCode(),
                                  data: t.url,
                                  drawText: false,
                                ),
                              ),
                            ),
                            pw.Text(
                              intro,
                              style: introStyle,
                              textAlign: pw.TextAlign.center,
                              maxLines: 2,
                            ),
                            pw.Text(
                              tr('Quét để gọi món'),
                              style: hintStyle,
                              textAlign: pw.TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
  return Uint8List.fromList(await doc.save());
}

Future<void> layoutPosQrTablePdf({
  required List<PosQrTablePrintItem> tables,
  required String storeName,
  double cellCm = kPosTableQrPdfCellCm,
}) async {
  if (tables.isEmpty) return;
  final bytes = await buildPosQrTablePdfBytes(
    tables: tables,
    storeName: storeName,
    cellCm: cellCm,
  );
  await Printing.layoutPdf(
    onLayout: (_) async => bytes,
    name: 'qr-order-ban.pdf',
  );
}

Future<void> sharePosQrTablePdf({
  required List<PosQrTablePrintItem> tables,
  required String storeName,
  double cellCm = kPosTableQrPdfCellCm,
}) async {
  if (tables.isEmpty) return;
  final bytes = await buildPosQrTablePdfBytes(
    tables: tables,
    storeName: storeName,
    cellCm: cellCm,
  );
  await Printing.sharePdf(bytes: bytes, filename: 'qr-order-ban.pdf');
}

class PosQrLabelPrinterChoice {
  PosQrLabelPrinterChoice._({this.local, this.cloud});

  factory PosQrLabelPrinterChoice.local(PosLocalPrinterProfile local) =>
      PosQrLabelPrinterChoice._(local: local);

  factory PosQrLabelPrinterChoice.cloud(PosStorePrinter cloud) =>
      PosQrLabelPrinterChoice._(cloud: cloud);

  final PosLocalPrinterProfile? local;
  final PosStorePrinter? cloud;

  String get name =>
      local?.name.trim().isNotEmpty == true
          ? local!.name
          : (cloud?.name.trim().isNotEmpty == true
              ? cloud!.name
              : 'Máy tem');

  String get subtitle {
    if (local != null) {
      return 'Nội bộ · ${local!.connectionType.label} · tem 60×40';
    }
    return 'Agent · tem 60×40';
  }

  PosLabelPrinterSettings toSettings() {
    if (local != null) {
      return local!.toLabelSettings().copyWith(enabled: true);
    }
    return toLabelSettings(cloud!).copyWith(enabled: true);
  }
}

Future<List<PosQrLabelPrinterChoice>> listPosQrLabelPrinters() async {
  final out = <PosQrLabelPrinterChoice>[];
  if (!kIsWeb) {
    final all = await PosLocalPrintersStore.instance.loadAll();
    var locals = all
        .where((p) =>
            PosLocalPrintersStore.profileAllowsDirectLocal(p) &&
            p.isLabel &&
            (p.hasRole(PosLocalPrinterRoles.kitchenLabel) ||
                p.hasRole(PosLocalPrinterRoles.barcodeLabel)))
        .toList();
    if (locals.isEmpty) {
      locals = all
          .where((p) =>
              PosLocalPrintersStore.profileAllowsDirectLocal(p) && p.isLabel)
          .toList();
    }
    for (final p in locals) {
      out.add(PosQrLabelPrinterChoice.local(p));
    }
  }

  await PosPrintOrchestrator.instance.refreshConfig();
  final orch = PosPrintOrchestrator.instance;
  final seen = <String>{};
  for (final p in [
    ...orch.resolvePrinters(PosCloudDocumentTypes.kitchenLabel),
    ...orch.resolvePrinters(PosCloudDocumentTypes.barcodeLabel),
    ...orch.printers.where((x) => x.isLabelPrinter && x.isActive),
  ]) {
    if (!p.isActive || !p.isLabelPrinter) continue;
    if (!seen.add(p.id)) continue;
    // Tránh trùng máy local đã chọn.
    if (out.any((c) =>
        c.local != null &&
        ((c.local!.lanHost ?? '') == (p.lanHost ?? '') &&
            (c.local!.usbDeviceName ?? '') == (p.usbDeviceName ?? '') &&
            (c.local!.bluetoothAddress ?? '') == (p.bluetoothAddress ?? '')))) {
      continue;
    }
    out.add(PosQrLabelPrinterChoice.cloud(p));
  }
  return out;
}

Future<bool> printPosQrTablesToLabelPrinter({
  required List<PosQrTablePrintItem> tables,
  required String storeName,
  required PosQrLabelPrinterChoice printer,
  bool showFeedback = true,
}) async {
  if (tables.isEmpty) return false;
  final settings = printer.toSettings();
  final dpi = settings.dpi <= 0 ? 203 : settings.dpi;
  final rasters = <({Uint8List raster, int widthPx, int heightPx})>[];
  for (final t in tables) {
    final r = await PosLabelRenderer.renderTableQrLabel(
      storeName: storeName,
      tableLabel: t.label,
      qrUrl: t.url,
      footer: kPosTableQrSboxIntro,
      widthMm: kPosTableQrLabelWidthMm,
      heightMm: kPosTableQrLabelHeightMm,
      dpi: dpi,
    );
    if (PosLabelRenderer.hasEnoughInk(r.raster)) {
      rasters.add(r);
    }
  }
  if (rasters.isEmpty) {
    if (showFeedback) {
      NotificationOverlayManager().showError(
        title: 'Không in được',
        message: tr('Không tạo được ảnh tem QR'),
      );
    }
    return false;
  }

  final jobs = PosLabelPrinterService.buildCupRasterByteJobs(
    rasters,
    settings: settings,
    widthMm: kPosTableQrLabelWidthMm,
    heightMm: kPosTableQrLabelHeightMm,
  );

  if (printer.local != null && !kIsWeb) {
    final ok = await PosLabelPrinterService.printCupRasters(
      rasters,
      settings: settings,
      widthMm: kPosTableQrLabelWidthMm,
      heightMm: kPosTableQrLabelHeightMm,
    );
    if (showFeedback) {
      if (ok) {
        NotificationOverlayManager().showSuccess(
          title: 'Đã in tem QR',
          message: '${tables.length} tem · ${printer.name}',
        );
      } else {
        NotificationOverlayManager().showError(
          title: 'In tem thất bại',
          message: printer.name,
        );
      }
    }
    return ok;
  }

  if (printer.cloud == null) return false;
  var allOk = true;
  for (var i = 0; i < jobs.length; i++) {
    final ok = await PosPrintOrchestrator.instance.dispatchEscPos(
      documentType: PosCloudDocumentTypes.kitchenLabel,
      bytes: jobs[i],
      printerId: printer.cloud!.id,
      showFeedback: showFeedback && i == jobs.length - 1,
      successTitle: 'Tem QR bàn',
      skipDedup: true,
      waitForCompletion: false,
      acceptClaimedAsSuccess: true,
      hangAfter: const Duration(seconds: 90),
    );
    if (!ok) {
      allOk = false;
      break;
    }
  }
  if (showFeedback && allOk && jobs.length > 1) {
    NotificationOverlayManager().showSuccess(
      title: 'Đã gửi tem QR',
      message: '${tables.length} tem · ${printer.name}',
    );
  }
  return allOk;
}

/// Chọn máy tem trong bottom sheet. Trả null nếu hủy.
Future<PosQrLabelPrinterChoice?> pickPosQrLabelPrinter(
  BuildContext context,
) async {
  final printers = await listPosQrLabelPrinters();
  if (!context.mounted) return null;
  if (printers.isEmpty) {
    NotificationOverlayManager().showError(
      title: 'Chưa có máy tem',
      message: tr(
        'Vào Máy in nội bộ / Máy in cửa hàng → thêm máy Tem (TSPL), '
        'gắn vai trò Tem bếp hoặc Tem mã vạch.',
      ),
    );
    return null;
  }
  return showModalBottomSheet<PosQrLabelPrinterChoice>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Text(
              tr('Chọn máy in tem 60×40'),
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
            ),
          ),
          for (final p in printers)
            ListTile(
              leading: const Icon(Icons.label_outline),
              title: Text(p.name),
              subtitle: Text(p.subtitle),
              onTap: () => Navigator.pop(ctx, p),
            ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
}
