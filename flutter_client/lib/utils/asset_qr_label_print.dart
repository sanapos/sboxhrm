import 'dart:ui' as ui;

import 'package:barcode/barcode.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../l10n/app_tr.dart';
import '../models/asset.dart';
import '../models/pos_store_printer.dart';
import '../widgets/notification_overlay.dart';
import 'file_saver.dart' as file_saver;
import 'pos_label_printer_service.dart';
import 'pos_label_renderer.dart';
import 'pos_pdf_fonts.dart';
import 'pos_print_orchestrator.dart';
import 'pos_qr_table_print.dart';

/// Khổ tem QR tài sản: tem nhiệt (máy in tem POS) hoặc giấy decal A4 nhiều tem / trang (máy in văn phòng).
enum AssetQrLabelSize {
  thermal40x30(40, 30, 'Tem nhiệt 40×30'),
  thermal50x30(50, 30, 'Tem nhiệt 50×30'),
  a4(70, 37.125, 'Giấy A4 (24 tem / trang)');

  const AssetQrLabelSize(this.widthMm, this.heightMm, this.label);

  final double widthMm;
  final double heightMm;
  final String label;

  bool get isThermal => this != AssetQrLabelSize.a4;
}

/// Lưới tem trên giấy A4 (decal 3 cột × 8 hàng, ô 70×37 mm).
const int kAssetQrA4Cols = 3;
const int kAssetQrA4Rows = 8;

const _kPrefSize = 'asset_qr_label_size';

/// Nội dung mã QR in trên tem = mã QR của tài sản (trống thì mã tài sản) — đúng cái API tra cứu
/// `GET /api/Assets/lookup?code=` so khớp (QrCode hoặc AssetCode), nên quét tem là mở đúng tài sản.
String assetQrPayload(Asset a) {
  final qr = (a.qrCode ?? '').trim();
  return qr.isNotEmpty ? qr : a.assetCode.trim();
}

/// Dòng «vị trí · người đang giữ» trên tem (bỏ phần trống).
String assetQrHolderLine(Asset a) => [
      (a.location ?? '').trim(),
      (a.currentAssigneeName ?? '').trim(),
    ].where((s) => s.isNotEmpty).join(' · ');

class AssetQrLabelItem {
  const AssetQrLabelItem({
    required this.qrData,
    required this.assetCode,
    required this.assetName,
    this.holder = '',
  });

  factory AssetQrLabelItem.fromAsset(Asset a) => AssetQrLabelItem(
        qrData: assetQrPayload(a),
        assetCode: a.assetCode.trim(),
        assetName: a.name.trim(),
        holder: assetQrHolderLine(a),
      );

  final String qrData;
  final String assetCode;
  final String assetName;
  final String holder;
}

/// Danh sách tem cần in (mỗi tài sản [copies] tem, bỏ tài sản không có mã).
List<AssetQrLabelItem> assetQrLabelItems(List<Asset> assets, {int copies = 1}) => [
      for (final a in assets)
        if (assetQrPayload(a).isNotEmpty)
          for (var i = 0; i < copies.clamp(1, 100); i++) AssetQrLabelItem.fromAsset(a),
    ];

Future<AssetQrLabelSize> loadAssetQrLabelSize() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final name = prefs.getString(_kPrefSize);
    return AssetQrLabelSize.values.firstWhere((s) => s.name == name, orElse: () => AssetQrLabelSize.thermal50x30);
  } catch (_) {
    return AssetQrLabelSize.thermal50x30;
  }
}

Future<void> saveAssetQrLabelSize(AssetQrLabelSize size) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kPrefSize, size.name);
  } catch (_) {}
}

/// Ảnh một tem nhiệt (xem trước / PDF khổ tem).
Future<ui.Image> renderAssetQrLabelImage(
  AssetQrLabelItem item, {
  required AssetQrLabelSize size,
  String? companyName,
  int dpi = 203,
}) =>
    PosLabelRenderer.renderAssetQrLabelImage(
      qrData: item.qrData,
      assetCode: item.assetCode,
      assetName: item.assetName,
      holder: item.holder,
      companyName: companyName,
      widthMm: size.widthMm,
      heightMm: size.heightMm,
      dpi: dpi,
    );

