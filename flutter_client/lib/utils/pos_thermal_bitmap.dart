import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'vietnamese_font.dart';
import '../l10n/app_tr.dart';
import '../models/pos_print_template_v2.dart';

/// Một dòng trên hóa đơn cần render ảnh.
class PosReceiptImageLine {
  const PosReceiptImageLine({
    required this.text,
    this.rightText,
    this.colQty,
    this.colPrice,
    this.colTotal,
    this.rightSlotFrac,
    this.bold = false,
    this.center = false,
    this.right = false,
    this.fontSize = 22,
    this.isDivider = false,
  });

  final String text;
  /// Nếu có: vẽ trái–phải full khổ (dòng tổng).
  final String? rightText;
  /// Cột hàng hóa — căn pixel cố định, không ghép một chuỗi.
  final String? colQty;
  final String? colPrice;
  final String? colTotal;
  /// Tỉ lệ cột phải (cặp nhãn/tiền hoặc tên/SL bếp). Mặc định 0.38.
  final double? rightSlotFrac;
  final bool bold;
  final bool center;
  final bool right;
  final double fontSize;
  /// Vẽ đường kẻ ngang đặc bằng chiều rộng giấy (không dùng ===== / -----).
  final bool isDivider;

  bool get hasSaleColumns =>
      colQty != null || colPrice != null || colTotal != null;
}

/// Chuyển chữ tiếng Việt thành lệnh ESC/POS raster (GS v 0).
class PosThermalBitmapEncoder {
  static bool _fontsLoaded = false;

  static int paperDots(int paperWidthMm) => paperWidthMm <= 58 ? 384 : 576;

  static Future<void> ensureFont() async {
    if (_fontsLoaded) return;
    // Font đã khai báo trong pubspec — KHÔNG gọi FontLoader cùng family
    // (load trùng làm vỡ glyph / fallback Arial → “lỗi font” trên bill ảnh).
    try {
      await preloadVietnameseFonts();
    } catch (e) {
      debugPrint('ensureFont preload: $e');
    }
    _fontsLoaded = true;
  }

  /// Style chỉ dùng BeVietnamPro — không fallback Arial/sans (thiếu tiếng Việt).
  static TextStyle _thermalStyle({
    required double fontSize,
    required bool bold,
  }) {
    return const TextStyle().copyWith(
      fontFamily: kVietnameseFontFamily,
      fontFamilyFallback: const ['Be Vietnam Pro'],
      fontSize: fontSize,
      fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
      color: const Color(0xFF000000),
      height: 1.28,
      letterSpacing: 0.15,
    );
  }

  /// PNG đúng khổ giấy — Sunmi T1 printImage (không dùng printRow).
  static Future<Uint8List?> receiptToPng(
    List<PosReceiptImageLine> lines, {
    required int paperDots,
    double lineGap = 3,
    PosPrintFrameStyle frameStyle = PosPrintFrameStyle.none,
    double frameInsetMm = 2.5,
    double frameMarginMm = 1.5,
    int trailingFeedLines = 0,
  }) async {
    final image = await _renderReceiptImage(
      lines,
      paperDots: paperDots,
      lineGap: lineGap,
      frameStyle: frameStyle,
      frameInsetMm: frameInsetMm,
      frameMarginMm: frameMarginMm,
      trailingFeedLines: trailingFeedLines,
    );
    if (image == null) return null;
    final trimmed = await _trimTrailingWhite(image, keepPx: 0);
    if (!identical(trimmed, image)) image.dispose();
    final bd = await trimmed.toByteData(format: ui.ImageByteFormat.png);
    trimmed.dispose();
    return bd?.buffer.asUint8List();
  }

