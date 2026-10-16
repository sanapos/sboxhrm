import 'dart:typed_data';

import 'package:barcode/barcode.dart';
import 'package:excel/excel.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../models/pos_label_design.dart';
import '../models/pos_print_template.dart';
import '../models/pos_product.dart';
import 'pos_label_design_painter.dart';
import 'file_saver.dart' as file_saver;
import 'pos_pdf_fonts.dart';
import '../models/pos_print_template_v2.dart';
import 'pos_label_renderer.dart';
import 'pos_print_template_compiler.dart';
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

/// Dòng thông số dưới tên hàng (tem mã vạch thông số hàng hóa).
enum PosBarcodeSpecMode {
  withoutSpecs,
  withSpecs;

  String get label => switch (this) {
        PosBarcodeSpecMode.withoutSpecs => 'Không in thông số',
        PosBarcodeSpecMode.withSpecs => 'In thông số (thuộc tính, thương hiệu, khối lượng, kích thước, bảo hành)',
      };
}

/// Thông số hàng hóa in trên tem: thuộc tính (Màu: Đỏ · Size: L), thương hiệu, khối lượng,
/// kích thước, bảo hành. Rỗng → null.
String? posProductSpecText(PosProduct p) {
  String num(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2).replaceAll(RegExp(r'0+$'), '');
  final parts = <String>[
    for (final a in p.attributes ?? const [])
      if (a.value.trim().isNotEmpty)
        a.attributeName.trim().isEmpty ? a.value.trim() : '${a.attributeName.trim()}: ${a.value.trim()}',
    if ((p.brandName ?? '').trim().isNotEmpty) 'TH: ${p.brandName!.trim()}',
    if ((p.weight ?? 0) > 0) 'KL: ${num(p.weight!)} ${p.weightUnit.trim().isEmpty ? 'g' : p.weightUnit.trim()}',
    if ((p.lengthCm ?? 0) > 0 || (p.widthCm ?? 0) > 0 || (p.heightCm ?? 0) > 0)
      'KT: ${[p.lengthCm, p.widthCm, p.heightCm].where((v) => (v ?? 0) > 0).map((v) => num(v!)).join('×')} cm',
    if ((p.warrantyMonths ?? 0) > 0) 'BH: ${p.warrantyMonths} tháng',
  ];
  return parts.isEmpty ? null : parts.join(' · ');
}

/// Từng trường thông số (tem thông số / tự soạn). Trống → ''.
Map<String, String> posProductSpecTokens(PosProduct p) {
  String num(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2).replaceAll(RegExp(r'0+$'), '');
  final dims = [p.lengthCm, p.widthCm, p.heightCm].where((v) => (v ?? 0) > 0).map((v) => num(v!)).join('×');
  return {
    'Thuong_Hieu': (p.brandName ?? '').trim(),
    'Nhom_Hang': (p.categoryName ?? '').trim(),
    'Nha_Cung_Cap': (p.supplierName ?? '').trim(),
    'Thuoc_Tinh': [
      for (final a in p.attributes ?? const [])
        if (a.value.trim().isNotEmpty)
          a.attributeName.trim().isEmpty ? a.value.trim() : '${a.attributeName.trim()}: ${a.value.trim()}',
    ].join(' · '),
    'Khoi_Luong_SP': (p.weight ?? 0) > 0
        ? '${num(p.weight!)} ${p.weightUnit.trim().isEmpty ? 'g' : p.weightUnit.trim()}'
        : '',
    'Kich_Thuoc': dims.isEmpty ? '' : '$dims cm',
    'Bao_Hanh': (p.warrantyMonths ?? 0) > 0 ? '${p.warrantyMonths} tháng' : '',
    'Mo_Ta': (p.description ?? '').trim(),
  };
}