Future<Uint8List?> renderAssetQrLabelPng(
  AssetQrLabelItem item, {
  required AssetQrLabelSize size,
  String? companyName,
  int dpi = 203,
}) async {
  final img = await renderAssetQrLabelImage(item, size: size, companyName: companyName, dpi: dpi);
  final data = await img.toByteData(format: ui.ImageByteFormat.png);
  return data?.buffer.asUint8List();
}

/// PDF tem QR tài sản. Tem nhiệt: mỗi trang = 1 tem đúng khổ (in qua driver máy tem trên máy tính).
/// A4: lưới 3×8 tem / trang, QR vẽ dạng vector cho sắc nét trên máy in văn phòng.
Future<Uint8List> buildAssetQrLabelPdfBytes(
  List<AssetQrLabelItem> items, {
  required AssetQrLabelSize size,
  String? companyName,
}) async {
  final fonts = await loadPosPdfFonts();
  final doc = pw.Document(theme: pw.ThemeData.withFont(base: fonts.regular, bold: fonts.bold));
  if (size.isThermal) {
    final format = PdfPageFormat(size.widthMm * PdfPageFormat.mm, size.heightMm * PdfPageFormat.mm);
    final cache = <AssetQrLabelItem, pw.ImageProvider>{};
    for (final it in items) {
      final img = cache[it] ??= pw.MemoryImage(
          (await renderAssetQrLabelPng(it, size: size, companyName: companyName, dpi: 300)) ?? Uint8List(0));
      doc.addPage(pw.Page(
        pageFormat: format,
        margin: pw.EdgeInsets.zero,
        build: (_) => pw.Image(img, fit: pw.BoxFit.fill),
      ));
    }
    return Uint8List.fromList(await doc.save());
  }

  const perPage = kAssetQrA4Cols * kAssetQrA4Rows;
  final cellW = PdfPageFormat.a4.width / kAssetQrA4Cols;
  final cellH = PdfPageFormat.a4.height / kAssetQrA4Rows;
  final company = (companyName ?? '').trim();
  for (var i = 0; i < items.length; i += perPage) {
    final chunk = items.skip(i).take(perPage).toList();
    doc.addPage(pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: pw.EdgeInsets.zero,
      build: (_) => pw.Wrap(children: [
        for (final it in chunk)
          pw.Container(
            width: cellW,
            height: cellH,
            padding: const pw.EdgeInsets.all(3 * PdfPageFormat.mm),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: PdfColors.grey300, width: 0.3),
            ),
            child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.center, children: [
              pw.SizedBox(
                width: cellH - 6 * PdfPageFormat.mm,
                height: cellH - 6 * PdfPageFormat.mm,
                child: pw.BarcodeWidget(barcode: Barcode.qrCode(), data: it.qrData, drawText: false),
              ),
              pw.SizedBox(width: 2.5 * PdfPageFormat.mm),
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  mainAxisAlignment: pw.MainAxisAlignment.center,
                  children: [
                    if (company.isNotEmpty)
                      pw.Text(company,
                          maxLines: 1, style: pw.TextStyle(font: fonts.bold, fontSize: 6.5, color: PdfColors.grey700)),
                    pw.Text(it.assetCode, maxLines: 2, style: pw.TextStyle(font: fonts.bold, fontSize: 10.5)),
                    pw.SizedBox(height: 1.5),
                    pw.Text(it.assetName, maxLines: 3, style: const pw.TextStyle(fontSize: 8)),
                    if (it.holder.isNotEmpty) ...[
                      pw.SizedBox(height: 1.5),
                      pw.Text(it.holder,
                          maxLines: 2, style: const pw.TextStyle(fontSize: 6.5, color: PdfColors.grey800)),
                    ],
                  ],
                ),
              ),
            ]),
          ),
      ]),
    ));
  }
  return Uint8List.fromList(await doc.save());
}

