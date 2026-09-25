/// Tên miền của hai server SBOX — mỗi server có database riêng:
/// - HRM: `sboxhrm.com` (+ tên cũ `sbox.sana.vn`)
/// - POS: `sboxpos.com`
///
/// App build riêng cho từng server bằng `--dart-define=SBOX_SERVER=pos|hrm`
/// (mặc định `hrm`). Mọi link công khai (màn khách, tải APK) phải lấy theo
/// server đang kết nối, không ghi cứng một tên miền.
abstract final class SboxEndpoints {
  static const hrmSite = 'https://sboxhrm.com';
  static const hrmLegacySite = 'https://sbox.sana.vn';
  static const posSite = 'https://sboxpos.com';

  static const String _buildServer =
      String.fromEnvironment('SBOX_SERVER', defaultValue: 'hrm');

  /// Bản build này dành cho server POS (sboxpos.com).
  static bool get buildIsPos => _buildServer.toLowerCase() == 'pos';

  /// Server mặc định của bản build (khi không truyền `API_BASE`).
  static String get buildDefaultApi => buildIsPos ? posSite : hrmSite;

  static bool isPosHost(String host) {
    final h = host.toLowerCase();
    return h == 'sboxpos.com' || h.endsWith('.sboxpos.com');
  }

  static bool isHrmHost(String host) {
    final h = host.toLowerCase();
    return h == 'sboxhrm.com' ||
        h.endsWith('.sboxhrm.com') ||
        h == 'sana.vn' ||
        h.endsWith('.sana.vn');
  }

  static bool isPosServer(String baseUrl) =>
      isPosHost(Uri.tryParse(baseUrl)?.host ?? '');

  /// Trang web công khai của server đang kết nối (màn khách, tải APK).
  static String publicSiteFor(String apiBase) =>
      isPosServer(apiBase) ? posSite : hrmSite;

  /// Các origin cùng một server (cùng database) — chỉ dùng làm dự phòng
  /// trong nhóm này, không bao giờ nhảy sang server kia.
  static List<String> sameServerOrigins(String apiBase) =>
      isPosServer(apiBase) ? const [posSite] : const [hrmSite, hrmLegacySite];
}