/// Dòng chi tiết in dưới tên: tem cân (gắn sẵn) hoặc thông số hàng khi bật.
String? posLabelDetailFor(PosProduct p, PosBarcodePrintOptions opts) =>
    posLabelDetail[p] ??
    (opts.specMode == PosBarcodeSpecMode.withSpecs ? posProductSpecText(p) : null);

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
  // Khổ tùy chỉnh (mẫu tem thông số / tự soạn): roll_1_{rộng}x{cao}.
  final d = PosPrintPaperSizes.customLabelDims(id);
  if (d == null) return null;
  final name = PosPrintPaperSizes.displayLabel(id);
  return PosBarcodeLabelTemplate(
    id: id,
    name: name,
    sizeLabel: name.replaceFirst('Tem ', ''),
    labelWidthMm: d.$1,
    labelHeightMm: d.$2,
  );
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
    this.specMode = PosBarcodeSpecMode.withoutSpecs,
    this.layout,
    this.design,
  });

  final PosBarcodeLabelTemplate template;
  final int copiesPerProduct;
  final PosBarcodeCodeField codeField;
  final PosBarcodePriceMode priceMode;
  final PosBarcodeUnitMode unitMode;
  final PosBarcodeStoreMode storeMode;
  final String? storeName;
  final PosBarcodeSpecMode specMode;

  /// Mẫu tem cửa hàng (màn Mẫu in → Tem sản phẩm). null = bố cục chuẩn SBOX.
  final PosPrintTemplateV2? layout;

  /// Mẫu tem trình soạn tem (đặt tự do) — có thì in theo mẫu này (bỏ qua [layout] và các tuỳ chọn giá / cửa hàng:
  /// nội dung do mẫu quyết định).
  final PosLabelDesign? design;
}

/// Khổ in (cuộn, số tem / hàng, khe) theo mẫu trình soạn tem.
PosBarcodeLabelTemplate posBarcodeLabelTemplateForDesign(PosLabelDesign d) {
  final cols = d.columns.clamp(1, 4);
  final id = PosPrintPaperSizes.customLabelId(d.widthMm, d.heightMm);
  return PosBarcodeLabelTemplate(
    id: cols > 1 ? '${id}_x$cols' : id,
    name: 'Tem ${d.sizeLabel}',
    sizeLabel: d.sizeLabel,
    labelWidthMm: d.widthMm,
    labelHeightMm: d.heightMm,
    cols: cols,
    pageWidthMm: cols > 1 ? d.widthMm * cols + d.columnGapMm * (cols - 1) : null,
    labelGapMm: cols > 1 ? d.columnGapMm : 1.0,
  );
}

/// Dữ liệu một tem hàng hóa cho mẫu thiết kế (token giống màn Mẫu in).
Map<String, String> posBarcodeLabelData(PosProduct p, PosBarcodePrintOptions opts) {
  final money = NumberFormat('#,##0', 'vi_VN');
  final code = switch (opts.codeField) {
    PosBarcodeCodeField.barcode =>
      (p.barcode?.trim().isNotEmpty == true) ? p.barcode!.trim() : p.productCode,
    PosBarcodeCodeField.productCode => p.productCode,
  };
  // Mẫu trình soạn tem: nội dung do mẫu quyết định — luôn có giá (số), tên cửa hàng; ĐVT là trường riêng.
  final forDesign = opts.design != null;
  var price = '';
  if (forDesign || opts.priceMode == PosBarcodePriceMode.withVnd) {
    price = money.format(p.basePrice);
    if (!forDesign && opts.unitMode == PosBarcodeUnitMode.withUnit && p.baseUnitName.isNotEmpty) {
      price = '$price/${p.baseUnitName}';
    }
  }
  return {
    'Ten_Cua_Hang':
        forDesign || opts.storeMode == PosBarcodeStoreMode.withStore ? (opts.storeName ?? '') : '',
    'Ten_Hang_Hoa': p.name,
    'Ma_Hang': p.productCode,
    'Ma_Vach': code,
    'Don_Gia': price,
    'Don_Vi_Tinh': p.baseUnitName,
    'Thong_So': posProductSpecText(p) ?? '',
    ...posProductSpecTokens(p),
    'Lo_HSD': posLabelDetail[p] ?? '',
    'Ngay': DateFormat('dd/MM/yyyy').format(DateTime.now()),
    'So_Luong': '1',
    // Tem cân: khối lượng, đơn giá/kg, thành tiền, ngày giờ in, HSD… (ghi đè token trùng tên).
    ...?posScaleLabelData[p],
  };
}

/// Biên dịch mẫu tem cửa hàng cho một hàng. Bỏ khối giá / tên cửa hàng khi chọn «Không in giá» /
/// «Không in tên cửa hàng» (mẫu có chữ «{Don_Gia} đ» sẽ không còn in « đ» trơ trọi).
PosPrintCompiledOutput compilePosBarcodeLayout(PosProduct p, PosBarcodePrintOptions opts) {
  final tpl = opts.layout!;
  bool uses(PosPrintBlock b, String token) =>
      b.field == token ||
      b.leftField == token ||
      b.rightField == token ||
      (b.text ?? '').contains('{$token}');
  final blocks = tpl.blocks.where((b) {
    if (opts.priceMode == PosBarcodePriceMode.withoutPrice && uses(b, 'Don_Gia')) return false;
    if (opts.storeMode == PosBarcodeStoreMode.withoutStore && uses(b, 'Ten_Cua_Hang')) return false;
    if (opts.specMode == PosBarcodeSpecMode.withoutSpecs && uses(b, 'Thong_So') && posLabelDetail[p] == null) {
      return false;
    }
    return true;
  }).toList();
  return PosPrintTemplateCompiler.compile(
    template: tpl.copyWith(blocks: blocks),
    data: posBarcodeLabelData(p, opts),
    lineItems: const [],
  );
}