  /// Render toàn bộ hóa đơn thành một ảnh bitmap (ổn định nhất cho Zywell/LAN/BT).
  static Future<List<int>?> receiptToRaster(
    List<PosReceiptImageLine> lines, {
    required int paperDots,
    double lineGap = 3,
    PosPrintFrameStyle frameStyle = PosPrintFrameStyle.none,
    double frameInsetMm = 2.5,
    double frameMarginMm = 1.5,
    bool initPrinter = true,
    int keepPx = 1,
  }) async {
    final image = await _renderReceiptImage(
      lines,
      paperDots: paperDots,
      lineGap: lineGap,
      frameStyle: frameStyle,
      frameInsetMm: frameInsetMm,
      frameMarginMm: frameMarginMm,
    );
    if (image == null) return null;
    var work = await _trimTrailingWhite(image, keepPx: keepPx);
    if (!identical(work, image)) image.dispose();
    if (work.width != paperDots) {
      final scaled = await _scaleToWidth(work, paperDots);
      if (!identical(scaled, work)) work.dispose();
      work = scaled;
    }
    try {
      return await _imageToEscPos(
        work,
        initPrinter: initPrinter,
        keepPx: keepPx,
      );
    } finally {
      work.dispose();
    }
  }

  /// PNG → GS v 0 (V2s: tránh Sunmi printImage tự đẩy đuôi giấy).
  static Future<List<int>?> pngToEscPos(
    Uint8List png, {
    bool initPrinter = false,
    int keepPx = 0,
  }) async {
    try {
      final codec = await ui.instantiateImageCodec(png);
      final frame = await codec.getNextFrame();
      final image = frame.image;
      try {
        var work = image;
        var maxW = image.width;
        if (maxW > 576 && maxW <= 1152) {
          maxW = 576;
        } else if (maxW > 384 && maxW <= 768) {
          maxW = 384;
        }
        if (work.width != maxW) {
          work = await _scaleToWidth(image, maxW);
        }
        try {
          return _imageToEscPos(
            work,
            initPrinter: initPrinter,
            keepPx: keepPx,
          );
        } finally {
          if (!identical(work, image)) work.dispose();
        }
      } finally {
        image.dispose();
      }
    } catch (_) {
      return null;
    }
  }

  static ({
    double nameW,
    double qtyW,
    double priceW,
    double totalW,
    double gap,
  }) _saleColWidths(
    double contentW, {
    TextStyle? style,
    List<PosReceiptImageLine> saleLines = const [],
  }) {
    final k58 = contentW < 900;
    final gap = k58 ? 20.0 : 12.0;
    final measureStyle = style ??
        const TextStyle(fontSize: 20, fontWeight: FontWeight.w700);
    double measure(String s, double minW, double maxW) {
      final tp = TextPainter(
        text: TextSpan(text: s.isEmpty ? '0' : s, style: measureStyle),
        textDirection: TextDirection.ltr,
        maxLines: 1,
      )..layout();
      return (tp.width + 10).clamp(minW, maxW);
    }

    final anyQty = saleLines.any((l) => l.colQty != null);
    final anyPrice = saleLines.any((l) => l.colPrice != null);
    final anyTotal = saleLines.any((l) => l.colTotal != null);
    final qtyW = anyQty ? measure('SL', k58 ? 56.0 : 44.0, k58 ? 80.0 : 80.0) : 0.0;
    var priceW = 0.0;
    var totalW = 0.0;
    final capPrice = k58 ? 160.0 : 268.0;
    final capTotal = k58 ? 168.0 : 288.0;
    if (anyPrice) {
      priceW = k58 ? 80.0 : 80.0;
      if (saleLines.isEmpty) {
        priceW = measure('000k', priceW, capPrice);
      } else {
        for (final line in saleLines) {
          final p = (line.colPrice ?? '').trim();
          if (p.isNotEmpty) priceW = measure(p, priceW, capPrice);
        }
      }
    }
    if (anyTotal) {
      totalW = k58 ? 88.0 : 88.0;
      if (saleLines.isEmpty) {
        totalW = measure('000k', totalW, capTotal);
      } else {
        for (final line in saleLines) {
          final t = (line.colTotal ?? '').trim();
          if (t.isNotEmpty) totalW = measure(t, totalW, capTotal);
        }
      }
    }
    final colCount = (anyQty ? 1 : 0) + (anyPrice ? 1 : 0) + (anyTotal ? 1 : 0);
    final nameW =
        (contentW - qtyW - priceW - totalW - gap * colCount).clamp(96.0, contentW);
    return (
      nameW: nameW,
      qtyW: qtyW,
      priceW: priceW,
      totalW: totalW,
      gap: gap,
    );
  }

