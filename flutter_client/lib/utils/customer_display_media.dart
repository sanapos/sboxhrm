import '../models/customer_display_models.dart';
import '../services/api_service.dart';

/// Chuẩn kích thước media màn hình phụ.
/// Chờ khách: media chiếu toàn màn. Đang bán: màn ngang → media ~62% bên trái, hóa đơn bên phải;
/// màn dọc → dải media 16:9 phía trên, hóa đơn bên dưới.
class CustomerDisplayMediaSpec {
  static const recommendedImage =
      'Màn ngang: 1920×1080 (16:9) · màn dọc: 1080×1920 (9:16). Ảnh khác tỉ lệ vẫn hiện trọn, viền lấp bằng ảnh làm mờ';
  static const recommendedVideo =
      '16:9, 1280×720 hoặc 1920×1080, MP4 H.264, nên dưới 50MB · video tự tắt tiếng, phát hết rồi chuyển mục';
  static const layoutNote =
      'Chờ khách: ảnh / video chiếu toàn màn. Khi có đơn: màn ngang chia media | hóa đơn, màn dọc chia media trên | hóa đơn dưới. '
      'Chữ và mã QR tự co giãn theo kích thước màn (7″ đến TV 1080p).';
}

/// Resolve URL ảnh/video cho màn phụ (public-serve + Drive/Dropbox).
String resolveCustomerDisplayMediaUrl(ApiService api, String? raw) {
  final t = (raw ?? '').trim();
  if (t.isEmpty) return '';
  final external = CustomerDisplayConfig.normalizeExternalMediaUrl(t);
  // Link ngoài (Drive/CDN) — không qua API serve.
  if (external.startsWith('http://') || external.startsWith('https://')) {
    final lower = external.toLowerCase();
    if (lower.contains('drive.google.com') ||
        lower.contains('dropbox.com') ||
        lower.contains('dropboxusercontent.com') ||
        (!lower.contains('/api/upload/'))) {
      // CDN / Drive trực tiếp
      if (lower.contains('drive.google.com') ||
          lower.contains('dropbox') ||
          lower.contains('.mp4') ||
          lower.contains('.webm') ||
          lower.contains('.mov') ||
          lower.contains('.jpg') ||
          lower.contains('.jpeg') ||
          lower.contains('.png') ||
          lower.contains('.webp')) {
        return external;
      }
    }
  }
  return api.getPublicFileUrl(external);
}
