import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'vietnamese_font.dart';
import '../l10n/app_tr.dart';

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
  }) async {
    final image = await _renderReceiptImage(
      lines,
      paperDots: paperDots,
      lineGap: lineGap,
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
  }) async {
    final image = await _renderReceiptImage(
      lines,
      paperDots: paperDots,
      lineGap: lineGap,
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
  }) _saleColWidths(double contentW) {
    final k58 = contentW < 900;
    final gap = k58 ? 20.0 : 28.0;
    final qtyW = k58 ? 70.0 : 96.0;
    final moneyW = k58 ? 160.0 : 200.0;
    final nameW =
        (contentW - qtyW - moneyW * 2 - gap * 3).clamp(140.0, contentW);
    return (
      nameW: nameW,
      qtyW: qtyW,
      priceW: moneyW,
      totalW: moneyW,
      gap: gap,
    );
  }

  static TextPainter _tp(
    String text, {
    required TextStyle style,
    required double maxWidth,
    TextAlign align = TextAlign.left,
    int maxLines = 3,
  }) {
    return TextPainter(
      text: TextSpan(text: tr(text), style: style),
      textAlign: align,
      textDirection: TextDirection.ltr,
      maxLines: maxLines,
      ellipsis: maxLines == 1 ? '…' : null,
    )..layout(maxWidth: maxWidth);
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
  }) async {
    if (lines.isEmpty) return null;
    await ensureFont();

    final scale = 2;
    final renderW = paperDots * scale;
    final pad = 8.0 * scale;
    final contentW = renderW - pad * 2;
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
        final cols = _saleColWidths(contentW);
        final nameTp = _tp(line.text, style: style, maxWidth: cols.nameW);
        painters.add(nameTp);
        totalH += nameTp.height + lineGap * scale;
        continue;
      }
      if ((line.rightText ?? '').trim().isNotEmpty) {
        final leftTp = _tp(
          line.text,
          style: style,
          maxWidth: contentW * 0.58,
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
        align: line.center ? TextAlign.center : TextAlign.left,
        maxLines: 4,
      );

      if (tp.height <= 0) {
        painters.add(null);
        continue;
      }
      painters.add(tp);
      totalH += tp.height + lineGap * scale;
    }

    final hHi = totalH.ceil().clamp(1, 16000);
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawRect(
      Rect.fromLTWH(0, 0, renderW.toDouble(), hHi.toDouble()),
      Paint()..color = const Color(0xFFFFFFFF),
    );

    var y = 0.0;
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
        final cols = _saleColWidths(contentW);
        final nameTp = _tp(line.text, style: style, maxWidth: cols.nameW);
        final qtyTp = _tp(
          line.colQty ?? '',
          style: style,
          maxWidth: cols.qtyW,
          align: TextAlign.right,
          maxLines: 1,
        );
        final priceTp = _tp(
          line.colPrice ?? '',
          style: style,
          maxWidth: cols.priceW,
          align: TextAlign.right,
          maxLines: 1,
        );
        final totalTp = _tp(
          line.colTotal ?? '',
          style: style,
          maxWidth: cols.totalW,
          align: TextAlign.right,
          maxLines: 1,
        );
        nameTp.paint(canvas, Offset(pad, y));
        var x = pad + cols.nameW + cols.gap;
        _paintInSlot(
          canvas,
          qtyTp,
          slotLeft: x,
          slotW: cols.qtyW,
          y: y,
          align: TextAlign.center,
        );
        x += cols.qtyW + cols.gap;
        _paintInSlot(
          canvas,
          priceTp,
          slotLeft: x,
          slotW: cols.priceW,
          y: y,
          align: TextAlign.right,
        );
        x += cols.priceW + cols.gap;
        _paintInSlot(
          canvas,
          totalTp,
          slotLeft: x,
          slotW: cols.totalW,
          y: y,
          align: TextAlign.right,
        );
        y += nameTp.height + lineGap * scale;
        continue;
      }
      final right = (line.rightText ?? '').trim();
      if (right.isNotEmpty) {
        final pairGap = contentW < 900 ? 20.0 : 32.0;
        final rightFrac = (line.rightSlotFrac ?? 0.38).clamp(0.16, 0.48);
        final rightW = contentW * rightFrac;
        final leftW = contentW - rightW - pairGap;
        final leftTp = _tp(line.text, style: style, maxWidth: leftW);
        final rightTp = _tp(
          right,
          style: style,
          maxWidth: rightW,
          align: TextAlign.right,
          maxLines: 2,
        );
        leftTp.paint(canvas, Offset(pad, y));
        _paintInSlot(
          canvas,
          rightTp,
          slotLeft: pad + leftW + pairGap,
          slotW: rightW,
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
          : pad;
      tp.paint(canvas, Offset(x, y));
      y += tp.height + lineGap * scale;
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
