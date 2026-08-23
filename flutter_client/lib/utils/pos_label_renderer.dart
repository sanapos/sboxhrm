import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:barcode/barcode.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/pos_product.dart';
import '../models/pos_print_template_v2.dart';
import 'pos_barcode_print.dart';
import 'pos_print_template_compiler.dart';
import 'pos_receipt_layout.dart';
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
    var y = bounds.top + pad;
    final contentLeft = bounds.left + leftInset + pad;
    final innerW = (bounds.width - leftInset - pad * 2).clamp(8.0, bounds.width);
    canvas.save();
    canvas.clipRect(bounds);
    // Chừa chỗ mã + giá phía dưới trước khi tính chiều cao barcode.
    final footerBudget = (small ? 14.0 : (wide ? 22.0 : 16.0)) +
        (item.priceText != null ? (small ? 12.0 : (wide ? 18.0 : 14.0)) : 0) +
        pad +
        4;

    final nameSize = small ? 13.0 : (wide ? 20.0 : 16.0);
    final codeSize = small ? 10.0 : (wide ? 13.0 : 11.0);
    final priceSize = small ? 13.0 : (wide ? 18.0 : 15.0);
    final storeSize = small ? 9.0 : (wide ? 12.0 : 10.0);
    final maxY = bounds.bottom - pad;

    if (item.storeName != null && !small && y < maxY - footerBudget) {
      y += await _drawText(
        canvas,
        item.storeName!,
        contentLeft,
        y,
        innerW,
        fontSize: storeSize,
        maxLines: 1,
        center: true,
        maxHeight: 16,
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
      maxLines: small ? 2 : 2,
      center: true,
      maxHeight: small ? 32 : 44,
    );
    y += 3;

    final remaining = maxY - y - footerBudget;
    final barcodeH = remaining
        .clamp(
          small ? 12.0 : 18.0,
          bounds.height * (small ? 0.22 : (wide ? 0.32 : 0.28)),
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

    if (!small) {
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
        maxHeight: 16,
      );
    }

    if (item.priceText != null && y < maxY - 8) {
      y += 2;
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
        maxHeight: maxY - y,
      );
    }
    canvas.restore();
  }

  /// Tem QR gọi món tại bàn — khổ mặc định 60×40 mm.
  static Future<({Uint8List raster, int widthPx, int heightPx})>
      renderTableQrLabel({
    required String storeName,
    required String tableLabel,
    required String qrUrl,
    String footer = 'SBOX POS · Quét để gọi món',
    double widthMm = 60,
    double heightMm = 40,
    int dpi = 203,
  }) async {
    await PosThermalBitmapEncoder.ensureFont();
    final w = mmToDots(widthMm, dpi);
    final h = mmToDots(heightMm, dpi);
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    canvas.drawRect(
      ui.Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
      ui.Paint()..color = const ui.Color(0xFFFFFFFF),
    );

    const pad = 4.0;
    var y = pad;
    final contentW = (w - pad * 2).toDouble();

    final store = storeName.trim();
    if (store.isNotEmpty) {
      y += await _drawText(
        canvas,
        store,
        pad,
        y,
        contentW,
        fontSize: 15,
        bold: true,
        maxLines: 1,
        center: true,
        maxHeight: 18,
      );
      y += 2;
    }

    y += await _drawText(
      canvas,
      tableLabel.trim().isEmpty ? 'Bàn' : tableLabel.trim(),
      pad,
      y,
      contentW,
      fontSize: 18,
      bold: true,
      maxLines: 1,
      center: true,
      maxHeight: 22,
    );
    y += 2;

    const footerH = 22.0;
    final qrBudget = (h - y - footerH - pad).clamp(48.0, h.toDouble());
    final qrSize = qrBudget < contentW ? qrBudget : contentW;
    final qrLeft = pad + (contentW - qrSize) / 2;
    _drawQr(canvas, qrUrl, ui.Rect.fromLTWH(qrLeft, y, qrSize, qrSize));
    y += qrSize + 2;

    await _drawText(
      canvas,
      footer,
      pad,
      y.clamp(0, h - footerH),
      contentW,
      fontSize: 10,
      bold: false,
      maxLines: 2,
      center: true,
      maxHeight: footerH,
    );

    final picture = recorder.endRecording();
    final image = await picture.toImage(w, h);
    return _imageToRaster(image);
  }

  static void _drawQr(ui.Canvas canvas, String data, ui.Rect rect) {
    if (data.isEmpty || rect.height < 8 || rect.width < 8) return;
    try {
      final bc = Barcode.qrCode();
      final elements = bc.make(data, width: rect.width, height: rect.height);
      final paint = ui.Paint()..color = const ui.Color(0xFF000000);
      for (final e in elements) {
        if (e is BarcodeBar && e.black) {
          canvas.drawRect(
            ui.Rect.fromLTWH(
              rect.left + e.left,
              rect.top + e.top,
              e.width,
              e.height,
            ),
            paint,
          );
        }
      }
    } catch (_) {
      // QR không hợp lệ
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
    bool right = false,
    double? maxHeight,
  }) async {
    if (text.trim().isEmpty || maxW <= 0) return 0;
    if (maxHeight != null && maxHeight < fontSize * 0.7) return 0;
    final align = center
        ? TextAlign.center
        : (right ? TextAlign.right : TextAlign.left);
    final tp = TextPainter(
      text: TextSpan(
        text: text.trim(),
        style: vietnameseTextStyle(
          TextStyle(
            fontSize: fontSize,
            fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
            color: const Color(0xFF000000),
            height: 1.08,
          ),
        ),
      ),
      textAlign: align,
      textDirection: ui.TextDirection.ltr,
      maxLines: maxLines,
      ellipsis: '…',
    )..layout(maxWidth: maxW);
    if (maxHeight != null && tp.height > maxHeight) {
      // Cắt dòng cho vừa chiều cao tem — không tràn viền dưới.
      final fitLines = (maxHeight / (fontSize * 1.08)).floor().clamp(1, maxLines);
      final tp2 = TextPainter(
        text: TextSpan(
          text: text.trim(),
          style: vietnameseTextStyle(
            TextStyle(
              fontSize: fontSize,
              fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
              color: const Color(0xFF000000),
              height: 1.08,
            ),
          ),
        ),
        textAlign: align,
        textDirection: ui.TextDirection.ltr,
        maxLines: fitLines,
        ellipsis: '…',
      )..layout(maxWidth: maxW);
      final dx2 = center
          ? x + ((maxW - tp2.width) / 2).clamp(0.0, maxW)
          : (right ? x + (maxW - tp2.width).clamp(0.0, maxW) : x);
      tp2.paint(canvas, Offset(dx2, y));
      return tp2.height.clamp(0.0, maxHeight);
    }
    final dx = center
        ? x + ((maxW - tp.width) / 2).clamp(0.0, maxW)
        : (right ? x + (maxW - tp.width).clamp(0.0, maxW) : x);
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
    final maxY = h - bottom;
    double fs(double base) => base * scale;
    canvas.save();
    canvas.clipRect(ui.Rect.fromLTWH(
      contentLeft,
      top,
      innerW,
      (maxY - top).clamp(1, h.toDouble()),
    ));

    if (showHeader && wide) {
      y += await _drawText(
        canvas,
        'TEM LY',
        contentLeft,
        y,
        innerW,
        fontSize: fs(17),
        bold: true,
        maxLines: 1,
        center: true,
        maxHeight: maxY - y,
      );
      y += 2;
    }

    final table = (tableLabel ?? '').trim();
    if (showTable && table.isNotEmpty && y < maxY - 8) {
      y += await _drawText(
        canvas,
        table,
        contentLeft,
        y,
        innerW,
        fontSize: fs(wide ? 20 : 17),
        bold: true,
        maxLines: 1,
        maxHeight: maxY - y,
      );
      y += 2;
    }
    final order = (orderNo ?? '').trim();
    if (showOrderNo && order.isNotEmpty && wide && y < maxY - 8) {
      y += await _drawText(
        canvas,
        PosReceiptLayout.formatSaleInvoiceNo(order),
        contentLeft,
        y,
        innerW,
        fontSize: fs(13),
        bold: true,
        maxLines: 1,
        maxHeight: maxY - y,
      );
      y += 2;
    }

    if (y < maxY - 6) {
      canvas.drawRect(
        ui.Rect.fromLTWH(contentLeft, y, innerW, 2),
        ui.Paint()..color = const ui.Color(0xFF000000),
      );
      y += 5;
    }

    if (y < maxY - 10) {
      final name = productName.trim().isEmpty ? 'Mon' : productName.trim();
      final qty =
          (qtyLabel ?? '1').trim().isEmpty ? '1' : (qtyLabel ?? '1').trim();
      final nameW = showQty ? (innerW * 0.72).clamp(40.0, innerW) : innerW;
      final nameH = await _drawText(
        canvas,
        name,
        contentLeft,
        y,
        nameW,
        fontSize: fs(wide ? 20 : 17),
        bold: true,
        maxLines: 2,
        maxHeight: (maxY - y - 16).clamp(14, 80),
      );
      var rowH = nameH;
      if (showQty) {
        final qtyH = await _drawText(
          canvas,
          qty,
          contentLeft,
          y,
          innerW,
          fontSize: fs(wide ? 20 : 17),
          bold: true,
          maxLines: 1,
          right: true,
          maxHeight: (maxY - y - 16).clamp(14, 40),
        );
        if (qtyH > rowH) rowH = qtyH;
      }
      y += rowH + 3;
    }

    final tops = (toppings ?? '').trim();
    if (showToppings && tops.isNotEmpty && y < maxY - 14) {
      final parts = tops
          .split(RegExp(r'[\n,;]+'))
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .map((e) => e.startsWith('+') ? e : '+ $e')
          .toList();
      for (final part in parts) {
        if (y >= maxY - 12) break;
        y += await _drawText(
          canvas,
          part,
          contentLeft,
          y,
          innerW,
          fontSize: fs(wide ? 13 : 11),
          maxLines: 2,
          maxHeight: (maxY - y - 10).clamp(12, 36),
        );
        y += 1;
      }
    }
    final n = (note ?? '').trim();
    if (showNote && n.isNotEmpty && y < maxY - 14) {
      y += await _drawText(
        canvas,
        n,
        contentLeft,
        y,
        innerW,
        fontSize: fs(wide ? 13 : 11),
        maxLines: 1,
        maxHeight: maxY - y - 12,
      );
      y += 2;
    }


    canvas.restore();
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
    final framed = output.frameStyle != PosPrintFrameStyle.none;
    // Tem nhỏ: không cộng dồn frame+printer tới 20mm (nuốt hết 30mm cao).
    final maxExtra = hMm <= 40 ? 2.5 : (hMm <= 60 ? 4.0 : 8.0);
    final marginMm = framed ? output.frameMarginMm.clamp(0.5, maxExtra) : 0.0;
    final insetMm = framed ? output.frameInsetMm.clamp(0.5, maxExtra) : 0.0;
    final extraMm = (marginMm + insetMm).clamp(0.0, maxExtra * 1.5);
    final left = mmToDots((marginLeftMm + extraMm).clamp(0, 8), dpi).toDouble();
    final right = mmToDots((marginRightMm + extraMm).clamp(0, 8), dpi).toDouble();
    final top = mmToDots((marginTopMm + extraMm).clamp(0, 6), dpi).toDouble();
    final bottom = mmToDots((marginBottomMm + extraMm).clamp(0, 6), dpi).toDouble();
    // Co chữ để vừa chiều cao tem thay vì cắt trắng phần dưới.
    var scale = fontScale.clamp(0.55, 1.6);
    final stepCount = output.steps.where((s) {
      if (s is PosPrintCompiledLine) {
        return !s.isDivider && s.text.trim().isNotEmpty;
      }
      return s is PosPrintCompiledSaleRow;
    }).length;
    if (stepCount > 0 && hMm <= 50) {
      final avail = (h - top - bottom).clamp(40.0, h.toDouble());
      final est = stepCount * 18.0 * scale;
      if (est > avail) {
        scale = (scale * avail / est).clamp(0.55, scale);
      }
    }
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
    canvas.save();
    canvas.clipRect(ui.Rect.fromLTWH(contentLeft, top, innerW, (maxY - top).clamp(1, h.toDouble())));

    for (final step in output.steps) {
      if (y >= maxY - 4) break;
      final remain = maxY - y;
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
          y += 3;
          continue;
        }
        final fs = (step.fontSize * 0.72 * scale).clamp(11.0, 32.0);
        y += await _drawText(
          canvas,
          step.text,
          contentLeft,
          y,
          innerW,
          fontSize: fs,
          bold: step.bold,
          maxLines: step.center ? 2 : 2,
          center: step.center,
          maxHeight: remain,
        );
        y += 2;
      } else if (step is PosPrintCompiledSaleRow) {
        final fs = (step.fontSize * 0.72 * scale).clamp(11.0, 26.0);
        if (step.nameOnly) {
          y += await _drawText(
            canvas,
            step.name,
            contentLeft,
            y,
            innerW,
            fontSize: fs,
            bold: step.bold,
            maxLines: 2,
            maxHeight: remain,
          );
          y += 2;
        } else if (step.showQty && !step.showPrice && !step.showTotal) {
          final nameW = (innerW * 0.75).clamp(40.0, innerW);
          final nameH = await _drawText(
            canvas,
            step.name,
            contentLeft,
            y,
            nameW,
            fontSize: fs,
            bold: step.bold,
            maxLines: 2,
            maxHeight: remain,
          );
          final qtyH = await _drawText(
            canvas,
            step.qty,
            contentLeft,
            y,
            innerW,
            fontSize: fs,
            bold: step.bold,
            maxLines: 1,
            right: true,
            maxHeight: remain,
          );
          y += (nameH > qtyH ? nameH : qtyH) + 2;
        } else {
        final qtyW = step.showQty ? innerW * 0.14 : 0.0;
        final priceW = step.showPrice ? innerW * 0.22 : 0.0;
        final totalW = step.showTotal ? innerW * 0.24 : 0.0;
        final nameW = (innerW - qtyW - priceW - totalW).clamp(20.0, innerW);
        final nameH = await _drawText(
          canvas,
          step.name,
          contentLeft,
          y,
          nameW,
          fontSize: fs,
          bold: step.bold,
          maxLines: 2,
          maxHeight: remain,
        );
        var rowH = nameH;
        var x = contentLeft + nameW;
        if (step.showQty) {
          final qtyH = await _drawText(
            canvas,
            step.qty,
            x,
            y,
            qtyW,
            fontSize: fs,
            bold: step.bold,
            maxLines: 1,
            right: true,
            maxHeight: remain,
          );
          if (qtyH > rowH) rowH = qtyH;
          x += qtyW;
        }
        if (step.showPrice) {
          final priceH = await _drawText(
            canvas,
            step.price,
            x,
            y,
            priceW,
            fontSize: fs,
            bold: step.bold,
            maxLines: 1,
            right: true,
            maxHeight: remain,
          );
          if (priceH > rowH) rowH = priceH;
          x += priceW;
        }
        if (step.showTotal) {
          final totalH = await _drawText(
            canvas,
            step.total,
            x,
            y,
            totalW,
            fontSize: fs,
            bold: step.bold,
            maxLines: 1,
            right: true,
            maxHeight: remain,
          );
          if (totalH > rowH) rowH = totalH;
        }
        y += rowH + 2;
        }
      } else if (step is PosPrintCompiledPair) {
        final fs = (step.fontSize * 0.72 * scale).clamp(11.0, 26.0);
        // Tên món + SL: tên ~3/4 khổ; cặp bàn/giờ giữ ~62%.
        final rightTrim = step.right.trim();
        final nameQtyPair = rightTrim.isNotEmpty &&
            rightTrim.length <= 8 &&
            !rightTrim.contains(':');
        final leftFrac = nameQtyPair ? 0.75 : 0.62;
        final leftH = await _drawText(
          canvas,
          step.left,
          contentLeft,
          y,
          innerW * leftFrac,
          fontSize: fs,
          bold: step.bold,
          maxLines: nameQtyPair ? 2 : 1,
          maxHeight: remain,
        );
        final rightH = await _drawText(
          canvas,
          step.right,
          contentLeft,
          y,
          innerW,
          fontSize: fs,
          bold: step.bold,
          maxLines: 1,
          right: true,
          maxHeight: remain,
        );
        y += (leftH > rightH ? leftH : rightH) + 2;
      } else if (step is PosPrintCompiledBarcode) {
        final remain = maxY - y - 16;
        final barH = remain.clamp(18.0, 48.0);
        if (barH >= 16 && step.data.trim().isNotEmpty) {
          _drawBarcode(
            canvas,
            step.data.trim(),
            ui.Rect.fromLTWH(contentLeft, y, innerW, barH),
          );
          y += barH + 2;
          if (step.showText && y < maxY - 10) {
            y += await _drawText(
              canvas,
              step.data.trim(),
              contentLeft,
              y,
              innerW,
              fontSize: 11,
              bold: true,
              maxLines: 1,
              center: true,
              maxHeight: maxY - y,
            );
          }
        }
      }
    }
    canvas.restore();

    if (framed) {
      const stroke = 2.2;
      final box = mmToDots(marginMm.clamp(0.5, 8.0), dpi).toDouble().clamp(2.0, 40.0);
      final rect = ui.Rect.fromLTWH(box, box, w - box * 2, h - box * 2);
      final rr = output.frameStyle == PosPrintFrameStyle.rounded
          ? ui.RRect.fromRectAndRadius(
              rect,
              ui.Radius.circular(wMm >= 48 ? 10 : 8),
            )
          : ui.RRect.fromRectAndRadius(rect, ui.Radius.zero);
      canvas.drawRRect(
        rr,
        ui.Paint()
          ..color = const ui.Color(0xFF000000)
          ..style = ui.PaintingStyle.stroke
          ..strokeWidth = stroke,
      );
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
