import 'dart:typed_data';

import 'package:barcode/barcode.dart';
import 'package:excel/excel.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../models/pos_product.dart';
import 'file_saver.dart' as file_saver;
import 'pos_label_printer_settings.dart';
import 'pos_label_printer_service.dart';

enum PosBarcodeCodeField {
  productCode,
  barcode;

  String get label => switch (this) {
        PosBarcodeCodeField.productCode => 'Mã hàng',
        PosBarcodeCodeField.barcode => 'Mã vạch',
      };
}

enum PosBarcodePriceMode {
  withVnd,
  withoutPrice;

  String get label => switch (this) {
        PosBarcodePriceMode.withVnd => 'Giá kèm VNĐ',
        PosBarcodePriceMode.withoutPrice => 'Không in giá',
      };
}

enum PosBarcodeUnitMode {
  withoutUnit,
  withUnit;

  String get label => switch (this) {
        PosBarcodeUnitMode.withoutUnit => 'Giá không kèm đơn vị tính',
        PosBarcodeUnitMode.withUnit => 'Giá kèm đơn vị tính',
      };
}

enum PosBarcodeStoreMode {
  withoutStore,
  withStore;

  String get label => switch (this) {
        PosBarcodeStoreMode.withoutStore => 'Không in tên cửa hàng',
        PosBarcodeStoreMode.withStore => 'In tên cửa hàng',
      };
}

class PosBarcodeLabelTemplate {
  const PosBarcodeLabelTemplate({
    required this.id,
    required this.name,
    required this.sizeLabel,
    required this.labelWidthMm,
    required this.labelHeightMm,
    this.cols = 1,
    this.rows = 1,
    this.pageWidthMm,
    this.pageHeightMm,
    this.labelGapMm = 1.0,
  });

  final String id;
  final String name;
  final String sizeLabel;
  final double labelWidthMm;
  final double labelHeightMm;
  final int cols;
  final int rows;
  final double? pageWidthMm;
  final double? pageHeightMm;
  /// Khoảng cách giữa các nhãn trên cùng một hàng (mm).
  final double labelGapMm;

  double get rollPageWidthMm => pageWidthMm ?? (labelWidthMm * cols);
  double get rollPageHeightMm => pageHeightMm ?? labelHeightMm;

  PdfPageFormat get pageFormat => PdfPageFormat(
        rollPageWidthMm * PdfPageFormat.mm,
        rollPageHeightMm * PdfPageFormat.mm,
        marginAll: cols > 1 ? 0.5 : 1,
      );

  PdfPageFormat get singleLabelFormat => PdfPageFormat(
        labelWidthMm * PdfPageFormat.mm,
        labelHeightMm * PdfPageFormat.mm,
        marginAll: 2,
      );

  bool get isSheet => pageWidthMm != null && rows > 1;
}

