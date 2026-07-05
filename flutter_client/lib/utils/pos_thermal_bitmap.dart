import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FontLoader, rootBundle;
import 'package:http/http.dart' as http;

import 'vietnamese_font.dart';

/// Một dòng trên hóa đơn cần render ảnh.
class PosReceiptImageLine {
  const PosReceiptImageLine({
    required this.text,
    this.bold = false,
    this.center = false,
    this.fontSize = 22,
  });

  final String text;
  final bool bold;
  final bool center;
  final double fontSize;
}

/// Chuyển chữ tiếng Việt thành lệnh ESC/POS raster (GS v 0).
class PosThermalBitmapEncoder {
  static bool _fontsLoaded = false;

  static int paperDots(int paperWidthMm) => paperWidthMm <= 58 ? 384 : 576;

  static Future<void> ensureFont() async {
    if (_fontsLoaded) return;
    final loader = FontLoader(kVietnameseFontFamily)
      ..addFont(rootBundle.load('assets/fonts/BeVietnamPro-Regular.ttf'))
      ..addFont(rootBundle.load('assets/fonts/BeVietnamPro-Bold.ttf'));
    await loader.load();
    _fontsLoaded = true;
  }

  /// Render toàn bộ hóa đơn thành một ảnh bitmap (ổn định nhất cho Zywell).
  static Future<List<int>?> receiptToRaster(
    List<PosReceiptImageLine> lines, {
    required int paperDots,
    double lineGap = 3,
  }) async {
    if (lines.isEmpty) return null;
    await ensureFont();

    final painters = <TextPainter?>[];
    var totalH = 0.0;

    for (final line in lines) {
      if (line.text.trim().isEmpty) {
        painters.add(null);
        totalH += 10;
        continue;
      }

      final tp = TextPainter(
        text: TextSpan(
          text: line.text,
          style: vietnameseTextStyle(
            TextStyle(
              fontSize: line.fontSize,
              fontWeight: line.bold ? FontWeight.w700 : FontWeight.w400,
              color: const Color(0xFF000000),
              height: 1.15,
            ),
          ),
        ),
        textAlign: line.center ? TextAlign.center : TextAlign.left,
        textDirection: TextDirection.ltr,
        maxLines: 4,
      )..layout(maxWidth: paperDots.toDouble());

      if (tp.height <= 0) {
        painters.add(null);
        continue;
      }
      painters.add(tp);
      totalH += tp.height + lineGap;
    }

    final h = totalH.ceil().clamp(1, 8000);
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawRect(
      Rect.fromLTWH(0, 0, paperDots.toDouble(), h.toDouble()),
      Paint()..color = const Color(0xFFFFFFFF),
    );

    var y = 0.0;
    for (var i = 0; i < painters.length; i++) {
      final tp = painters[i];
      if (tp == null) {
        y += 10;
        continue;
      }
      final x = tp.textAlign == TextAlign.center
          ? ((paperDots - tp.width) / 2).clamp(0.0, paperDots.toDouble())
          : 0.0;
      tp.paint(canvas, Offset(x, y));
      y += tp.height + lineGap;
    }

    final picture = recorder.endRecording();
    final image = await picture.toImage(paperDots, h);
    return _imageToEscPos(image);
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
          text: text,
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

  static Future<List<int>?> _imageToEscPos(ui.Image image) async {
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
          if (lum < 168) {
            b |= (0x80 >> bit);
          }
        }
        raster.add(b);
      }
    }

    if (!raster.any((b) => b != 0)) return null;

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
