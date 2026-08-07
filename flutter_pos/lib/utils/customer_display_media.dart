import '../models/customer_display_models.dart';
import '../services/api_service.dart';

/// Chuẩn kích thước media màn hình phụ (cột trái ~60% màn 16:9).
class CustomerDisplayMediaSpec {
  static const recommendedImage = '1920×1080 (16:9) hoặc 1280×720';
  static const recommendedVideo = '1280×720 H.264 MP4, dưới 100MB trên Drive';
  static const layoutNote =
      'Màn 16:9: cột media ~60% rộng × full cao (vd. 1152×1080 trên TV 1920×1080). '
      'Ảnh/video fit chứa trọn khung (letterbox), không cắt mất.';
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
