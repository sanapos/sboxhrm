import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:intl/intl.dart';

/// Gắn thời gian + tọa độ lên ảnh hiện trường (JPEG bytes).
Uint8List applySitePhotoWatermark(
  Uint8List jpegBytes, {
  required DateTime capturedAt,
  double? latitude,
  double? longitude,
  String? locationLabel,
}) {
  final decoded = img.decodeImage(jpegBytes);
  if (decoded == null) return jpegBytes;

  final local = capturedAt.toLocal();
  final timeLine = DateFormat('dd/MM/yyyy HH:mm:ss').format(local);
  final coordLine = (latitude != null && longitude != null)
      ? '${latitude.toStringAsFixed(6)}, ${longitude.toStringAsFixed(6)}'
      : 'GPS: chưa có';
  final locLine = (locationLabel != null && locationLabel.trim().isNotEmpty)
      ? locationLabel.trim()
      : null;

  final lines = <String>[
    'SBOX HRM · Ảnh hiện trường',
    timeLine,
    if (locLine != null) locLine,
    coordLine,
  ];

  final font = img.arial24;
  const lineH = 28;
  const pad = 12;
  final boxH = pad * 2 + lineH * lines.length;
  final boxW = decoded.width;

  img.fillRect(
    decoded,
    x1: 0,
    y1: decoded.height - boxH,
    x2: boxW,
    y2: decoded.height,
    color: img.ColorRgba8(0, 0, 0, 170),
  );

  var y = decoded.height - boxH + pad;
  for (final line in lines) {
    img.drawString(
      decoded,
      line,
      font: font,
      x: pad,
      y: y,
      color: img.ColorRgba8(255, 255, 255, 255),
    );
    y += lineH;
  }

  var out = decoded;
  const maxW = 1280;
  if (out.width > maxW) {
    out = img.copyResize(out, width: maxW);
  }

  return Uint8List.fromList(img.encodeJpg(out, quality: 82));
}
