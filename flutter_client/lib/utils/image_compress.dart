import 'package:flutter/foundation.dart';

import 'package:image/image.dart' as img;

/// Nén ảnh trước khi upload (client) — server vẫn nén lại lần nữa.
/// Mục tiêu: tải nhanh + giảm payload trên mạng yếu.
/// Xoay ảnh theo EXIF (ảnh chụp dọc trên điện thoại) trước khi nén — JPEG mới không còn thẻ xoay.
Uint8List compressImageBytes(
  Uint8List raw, {
  int maxEdge = 1200,
  int jpegQuality = 78,
}) =>
    _compress(raw, maxEdge, jpegQuality).bytes;

/// Ảnh đã chuẩn bị để gửi: [decoded] = false khi không đọc được ảnh (vd HEIC) — [bytes] là file gốc.
typedef PreparedImage = ({Uint8List bytes, bool decoded});

PreparedImage _compress(Uint8List raw, int maxEdge, int jpegQuality) {
  if (raw.isEmpty) return (bytes: raw, decoded: false);
  try {
    final decoded = img.decodeImage(raw);
    if (decoded == null) return (bytes: raw, decoded: false);

    final ifd = decoded.exif.imageIfd;
    final rotated = ifd.hasOrientation && ifd.orientation != 1;
    var work = rotated ? img.bakeOrientation(decoded) : decoded;
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
    // Giữ gốc nếu JPEG không nhỏ hơn (PNG icon nhỏ…) — trừ khi đã phải xoay theo EXIF.
    if (out.isNotEmpty && (rotated || out.length < raw.length)) {
      return (bytes: out, decoded: true);
    }
    return (bytes: raw, decoded: true);
  } catch (_) {
    return (bytes: raw, decoded: false);
  }
}

PreparedImage _prepareJob(({Uint8List raw, int maxEdge, int jpegQuality}) a) =>
    _compress(a.raw, a.maxEdge, a.jpegQuality);

/// Như [compressImageBytes] nhưng chạy trên isolate nền (ảnh menu 12 MP nén mất vài giây — không đứng giao diện).
Future<PreparedImage> prepareImageForUpload(
  Uint8List raw, {
  int maxEdge = 1200,
  int jpegQuality = 78,
}) =>
    compute(_prepareJob, (raw: raw, maxEdge: maxEdge, jpegQuality: jpegQuality));

/// File HEIC / HEIF (ảnh iPhone) — gói image không giải mã được.
bool looksLikeHeic(Uint8List b) {
  if (b.length < 12 || b[4] != 0x66 || b[5] != 0x74 || b[6] != 0x79 || b[7] != 0x70) return false;
  final brand = String.fromCharCodes(b.sublist(8, 12));
  return const {'heic', 'heix', 'hevc', 'hevx', 'mif1', 'msf1'}.contains(brand);
}

String jpegFileName(String original) {
  final t = original.trim();
  if (t.isEmpty) return 'image.jpg';
  final dot = t.lastIndexOf('.');
  if (dot <= 0) return '$t.jpg';
  return '${t.substring(0, dot)}.jpg';
}