const posBarcodeLabelTemplates = [
  PosBarcodeLabelTemplate(
    id: 'roll_1_50x30',
    name: 'Tem 50×30',
    sizeLabel: '50 x 30 mm',
    labelWidthMm: 50,
    labelHeightMm: 30,
  ),
  PosBarcodeLabelTemplate(
    id: 'roll_1_40x30',
    name: 'Tem 40×30',
    sizeLabel: '40 x 30 mm',
    labelWidthMm: 40,
    labelHeightMm: 30,
  ),
  PosBarcodeLabelTemplate(
    id: 'roll_2_72x22',
    name: 'Tem 35×22 × 2',
    sizeLabel: '72 x 22 mm (2 tem)',
    labelWidthMm: 36,
    labelHeightMm: 22,
    cols: 2,
    pageWidthMm: 72,
    pageHeightMm: 22,
  ),
  PosBarcodeLabelTemplate(
    id: 'roll_3_104x22',
    name: 'Tem 35×22 × 3',
    sizeLabel: '104 x 22 mm (3 tem)',
    labelWidthMm: 34.67,
    labelHeightMm: 22,
    cols: 3,
    pageWidthMm: 104,
    pageHeightMm: 22,
  ),
  PosBarcodeLabelTemplate(
    id: 'roll_1_60x40',
    name: 'Tem 60×40',
    sizeLabel: '60 x 40 mm',
    labelWidthMm: 60,
    labelHeightMm: 40,
  ),
  PosBarcodeLabelTemplate(
    id: 'roll_1_58x40',
    name: 'Tem 58×40',
    sizeLabel: '58 x 40 mm',
    labelWidthMm: 58,
    labelHeightMm: 40,
  ),
  PosBarcodeLabelTemplate(
    id: 'roll_1_75x100',
    name: 'Tem 75×100 (A7)',
    sizeLabel: '75 x 100 mm',
    labelWidthMm: 75,
    labelHeightMm: 100,
  ),
  PosBarcodeLabelTemplate(
    id: 'roll_1_100x150',
    name: 'Tem 100×150 (A6)',
    sizeLabel: '100 x 150 mm',
    labelWidthMm: 100,
    labelHeightMm: 150,
  ),
  PosBarcodeLabelTemplate(
    id: 'roll_1_100x50',
    name: 'Tem 100×50',
    sizeLabel: '100 x 50 mm',
    labelWidthMm: 100,
    labelHeightMm: 50,
  ),
  PosBarcodeLabelTemplate(
    id: 'roll_2_74x22',
    name: 'Tem 37×22 × 2',
    sizeLabel: '74 x 22 mm (2 tem)',
    labelWidthMm: 37,
    labelHeightMm: 22,
    cols: 2,
    pageWidthMm: 74,
    pageHeightMm: 22,
  ),
  PosBarcodeLabelTemplate(
    id: 'sheet_12_tomy103',
    name: 'Tờ 12 nhãn Tomy 103',
    sizeLabel: '202 x 167 mm',
    labelWidthMm: 67.3,
    labelHeightMm: 41.75,
    cols: 3,
    rows: 4,
    pageWidthMm: 202,
    pageHeightMm: 167,
  ),
  PosBarcodeLabelTemplate(
    id: 'sheet_65_a4',
    name: 'Tờ 65 nhãn A4',
    sizeLabel: 'A4 - Tomy 145',
    labelWidthMm: 38.1,
    labelHeightMm: 21.2,
    cols: 5,
    rows: 13,
    pageWidthMm: 210,
    pageHeightMm: 297,
  ),
  PosBarcodeLabelTemplate(
    id: 'jewelry_75x10',
    name: 'Tem trang sức',
    sizeLabel: '75 x 10 mm',
    labelWidthMm: 75,
    labelHeightMm: 10,
  ),
];

PosBarcodeLabelTemplate? posBarcodeLabelTemplateById(String id) {
  for (final t in posBarcodeLabelTemplates) {
    if (t.id == id) return t;
  }
  return null;
}

PosBarcodeLabelTemplate get defaultBarcodeLabelTemplate =>
    posBarcodeLabelTemplates.firstWhere((t) => t.id == 'roll_1_50x30');

class PosBarcodePrintOptions {
  const PosBarcodePrintOptions({
    required this.template,
    this.copiesPerProduct = 1,
    this.codeField = PosBarcodeCodeField.productCode,
    this.priceMode = PosBarcodePriceMode.withVnd,
    this.unitMode = PosBarcodeUnitMode.withoutUnit,
    this.storeMode = PosBarcodeStoreMode.withoutStore,
    this.storeName,
  });

  final PosBarcodeLabelTemplate template;
  final int copiesPerProduct;
  final PosBarcodeCodeField codeField;
  final PosBarcodePriceMode priceMode;
  final PosBarcodeUnitMode unitMode;
  final PosBarcodeStoreMode storeMode;
  final String? storeName;
}

/// Tạo PDF tem mã vạch, trả về bytes.
Future<Uint8List> buildPosBarcodeLabelPdfBytes(
  List<PosProduct> products, {
  required PosBarcodePrintOptions options,
}) async {
  final copies = options.copiesPerProduct.clamp(1, 5000);
  final pdf = await _buildLabelPdf(products, options, copies);
  return Uint8List.fromList(await pdf.save());
}

/// In tem trực tiếp ra máy in nhãn (Bluetooth / LAN / USB).
Future<bool> printPosBarcodeLabelsToDevice(
  List<PosProduct> products, {
  required PosBarcodePrintOptions options,
  required PosLabelPrinterSettings settings,
}) =>
    PosLabelPrinterService.printLabels(
      products,
      options: options,
      settings: settings,
    );

