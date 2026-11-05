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

/// PNG trắng đen cạnh [size], mỗi ô QR đúng số nguyên điểm in, viền trắng tối thiểu 4 ô.
/// Ô lẻ điểm (làm tròn + nới) làm ô đen rộng gấp đôi ô trắng — máy in nhiệt nở nét thêm là hết quét được.
Future<Uint8List?> posQrPngBytes(String data, {int size = 360}) async {
  if (data.trim().isEmpty) return null;
  try {
    final qr = Barcode.qrCode(
      errorCorrectLevel: BarcodeQRCorrectionLevel.medium,
    );
    // Đo số ô mỗi cạnh: dựng thử rất rộng rồi chia cho chiều cao một hàng.
    const probe = 100000.0;
    final rowH = qr.make(data, width: probe, height: probe, drawText: false).whereType<BarcodeBar>().first.height;
    final cells = (probe / rowH).round();
    final module = size ~/ (cells + 8) < 1 ? 1 : size ~/ (cells + 8);
    final origin = (size - cells * module) ~/ 2;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.toDouble(), size.toDouble()),
      Paint()..color = const Color(0xFFFFFFFF),
    );
    final ink = Paint()
      ..color = const Color(0xFF000000)
      ..isAntiAlias = false;
    for (final e in qr.make(data, width: cells.toDouble(), height: cells.toDouble(), drawText: false)) {
      if (e is BarcodeBar && e.black) {
        canvas.drawRect(
          Rect.fromLTWH(
            origin + e.left.roundToDouble() * module,
            origin + e.top.roundToDouble() * module,
            e.width.roundToDouble() * module,
            e.height.roundToDouble() * module,
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