String _pdfName() => 'TemQR_TaiSan_${DateFormat('yyyyMMdd_HHmm').format(DateTime.now())}.pdf';

/// Mở hộp in của hệ điều hành (web: mở PDF ở tab mới để in).
Future<void> printAssetQrLabelPdf(
  List<AssetQrLabelItem> items, {
  required AssetQrLabelSize size,
  String? companyName,
}) async {
  if (items.isEmpty) return;
  final bytes = await buildAssetQrLabelPdfBytes(items, size: size, companyName: companyName);
  if (kIsWeb) {
    await file_saver.openPdfInNewTab(bytes, _pdfName());
  } else {
    await Printing.layoutPdf(onLayout: (_) async => bytes, name: _pdfName());
  }
}

Future<void> shareAssetQrLabelPdf(
  List<AssetQrLabelItem> items, {
  required AssetQrLabelSize size,
  String? companyName,
}) async {
  if (items.isEmpty) return;
  final bytes = await buildAssetQrLabelPdfBytes(items, size: size, companyName: companyName);
  if (kIsWeb) {
    await file_saver.saveFileBytes(bytes, _pdfName(), 'application/pdf');
  } else {
    await Printing.sharePdf(bytes: bytes, filename: _pdfName());
  }
}

/// Ảnh raster (đen trắng, đúng mật độ điểm máy tem) cho từng tem nhiệt.
Future<List<({Uint8List raster, int widthPx, int heightPx})>> renderAssetQrLabelRasters(
  List<AssetQrLabelItem> items, {
  required AssetQrLabelSize size,
  String? companyName,
  int dpi = 203,
}) async => [
      for (final it in items)
        await PosLabelRenderer.renderAssetQrLabel(
          qrData: it.qrData,
          assetCode: it.assetCode,
          assetName: it.assetName,
          holder: it.holder,
          companyName: companyName,
          widthMm: size.widthMm,
          heightMm: size.heightMm,
          dpi: dpi,
        ),
    ];

/// In tem nhiệt ra máy tem đã cài (máy nội bộ gửi thẳng, máy cửa hàng qua Agent) —
/// cùng đường gửi với tem QR bàn / tem ly.
Future<bool> printAssetQrLabelsToLabelPrinter(
  List<AssetQrLabelItem> items, {
  required AssetQrLabelSize size,
  required PosQrLabelPrinterChoice printer,
  String? companyName,
}) async {
  if (items.isEmpty || !size.isThermal) return false;
  final settings = printer.toSettings();
  final rasters = await renderAssetQrLabelRasters(items,
      size: size, companyName: companyName, dpi: settings.dpi <= 0 ? 203 : settings.dpi);
  var ok = false;
  if (printer.local != null && !kIsWeb) {
    ok = await PosLabelPrinterService.printCupRasters(
      rasters,
      settings: settings,
      widthMm: size.widthMm,
      heightMm: size.heightMm,
    );
  } else if (printer.cloud != null) {
    final jobs = PosLabelPrinterService.buildCupRasterByteJobs(
      rasters,
      settings: settings,
      widthMm: size.widthMm,
      heightMm: size.heightMm,
    );
    ok = true;
    for (final j in jobs) {
      final sent = await PosPrintOrchestrator.instance.dispatchEscPos(
        documentType: PosCloudDocumentTypes.barcodeLabel,
        bytes: j,
        printerId: printer.cloud!.id,
        showFeedback: false,
        successTitle: 'Tem QR tài sản',
        skipDedup: true,
        waitForCompletion: false,
        acceptClaimedAsSuccess: true,
        hangAfter: const Duration(seconds: 90),
      );
      if (!sent) {
        ok = false;
        break;
      }
    }
  }
  if (ok) {
    NotificationOverlayManager().showSuccess(
      title: 'Đã in tem QR tài sản',
      message: '${items.length} tem · ${printer.name}',
    );
  } else {
    NotificationOverlayManager().showError(title: 'In tem thất bại', message: printer.name);
  }
  return ok;
}

