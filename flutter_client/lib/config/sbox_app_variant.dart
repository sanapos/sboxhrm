import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// Biến thể app: HRM (mặc định) hoặc POS độc lập cho Play Store.
///
/// Bật POS bằng `--flavor pos` (package `sbox.sana.vn.pos`) và/hoặc
/// `--dart-define=SBOX_POS_STANDALONE=true`.
/// SBOX KDS (chỉ màn hình bếp, Android 7+): `--flavor kds --dart-define=SBOX_APP=kds`
/// (package `sbox.sana.vn.kitchen`) — là một dạng POS độc lập. Bản KDS Android 6 vẫn build từ flutter_pos.
/// SBOX Staff (app nhân viên: chấm công, lịch, lương, đơn từ, gọi món):
/// `--flavor staff --dart-define=SBOX_APP=staff` (package `sbox.sana.vn.staff`).
/// Web: `sboxpos.com` chỉ branding POS; `sboxhrm.com` chỉ branding HRM.
abstract final class SboxAppVariant {
  static const androidPosApplicationId = 'sbox.sana.vn.pos';
  static const androidKdsApplicationId = 'sbox.sana.vn.kitchen';
  static const androidStaffApplicationId = 'sbox.sana.vn.staff';
  static const posGreen = 0xFF2E7D32;
  static const hrmBlue = 0xFF0C56D0;

  static const bool _fromDefine = bool.fromEnvironment(
    'SBOX_POS_STANDALONE',
    defaultValue: false,
  );

  static const bool _kdsFromDefine =
      String.fromEnvironment('SBOX_APP') == 'kds';

  static const bool _staffFromDefine =
      String.fromEnvironment('SBOX_APP') == 'staff';

  static bool _fromPackage = false;
  static bool _kdsFromPackage = false;
  static bool _staffFromPackage = false;

  /// App SBOX KDS: đăng nhập xong chỉ mở màn hình bếp.
  static bool get kitchenApp => _kdsFromDefine || _kdsFromPackage;

  /// App SBOX Staff: khung tự phục vụ cho nhân viên ([StaffShell]), không mở menu quản trị HRM.
  static bool get staffApp => _staffFromDefine || _staffFromPackage;

  static bool get standalonePos => _fromDefine || _fromPackage || kitchenApp;

  /// Trang web sboxpos.com — chỉ đổi logo/chữ login & marketing, không đổi shell app.
  static bool get posWebHost {
    if (!kIsWeb) return false;
    final h = Uri.base.host.toLowerCase();
    return h == 'sboxpos.com' ||
        h == 'www.sboxpos.com' ||
        h.startsWith('sboxpos.');
  }

  static bool get posBranding => standalonePos || posWebHost;

  static String get productLine => kitchenApp
      ? 'SBOX KDS'
      : (posBranding ? 'SBOX POS' : (staffApp ? 'SBOX Staff' : 'SBOX HRM'));

  static String get slogan => posBranding
      ? 'Giải pháp toàn diện giúp cửa hàng vận hành hiệu quả, tối ưu doanh thu'
      : 'Chấm công nhanh · Tính lương chuẩn';

  static String get loginHeroTitle => posBranding
      ? 'Bán hàng nhanh\nQuản lý cửa hàng chuẩn'
      : 'Chấm công & tính lương\nthời gian thực';

  static String get loginSubtitle => kitchenApp
      ? 'Đăng nhập để mở màn hình bếp SBOX KDS.'
      : posBranding
      ? 'Nhập thông tin để vào SBOX POS.'
      : staffApp
      ? 'Đăng nhập bằng tài khoản nhân viên để chấm công, xem lịch và phiếu lương.'
      : 'Nhập thông tin để truy cập hệ thống quản trị.';

  static String get registerTitle =>
      posBranding ? 'Đăng ký cửa hàng' : 'Đăng ký doanh nghiệp';

  static String get registerSubtitle => posBranding
      ? 'Tạo tài khoản SBOX POS để bắt đầu bán hàng.'
      : 'Tạo tài khoản doanh nghiệp mới để bắt đầu.';

  static String get registerButton =>
      posBranding ? 'Đăng ký cửa hàng' : 'Đăng ký doanh nghiệp';

  static String get copyright =>
      posBranding ? '© 2026 SBOX POS' : '© 2026 SBOX HRM';

  static String get logoAsset =>
      posBranding ? 'assets/sbox_pos_logo.png' : 'assets/logo.png';

  static String get materialAppTitle => productLine;

  static Future<void> bootstrap() async {
    if (_fromDefine || _kdsFromDefine || _staffFromDefine || kIsWeb) return;
    try {
      final info = await PackageInfo.fromPlatform();
      _fromPackage = info.packageName == androidPosApplicationId;
      _kdsFromPackage = info.packageName == androidKdsApplicationId;
      _staffFromPackage = info.packageName == androidStaffApplicationId;
    } catch (_) {}
  }
}