/// Tạo PDF tem mã vạch, trả về bytes.
Future<Uint8List> buildPosBarcodeLabelPdfBytes(
  List<PosProduct> products, {
  required PosBarcodePrintOptions options,
  List<int>? copiesPerItem,
}) async {
  final copies = options.copiesPerProduct.clamp(1, 5000);
  final pdf = await _buildLabelPdf(products, options, copies, copiesPerItem);
  return Uint8List.fromList(await pdf.save());
}

/// In tem trực tiếp ra máy in nhãn (Bluetooth / LAN / USB).
Future<bool> printPosBarcodeLabelsToDevice(
  List<PosProduct> products, {
  required PosBarcodePrintOptions options,
  required PosLabelPrinterSettings settings,
  List<int>? copiesPerItem,
}) =>
    PosLabelPrinterService.printLabels(
      products,
      options: options,
      settings: settings,
      copiesPerItem: copiesPerItem,
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
        template: defaultBarcodeLabelTemplate,
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
  int copies, [
  List<int>? copiesPerItem,
]) async {
  final fonts = await loadPosPdfFonts();
  final font = fonts.regular;
  final fontBold = fonts.bold;
  final pdf = pw.Document(
    theme: pw.ThemeData.withFont(base: font, bold: fontBold),
  );
  final moneyFmt = NumberFormat('#,##0', 'vi_VN');
  final t = opts.template;

  final labels = <pw.Widget>[];
  for (var i = 0; i < products.length; i++) {
    final per = copiesPerItem != null && i < copiesPerItem.length ? copiesPerItem[i] : 1;
    final n = (per.clamp(0, 5000) * copies).clamp(0, 5000);
    if (n == 0) continue;
    final label = opts.design != null
        ? await _designLabelWidget(products[i], opts)
        : opts.layout != null
            ? await _layoutLabelWidget(products[i], opts)
            : _labelWidget(products[i], opts, moneyFmt, font, fontBold);
    for (var c = 0; c < n; c++) {
      labels.add(label);
    }
  }

  // Mẫu trình soạn tem: trang đúng khổ tem (không lề), tem nằm kín ô.
  final design = opts.design;
  if (design != null) {
    final cols = t.cols.clamp(1, 4);
    final pageFormat = PdfPageFormat(t.rollPageWidthMm * PdfPageFormat.mm, t.labelHeightMm * PdfPageFormat.mm);
    for (var i = 0; i < labels.length; i += cols) {
      final chunk = labels.sublist(i, (i + cols).clamp(0, labels.length));
      pdf.addPage(pw.Page(
        pageFormat: pageFormat,
        margin: pw.EdgeInsets.zero,
        build: (_) => pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          for (var c = 0; c < chunk.length; c++) ...[
            if (c > 0) pw.SizedBox(width: design.columnGapMm * PdfPageFormat.mm),
            pw.SizedBox(
              width: design.widthMm * PdfPageFormat.mm,
              height: design.heightMm * PdfPageFormat.mm,
              child: chunk[c],
            ),
          ],
        ]),
      ));
    }
    return pdf;
  }

  if (t.cols > 1 || t.rows > 1) {
    final perPage = t.cols * t.rows;
    final gapW = t.labelGapMm * PdfPageFormat.mm;
    final totalGap = t.cols > 1 ? gapW * (t.cols - 1) : 0;
    final pageInnerW = t.pageFormat.availableWidth - totalGap;
    final labelW = pageInnerW / t.cols;
    final labelH = t.isSheet
        ? t.pageFormat.availableHeight / t.rows
        : t.pageFormat.availableHeight;

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

/// Tem theo mẫu trình soạn tem → ảnh 300 dpi (cùng bộ vẽ với màn soạn / máy tem).
Future<pw.Widget> _designLabelWidget(PosProduct p, PosBarcodePrintOptions opts) async {
  final d = opts.design!.copyWith(columns: 1);
  final png = await PosLabelDesignPainter.renderPng(d, posBarcodeLabelData(p, opts), pxPerMm: 300 / 25.4);
  if (png == null) return pw.SizedBox();
  return pw.Image(pw.MemoryImage(png), fit: pw.BoxFit.fill);
}

/// Tem theo mẫu cửa hàng → ảnh 300 dpi (giống tem in thẳng), một ảnh dùng chung cho mọi bản sao.
Future<pw.Widget> _layoutLabelWidget(PosProduct p, PosBarcodePrintOptions opts) async {
  final t = opts.template;
  final w = t.cols > 1 && !t.isSheet ? PosLabelRenderer.rowCellWidthMm(t) : t.labelWidthMm;
  final r = await PosLabelRenderer.renderCompiledLabel(
    output: compilePosBarcodeLayout(p, opts),
    widthMm: w,
    heightMm: t.labelHeightMm,
    dpi: 300,
  );
  final rgba = Uint8List(r.widthPx * r.heightPx * 4);
  final bpr = (r.widthPx + 7) ~/ 8;
  for (var y = 0; y < r.heightPx; y++) {
    for (var x = 0; x < r.widthPx; x++) {
      final v = (r.raster[y * bpr + (x >> 3)] >> (7 - (x & 7))) & 1 == 1 ? 0 : 255;
      final i = (y * r.widthPx + x) * 4;
      rgba[i] = v;
      rgba[i + 1] = v;
      rgba[i + 2] = v;
      rgba[i + 3] = 255;
    }
  }
  return pw.Image(pw.RawImage(bytes: rgba, width: r.widthPx, height: r.heightPx), fit: pw.BoxFit.contain);
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

  final detail = posLabelDetailFor(p, opts);
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
    if (detail != null && detail.isNotEmpty)
      pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 0.5),
        child: pw.Text(
          detail,
          maxLines: 2,
          overflow: pw.TextOverflow.clip,
          style: pw.TextStyle(font: font, fontSize: metaSize * 0.9),
          textAlign: pw.TextAlign.center,
        ),
      ),
    pw.Center(
      child: pw.BarcodeWidget(
        barcode: posBarcodeSymbology(code),
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
  List<int>? copiesPerItem,
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
    TextCellValue('Thông số'),
    TextCellValue('Số lượng in'),
    TextCellValue('Mẫu giấy'),
  ]);

  final moneyFmt = NumberFormat('#,##0', 'vi_VN');
  for (var i = 0; i < products.length; i++) {
    final p = products[i];
    final per = copiesPerItem != null && i < copiesPerItem.length ? copiesPerItem[i] : 1;
    sheet.appendRow([
      TextCellValue(p.productCode),
      TextCellValue(p.name),
      TextCellValue(p.barcode ?? ''),
      TextCellValue(moneyFmt.format(p.basePrice)),
      TextCellValue(p.baseUnitName),
      TextCellValue(posProductSpecText(p) ?? ''),
      IntCellValue(per * options.copiesPerProduct),
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

/// Dòng chi tiết in thêm dưới tên trên tem (vd tem cân: «0,450 kg × 150.000đ/kg · HSD 08/10»).
/// Gắn theo đối tượng hàng (tem cân dùng hàng tạm), không đổi model.
final posLabelDetail = Expando<String>('posLabelDetail');

/// Dữ liệu riêng tem cân (token mẫu «Tem cân»: Khoi_Luong, Don_Gia_Kg, Thanh_Tien, Ngay_Gio_In, HSD, PLU…),
/// gắn theo đối tượng hàng tạm của từng gói.
final posScaleLabelData = Expando<Map<String, String>>('posScaleLabelData');

/// EAN-13 / EAN-8 khi mã đúng chuẩn (mã vạch siêu thị, tem cân), còn lại Code128.
Barcode posBarcodeSymbology(String data) {
  bool validEan(String c) {
    var sum = 0;
    final n = c.length - 1;
    for (var i = 0; i < n; i++) {
      final d = c.codeUnitAt(n - 1 - i) - 48;
      sum += i.isEven ? d * 3 : d;
    }
    return (10 - sum % 10) % 10 == c.codeUnitAt(n) - 48;
  }

  final isDigits = RegExp(r'^\d+$').hasMatch(data);
  if (isDigits && data.length == 13 && validEan(data)) return Barcode.ean13(drawEndChar: false);
  if (isDigits && data.length == 8 && validEan(data)) return Barcode.ean8();
  return Barcode.code128();
}