Future<void> printPosBarcodeLabels(
  List<PosProduct> products, {
  PosBarcodePrintOptions? options,
  int copiesPerProduct = 1,
  bool previewOnly = false,
}) async {
  if (products.isEmpty) return;
  final opts = options ??
      PosBarcodePrintOptions(
        template: posBarcodeLabelTemplates[3],
        copiesPerProduct: copiesPerProduct,
      );
  final bytes = await buildPosBarcodeLabelPdfBytes(products, options: opts);
  final filename =
      'TemMaHang_${DateFormat('yyyyMMdd_HHmm').format(DateTime.now())}.pdf';

  if (previewOnly) {
    if (kIsWeb) {
      await file_saver.openPdfInNewTab(bytes, filename);
    } else {
      await Printing.layoutPdf(onLayout: (_) async => bytes, name: filename);
    }
  } else {
    await Printing.sharePdf(bytes: bytes, filename: filename);
  }
}

Future<pw.Document> _buildLabelPdf(
  List<PosProduct> products,
  PosBarcodePrintOptions opts,
  int copies,
) async {
  final font = await PdfGoogleFonts.notoSansRegular();
  final fontBold = await PdfGoogleFonts.notoSansBold();
  final pdf = pw.Document(
    theme: pw.ThemeData.withFont(base: font, bold: fontBold),
  );
  final moneyFmt = NumberFormat('#,##0', 'vi_VN');
  final t = opts.template;

  final labels = <pw.Widget>[];
  for (final p in products) {
    for (var c = 0; c < copies; c++) {
      labels.add(_labelWidget(p, opts, moneyFmt, font, fontBold));
    }
  }

  if (t.cols > 1 || t.rows > 1) {
    final perPage = t.cols * t.rows;
    final gapW = t.labelGapMm * PdfPageFormat.mm;
    final totalGap = t.cols > 1 ? gapW * (t.cols - 1) : 0;
    final pageInnerW = t.rollPageWidthMm * PdfPageFormat.mm - totalGap;
    final labelW = pageInnerW / t.cols;
    final labelH = t.labelHeightMm * PdfPageFormat.mm;

    for (var i = 0; i < labels.length; i += perPage) {
      final end = (i + perPage > labels.length) ? labels.length : i + perPage;
      final chunk = labels.sublist(i, end);

      pdf.addPage(
        pw.Page(
          pageFormat: t.pageFormat,
          build: (_) {
            if (t.isSheet) {
              return pw.Column(
                children: List.generate(t.rows, (row) {
                  return pw.Row(
                    children: List.generate(t.cols, (col) {
                      final idx = row * t.cols + col;
                      if (idx >= chunk.length) {
                        return pw.SizedBox(width: labelW, height: labelH);
                      }
                      return _labelCell(chunk[idx], labelW, labelH);
                    }),
                  );
                }),
              );
            }
            // Giấy cuộn: nhãn xếp ngang, có khe cách
            final rowChildren = <pw.Widget>[];
            for (var c = 0; c < chunk.length; c++) {
              if (c > 0) rowChildren.add(pw.SizedBox(width: gapW));
              rowChildren.add(_labelCell(chunk[c], labelW, labelH));
            }
            return pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: rowChildren,
            );
          },
        ),
      );
    }
  } else {
    for (final label in labels) {
      pdf.addPage(
        pw.Page(pageFormat: t.singleLabelFormat, build: (_) => label),
      );
    }
  }
  return pdf;
}

pw.Widget _labelCell(pw.Widget child, double width, double height) {
  return pw.Container(
    width: width,
    height: height,
    padding: const pw.EdgeInsets.symmetric(horizontal: 2, vertical: 1),
    child: pw.ClipRect(child: child),
  );
}