Future<PosQrLabelPrinterChoice?> _pickLabelPrinter(BuildContext context, AssetQrLabelSize size) async {
  final printers = await listPosQrLabelPrinters();
  if (!context.mounted) return null;
  if (printers.isEmpty) {
    NotificationOverlayManager().showError(
      title: 'Chưa có máy in tem',
      message: tr('Vào Máy in nội bộ / Máy in cửa hàng → thêm máy Tem (TSPL), '
          'hoặc chọn «Giấy A4» để in bằng máy in văn phòng.'),
    );
    return null;
  }
  if (printers.length == 1) return printers.first;
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
            child: Text(tr('Chọn máy in tem ${size.label.replaceFirst('Tem nhiệt ', '')}'),
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
          ),
          for (final p in printers)
            ListTile(
              leading: const Icon(Icons.label_outline),
              title: Text(p.name),
              subtitle: Text(p.local != null ? tr('Máy nội bộ · ${p.local!.connectionType.label}') : tr('Máy cửa hàng (Agent)')),
              onTap: () => Navigator.pop(ctx, p),
            ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
}

/// Hộp thoại «In tem QR» cho 1 hoặc nhiều tài sản.
Future<void> showAssetQrLabelPrintDialog(
  BuildContext context, {
  required List<Asset> assets,
  String? companyName,
}) async {
  if (assets.isEmpty) return;
  final size = await loadAssetQrLabelSize();
  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (_) => AssetQrLabelPrintDialog(assets: assets, companyName: companyName, initialSize: size),
  );
}

class AssetQrLabelPrintDialog extends StatefulWidget {
  const AssetQrLabelPrintDialog({
    super.key,
    required this.assets,
    this.companyName,
    this.initialSize = AssetQrLabelSize.thermal50x30,
  });

  final List<Asset> assets;
  final String? companyName;
  final AssetQrLabelSize initialSize;

  @override
  State<AssetQrLabelPrintDialog> createState() => _AssetQrLabelPrintDialogState();
}

class _AssetQrLabelPrintDialogState extends State<AssetQrLabelPrintDialog> {
  late AssetQrLabelSize _size = widget.initialSize;
  int _copies = 1;
  bool _busy = false;
  Future<Uint8List?>? _preview;

  List<Asset> get _printable => widget.assets.where((a) => assetQrPayload(a).isNotEmpty).toList();

  @override
  void initState() {
    super.initState();
    _refreshPreview();
  }

  void _refreshPreview() {
    final first = _printable.isEmpty ? null : AssetQrLabelItem.fromAsset(_printable.first);
    _preview = first == null
        ? Future.value(null)
        : renderAssetQrLabelPng(
            first,
            size: _size,
            companyName: widget.companyName,
          );
  }

  int get _labelCount => _printable.length * _copies;

