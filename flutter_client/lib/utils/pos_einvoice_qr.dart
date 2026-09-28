import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:barcode/barcode.dart';
import 'package:flutter/painting.dart';

/// Ảnh QR sinh tại máy (không gọi mạng) — dùng cho mã QR tra cứu HĐĐT trên bill.
/// Bộ in nhận «qrdata:<nội dung>» ở chỗ vốn nhận URL ảnh (VietQR).
const kPosInlineQrScheme = 'qrdata:';

String posInlineQrUrl(String data) =>
    '$kPosInlineQrScheme${Uri.encodeComponent(data)}';

String? posInlineQrData(String url) => url.startsWith(kPosInlineQrScheme)
    ? Uri.decodeComponent(url.substring(kPosInlineQrScheme.length))
    : null;

/// PNG trắng đen, có viền trắng (quiet zone) — nét không khử răng cưa cho máy in nhiệt.
Future<Uint8List?> posQrPngBytes(String data, {int size = 360}) async {
  if (data.trim().isEmpty) return null;
  try {
    final qr = Barcode.qrCode(
      errorCorrectLevel: BarcodeQRCorrectionLevel.medium,
    );
    const quiet = 16.0;
    final inner = size - quiet * 2;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.toDouble(), size.toDouble()),
      Paint()..color = const Color(0xFFFFFFFF),
    );
    final ink = Paint()
      ..color = const Color(0xFF000000)
      ..isAntiAlias = false;
    for (final e in qr.make(data, width: inner, height: inner, drawText: false)) {
      if (e is BarcodeBar && e.black) {
        // Làm tròn + nới 0.5px để các ô liền nhau không hở vạch trắng.
        canvas.drawRect(
          Rect.fromLTWH(
            (quiet + e.left).floorToDouble(),
            (quiet + e.top).floorToDouble(),
            e.width.ceilToDouble() + 0.5,
            e.height.ceilToDouble() + 0.5,
          ),
          ink,
        );
      }
    }
    final image = await recorder.endRecording().toImage(size, size);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    return bytes?.buffer.asUint8List();
  } catch (_) {
    return null;
  }
}

/// SVG cho bản in HTML / xem trước trình duyệt.
String posQrSvg(String data, {double size = 120}) {
  try {
    return Barcode.qrCode(errorCorrectLevel: BarcodeQRCorrectionLevel.medium)
        .toSvg(data, width: size, height: size, drawText: false);
  } catch (_) {
    return '';
  }
}