pw.Widget _labelWidget(
  PosProduct p,
  PosBarcodePrintOptions opts,
  NumberFormat moneyFmt,
  pw.Font font,
  pw.Font fontBold,
) {
  final code = switch (opts.codeField) {
    PosBarcodeCodeField.barcode =>
      (p.barcode?.trim().isNotEmpty == true) ? p.barcode!.trim() : p.productCode,
    PosBarcodeCodeField.productCode => p.productCode,
  };

  final t = opts.template;
  final small = t.labelHeightMm <= 22;
  final nameSize = small ? 4.8 : 7.0;
  final metaSize = small ? 5.0 : 6.5;
  final storeSize = small ? 4.5 : 6.0;
  // Chừa header + mã + giá; barcode tối đa ~25% chiều cao tem.
  final hasStore = opts.storeMode == PosBarcodeStoreMode.withStore &&
      opts.storeName != null &&
      opts.storeName!.isNotEmpty;
  final hasPrice = opts.priceMode == PosBarcodePriceMode.withVnd;
  final reserveMm = (hasStore ? storeSize * 0.4 : 0) +
      nameSize * (small ? 0.45 : 0.7) +
      metaSize * 0.45 +
      (hasPrice ? metaSize * 0.45 : 0) +
      2.5;
  final barcodeH = ((t.labelHeightMm - reserveMm) * PdfPageFormat.mm)
      .clamp(small ? 7.0 : 9.0, t.labelHeightMm * PdfPageFormat.mm * (small ? 0.22 : 0.26));
  final labelInnerW = small
      ? (t.labelWidthMm - (t.cols > 1 ? t.labelGapMm / t.cols : 0) - 2) *
          PdfPageFormat.mm
      : t.labelWidthMm * PdfPageFormat.mm - 8;
  final barcodeW = labelInnerW.clamp(20.0, t.labelWidthMm * PdfPageFormat.mm);

  final lines = <pw.Widget>[
    if (opts.storeMode == PosBarcodeStoreMode.withStore &&
        opts.storeName != null &&
        opts.storeName!.isNotEmpty)
      pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 0.5),
        child: pw.Text(
          opts.storeName!,
          maxLines: 1,
          overflow: pw.TextOverflow.clip,
          style: pw.TextStyle(font: font, fontSize: storeSize),
          textAlign: pw.TextAlign.center,
        ),
      ),
    pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 0.5),
      child: pw.Text(
        p.name,
        maxLines: small ? 1 : 2,
        overflow: pw.TextOverflow.clip,
        style: pw.TextStyle(font: font, fontSize: nameSize),
        textAlign: pw.TextAlign.center,
      ),
    ),
    pw.Center(
      child: pw.BarcodeWidget(
        barcode: Barcode.code128(),
        data: code,
        width: barcodeW,
        height: barcodeH,
        drawText: false,
      ),
    ),
    pw.SizedBox(height: 0.5),
    pw.Text(
      code,
      maxLines: 1,
      overflow: pw.TextOverflow.clip,
      style: pw.TextStyle(font: fontBold, fontSize: metaSize),
      textAlign: pw.TextAlign.center,
    ),
  ];

  if (opts.priceMode == PosBarcodePriceMode.withVnd) {
    var priceText = moneyFmt.format(p.basePrice);
    if (opts.unitMode == PosBarcodeUnitMode.withUnit &&
        p.baseUnitName.isNotEmpty) {
      priceText = '$priceText/${p.baseUnitName}';
    }
    priceText = '$priceText VND';
    lines.add(pw.Text(
      priceText,
      maxLines: 1,
      style: pw.TextStyle(font: fontBold, fontSize: metaSize),
      textAlign: pw.TextAlign.center,
    ));
  }

  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.stretch,
    mainAxisAlignment: pw.MainAxisAlignment.center,
    mainAxisSize: pw.MainAxisSize.min,
    children: lines,
  );
}

Future<void> exportPosBarcodeLabelsExcel(
  List<PosProduct> products, {
  required PosBarcodePrintOptions options,
}) async {
  final excel = Excel.createExcel();
  final sheet = excel['Tem ma'];
  excel.delete('Sheet1');

  sheet.appendRow([
    TextCellValue('Mã hàng'),
    TextCellValue('Tên hàng'),
    TextCellValue('Mã vạch'),
    TextCellValue('Giá bán'),
    TextCellValue('Đơn vị'),
    TextCellValue('Số lượng in'),
    TextCellValue('Mẫu giấy'),
  ]);

  final moneyFmt = NumberFormat('#,##0', 'vi_VN');
  for (final p in products) {
    sheet.appendRow([
      TextCellValue(p.productCode),
      TextCellValue(p.name),
      TextCellValue(p.barcode ?? ''),
      TextCellValue(moneyFmt.format(p.basePrice)),
      TextCellValue(p.baseUnitName),
      IntCellValue(options.copiesPerProduct),
      TextCellValue(options.template.name),
    ]);
  }

  final bytes = excel.encode();
  if (bytes == null) return;
  await file_saver.saveFileBytes(
    Uint8List.fromList(bytes),
    'TemMaHang_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.xlsx',
    'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
  );
}