  Future<void> _run(Future<void> Function(List<AssetQrLabelItem> items) action) async {
    if (_busy) return;
    final items = assetQrLabelItems(_printable, copies: _copies);
    if (items.isEmpty) return;
    setState(() => _busy = true);
    await saveAssetQrLabelSize(_size);
    try {
      await action(items);
    } catch (e) {
      NotificationOverlayManager().showError(title: 'Không in được', message: '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _printToLabelPrinter() => _run((items) async {
        final printer = await _pickLabelPrinter(context, _size);
        if (printer == null) return;
        final ok = await printAssetQrLabelsToLabelPrinter(items,
            size: _size, printer: printer, companyName: widget.companyName);
        if (ok && mounted) Navigator.of(context).pop();
      });

  Future<void> _printPdf() =>
      _run((items) => printAssetQrLabelPdf(items, size: _size, companyName: widget.companyName));

  Future<void> _sharePdf() =>
      _run((items) => shareAssetQrLabelPdf(items, size: _size, companyName: widget.companyName));

  @override
  Widget build(BuildContext context) {
    final skipped = widget.assets.length - _printable.length;
    final pages = (_labelCount / (kAssetQrA4Cols * kAssetQrA4Rows)).ceil();
    return AlertDialog(
      title: Row(children: [
        const Icon(Icons.qr_code_2_rounded),
        const SizedBox(width: 8),
        Expanded(child: Text(tr('In tem QR tài sản'))),
      ]),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                widget.assets.length == 1
                    ? '${widget.assets.first.assetCode} · ${widget.assets.first.name}'
                    : tr('${_printable.length} tài sản đã chọn'),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              if (skipped > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(tr('Bỏ qua $skipped tài sản chưa có mã'),
                      style: const TextStyle(fontSize: 12, color: Colors.orange)),
                ),
              const SizedBox(height: 12),
              Text(tr('Khổ tem'), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              for (final s in AssetQrLabelSize.values)
                ListTile(
                  key: ValueKey('asset-qr-size-${s.name}'),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    s == _size ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                    color: s == _size ? Theme.of(context).colorScheme.primary : null,
                  ),
                  title: Text(tr(s.label)),
                  subtitle: Text(tr(s.isThermal ? 'Máy in tem (Bluetooth / LAN / USB)' : 'Máy in văn phòng · giấy decal A4 3×8')),
                  onTap: _busy
                      ? null
                      : () => setState(() {
                            _size = s;
                            _refreshPreview();
                          }),
                ),
              const SizedBox(height: 4),
              Row(children: [
                Expanded(child: Text(tr('Số tem mỗi tài sản'))),
                IconButton(
                  onPressed: _copies > 1 && !_busy ? () => setState(() => _copies--) : null,
                  icon: const Icon(Icons.remove_circle_outline),
                ),
                Text('$_copies', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                IconButton(
                  onPressed: _copies < 100 && !_busy ? () => setState(() => _copies++) : null,
                  icon: const Icon(Icons.add_circle_outline),
                ),
              ]),
              const SizedBox(height: 8),
              Center(
                child: FutureBuilder<Uint8List?>(
                  future: _preview,
                  builder: (_, snap) {
                    final png = snap.data;
                    if (png == null) {
                      return const SizedBox(height: 150, child: Center(child: CircularProgressIndicator()));
                    }
                    return Container(
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.black26),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: Image.memory(png, height: 150, filterQuality: FilterQuality.medium),
                    );
                  },
                ),
              ),
              const SizedBox(height: 6),
              Text(
                _size.isThermal
                    ? tr('Tổng $_labelCount tem')
                    : tr('Tổng $_labelCount tem · $pages trang A4'),
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 12, color: Colors.black54),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: _busy ? null : () => Navigator.pop(context), child: Text(tr('Đóng'))),
        OutlinedButton.icon(
          onPressed: _busy || _labelCount == 0 ? null : _sharePdf,
          icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
          label: Text(tr('Lưu PDF')),
        ),
        if (_size.isThermal)
          FilledButton.icon(
            onPressed: _busy || _labelCount == 0 ? null : _printToLabelPrinter,
            icon: const Icon(Icons.print_rounded, size: 18),
            label: Text(tr('In ra máy tem')),
          )
        else
          FilledButton.icon(
            onPressed: _busy || _labelCount == 0 ? null : _printPdf,
            icon: const Icon(Icons.print_rounded, size: 18),
            label: Text(tr('In')),
          ),
      ],
    );
  }
}

/// Ô hiện mã QR tài sản (chi tiết tài sản) — vẽ bằng cùng bộ QR với tem in.
class AssetQrCodeView extends StatelessWidget {
  const AssetQrCodeView({super.key, required this.data, this.size = 120});

  final String data;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        padding: EdgeInsets.all(size * 0.06),
        color: Colors.white,
        child: CustomPaint(painter: _QrPainter(data)),
      );
}

class _QrPainter extends CustomPainter {
  _QrPainter(this.data);

  final String data;

  @override
  void paint(Canvas canvas, Size size) =>
      PosLabelRenderer.paintQr(canvas, data, Offset.zero & size);

  @override
  bool shouldRepaint(_QrPainter old) => old.data != data;
}
