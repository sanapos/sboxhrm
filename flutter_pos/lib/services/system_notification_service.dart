/// Thông báo khay hệ thống (tray) cho POS Android 6.
///
/// `flutter_pos` không dùng `flutter_local_notifications` (không có trong pubspec,
/// bản tương thích Flutter 3.22 / minSdk 23) — POS A6 báo bằng overlay + loa
/// (PosQrOrderVoiceAlert). Giữ API mà màn bán hàng / thông báo gọi tới.
class SystemNotificationService {
  static final SystemNotificationService _instance =
      SystemNotificationService._internal();
  factory SystemNotificationService() => _instance;
  SystemNotificationService._internal();

  /// Không có thông báo khay → không có gì để xóa.
  Future<void> cancelAll() async {}
}
