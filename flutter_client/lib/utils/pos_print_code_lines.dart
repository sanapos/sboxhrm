import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:barcode/barcode.dart';
import 'package:flutter/painting.dart';

import 'pos_einvoice_qr.dart';
import 'pos_print_template_compiler.dart';
import 'pos_thermal_bitmap.dart';

/// Mã vạch / QR / VietQR của mẫu V2 → dòng ảnh của bộ vẽ hóa đơn.
///
/// Xem trước trong trình soạn mẫu, Sunmi và máy in LAN/USB cùng gọi hàm này, nên mã in ra
/// giống hệt bản xem trước (cỡ, vị trí, chữ dưới mã). Trước đây xem trước tự vẽ mã còn máy in
/// dùng lệnh mã vạch riêng của từng hãng (máy LAN chế độ ảnh còn in mã thành dòng chữ).

/// Độ rộng một vạch mảnh CODE128 (điểm in) — như `GS w 2` / Sunmi size 2.
const kPosBarcodeModuleDots = 2;

/// Cạnh QR tự soạn theo «chiều cao» trong mẫu (điểm in).
int posPrintCustomQrDots(int barcodeHeight) => (barcodeHeight * 1.6).round().clamp(96, 360);

/// Cạnh VietQR tối đa để còn lề hai bên trên khổ giấy.
int posPrintVietQrDots(int size, int paperDots) => size.clamp(120, paperDots - 32);

Future<Uint8List?> _pngOf(int w, int h, void Function(Canvas c, Paint ink) draw) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()), Paint()..color = const Color(0xFFFFFFFF));
  draw(
    canvas,
    Paint()
      ..color = const Color(0xFF000000)
      ..isAntiAlias = false,
  );
  final image = await recorder.endRecording().toImage(w, h);
  final bd = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return bd?.buffer.asUint8List();
}

/// CODE128 trắng đen, mỗi vạch đúng bội số điểm in. Quá khổ thì giảm vạch còn 1 điểm.
Future<Uint8List?> posBarcodePngBytes(String data, {required int heightDots, required int maxWidthDots}) async {
  final code = data.trim();
  if (code.isEmpty) return null;
  try {
    final bc = Barcode.code128();
    // Đo số module: dựng thử rất rộng rồi chia cho vạch mảnh nhất.
    const probe = 100000.0;
    final els = bc.make(code, width: probe, height: 10, drawText: false).whereType<BarcodeBar>().toList();
    if (els.isEmpty) return null;
    final unit = els.map((e) => e.width).reduce((a, b) => a < b ? a : b);
    final modules = (probe / unit).round();
    var module = kPosBarcodeModuleDots;
    while (module > 1 && modules * module > maxWidthDots) {
      module--;
    }
    final w = modules * module;
    final h = heightDots.clamp(16, 300);
    return _pngOf(w, h, (c, ink) {
      for (final e in bc.make(code, width: w.toDouble(), height: h.toDouble(), drawText: false)) {
        if (e is BarcodeBar && e.black) {
          c.drawRect(Rect.fromLTWH(e.left.roundToDouble(), 0, e.width.roundToDouble(), h.toDouble()), ink);
        }
      }
    });
  } catch (_) {
    return null;
  }
}

/// Ảnh VietQR: «qrdata:» và mẫu xem trước sinh tại máy, còn lại tải từ VietQR.
Future<Uint8List?> _vietQrBytes(String url, int dots) async {
  final inline = posInlineQrData(url);
  if (inline != null) return posQrPngBytes(inline, size: dots);
  if (url == 'sample') return posQrPngBytes('SBOX VIETQR MAU 0123456789', size: dots);
  return PosThermalBitmapEncoder.networkPngBytes(url, maxWidth: dots);
}

/// Bước mã ([PosPrintCompiledQr] / [PosPrintCompiledBarcode]) → các dòng ảnh in.
/// Trả rỗng nếu không phải bước mã.
Future<List<PosReceiptImageLine>> posPrintCodeStepLines(Object step, {required int paperDots}) async {
  final maxW = paperDots - 16;
  if (step is PosPrintCompiledBarcode) {
    final data = step.data.trim();
    if (data.isEmpty) return const [];
    final idx = step.sourceBlockIndex;
    if (step.qr) {
      final dots = posPrintCustomQrDots(step.height).clamp(64, maxW);
      final png = await posQrPngBytes(data, size: dots);
      return [
        if (png != null)
          PosReceiptImageLine(text: '', imageBytes: png, imageWidthDots: dots.toDouble(), center: true, spaceBefore: 4, sourceBlockIndex: idx)
        else
          PosReceiptImageLine(text: data, fontSize: 18, center: true, sourceBlockIndex: idx),
        if (png != null && step.showText) PosReceiptImageLine(text: data, fontSize: 18, center: true, sourceBlockIndex: idx),
      ];
    }
    final png = await posBarcodePngBytes(data, heightDots: step.height, maxWidthDots: maxW);
    if (png == null) {
      return [PosReceiptImageLine(text: data, fontSize: 22, bold: true, center: true, sourceBlockIndex: idx)];
    }
    final img = await ui.instantiateImageCodec(png).then((c) => c.getNextFrame()).then((f) => f.image);
    final w = img.width.toDouble();
    img.dispose();
    return [
      PosReceiptImageLine(text: '', imageBytes: png, imageWidthDots: w, center: true, spaceBefore: 6, sourceBlockIndex: idx),
      if (step.showText) PosReceiptImageLine(text: data, fontSize: 20, center: true, sourceBlockIndex: idx),
    ];
  }
  if (step is PosPrintCompiledQr) {
    final idx = step.sourceBlockIndex;
    final dots = posPrintVietQrDots(step.size, paperDots);
    final png = await _vietQrBytes(step.imageUrl, dots);
    final title = (step.title ?? '').trim();
    final caption = step.caption.trim();
    final amount = (step.amountText ?? '').trim();
    return [
      if (title.isNotEmpty) PosReceiptImageLine(text: title, fontSize: 24, bold: true, center: true, spaceBefore: 4, sourceBlockIndex: idx),
      if (png != null)
        PosReceiptImageLine(text: '', imageBytes: png, imageWidthDots: dots.toDouble(), center: true, spaceBefore: 4, sourceBlockIndex: idx),
      if (caption.isNotEmpty) PosReceiptImageLine(text: caption, fontSize: 22, bold: true, center: true, sourceBlockIndex: idx),
      if (amount.isNotEmpty) PosReceiptImageLine(text: '$amount đ', fontSize: 26, bold: true, center: true, sourceBlockIndex: idx),
    ];
  }
  return const [];
}

/// Toàn bộ mẫu đã biên dịch → dòng ảnh in (chữ, ảnh, mã). Xem trước và Sunmi dùng chung.
Future<List<PosReceiptImageLine>> posPrintOutputImageLines(PosPrintCompiledOutput output, {required int paperDots}) async {
  final lines = <PosReceiptImageLine>[];
  for (final step in output.steps) {
    if (step is PosPrintCompiledQr || step is PosPrintCompiledBarcode) {
      lines.addAll(await posPrintCodeStepLines(step, paperDots: paperDots));
      continue;
    }
    final line = compiledStepToImageLine(step);
    if (line != null) lines.add(line);
  }
  return lines;
}
