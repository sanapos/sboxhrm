import 'dart:math' as math;
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
    this.detailText,
  });

  final String name;
  final String code;
  final String? priceText;
  final String? storeName;
  /// Dòng phụ dưới tên (tem cân: khối lượng × đơn giá, HSD).
  final String? detailText;
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
      detailText: posLabelDetailFor(p, opts),
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
    final gap = mmToDots(template.labelGapMm, dpi);
    // Ô tem = (khổ cuộn − khe) / số cột. Trước đây lấy bề rộng tem danh nghĩa (36 mm × 2 + khe 1 mm = 73 mm
    // trên cuộn 72 mm) → tem cuối hàng bị cắt mép phải.
    final labelW = ((w - gap * (template.cols - 1)) / template.cols).floor();
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
        (item.detailText != null ? (small ? 10.0 : 14.0) : 0) +
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

    if (item.detailText != null && item.detailText!.isNotEmpty) {
      y += await _drawText(
        canvas,
        item.detailText!,
        contentLeft,
        y,
        innerW,
        fontSize: small ? 9.0 : (wide ? 13.0 : 11.0),
        maxLines: small ? 1 : 2,
        center: true,
        maxHeight: small ? 12 : 30,
      );
      y += 2;
    }

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

  /// Bề rộng một ô tem trên cuộn nhiều tem / hàng (mm).
  static double rowCellWidthMm(PosBarcodeLabelTemplate t) =>
      (t.rollPageWidthMm - t.labelGapMm * (t.cols - 1)) / t.cols;

  /// Ghép các tem đã vẽ (1-bit) thành một hàng của cuộn nhiều tem.
  static ({Uint8List raster, int widthPx, int heightPx}) composeRow(
    List<({Uint8List raster, int widthPx, int heightPx})> cells,
    PosBarcodeLabelTemplate template, {
    int dpi = 203,
  }) {
    final w = mmToDots(template.rollPageWidthMm, dpi);
    final h = mmToDots(template.labelHeightMm, dpi);
    final gap = mmToDots(template.labelGapMm, dpi);
    final pitch = ((w - gap * (template.cols - 1)) / template.cols).floor() + gap;
    final bpr = (w + 7) ~/ 8;
    final out = Uint8List(bpr * h);
    for (var c = 0; c < cells.length && c < template.cols; c++) {
      final cell = cells[c];
      final cbpr = (cell.widthPx + 7) ~/ 8;
      final x0 = c * pitch;
      for (var y = 0; y < h && y < cell.heightPx; y++) {
        for (var x = 0; x < cell.widthPx; x++) {
          final tx = x0 + x;
          if (tx >= w) break;
          if ((cell.raster[y * cbpr + (x >> 3)] >> (7 - (x & 7))) & 1 == 1) {
            out[y * bpr + (tx >> 3)] |= 0x80 >> (tx & 7);
          }
        }
      }
    }
    return (raster: out, widthPx: w, heightPx: h);
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
        fontSize: 16,
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

  /// Tem QR tài sản (khổ ngang, vd 40×30 / 50×30): QR bên trái, bên phải tên công ty, mã tài sản (đậm),
  /// tên tài sản, vị trí / người đang giữ. Trả ảnh để xem trước, xuất PDF hoặc chuyển raster cho máy tem.
  static Future<ui.Image> renderAssetQrLabelImage({
    required String qrData,
    required String assetCode,
    required String assetName,
    String? holder,
    String? companyName,
    double widthMm = 50,
    double heightMm = 30,
    int dpi = 203,
  }) async {
    await PosThermalBitmapEncoder.ensureFont();
    final w = mmToDots(widthMm, dpi);
    final h = mmToDots(heightMm, dpi);
    final k = dpi / 203;
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    canvas.drawRect(
      ui.Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
      ui.Paint()..color = const ui.Color(0xFFFFFFFF),
    );
    final pad = 1.5 * dpi / 25.4;
    final qrSize = math.min(h - pad * 2, w * 0.5);
    _drawQr(canvas, qrData, ui.Rect.fromLTWH(pad, (h - qrSize) / 2, qrSize, qrSize));

    final x = pad + qrSize + 2 * dpi / 25.4;
    final cw = w - x - pad;
    final bottom = h - pad;
    var y = pad;
    final company = (companyName ?? '').trim();
    if (company.isNotEmpty) {
      y += await _drawText(canvas, company, x, y, cw, fontSize: 13 * k, bold: true, maxLines: 1);
      y += 3 * k;
    }
    // Mã tài sản là chữ người đọc đối chiếu → thu nhỏ cho vừa 1 dòng, không ngắt giữa mã.
    var codeSize = 21 * k;
    while (codeSize > 12 * k) {
      final tp = TextPainter(
        text: TextSpan(
          text: assetCode.trim(),
          style: vietnameseTextStyle(TextStyle(fontSize: codeSize, fontWeight: FontWeight.w700, height: 1.08)),
        ),
        textDirection: ui.TextDirection.ltr,
        maxLines: 1,
      )..layout();
      if (tp.width <= cw) break;
      codeSize -= 1 * k;
    }
    y += await _drawText(canvas, assetCode, x, y, cw,
        fontSize: codeSize, bold: true, maxLines: 2, maxHeight: bottom - y);
    y += 3 * k;
    final who = (holder ?? '').trim();
    // Chừa chỗ cho dòng vị trí / người giữ ở đáy tem.
    final holderH = who.isEmpty ? 0.0 : 30 * k;
    y += await _drawText(canvas, assetName, x, y, cw,
        fontSize: 15 * k, maxLines: 3, maxHeight: bottom - holderH - y);
    if (who.isNotEmpty) {
      await _drawText(canvas, who, x, math.max(y + 2 * k, bottom - holderH), cw,
          fontSize: 12.5 * k, maxLines: 2, maxHeight: bottom - math.max(y + 2 * k, bottom - holderH));
    }
    return recorder.endRecording().toImage(w, h);
  }

  static Future<({Uint8List raster, int widthPx, int heightPx})> renderAssetQrLabel({
    required String qrData,
    required String assetCode,
    required String assetName,
    String? holder,
    String? companyName,
    double widthMm = 50,
    double heightMm = 30,
    int dpi = 203,
  }) async =>
      _imageToRaster(await renderAssetQrLabelImage(
        qrData: qrData,
        assetCode: assetCode,
        assetName: assetName,
        holder: holder,
        companyName: companyName,
        widthMm: widthMm,
        heightMm: heightMm,
        dpi: dpi,
      ));

  /// Dùng chung cho tem thiết kế tự do (PosLabelDesignPainter).
  static void paintBarcode(ui.Canvas canvas, String data, ui.Rect rect) => _drawBarcode(canvas, data, rect);
  static void paintQr(ui.Canvas canvas, String data, ui.Rect rect) => _drawQr(canvas, data, rect);
  static Future<({Uint8List raster, int widthPx, int heightPx})> imageToRaster(ui.Image image) =>
      _imageToRaster(image);

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

  /// Mã vạch khớp lưới điểm in: mỗi module = số nguyên điểm, căn giữa, chừa lề trắng (quiet zone).
  /// Trước đây kéo giãn theo bề rộng tem → module lẻ điểm (vd 2,4 điểm), vạch dày mỏng không đều
  /// sau khi chuyển đen trắng → máy quét đọc chậm / không đọc được, nhất là tem 35×22.
  static void _drawBarcode(ui.Canvas canvas, String data, ui.Rect rect) {
    if (data.isEmpty || rect.height < 8 || rect.width < 8) return;
    try {
      final bc = posBarcodeSymbology(data);
      // Đo số module: bản vẽ thử rộng 1000 → vạch hẹp nhất = 1 module.
      final probe = bc.make(data, width: 1000, height: rect.height, drawText: false);
      var minBar = double.infinity;
      for (final e in probe) {
        if (e is BarcodeBar && e.width > 0 && e.width < minBar) minBar = e.width;
      }
      var drawW = rect.width;
      var left = rect.left;
      if (minBar.isFinite && minBar > 0) {
        final modules = (1000 / minBar).round();
        // Ưu tiên chừa 10 module lề mỗi bên; tem quá hẹp thì bỏ dần lề.
        var moduleW = (rect.width / (modules + 20)).floorToDouble();
        if (moduleW < 1) moduleW = (rect.width / modules).floorToDouble();
        if (moduleW >= 1) {
          drawW = moduleW * modules;
          left = (rect.left + (rect.width - drawW) / 2).roundToDouble();
        }
      }
      final elements = bc.make(data, width: drawW, height: rect.height, drawText: false);
      final paint = ui.Paint()
        ..color = const ui.Color(0xFF000000)
        ..isAntiAlias = false;
      for (final e in elements) {
        if (e is BarcodeBar && e.black) {
          canvas.drawRect(
            ui.Rect.fromLTWH(
              (left + e.left).roundToDouble(),
              rect.top,
              e.width.roundToDouble(),
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

  /// Ảnh nhãn vận đơn của hãng (trang PDF / HTML đã dựng) → raster máy tem [widthMm]×[heightMm].
  /// Cắt viền trắng, xoay 90° nếu khác chiều tem, thu phóng vừa khổ (giữ tỉ lệ), nền trắng.
  static Future<({Uint8List raster, int widthPx, int heightPx})> rasterFromImage(
    ui.Image src, {
    double widthMm = 100,
    double heightMm = 150,
    int dpi = 203,
    bool trimWhite = true,
  }) async {
    final w = mmToDots(widthMm, dpi);
    final h = mmToDots(heightMm, dpi);
    var crop = ui.Rect.fromLTWH(0, 0, src.width.toDouble(), src.height.toDouble());
    if (trimWhite) {
      final data = await src.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (data != null) {
        final px = data.buffer.asUint8List();
        var minX = src.width, minY = src.height, maxX = -1, maxY = -1;
        for (var y = 0; y < src.height; y += 2) {
          for (var x = 0; x < src.width; x += 2) {
            final i = (y * src.width + x) * 4;
            if (px[i + 3] < 32) continue; // trong suốt = giấy trắng
            final lum = 0.299 * px[i] + 0.587 * px[i + 1] + 0.114 * px[i + 2];
            if (lum < 200) {
              if (x < minX) minX = x;
              if (x > maxX) maxX = x;
              if (y < minY) minY = y;
              if (y > maxY) maxY = y;
            }
          }
        }
        if (maxX > minX && maxY > minY) {
          final pad = src.width * 0.01;
          crop = ui.Rect.fromLTRB(
            (minX - pad).clamp(0, src.width.toDouble()),
            (minY - pad).clamp(0, src.height.toDouble()),
            (maxX + pad).clamp(0, src.width.toDouble()),
            (maxY + pad).clamp(0, src.height.toDouble()),
          );
        }
      }
    }
    final rotate = (crop.width > crop.height) != (w > h);
    final srcW = rotate ? crop.height : crop.width;
    final srcH = rotate ? crop.width : crop.height;
    final scale = (w / srcW) < (h / srcH) ? (w / srcW) : (h / srcH);
    final dw = srcW * scale;
    final dh = srcH * scale;

    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    canvas.drawRect(
      ui.Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
      ui.Paint()..color = const ui.Color(0xFFFFFFFF),
    );
    canvas.save();
    canvas.translate(w / 2, h / 2);
    if (rotate) canvas.rotate(1.5707963267948966);
    final dst = rotate
        ? ui.Rect.fromCenter(center: ui.Offset.zero, width: dh, height: dw)
        : ui.Rect.fromCenter(center: ui.Offset.zero, width: dw, height: dh);
    canvas.drawImageRect(src, crop, dst, ui.Paint()..filterQuality = ui.FilterQuality.high);
    canvas.restore();
    final image = await recorder.endRecording().toImage(w, h);
    return _imageToRaster(image);
  }

  /// Tem vận đơn tự in (đơn tự giao / hãng không trả nhãn): khổ mặc định 100×150.
  /// Người gửi, người nhận (to, rõ), địa chỉ, COD, mã đơn dạng mã vạch, hãng + mã vận đơn, danh sách hàng.
  static Future<({Uint8List raster, int widthPx, int heightPx})> renderShippingSelfLabel({
    required String orderNo,
    required String receiverName,
    required String receiverPhone,
    required String receiverAddress,
    double codAmount = 0,
    String? senderName,
    String? senderPhone,
    String? carrierName,
    String? trackingCode,
    String? note,
    List<String> itemLines = const [],
    int itemCount = 0,
    DateTime? date,
    double widthMm = 100,
    double heightMm = 150,
    int dpi = 203,
  }) async {
    await PosThermalBitmapEncoder.ensureFont();
    final w = mmToDots(widthMm, dpi);
    final h = mmToDots(heightMm, dpi);
    final k = dpi / 203; // cỡ chữ theo mật độ điểm
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    canvas.drawRect(
      ui.Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
      ui.Paint()..color = const ui.Color(0xFFFFFFFF),
    );
    final line = ui.Paint()
      ..color = const ui.Color(0xFF000000)
      ..strokeWidth = 2 * k;
    final pad = 14.0 * k;
    final cw = w - pad * 2;
    var y = pad;
    void rule() {
      canvas.drawLine(ui.Offset(pad, y), ui.Offset(w - pad, y), line);
      y += 8 * k;
    }

    // Đầu tem: hãng + mã vận đơn (mã vạch) — hoặc mã đơn khi tự giao.
    final code = (trackingCode ?? '').trim().isNotEmpty ? trackingCode!.trim() : orderNo.trim();
    y += await _drawText(canvas, (carrierName ?? '').trim().isEmpty ? 'GIAO HÀNG' : carrierName!.trim().toUpperCase(),
        pad, y, cw, fontSize: 30 * k, bold: true, maxLines: 1, center: true);
    y += 6 * k;
    if (code.isNotEmpty) {
      _drawBarcode(canvas, code, ui.Rect.fromLTWH(pad, y, cw, 110 * k));
      y += 116 * k;
      y += await _drawText(canvas, code, pad, y, cw, fontSize: 26 * k, bold: true, maxLines: 1, center: true);
    }
    y += 6 * k;
    rule();

    // Người gửi (nhỏ).
    final sender = [
      if ((senderName ?? '').trim().isNotEmpty) senderName!.trim(),
      if ((senderPhone ?? '').trim().isNotEmpty) senderPhone!.trim(),
    ].join(' · ');
    if (sender.isNotEmpty) {
      y += await _drawText(canvas, 'Từ: $sender', pad, y, cw, fontSize: 20 * k, maxLines: 2);
      y += 4 * k;
      rule();
    }

    // Người nhận (lớn).
    y += await _drawText(canvas, 'ĐẾN:', pad, y, cw, fontSize: 20 * k, bold: true, maxLines: 1);
    y += await _drawText(canvas, receiverName.trim().isEmpty ? 'Khách hàng' : receiverName.trim(),
        pad, y, cw, fontSize: 34 * k, bold: true, maxLines: 2);
    if (receiverPhone.trim().isNotEmpty) {
      y += await _drawText(canvas, receiverPhone.trim(), pad, y, cw, fontSize: 34 * k, bold: true, maxLines: 1);
    }
    y += 2 * k;
    y += await _drawText(canvas, receiverAddress.trim(), pad, y, cw, fontSize: 24 * k, maxLines: 4);
    y += 6 * k;
    rule();

    // COD.
    final money = NumberFormat('#,##0', 'vi_VN');
    if (codAmount > 0) {
      final boxH = 64 * k;
      canvas.drawRect(ui.Rect.fromLTWH(pad, y, cw, boxH), ui.Paint()..color = const ui.Color(0xFF000000));
      final tp = TextPainter(
        text: TextSpan(
          text: 'THU HỘ: ${money.format(codAmount)}đ',
          style: vietnameseTextStyle(TextStyle(
            fontSize: 34 * k,
            fontWeight: FontWeight.w700,
            color: const Color(0xFFFFFFFF),
          )),
        ),
        textAlign: TextAlign.center,
        textDirection: ui.TextDirection.ltr,
        maxLines: 1,
      )..layout(maxWidth: cw);
      tp.paint(canvas, ui.Offset(pad + (cw - tp.width) / 2, y + (boxH - tp.height) / 2));
      y += boxH + 8 * k;
    } else {
      y += await _drawText(canvas, 'Đã thanh toán — không thu tiền', pad, y, cw,
          fontSize: 24 * k, bold: true, maxLines: 1, center: true);
      y += 6 * k;
    }
    rule();

    // Hàng hóa + ghi chú (phần còn lại của tem).
    final footerH = 30 * k;
    final itemsMaxH = h - y - footerH - pad;
    if (itemLines.isNotEmpty && itemsMaxH > 24 * k) {
      final shown = itemLines.take(8).join('\n') +
          (itemLines.length > 8 ? '\n… và ${itemLines.length - 8} dòng khác' : '');
      y += await _drawText(canvas, 'Hàng (${itemCount > 0 ? itemCount : itemLines.length}):\n$shown', pad, y, cw,
          fontSize: 20 * k, maxLines: 10, maxHeight: itemsMaxH * (note == null ? 1 : 0.7));
      y += 4 * k;
    }
    if ((note ?? '').trim().isNotEmpty && h - y - footerH - pad > 20 * k) {
      y += await _drawText(canvas, 'Ghi chú: ${note!.trim()}', pad, y, cw,
          fontSize: 20 * k, bold: true, maxLines: 3, maxHeight: h - y - footerH - pad);
    }
    await _drawText(
      canvas,
      'Đơn $orderNo · ${DateFormat('dd/MM/yyyy HH:mm').format(date ?? DateTime.now())}',
      pad,
      h - pad - footerH + 6 * k,
      cw,
      fontSize: 18 * k,
      maxLines: 1,
      center: true,
    );
    final image = await recorder.endRecording().toImage(w, h);
    return _imageToRaster(image);
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
    final baseLeft = left;
    final baseInnerW = (w - left - right).clamp(40.0, w.toDouble());
    final maxY = h - bottom;
    canvas.save();
    canvas.clipRect(ui.Rect.fromLTWH(baseLeft, top, baseInnerW, (maxY - top).clamp(1, h.toDouble())));
    // Khoảng cách / thụt lề trong mẫu là điểm in — tem cùng hệ số với cỡ chữ (×0.72).
    // Máy 300 dpi: cùng cỡ điểm thì chữ nhỏ hơn 1,5 lần → nhân theo dpi để tem in ra cùng cỡ thật.
    final dpiK = dpi / 203;
    final layoutK = 0.72 * scale * dpiK;
    // Tem lớn (75×100, 100×150): cho chữ to hơn mức trần của tem 50×30.
    final sizeK = (wMm / 50).clamp(1.0, 2.5);

    for (final step in output.steps) {
      if (y >= maxY - 4) break;
      final lay = switch (step) {
        PosPrintCompiledLine x => x.layout,
        PosPrintCompiledPair x => x.layout,
        PosPrintCompiledSaleRow x => x.layout,
        PosPrintCompiledImage x => x.layout,
        _ => null,
      };
      y += (lay?.spaceBefore ?? 0) * layoutK;
      final indL = (lay?.indentLeft ?? 0) * layoutK;
      final indR = (lay?.indentRight ?? 0) * layoutK;
      final contentLeft = baseLeft + indL;
      final innerW = (baseInnerW - indL - indR).clamp(30.0, baseInnerW);
      final remain = maxY - y;
      if (step is PosPrintCompiledImage) {
        try {
          final codec = await ui.instantiateImageCodec(step.bytes);
          final img = (await codec.getNextFrame()).image;
          var iw = innerW * step.widthFrac.clamp(0.1, 1.0);
          var ih = iw * img.height / img.width;
          if (ih > remain) {
            ih = remain;
            iw = ih * img.width / img.height;
          }
          final x = step.align == PosPrintTextAlign.center
              ? contentLeft + (innerW - iw) / 2
              : step.align == PosPrintTextAlign.right
                  ? contentLeft + innerW - iw
                  : contentLeft;
          canvas.drawImageRect(
            img,
            ui.Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()),
            ui.Rect.fromLTWH(x, y, iw, ih),
            ui.Paint()..filterQuality = ui.FilterQuality.high,
          );
          img.dispose();
          y += ih + 2;
        } catch (_) {}
        y += (lay?.spaceAfter ?? 0) * layoutK;
        continue;
      }
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
          final minH = (lay?.minHeight ?? 0) * layoutK;
          y += minH > 3 ? minH : 3;
          y += (lay?.spaceAfter ?? 0) * layoutK;
          continue;
        }
        final fs = (step.fontSize * 0.72 * scale * dpiK).clamp(11.0 * dpiK, 32.0 * dpiK * sizeK);
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
        final fs = (step.fontSize * 0.72 * scale * dpiK).clamp(11.0 * dpiK, 26.0 * dpiK * sizeK);
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
      } else if (step is PosPrintCompiledBarcode && step.qr) {
        // QR tự soạn: ô vuông lớn nhất còn chỗ (chừa dòng chữ phía sau), căn giữa.
        final idx = output.steps.indexOf(step);
        var after = 0.0;
        for (final s in output.steps.skip(idx + 1)) {
          if (s is PosPrintCompiledLine && !s.isDivider && s.text.trim().isNotEmpty) {
            after += s.fontSize * 0.72 * scale * dpiK * 1.15 + 2;
          }
        }
        final textH = step.showText ? 24 * dpiK : 0;
        final room = maxY - y - after - textH - 2;
        // Cỡ QR (40–120) = tỷ lệ phần trống còn lại của tem: 120 = lấp đầy, 60 = một nửa.
        final k = step.height.clamp(40, 120) / 120;
        var side = ([innerW, room].reduce((a, b) => a < b ? a : b) * k).toDouble();
        if (side < 24 * dpiK) side = [innerW, maxY - y - 2].reduce((a, b) => a < b ? a : b);
        if (side >= 16 && step.data.trim().isNotEmpty) {
          _drawQr(canvas, step.data.trim(),
              ui.Rect.fromLTWH(contentLeft + (innerW - side) / 2, y, side, side));
          y += side + 2;
          if (step.showText && y < maxY - 10) {
            y += await _drawText(
              canvas,
              step.data.trim(),
              contentLeft,
              y,
              innerW,
              fontSize: 9 * dpiK,
              bold: false,
              maxLines: 2,
              center: true,
              maxHeight: maxY - y,
            );
          }
        }
      } else if (step is PosPrintCompiledBarcode) {
        // Chiều cao theo mẫu (trước đây bỏ qua, luôn 18–48 điểm) nhưng chừa chỗ cho các dòng chữ phía sau
        // (giá dưới mã vạch không bị đẩy khỏi tem).
        final idx = output.steps.indexOf(step);
        var after = 0.0;
        for (final s in output.steps.skip(idx + 1)) {
          if (s is PosPrintCompiledLine && !s.isDivider && s.text.trim().isNotEmpty) {
            after += s.fontSize * 0.72 * scale * dpiK * 1.15 + 2;
          }
        }
        final textH = step.showText ? 14 * dpiK : 0;
        // Tối thiểu ~30% chiều cao tem: mã vạch cao dễ quét, tem không bỏ trống nửa dưới.
        final want = [step.height * 0.72 * scale * dpiK, h * 0.30].reduce((a, b) => a > b ? a : b);
        final remain = maxY - y - after - textH - 2;
        final barH = want.clamp(16.0 * dpiK, remain < 16 * dpiK ? 16 * dpiK : remain).toDouble();
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
              fontSize: 11 * dpiK,
              bold: true,
              maxLines: 1,
              center: true,
              maxHeight: maxY - y,
            );
          }
        }
      }
      y += (lay?.spaceAfter ?? 0) * layoutK;
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