  static ({double leftW, double rightW, double gap}) _pairSlotWidths({
    required double contentW,
    required TextStyle style,
    required String left,
    required String right,
    double? rightFrac,
  }) {
    final gap = contentW < 900 ? 16.0 : 24.0;
    final maxRight = contentW * 0.62;
    final minRight = contentW * ((rightFrac ?? 0.22).clamp(0.16, 0.40));
    final rightTp = TextPainter(
      text: TextSpan(text: right, style: style),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    final needed = rightTp.width + 12;
    final rightW = needed.clamp(minRight, maxRight);
    final leftW = (contentW - rightW - gap).clamp(48.0, contentW);
    return (leftW: leftW, rightW: rightW, gap: gap);
  }

  static TextPainter _tp(
    String text, {
    required TextStyle style,
    required double maxWidth,
    TextAlign align = TextAlign.left,
    int maxLines = 3,
    bool ellipsis = true,
  }) {
    return TextPainter(
      text: TextSpan(text: tr(text), style: style),
      textAlign: align,
      textDirection: TextDirection.ltr,
      maxLines: maxLines,
      ellipsis: (ellipsis && maxLines == 1) ? '…' : null,
    )..layout(maxWidth: maxWidth.clamp(1.0, 10000.0));
  }

  static void _paintInSlot(
    Canvas canvas,
    TextPainter tp, {
    required double slotLeft,
    required double slotW,
    required double y,
    required TextAlign align,
  }) {
    final x = switch (align) {
      TextAlign.center =>
        slotLeft + ((slotW - tp.width) / 2).clamp(0.0, slotW),
      TextAlign.right =>
        (slotLeft + slotW - tp.width).clamp(slotLeft, slotLeft + slotW),
      _ => slotLeft,
    };
    canvas.save();
    canvas.clipRect(Rect.fromLTWH(slotLeft, y, slotW, tp.height + 8));
    tp.paint(canvas, Offset(x, y));
    canvas.restore();
  }

  static Future<ui.Image?> _renderReceiptImage(
    List<PosReceiptImageLine> lines, {
    required int paperDots,
    double lineGap = 3,
    PosPrintFrameStyle frameStyle = PosPrintFrameStyle.none,
    double frameInsetMm = 2.5,
    double frameMarginMm = 1.5,
    int trailingFeedLines = 0,
  }) async {
    if (lines.isEmpty) return null;
    await ensureFont();

    final scale = 2;
    final renderW = paperDots * scale;
    final framed = frameStyle != PosPrintFrameStyle.none;
    final mm = paperDots <= 384 ? 58.0 : 80.0;
    final margin = framed
        ? (paperDots / mm * frameMarginMm.clamp(0.5, 8.0) * scale)
        : 0.0;
    final inset = framed
        ? (paperDots / mm * frameInsetMm.clamp(1.0, 12.0) * scale)
        : 0.0;
    final pad = framed ? (margin + inset) : (8.0 * scale);
    final contentW = renderW - pad * 2;
    final saleColLines = lines.where((l) => l.hasSaleColumns).toList();
    final painters = <TextPainter?>[];
    var totalH = 0.0;

    for (final line in lines) {
      if (line.isDivider) {
        painters.add(null);
        totalH += 6.0 * scale;
        continue;
      }
      final style = _thermalStyle(
        fontSize: line.fontSize * scale,
        bold: line.bold,
      );
      if (line.hasSaleColumns) {
        final cols = _saleColWidths(
          contentW,
          style: style,
          saleLines: saleColLines,
        );
        final nameTp = _tp(
          line.text,
          style: style,
          maxWidth: cols.nameW,
          maxLines: 2,
        );
        painters.add(nameTp);
        totalH += nameTp.height + lineGap * scale;
        continue;
      }
      if ((line.rightText ?? '').trim().isNotEmpty) {
        final slots = _pairSlotWidths(
          contentW: contentW,
          style: style,
          left: line.text,
          right: line.rightText!.trim(),
          rightFrac: line.rightSlotFrac,
        );
        final leftTp = _tp(
          line.text,
          style: style,
          maxWidth: slots.leftW,
          maxLines: 2,
        );
        painters.add(leftTp);
        totalH += leftTp.height + lineGap * scale;
        continue;
      }
      if (line.text.trim().isEmpty) {
        painters.add(null);
        totalH += 4.0 * scale;
        continue;
      }

      final tp = _tp(
        line.text,
        style: style,
        maxWidth: contentW,
        align: line.center
            ? TextAlign.center
            : line.right
                ? TextAlign.right
                : TextAlign.left,
        maxLines: 4,
      );

      if (tp.height <= 0) {
        painters.add(null);
        continue;
      }
      painters.add(tp);
      totalH += tp.height + lineGap * scale;
    }

    final trail = trailingFeedLines.clamp(0, 40) * 16.0;
    final hHi = (totalH + trail + (framed ? pad * 2 : 0)).ceil().clamp(1, 16000);
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawRect(
      Rect.fromLTWH(0, 0, renderW.toDouble(), hHi.toDouble()),
      Paint()..color = const Color(0xFFFFFFFF),
    );

    var y = framed ? pad : 0.0;
    for (var i = 0; i < painters.length; i++) {
      final line = lines[i];
      if (line.isDivider) {
        final ruleH = 3.0 * scale;
        final top = y + (6.0 * scale - ruleH) / 2;
        canvas.drawRect(
          Rect.fromLTWH(pad, top, contentW, ruleH),
          Paint()..color = const Color(0xFF000000),
        );
        y += 6.0 * scale;
        continue;
      }
      final style = _thermalStyle(
        fontSize: line.fontSize * scale,
        bold: line.bold,
      );
      if (line.hasSaleColumns) {
        final cols = _saleColWidths(
          contentW,
          style: style,
          saleLines: saleColLines,
        );
        final nameTp = _tp(
          line.text,
          style: style,
          maxWidth: cols.nameW,
          maxLines: 2,
        );
        final qtyTp = _tp(
          line.colQty ?? '',
          style: style,
          maxWidth: cols.qtyW,
          align: TextAlign.right,
          maxLines: 1,
          ellipsis: false,
        );
        final priceTp = _tp(
          line.colPrice ?? '',
          style: style,
          maxWidth: cols.priceW,
          align: TextAlign.right,
          maxLines: 1,
          ellipsis: false,
        );
        final totalTp = _tp(
          line.colTotal ?? '',
          style: style,
          maxWidth: cols.totalW,
          align: TextAlign.right,
          maxLines: 1,
          ellipsis: false,
        );
        nameTp.paint(canvas, Offset(pad, y));
        var x = pad + cols.nameW + cols.gap;
        if (cols.qtyW > 0) {
          _paintInSlot(
            canvas,
            qtyTp,
            slotLeft: x,
            slotW: cols.qtyW,
            y: y,
            align: TextAlign.center,
          );
          x += cols.qtyW + cols.gap;
        }
        if (cols.priceW > 0) {
          _paintInSlot(
            canvas,
            priceTp,
            slotLeft: x,
            slotW: cols.priceW,
            y: y,
            align: TextAlign.right,
          );
          x += cols.priceW + cols.gap;
        }
        if (cols.totalW > 0) {
          _paintInSlot(
            canvas,
            totalTp,
            slotLeft: x,
            slotW: cols.totalW,
            y: y,
            align: TextAlign.right,
          );
        }
        y += nameTp.height + lineGap * scale;
        continue;
      }
      final right = (line.rightText ?? '').trim();
      if (right.isNotEmpty) {
        final slots = _pairSlotWidths(
          contentW: contentW,
          style: style,
          left: line.text,
          right: right,
          rightFrac: line.rightSlotFrac,
        );
        final leftTp = _tp(line.text, style: style, maxWidth: slots.leftW, maxLines: 2);
        final rightTp = _tp(
          right,
          style: style,
          maxWidth: slots.rightW,
          align: TextAlign.right,
          maxLines: 1,
          ellipsis: false,
        );
        leftTp.paint(canvas, Offset(pad, y));
        _paintInSlot(
          canvas,
          rightTp,
          slotLeft: pad + slots.leftW + slots.gap,
          slotW: slots.rightW,
          y: y,
          align: TextAlign.right,
        );
        y += (leftTp.height > rightTp.height ? leftTp.height : rightTp.height) +
            lineGap * scale;
        continue;
      }
      final tp = painters[i];
      if (tp == null) {
        y += 4.0 * scale;
        continue;
      }
      final x = tp.textAlign == TextAlign.center
          ? pad + ((contentW - tp.width) / 2).clamp(0.0, contentW)
          : tp.textAlign == TextAlign.right
              ? pad + (contentW - tp.width).clamp(0.0, contentW)
              : pad;
      tp.paint(canvas, Offset(x, y));
      y += tp.height + lineGap * scale;
    }

    if (framed) {
      final stroke = 2.2 * scale;
      final rect = Rect.fromLTWH(
        margin,
        margin,
        renderW - margin * 2,
        hHi - margin * 2,
      );
      final rrect = frameStyle == PosPrintFrameStyle.rounded
          ? RRect.fromRectAndRadius(rect, Radius.circular(10.0 * scale))
          : RRect.fromRectAndRadius(rect, Radius.zero);
      canvas.drawRRect(
        rrect,
        Paint()
          ..color = const Color(0xFF000000)
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke,
      );
    }

    final picture = recorder.endRecording();
    final hiRes = await picture.toImage(renderW, hHi);
    final recorder2 = ui.PictureRecorder();
    final canvas2 = Canvas(recorder2);
    final outH = (hHi / scale).ceil().clamp(1, 8000);
    canvas2.drawImageRect(
      hiRes,
      Rect.fromLTWH(0, 0, renderW.toDouble(), hHi.toDouble()),
      Rect.fromLTWH(0, 0, paperDots.toDouble(), outH.toDouble()),
      Paint()..filterQuality = FilterQuality.medium,
    );
    final picture2 = recorder2.endRecording();
    final image = await picture2.toImage(paperDots, outH);
    hiRes.dispose();
    return image;
  }

  static Future<List<int>?> textLineToRaster(
    String text, {
    required int paperDots,
    double fontSize = 22,
    bool bold = false,
    bool center = false,
  }) {
    return receiptToRaster(
      [
        PosReceiptImageLine(
          text: tr(text),
          fontSize: fontSize,
          bold: bold,
          center: center,
        ),
      ],
      paperDots: paperDots,
      lineGap: 0,
    );
  }

  static Future<List<int>?> pairLineToRaster({
    required String left,
    required String right,
    required int paperDots,
    double fontSize = 20,
  }) {
    final maxChars = paperDots <= 384 ? 32 : 48;
    final l = left.trim();
    final r = right.trim();
    final space = maxChars - l.length - r.length;
    final combined = space >= 1 ? '$l${' ' * space}$r' : '$l $r';
    return textLineToRaster(
      combined,
      paperDots: paperDots,
      fontSize: fontSize,
    );
  }

  static bool rasterHasInk(List<int> raster) {
    if (raster.length <= 10) return false;
    for (var i = 8; i < raster.length - 1; i++) {
      if (raster[i] != 0) return true;
    }
    return false;
  }

  /// Tải VietQR rồi đặt giữa khổ giấy — T1 printImage ảnh nhỏ sẽ lệch trái.
  static Future<Uint8List?> qrCenteredOnPaper(
    String url, {
    required int paperDots,
  }) async {
    final qrDots = paperDots <= 384 ? 260 : 360;
    try {
      final res =
          await http.get(Uri.parse(url)).timeout(const Duration(seconds: 12));
      if (res.statusCode != 200 || res.bodyBytes.isEmpty) return null;
      final codec = await ui.instantiateImageCodec(
        res.bodyBytes,
        targetWidth: qrDots,
      );
      final frame = await codec.getNextFrame();
      final qr = frame.image;
      final padY = 10;
      final outH = qr.height + padY * 2;
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      canvas.drawRect(
        Rect.fromLTWH(0, 0, paperDots.toDouble(), outH.toDouble()),
        Paint()..color = const Color(0xFFFFFFFF),
      );
      final x = ((paperDots - qr.width) / 2).clamp(0.0, paperDots.toDouble());
      canvas.drawImage(qr, Offset(x, padY.toDouble()), Paint());
      final image = await recorder.endRecording().toImage(paperDots, outH);
      qr.dispose();
      final bd = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      return bd?.buffer.asUint8List();
    } catch (_) {
      return null;
    }
  }

  static Future<Uint8List?> networkPngBytes(
    String url, {
    int maxWidth = 280,
  }) async {
    try {
      final res = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 12));
      if (res.statusCode != 200 || res.bodyBytes.isEmpty) return null;
      final codec = await ui.instantiateImageCodec(
        res.bodyBytes,
        targetWidth: maxWidth,
      );
      final frame = await codec.getNextFrame();
      final png = await frame.image.toByteData(format: ui.ImageByteFormat.png);
      if (png == null) return null;
      return png.buffer.asUint8List();
    } catch (_) {
      return null;
    }
  }

  static Future<List<int>?> networkPngToEscPos(
    String url, {
    int maxWidth = 280,
  }) async {
    try {
      final res = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 12));
      if (res.statusCode != 200 || res.bodyBytes.isEmpty) return null;
      final codec = await ui.instantiateImageCodec(
        res.bodyBytes,
        targetWidth: maxWidth,
      );
      final frame = await codec.getNextFrame();
      return _imageToEscPos(frame.image);
    } catch (_) {
      return null;
    }
  }

  static List<int> insertRasterBeforeCut(List<int> receiptBytes, List<int> raster) {
    if (receiptBytes.length < 4) return [...receiptBytes, ...raster];
    // Cut: ESC d n + GS V m — tìm từ cuối.
    var cutStart = receiptBytes.length;
    for (var i = receiptBytes.length - 1; i >= 0; i--) {
      if (receiptBytes[i] == 0x56 && i > 0 && receiptBytes[i - 1] == 0x1D) {
        cutStart = i - 1;
        break;
      }
    }
    return [
      ...receiptBytes.sublist(0, cutStart),
      ...raster,
      ...receiptBytes.sublist(cutStart),
    ];
  }

  /// Cắt hàng trắng cuối ảnh — V2s không dao cắt, đuôi PNG trắng = giấy trắng.
  static Future<ui.Image> _trimTrailingWhite(
    ui.Image image, {
    int keepPx = 4,
  }) async {
    final w = image.width;
    final h = image.height;
    if (w <= 0 || h <= 2) return image;
    final bd = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (bd == null) return image;
    final rgba = bd.buffer.asUint8List();
    var lastInk = -1;
    for (var y = h - 1; y >= 0; y--) {
      var ink = false;
      final row = y * w * 4;
      for (var x = 0; x < w; x++) {
        final i = row + x * 4;
        final lum = 0.299 * rgba[i] + 0.587 * rgba[i + 1] + 0.114 * rgba[i + 2];
        if (lum < 250) {
          ink = true;
          break;
        }
      }
      if (ink) {
        lastInk = y;
        break;
      }
    }
    if (lastInk < 0) return image;
    final newH = (lastInk + 1 + keepPx).clamp(1, h);
    if (newH >= h) return image;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, w.toDouble(), newH.toDouble()),
      Rect.fromLTWH(0, 0, w.toDouble(), newH.toDouble()),
      Paint(),
    );
    final picture = recorder.endRecording();
    final cropped = await picture.toImage(w, newH);
    return cropped;
  }

  /// GS v 0 phải đúng số chấm khổ giấy. Ảnh render scale=2 (768px) in lên
  /// V2s 384 chấm sẽ quấn hàng → dư đúng một khúc giấy.
  static Future<ui.Image> _scaleToWidth(ui.Image image, int targetW) async {
    final w = image.width;
    final h = image.height;
    final tw = targetW.clamp(8, 576);
    if (w == tw || w <= 0 || h <= 0) return image;
    final th = (h * tw / w).round().clamp(1, 16000);
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
      Rect.fromLTWH(0, 0, tw.toDouble(), th.toDouble()),
      Paint()..filterQuality = FilterQuality.medium,
    );
    final picture = recorder.endRecording();
    return picture.toImage(tw, th);
  }

  static Future<List<int>?> _imageToEscPos(
    ui.Image image, {
    bool initPrinter = false,
    int keepPx = 1,
  }) async {
    final w = image.width;
    final h = image.height;
    if (w <= 0 || h <= 0) return null;

    final byteData = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (byteData == null) return null;
    final rgba = byteData.buffer.asUint8List();

    final bytesPerRow = (w + 7) ~/ 8;
    final raster = <int>[];

    for (var y = 0; y < h; y++) {
      for (var xByte = 0; xByte < bytesPerRow; xByte++) {
        var b = 0;
        for (var bit = 0; bit < 8; bit++) {
          final x = xByte * 8 + bit;
          if (x >= w) continue;
          final idx = (y * w + x) * 4;
          final lum = 0.299 * rgba[idx] +
              0.587 * rgba[idx + 1] +
              0.114 * rgba[idx + 2];
          // Ngưỡng thấp hơn → nét đậm, tránh răng cưa xám thành lỗ.
          if (lum < 160) {
            b |= (0x80 >> bit);
          }
        }
        raster.add(b);
      }
    }

    if (!raster.any((b) => b != 0)) return null;

    var lastInkRow = h - 1;
    for (var y = h - 1; y >= 0; y--) {
      var ink = false;
      final row = y * bytesPerRow;
      for (var i = 0; i < bytesPerRow; i++) {
        if (raster[row + i] != 0) {
          ink = true;
          break;
        }
      }
      if (ink) {
        lastInkRow = y;
        break;
      }
    }
    final keepH = (lastInkRow + 1 + keepPx).clamp(1, h);
    final cropped = keepH < h ? raster.sublist(0, keepH * bytesPerRow) : raster;

    return [
      if (initPrinter) ...[0x1B, 0x40],
      0x1D, 0x76, 0x30, 0x00,
      bytesPerRow & 0xFF,
      (bytesPerRow >> 8) & 0xFF,
      keepH & 0xFF,
      (keepH >> 8) & 0xFF,
      ...cropped,
    ];
  }

  /// 1 dòng đẩy giấy = 24 chấm (~3 mm @ 203 dpi), khớp `lineWrap` ESC/POS.
  static const dotsPerFeedLine = 24;

  static int feedDots(int lines) => lines.clamp(0, 40) * dotsPerFeedLine;

  /// Raster trắng (GS v 0) — V2s chỉ chịu đẩy giấy khi in thêm điểm ảnh.
  static List<int> feedOnlyRaster({
    required int paperDots,
    required int feedLines,
  }) {
    final extra = feedDots(feedLines);
    if (extra <= 0) return const <int>[];
    final w = paperDots.clamp(8, 576);
    final bpr = (w + 7) ~/ 8;
    final data = List<int>.filled(bpr * extra, 0);
    // 1 chấm cuối: firmware không được bỏ block toàn trắng.
    data[bpr * (extra - 1)] = 0x80;
    return [
      0x1D,
      0x76,
      0x30,
      0x00,
      bpr & 0xFF,
      (bpr >> 8) & 0xFF,
      extra & 0xFF,
      (extra >> 8) & 0xFF,
      ...data,
    ];
  }

  /// Nối hàng trắng vào GS v 0 cuối payload. LF / ESC d sau raster bị V2s nuốt.
  static List<int> extendGsV0TrailingDots(List<int> bytes, int extraDots) {
    final extra = extraDots.clamp(0, 2000);
    if (extra <= 0 || bytes.length < 8) return bytes;
    var i = 0;
    var lastCmd = -1;
    var lastBpr = 0;
    var lastH = 0;
    while (i + 7 < bytes.length) {
      if (bytes[i] == 0x1D &&
          bytes[i + 1] == 0x76 &&
          bytes[i + 2] == 0x30) {
        final bpr = bytes[i + 4] + (bytes[i + 5] << 8);
        final h = bytes[i + 6] + (bytes[i + 7] << 8);
        if (bpr <= 0 || bpr > 256 || h < 0) {
          i++;
          continue;
        }
        lastCmd = i;
        lastBpr = bpr;
        lastH = h;
        i += 8 + bpr * h;
        continue;
      }
      i++;
    }
    if (lastCmd < 0 || lastBpr <= 0) return bytes;
    final newH = (lastH + extra).clamp(1, 65535);
    final added = newH - lastH;
    if (added <= 0) return bytes;
    final dataStart = lastCmd + 8;
    final dataEnd = dataStart + lastBpr * lastH;
    if (dataEnd > bytes.length) return bytes;
    final zeros = List<int>.filled(lastBpr * added, 0);
    zeros[lastBpr * (added - 1)] = 0x80;
    return <int>[
      ...bytes.sublist(0, lastCmd + 6),
      newH & 0xFF,
      (newH >> 8) & 0xFF,
      ...bytes.sublist(dataStart, dataEnd),
      ...zeros,
      ...bytes.sublist(dataEnd),
    ];
  }

  /// V2s: nhồi feed vào cùng payload raster (không gửi LF rời).
  static List<int> appendHandheldFeed(
    List<int> bytes,
    int feedLines, {
    int paperDots = 384,
  }) {
    final n = feedLines.clamp(0, 40);
    if (n <= 0) return bytes;
    if (bytes.isEmpty) {
      return feedOnlyRaster(paperDots: paperDots, feedLines: n);
    }
    final extra = feedDots(n);
    final extended = extendGsV0TrailingDots(bytes, extra);
    if (extended.length != bytes.length) return extended;
    return <int>[
      ...bytes,
      ...feedOnlyRaster(paperDots: paperDots, feedLines: n),
    ];
  }

  /// Đường kẻ ngang đặc (GS v 0) đúng [paperDots] — thay ===== / -----.
  static List<int> horizontalRuleEscPos({
    required int paperDots,
    int thickness = 2,
  }) {
    final w = paperDots.clamp(8, 576);
    final h = thickness.clamp(1, 8);
    final bytesPerRow = (w + 7) ~/ 8;
    final raster = List<int>.filled(bytesPerRow * h, 0xFF);
    // Bit thừa ngoài bề rộng giấy → trắng.
    final rem = w % 8;
    if (rem != 0) {
      final mask = (0xFF << (8 - rem)) & 0xFF;
      for (var y = 0; y < h; y++) {
        raster[y * bytesPerRow + bytesPerRow - 1] = mask;
      }
    }
    return [
      0x1D, 0x76, 0x30, 0x00,
      bytesPerRow & 0xFF,
      (bytesPerRow >> 8) & 0xFF,
      h & 0xFF,
      (h >> 8) & 0xFF,
      ...raster,
      0x0A,
    ];
  }

  /// PNG mỏng cho Sunmi printImage — đường kẻ đúng khổ giấy.
  static Future<Uint8List?> horizontalRulePng({
    required int paperDots,
    int thickness = 3,
  }) async {
    final w = paperDots.clamp(8, 576);
    final h = (thickness + 6).clamp(4, 16);
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawRect(
      Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
      Paint()..color = const Color(0xFFFFFFFF),
    );
    final ruleH = thickness.toDouble();
    canvas.drawRect(
      Rect.fromLTWH(0, (h - ruleH) / 2, w.toDouble(), ruleH),
      Paint()..color = const Color(0xFF000000),
    );
    final image = await recorder.endRecording().toImage(w, h);
    final bd = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    return bd?.buffer.asUint8List();
  }

  static List<String> wrapText(String text, int maxChars) {
    final words = text.split(RegExp(r'\s+'));
    final lines = <String>[];
    var current = '';
    for (final word in words) {
      if (word.isEmpty) continue;
      if (current.isEmpty) {
        current = word;
        continue;
      }
      if (current.length + 1 + word.length <= maxChars) {
        current = '$current $word';
      } else {
        lines.add(current);
        current = word.length > maxChars ? word.substring(0, maxChars) : word;
      }
    }
    if (current.isNotEmpty) lines.add(current);
    if (lines.isEmpty && text.isNotEmpty) lines.add(text);
    return lines;
  }
}
