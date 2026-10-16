import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../models/pos_label_design.dart';
import 'pos_label_renderer.dart';
import 'pos_thermal_bitmap.dart';
import 'vietnamese_font.dart';

/// Vẽ tem thiết kế tự do — cùng một hàm cho khung soạn, ảnh xem trước, ảnh in nhiệt (raster) và PDF
/// → in ở đâu cũng giống màn soạn.
abstract final class PosLabelDesignPainter {
  static final _token = RegExp(r'\{(\w+)\}');

  /// Thay {Truong} bằng dữ liệu (trường không có → rỗng).
  static String resolve(String template, Map<String, String> data) =>
      template.replaceAllMapped(_token, (m) => data[m[1]] ?? '');

  /// Phần tử chữ có trường mà mọi trường đều trống → ẩn (vd «Bảo hành: {Bao_Hanh}» với hàng không bảo hành).
  static bool hasContent(String template, Map<String, String> data) {
    final tokens = _token.allMatches(template).map((m) => m[1]!).toList();
    if (tokens.isEmpty) return template.trim().isNotEmpty;
    return tokens.any((t) => (data[t] ?? '').trim().isNotEmpty);
  }

  /// Nội dung mặc định khi ô mã vạch / QR để trống.
  static String codeTemplate(PosLabelElement e) =>
      e.text.trim().isNotEmpty ? e.text : '{Ma_Vach}';

  /// Giải mã ảnh của mẫu (một lần trước khi vẽ).
  static Future<Map<String, ui.Image>> loadImages(PosLabelDesign d) async {
    final out = <String, ui.Image>{};
    for (final e in d.elements) {
      final data = e.imageData;
      if (e.type != PosLabelElementType.image || data == null || data.isEmpty) continue;
      try {
        final raw = base64Decode(data.contains(',') ? data.split(',').last : data);
        final codec = await ui.instantiateImageCodec(raw);
        out[e.id] = (await codec.getNextFrame()).image;
      } catch (_) {}
    }
    return out;
  }

  /// Vẽ một tem vào [origin] (góc trên trái, px). [pxPerMm] = tỉ lệ (máy in 203 dpi ≈ 8 px/mm).
  static void paint(
    ui.Canvas canvas,
    PosLabelDesign d,
    Map<String, String> data,
    double pxPerMm, {
    Offset origin = Offset.zero,
    Map<String, ui.Image> images = const {},
    bool background = true,
    bool placeholders = false,
  }) {
    final labelRect = Rect.fromLTWH(origin.dx, origin.dy, d.widthMm * pxPerMm, d.heightMm * pxPerMm);
    if (background) canvas.drawRect(labelRect, Paint()..color = Colors.white);
    canvas.save();
    canvas.clipRect(labelRect);
    for (final e in d.elements) {
      final r = Rect.fromLTWH(
        origin.dx + e.x * pxPerMm,
        origin.dy + e.y * pxPerMm,
        math.max(1, e.w * pxPerMm),
        math.max(1, e.h * pxPerMm),
      );
      paintElement(canvas, e, r, data, pxPerMm, images: images, placeholders: placeholders);
    }
    canvas.restore();
  }

