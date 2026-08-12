import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:barcode/barcode.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/pos_product.dart';
import 'pos_barcode_print.dart';
import 'pos_print_template_compiler.dart';
import 'pos_thermal_bitmap.dart';
import 'vietnamese_font.dart';

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

  /// Raster gần như trống (chỉ đường kẻ) → không nên gửi máy in.
  static bool hasEnoughInk(Uint8List raster, {double minRatio = 0.004}) {
    if (raster.isEmpty) return false;
    var black = 0;
    for (final b in raster) {
      // Đếm bit 1 (ESC/POS: đen).
      black += b.bitCount;
    }
    final totalBits = raster.length * 8;
    return black >= (totalBits * minRatio).ceil().clamp(24, 999999);
  }

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
    /// Lề trái nội dung (mm) — bù tem lệch trái / chữ dồn nửa tờ.
    double contentInsetLeftMm = 3.0,
  }) async {
    await PosThermalBitmapEncoder.ensureFont();
    final w = mmToDots(template.labelWidthMm, dpi);
    final h = mmToDots(template.labelHeightMm, dpi);
    return _renderToRaster(
      widthPx: w,
      heightPx: h,
      item: item,
      small: template.labelHeightMm <= 22,
      wide: template.labelWidthMm >= 48,
      contentInsetLeftMm: contentInsetLeftMm,
      dpi: dpi,
    );
  }

  /// Render một hàng nhãn (giấy cuộn nhiều cột).
  static Future<({Uint8List raster, int widthPx, int heightPx})> renderRow({
    required List<PosLabelRenderItem> items,
    required PosBarcodeLabelTemplate template,
    int dpi = 203,
    double contentInsetLeftMm = 3.0,
  }) async {
    await PosThermalBitmapEncoder.ensureFont();
    final w = mmToDots(template.rollPageWidthMm, dpi);
    final h = mmToDots(template.labelHeightMm, dpi);
    final labelW = mmToDots(template.labelWidthMm, dpi);
    final gap = mmToDots(template.labelGapMm, dpi);
    final small = template.labelHeightMm <= 22;
    final wide = template.labelWidthMm >= 48;

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
        wide: wide,
        contentInsetLeftMm: contentInsetLeftMm,
        dpi: dpi,
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
    bool wide = false,
    double contentInsetLeftMm = 3.0,
    int dpi = 203,
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
      wide: wide,
      contentInsetLeftMm: contentInsetLeftMm,
      dpi: dpi,
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
    bool wide = false,
    double contentInsetLeftMm = 3.0,
    int dpi = 203,
  }) async {
    final leftInset = mmToDots(contentInsetLeftMm.clamp(0, 8), dpi).toDouble();
    final pad = small ? 3.0 : (wide ? 6.0 : 4.0);
    var y = pad;
    final contentLeft = bounds.left + leftInset + pad;
    final innerW = (bounds.width - leftInset - pad * 2).clamp(8.0, bounds.width);
    // Chừa chỗ mã + giá phía dưới trước khi tính chiều cao barcode.
    final footerBudget = (small ? 14.0 : (wide ? 22.0 : 16.0)) +
        (item.priceText != null ? (small ? 12.0 : (wide ? 18.0 : 14.0)) : 0) +
        pad +
        4;

    final nameSize = small ? 11.0 : (wide ? 18.0 : 13.0);
    final codeSize = small ? 11.0 : (wide ? 15.0 : 12.0);
    final priceSize = small ? 11.0 : (wide ? 16.0 : 12.0);
    final storeSize = small ? 10.0 : (wide ? 13.0 : 11.0);

    if (item.storeName != null) {
      y += await _drawText(
        canvas,
        item.storeName!,
        contentLeft,
        y,
        innerW,
        fontSize: storeSize,
        maxLines: 1,
        center: true,
      );
      y += 2;
    }

    y += await _drawText(
      canvas,
      item.name,
      contentLeft,
      y,
      innerW,
      fontSize: nameSize,
      bold: true,
      maxLines: small ? 1 : 2,
      center: true,
    );
    y += 3;

    final remaining = bounds.height - y - footerBudget;
    final barcodeH = remaining
        .clamp(
          small ? 12.0 : 18.0,
          bounds.height * (small ? 0.26 : (wide ? 0.36 : 0.30)),
        )
        .toDouble();
    if (barcodeH >= 10 && item.code.isNotEmpty) {
      final barcodeRect = ui.Rect.fromLTWH(
        contentLeft,
        y,
        innerW,
        barcodeH,
      );
      _drawBarcode(canvas, item.code, barcodeRect);
      y += barcodeH + 3;
    }

    y += await _drawText(
      canvas,
      item.code,
      contentLeft,
      y,
      innerW,
      fontSize: codeSize,
      bold: true,
      maxLines: 1,
      center: true,
    );

    if (item.priceText != null) {
      y += 3;
      await _drawText(
        canvas,
        item.priceText!,
        contentLeft,
        y,
        innerW,
        fontSize: priceSize,
        bold: true,
        maxLines: 1,
        center: true,
      );
    }
  }

  static void _drawBarcode(ui.Canvas canvas, String data, ui.Rect rect) {
    if (data.isEmpty || rect.height < 8 || rect.width < 8) return;
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

  static Future<double> _drawText(
    ui.Canvas canvas,
    String text,
    double x,
    double y,
    double maxW, {
    required double fontSize,
    bool bold = false,
    int maxLines = 2,
    bool center = false,
  }) async {
    if (text.trim().isEmpty || maxW <= 0) return 0;
    final tp = TextPainter(
      text: TextSpan(
        text: text.trim(),
        style: vietnameseTextStyle(
          TextStyle(
            fontSize: fontSize,
            fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
            color: const Color(0xFF000000),
            height: 1.1,
          ),
        ),
      ),
      textAlign: center ? TextAlign.center : TextAlign.left,
      textDirection: ui.TextDirection.ltr,
      maxLines: maxLines,
      ellipsis: '…',
    )..layout(maxWidth: maxW);
    final dx = center ? x + ((maxW - tp.width) / 2).clamp(0.0, maxW) : x;
    tp.paint(canvas, Offset(dx, y));
    return tp.height;
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

  /// Tem ly / tem bếp — mặc định khổ 50×30 (máy tem phổ biến).
  static Future<({Uint8List raster, int widthPx, int heightPx})> renderCupTicket({
    required String productName,
    String? tableLabel,
    String? orderNo,
    String? toppings,
    String? note,
    String? qtyLabel,
    double widthMm = 50,
    double heightMm = 30,
    int dpi = 203,
    double marginLeftMm = 3.0,
    double marginRightMm = 2.0,
    double marginTopMm = 2.0,
    double marginBottomMm = 2.0,
    double fontScale = 1.2,
    bool showHeader = true,
    bool showTable = true,
    bool showOrderNo = true,
    bool showToppings = true,
    bool showNote = true,
    bool showQty = true,
    @Deprecated('Use marginLeftMm') double contentInsetLeftMm = 3.0,
  }) async {
    await PosThermalBitmapEncoder.ensureFont();
    final wMm = widthMm.clamp(20.0, 160.0).toDouble();
    final hMm = heightMm.clamp(10.0, 160.0).toDouble();
    final w = mmToDots(wMm, dpi).clamp(120, 1200).toInt();
    final h = mmToDots(hMm, dpi).clamp(80, 1200).toInt();
    final left = mmToDots(
      (marginLeftMm > 0 ? marginLeftMm : contentInsetLeftMm).clamp(0, 12),
      dpi,
    ).toDouble();
    final right = mmToDots(marginRightMm.clamp(0, 12), dpi).toDouble();
    final top = mmToDots(marginTopMm.clamp(0, 12), dpi).toDouble();
    final bottom = mmToDots(marginBottomMm.clamp(0, 12), dpi).toDouble();
    final scale = fontScale.clamp(0.85, 1.6);
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    canvas.drawRect(
      ui.Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
      ui.Paint()..color = const ui.Color(0xFFFFFFFF),
    );

    var y = top;
    final contentLeft = left;
    final innerW = (w - left - right).clamp(40.0, w.toDouble());
    final wide = wMm >= 48;
    double fs(double base) => base * scale;

    if (showHeader) {
      y += await _drawText(
        canvas,
        'TEM LY',
        contentLeft,
        y,
        innerW,
        fontSize: fs(wide ? 17 : 14),
        bold: true,
        maxLines: 1,
        center: true,
      );
      y += 3;
    }

    final table = (tableLabel ?? '').trim();
    if (showTable && table.isNotEmpty) {
      y += await _drawText(
        canvas,
        'Ban: $table',
        contentLeft,
        y,
        innerW,
        fontSize: fs(wide ? 15 : 12),
        bold: true,
        maxLines: 1,
      );
      y += 2;
    }
    final order = (orderNo ?? '').trim();
    if (showOrderNo && order.isNotEmpty) {
      y += await _drawText(
        canvas,
        'HD: $order',
        contentLeft,
        y,
        innerW,
        fontSize: fs(wide ? 13 : 11),
        bold: true,
        maxLines: 1,
      );
      y += 2;
    }

    canvas.drawRect(
      ui.Rect.fromLTWH(contentLeft, y, innerW, 2),
      ui.Paint()..color = const ui.Color(0xFF000000),
    );
    y += 5;

    y += await _drawText(
      canvas,
      productName.trim().isEmpty ? 'Mon' : productName.trim(),
      contentLeft,
      y,
      innerW,
      fontSize: fs(wide ? 20 : 15),
      bold: true,
      maxLines: 2,
      center: true,
    );
    y += 3;

    final tops = (toppings ?? '').trim();
    if (showToppings && tops.isNotEmpty) {
      y += await _drawText(
        canvas,
        '+ $tops',
        contentLeft,
        y,
        innerW,
        fontSize: fs(wide ? 13 : 11),
        maxLines: 2,
      );
      y += 2;
    }
    final n = (note ?? '').trim();
    if (showNote && n.isNotEmpty) {
      y += await _drawText(
        canvas,
        'GC: $n',
        contentLeft,
        y,
        innerW,
        fontSize: fs(wide ? 13 : 11),
        maxLines: 2,
      );
      y += 2;
    }

    if (showQty) {
      canvas.drawRect(
        ui.Rect.fromLTWH(contentLeft, y, innerW, 2),
        ui.Paint()..color = const ui.Color(0xFF000000),
      );
      y += 5;
      final qty =
          (qtyLabel ?? '1').trim().isEmpty ? '1' : (qtyLabel ?? '1').trim();
      final maxY = h - bottom;
      if (y < maxY) {
        await _drawText(
          canvas,
          'SL: $qty',
          contentLeft,
          y,
          innerW,
          fontSize: fs(wide ? 17 : 13),
          bold: true,
          maxLines: 1,
        );
      }
    }

    final picture = recorder.endRecording();
    final image = await picture.toImage(w, h);
    return _imageToRaster(image);
  }

  /// Render mẫu V2 đã biên dịch ra tem (khớp thiết kế mẫu in).
  static Future<({Uint8List raster, int widthPx, int heightPx})>
      renderCompiledLabel({
    required PosPrintCompiledOutput output,
    required double widthMm,
    required double heightMm,
    int dpi = 203,
    double marginLeftMm = 2.0,
    double marginRightMm = 2.0,
    double marginTopMm = 2.0,
    double marginBottomMm = 2.0,
    double fontScale = 1.0,
  }) async {
    await PosThermalBitmapEncoder.ensureFont();
    final wMm = widthMm.clamp(20.0, 160.0).toDouble();
    final hMm = heightMm.clamp(10.0, 160.0).toDouble();
    final w = mmToDots(wMm, dpi).clamp(120, 1200).toInt();
    final h = mmToDots(hMm, dpi).clamp(80, 1200).toInt();
    final left = mmToDots(marginLeftMm.clamp(0, 12), dpi).toDouble();
    final right = mmToDots(marginRightMm.clamp(0, 12), dpi).toDouble();
    final top = mmToDots(marginTopMm.clamp(0, 12), dpi).toDouble();
    final bottom = mmToDots(marginBottomMm.clamp(0, 12), dpi).toDouble();
    final scale = fontScale.clamp(0.85, 1.6);
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    canvas.drawRect(
      ui.Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
      ui.Paint()..color = const ui.Color(0xFFFFFFFF),
    );
    var y = top;
    final contentLeft = left;
    final innerW = (w - left - right).clamp(40.0, w.toDouble());
    final maxY = h - bottom;

    for (final step in output.steps) {
      if (y >= maxY) break;
      if (step is PosPrintCompiledLine) {
        if (step.isDivider) {
          canvas.drawRect(
            ui.Rect.fromLTWH(contentLeft, y, innerW, 2),
            ui.Paint()..color = const ui.Color(0xFF000000),
          );
          y += 5;
          continue;
        }
        if (step.text.trim().isEmpty) {
          y += 4;
          continue;
        }
        y += await _drawText(
          canvas,
          step.text,
          contentLeft,
          y,
          innerW,
          fontSize: (step.fontSize * 0.55 * scale).clamp(9.0, 28.0),
          bold: step.bold,
          maxLines: 3,
          center: step.center,
        );
        y += 2;
      } else if (step is PosPrintCompiledPair) {
        final fs = (step.fontSize * 0.55 * scale).clamp(9.0, 24.0);
        final leftH = await _drawText(
          canvas,
          step.left,
          contentLeft,
          y,
          innerW * 0.62,
          fontSize: fs,
          bold: step.bold,
          maxLines: 2,
        );
        final rightH = await _drawText(
          canvas,
          step.right,
          contentLeft + innerW * 0.55,
          y,
          innerW * 0.45,
          fontSize: fs,
          bold: step.bold,
          maxLines: 2,
          center: false,
        );
        // Align right column to the right edge.
        // Re-draw right flush-right by measuring — keep simple left+gap for tem.
        y += (leftH > rightH ? leftH : rightH) + 2;
      }
    }

    final picture = recorder.endRecording();
    final image = await picture.toImage(w, h);
    return _imageToRaster(image);
  }
}

extension on int {
  int get bitCount {
    var v = this & 0xFF;
    var n = 0;
    while (v != 0) {
      n += v & 1;
      v >>= 1;
    }
    return n;
  }
}
