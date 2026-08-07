import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:barcode/barcode.dart';
import 'package:intl/intl.dart';

import '../models/pos_product.dart';
import 'pos_barcode_print.dart';

/// Dữ liệu một nhãn cần render.
class PosLabelRenderItem {
  const PosLabelRenderItem({
    required this.name,
    required this.code,
    this.priceText,
    this.storeName,
  });

  final String name;
  final String code;
  final String? priceText;
  final String? storeName;
}

/// Render nhãn tem mã thành ảnh đen trắng (dots).
class PosLabelRenderer {
  static int mmToDots(double mm, int dpi) => (mm / 25.4 * dpi).round();

  static PosLabelRenderItem fromProduct(
    PosProduct p,
    PosBarcodePrintOptions opts,
    NumberFormat moneyFmt,
  ) {
    final code = switch (opts.codeField) {
      PosBarcodeCodeField.barcode =>
        (p.barcode?.trim().isNotEmpty == true) ? p.barcode!.trim() : p.productCode,
      PosBarcodeCodeField.productCode => p.productCode,
    };
    String? priceText;
    if (opts.priceMode == PosBarcodePriceMode.withVnd) {
      var t = moneyFmt.format(p.basePrice);
      if (opts.unitMode == PosBarcodeUnitMode.withUnit && p.baseUnitName.isNotEmpty) {
        t = '$t/${p.baseUnitName}';
      }
      priceText = '$t đ';
    }
    final store = opts.storeMode == PosBarcodeStoreMode.withStore ? opts.storeName : null;
    return PosLabelRenderItem(
      name: p.name,
      code: code,
      priceText: priceText,
      storeName: store?.trim().isNotEmpty == true ? store!.trim() : null,
    );
  }

  /// Render một nhãn đơn.
  static Future<({Uint8List raster, int widthPx, int heightPx})> renderSingle({
    required PosLabelRenderItem item,
    required PosBarcodeLabelTemplate template,
    int dpi = 203,
  }) async {
    final w = mmToDots(template.labelWidthMm, dpi);
    final h = mmToDots(template.labelHeightMm, dpi);
    return _renderToRaster(
      widthPx: w,
      heightPx: h,
      item: item,
      small: template.labelHeightMm <= 22,
    );
  }

  /// Render một hàng nhãn (giấy cuộn nhiều cột).
  static Future<({Uint8List raster, int widthPx, int heightPx})> renderRow({
    required List<PosLabelRenderItem> items,
    required PosBarcodeLabelTemplate template,
    int dpi = 203,
  }) async {
    final w = mmToDots(template.rollPageWidthMm, dpi);
    final h = mmToDots(template.labelHeightMm, dpi);
    final labelW = mmToDots(template.labelWidthMm, dpi);
    final gap = mmToDots(template.labelGapMm, dpi);
    final small = template.labelHeightMm <= 22;

    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    canvas.drawRect(
      ui.Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
      ui.Paint()..color = const ui.Color(0xFFFFFFFF),
    );

    var x = 0.0;
    for (var i = 0; i < items.length && i < template.cols; i++) {
      await _paintLabelOnCanvas(
        canvas,
        ui.Rect.fromLTWH(x, 0, labelW.toDouble(), h.toDouble()),
        items[i],
        small: small,
      );
      x += labelW + (i < items.length - 1 ? gap : 0);
    }

    final picture = recorder.endRecording();
    final image = await picture.toImage(w, h);
    return _imageToRaster(image);
  }

  static Future<({Uint8List raster, int widthPx, int heightPx})> _renderToRaster({
    required int widthPx,
    required int heightPx,
    required PosLabelRenderItem item,
    required bool small,
  }) async {
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    canvas.drawRect(
      ui.Rect.fromLTWH(0, 0, widthPx.toDouble(), heightPx.toDouble()),
      ui.Paint()..color = const ui.Color(0xFFFFFFFF),
    );
    await _paintLabelOnCanvas(
      canvas,
      ui.Rect.fromLTWH(0, 0, widthPx.toDouble(), heightPx.toDouble()),
      item,
      small: small,
    );
    final picture = recorder.endRecording();
    final image = await picture.toImage(widthPx, heightPx);
    return _imageToRaster(image);
  }

