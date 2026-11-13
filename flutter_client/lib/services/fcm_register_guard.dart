import 'package:shared_preferences/shared_preferences.dart';

/// Khóa lưu nhãn phiên «Đăng nhập thay» (Super Admin đăng nhập thay tài khoản cửa hàng).
/// Có khóa này = phiên trong máy là phiên của người khác.
const String kImpersonationLabelPrefKey = 'imp_label';

/// Access token dùng để gắn token FCM của máy này, hoặc null khi không được gắn.
///
/// Đọc ngay lúc gửi (không lấy từ lúc bắt đầu): việc đăng ký chạy nền, trên iOS có thể chờ
/// APNs tới 45 giây, và Firebase tự làm mới token bất kỳ lúc nào. Nếu lúc đó Super Admin
/// đang đăng nhập thay thì token máy bị gắn vào tài khoản cửa hàng kia → máy nhận thông báo
/// chấm công của cửa hàng khác.
String? fcmRegisterAccessToken(SharedPreferences prefs) {
  if ((prefs.getString(kImpersonationLabelPrefKey) ?? '').isNotEmpty) return null;
  final access = prefs.getString('access_token');
  if (access == null || access.isEmpty) return null;
  return access;
}
