import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// Nén ảnh trước khi upload (client) — server vẫn nén lại lần nữa.
/// Mục tiêu: tải nhanh + giảm payload trên mạng yếu.
Uint8List compressImageBytes(
  Uint8List raw, {
  int maxEdge = 1200,
  int jpegQuality = 78,
}) {
  if (raw.isEmpty) return raw;
  try {
    final decoded = img.decodeImage(raw);
    if (decoded == null) return raw;

    var work = decoded;
    final w = work.width;
    final h = work.height;
    if (w > maxEdge || h > maxEdge) {
      if (w >= h) {
        work = img.copyResize(
          work,
          width: maxEdge,
          interpolation: img.Interpolation.average,
        );
      } else {
        work = img.copyResize(
          work,
          height: maxEdge,
          interpolation: img.Interpolation.average,
        );
      }
    }

    final out = Uint8List.fromList(
      img.encodeJpg(work, quality: jpegQuality.clamp(40, 95)),
    );
    // Giữ gốc nếu JPEG không nhỏ hơn (PNG icon nhỏ…).
    if (out.isNotEmpty && out.length < raw.length) return out;
    return raw;
  } catch (_) {
    return raw;
  }
}

String jpegFileName(String original) {
  final t = original.trim();
  if (t.isEmpty) return 'image.jpg';
  final dot = t.lastIndexOf('.');
  if (dot <= 0) return '$t.jpg';
  return '${t.substring(0, dot)}.jpg';
}