  static Future<void> _paintLabelOnCanvas(
    ui.Canvas canvas,
    ui.Rect bounds,
    PosLabelRenderItem item, {
    required bool small,
  }) async {
    final pad = small ? 2.0 : 4.0;
    var y = pad;
    final innerW = bounds.width - pad * 2;

    if (item.storeName != null) {
      y += await _drawTextCentered(
        canvas,
        item.storeName!,
        bounds.left + pad,
        y,
        innerW,
        fontSize: small ? 9 : 11,
        maxLines: 1,
      );
      y += 2;
    }

    y += await _drawTextCentered(
      canvas,
      item.name,
      bounds.left + pad,
      y,
      innerW,
      fontSize: small ? 10 : 13,
      maxLines: small ? 1 : 2,
    );
    y += 2;

    final barcodeH = (bounds.height * (small ? 0.32 : 0.36)).clamp(12.0, 56.0);
    final barcodeRect = ui.Rect.fromLTWH(
      bounds.left + pad,
      y,
      innerW,
      barcodeH,
    );
    _drawBarcode(canvas, item.code, barcodeRect);
    y += barcodeH + 2;

    y += await _drawTextCentered(
      canvas,
      item.code,
      bounds.left + pad,
      y,
      innerW,
      fontSize: small ? 10 : 12,
      bold: true,
      maxLines: 1,
    );

    if (item.priceText != null) {
      y += 2;
      await _drawTextCentered(
        canvas,
        item.priceText!,
        bounds.left + pad,
        y,
        innerW,
        fontSize: small ? 10 : 12,
        bold: true,
        maxLines: 1,
      );
    }
  }

  static void _drawBarcode(ui.Canvas canvas, String data, ui.Rect rect) {
    if (data.isEmpty) return;
    try {
      final bc = Barcode.code128();
      final elements = bc.make(data, width: rect.width, height: rect.height);
      final paint = ui.Paint()..color = const ui.Color(0xFF000000);
      for (final e in elements) {
        if (e is BarcodeBar && e.black) {
          canvas.drawRect(
            ui.Rect.fromLTWH(
              rect.left + e.left,
              rect.top,
              e.width,
              e.height,
            ),
            paint,
          );
        }
      }
    } catch (_) {
      // Mã không hợp lệ
    }
  }

  static Future<double> _drawTextCentered(
    ui.Canvas canvas,
    String text,
    double x,
    double y,
    double maxW, {
    required double fontSize,
    bool bold = false,
    int maxLines = 2,
  }) async {
    if (text.isEmpty) return 0;
    final builder = ui.ParagraphBuilder(
      ui.ParagraphStyle(
        fontFamily: 'BeVietnamPro',
        fontSize: fontSize,
        fontWeight: bold ? ui.FontWeight.w700 : ui.FontWeight.w400,
        textAlign: ui.TextAlign.center,
        maxLines: maxLines,
      ),
    )..addText(text);
    final paragraph = builder.build()..layout(ui.ParagraphConstraints(width: maxW));
    canvas.drawParagraph(paragraph, ui.Offset(x, y));
    return paragraph.height;
  }

  static Future<({Uint8List raster, int widthPx, int heightPx})> _imageToRaster(
    ui.Image image,
  ) async {
    final w = image.width;
    final h = image.height;
    final byteData = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    final rgba = byteData?.buffer.asUint8List() ?? Uint8List(0);
    final bytesPerRow = (w + 7) ~/ 8;
    final raster = Uint8List(bytesPerRow * h);

    for (var row = 0; row < h; row++) {
      for (var xByte = 0; xByte < bytesPerRow; xByte++) {
        var b = 0;
        for (var bit = 0; bit < 8; bit++) {
          final x = xByte * 8 + bit;
          if (x >= w) continue;
          final idx = (row * w + x) * 4;
          if (idx + 2 >= rgba.length) continue;
          final lum = 0.299 * rgba[idx] +
              0.587 * rgba[idx + 1] +
              0.114 * rgba[idx + 2];
          if (lum < 168) b |= (0x80 >> bit);
        }
        raster[row * bytesPerRow + xByte] = b;
      }
    }
    return (raster: raster, widthPx: w, heightPx: h);
  }
}
