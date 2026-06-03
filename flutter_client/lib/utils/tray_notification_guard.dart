/// Tránh hiển thị 2 lần cùng một thông báo trên thanh hệ thống
/// (FCM khi nền + Flutter local khi SignalR reconnect).
class TrayNotificationGuard {
  TrayNotificationGuard._();

  static final Map<String, DateTime> _shown = {};
  static const Duration _window = Duration(minutes: 3);

  /// Trả về true nếu được phép hiện tray; false nếu đã hiện gần đây.
  static bool shouldShow(String? notificationId) {
    _purge();
    if (notificationId == null || notificationId.isEmpty) return true;
    final last = _shown[notificationId];
    if (last != null && DateTime.now().difference(last) < _window) {
      return false;
    }
    _shown[notificationId] = DateTime.now();
    return true;
  }

  static void _purge() {
    final now = DateTime.now();
    _shown.removeWhere((_, t) => now.difference(t) > _window);
  }
}