  /// Vẽ một phần tử vào ô [r] (px, toạ độ trên tem). Xoay quanh tâm ô.
  static void paintElement(
    ui.Canvas canvas,
    PosLabelElement e,
    Rect r,
    Map<String, String> data,
    double pxPerMm, {
    Map<String, ui.Image> images = const {},
    bool placeholders = false,
  }) {
    final rot = e.rotation % 360;
    final swap = rot == 90 || rot == 270;
    final local = Rect.fromCenter(
      center: Offset.zero,
      width: swap ? r.height : r.width,
      height: swap ? r.width : r.height,
    );
    canvas.save();
    canvas.clipRect(r);
    canvas.translate(r.center.dx, r.center.dy);
    if (rot != 0) canvas.rotate(rot * math.pi / 180);
    switch (e.type) {
      case PosLabelElementType.text:
        final s = resolve(e.text, data);
        final show = hasContent(e.text, data);
        if (e.invert && (show || placeholders)) {
          canvas.drawRect(local, Paint()..color = Colors.black);
        }
        if (show) {
          _paintText(canvas, e, s, local, pxPerMm, color: e.invert ? Colors.white : Colors.black);
        } else if (placeholders) {
          _paintText(canvas, e.copyWith(bold: false), e.text, local, pxPerMm,
              color: e.invert ? Colors.white54 : const Color(0xFF9AA4B2));
        }
      case PosLabelElementType.barcode:
        final code = resolve(codeTemplate(e), data).trim();
        if (code.isEmpty) {
          if (placeholders) _placeholderBox(canvas, local, 'Mã vạch', pxPerMm);
          break;
        }
        var bars = local;
        if (e.showText) {
          final textH = math.min(local.height * 0.32, 3.0 * pxPerMm);
          bars = Rect.fromLTRB(local.left, local.top, local.right, local.bottom - textH);
          final tp = _layout(code, textH * 0.82, false, local.width, 1, TextAlign.center, Colors.black);
          tp.paint(canvas, Offset(local.left + (local.width - tp.width) / 2, bars.bottom + (textH - tp.height) / 2));
        }
        PosLabelRenderer.paintBarcode(canvas, code, bars);
      case PosLabelElementType.qr:
        final content = resolve(codeTemplate(e), data).trim();
        final side = math.min(local.width, local.height);
        final q = Rect.fromCenter(center: local.center, width: side, height: side);
        if (content.isEmpty) {
          if (placeholders) _placeholderBox(canvas, q, 'QR', pxPerMm);
          break;
        }
        PosLabelRenderer.paintQr(canvas, content, q);
      case PosLabelElementType.image:
        final img = images[e.id];
        if (img == null) {
          if (placeholders) _placeholderBox(canvas, local, 'Ảnh', pxPerMm);
          break;
        }
        final src = Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble());
        final fit = applyBoxFit(BoxFit.contain, src.size, local.size);
        final dst = Alignment.center.inscribe(fit.destination, local);
        canvas.drawImageRect(img, Alignment.center.inscribe(fit.source, src), dst, Paint()..filterQuality = FilterQuality.medium);
      case PosLabelElementType.line:
        final t = math.max(1.0, e.strokeMm * pxPerMm);
        final p = Paint()..color = Colors.black;
        if (local.width >= local.height) {
          canvas.drawRect(Rect.fromCenter(center: local.center, width: local.width, height: t), p);
        } else {
          canvas.drawRect(Rect.fromCenter(center: local.center, width: t, height: local.height), p);
        }
      case PosLabelElementType.box:
        final t = math.max(1.0, e.strokeMm * pxPerMm);
        if (e.filled) {
          canvas.drawRect(local, Paint()..color = Colors.black);
        } else {
          canvas.drawRect(
            local.deflate(t / 2),
            Paint()
              ..color = Colors.black
              ..style = PaintingStyle.stroke
              ..strokeWidth = t,
          );
        }
    }
    canvas.restore();
  }

  static TextPainter _layout(String s, double fontPx, bool bold, double maxW, int maxLines, TextAlign align, Color color) =>
      TextPainter(
        text: TextSpan(
          text: s,
          style: vietnameseTextStyle(TextStyle(
            fontSize: fontPx,
            fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
            color: color,
            height: 1.1,
          )),
        ),
        textAlign: align,
        textDirection: TextDirection.ltr,
        maxLines: maxLines,
        ellipsis: '…',
      )..layout(minWidth: maxW, maxWidth: maxW);

  static void _paintText(ui.Canvas canvas, PosLabelElement e, String s, Rect box, double pxPerMm, {required Color color}) {
    if (s.trim().isEmpty) return;
    final align = switch (e.align) {
      PosLabelAlign.left => TextAlign.left,
      PosLabelAlign.center => TextAlign.center,
      PosLabelAlign.right => TextAlign.right,
    };
    final pad = e.invert ? 0.6 * pxPerMm : 0.0;
    final w = math.max(1.0, box.width - pad * 2);
    final h = box.height;
    final lines = e.maxLines.clamp(1, 12);
    var fontPx = math.max(2.0, e.fontSize * 0.3528 * pxPerMm);
    var tp = _layout(s.trim(), fontPx, e.bold, w, lines, align, color);
    if (e.autoShrink) {
      final minPx = fontPx * 0.55;
      while ((tp.height > h + 0.5 || tp.didExceedMaxLines) && fontPx > minPx) {
        fontPx *= 0.92;
        tp = _layout(s.trim(), fontPx, e.bold, w, lines, align, color);
      }
    }
    if (tp.height > h + 0.5) {
      // Vẫn cao hơn ô: cắt bớt dòng cho vừa, không tràn khỏi ô.
      final fit = (h / (fontPx * 1.1)).floor().clamp(1, lines);
      tp = _layout(s.trim(), fontPx, e.bold, w, fit, align, color);
    }
    final dy = switch (e.vAlign) {
      PosLabelVAlign.top => 0.0,
      PosLabelVAlign.middle => (h - tp.height) / 2,
      PosLabelVAlign.bottom => h - tp.height,
    };
    tp.paint(canvas, Offset(box.left + pad, box.top + math.max(0, dy)));
  }

  static void _placeholderBox(ui.Canvas canvas, Rect r, String label, double pxPerMm) {
    canvas.drawRect(r, Paint()..color = const Color(0xFFEFF2F6));
    final tp = _layout(label, math.min(r.height * 0.4, 3 * pxPerMm), false, r.width, 1, TextAlign.center,
        const Color(0xFF9AA4B2));
    tp.paint(canvas, Offset(r.left, r.top + (r.height - tp.height) / 2));
  }

  /// Ảnh một tem (xem trước / thumbnail).
  static Future<ui.Image> renderImage(
    PosLabelDesign d,
    Map<String, String> data, {
    double pxPerMm = 8,
    Map<String, ui.Image>? images,
  }) async {
    await PosThermalBitmapEncoder.ensureFont();
    final imgs = images ?? await loadImages(d);
    final w = (d.widthMm * pxPerMm).round();
    final h = (d.heightMm * pxPerMm).round();
    final rec = ui.PictureRecorder();
    final canvas = ui.Canvas(rec);
    paint(canvas, d, data, pxPerMm, images: imgs);
    return rec.endRecording().toImage(w, h);
  }

  static Future<Uint8List?> renderPng(PosLabelDesign d, Map<String, String> data, {double pxPerMm = 8}) async {
    final img = await renderImage(d, data, pxPerMm: pxPerMm);
    final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
    return bytes?.buffer.asUint8List();
  }

  /// Ảnh đen trắng một hàng tem (1–4 tem ngang) cho máy in tem nhiệt.
  static Future<({Uint8List raster, int widthPx, int heightPx})> renderRowRaster(
    PosLabelDesign d,
    List<Map<String, String>> rowData, {
    int dpi = 203,
  }) async {
    await PosThermalBitmapEncoder.ensureFont();
    final imgs = await loadImages(d);
    final pxPerMm = dpi / 25.4;
    final cols = d.columns.clamp(1, 4);
    final rowWmm = d.widthMm * cols + d.columnGapMm * (cols - 1);
    final w = (rowWmm * pxPerMm).round();
    final h = (d.heightMm * pxPerMm).round();
    final rec = ui.PictureRecorder();
    final canvas = ui.Canvas(rec);
    canvas.drawRect(Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()), Paint()..color = Colors.white);
    for (var i = 0; i < rowData.length && i < cols; i++) {
      paint(canvas, d, rowData[i], pxPerMm,
          origin: Offset(i * (d.widthMm + d.columnGapMm) * pxPerMm, 0), images: imgs);
    }
    final image = await rec.endRecording().toImage(w, h);
    return PosLabelRenderer.imageToRaster(image);
  }
}
