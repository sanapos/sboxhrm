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
      height: 1.12,
      letterSpacing: 0.2,
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
    final bd = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
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
    return _imageToEscPos(image, initPrinter: true);
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
    final gap = k58 ? 8.0 : 12.0;
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
    final qtyW = anyQty ? measure('999', k58 ? 36.0 : 44.0, k58 ? 64.0 : 80.0) : 0.0;
    var priceW = 0.0;
    var totalW = 0.0;
    final capPrice = k58 ? 200.0 : 268.0;
    final capTotal = k58 ? 216.0 : 288.0;
    if (anyPrice) {
      priceW = k58 ? 64.0 : 80.0;
      if (saleLines.isEmpty) {
        priceW = measure('000.000', priceW, capPrice);
      } else {
        for (final line in saleLines) {
          final p = (line.colPrice ?? '').trim();
          if (p.isNotEmpty) priceW = measure(p, priceW, capPrice);
        }
      }
    }
    if (anyTotal) {
      totalW = k58 ? 72.0 : 88.0;
      if (saleLines.isEmpty) {
        totalW = measure('000.000', totalW, capTotal);
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
        totalH += 10.0 * scale;
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

    final hHi = (totalH + (framed ? pad * 2 : 0)).ceil().clamp(1, 16000);
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
        y += 10.0 * scale;
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

  static Future<List<int>?> _imageToEscPos(
    ui.Image image, {
    bool initPrinter = false,
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

    return [
      if (initPrinter) ...[0x1B, 0x40],
      0x1D, 0x76, 0x30, 0x00,
      bytesPerRow & 0xFF,
      (bytesPerRow >> 8) & 0xFF,
      h & 0xFF,
      (h >> 8) & 0xFF,
      ...raster,
      0x0A,
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
