/// Màn thu ngân đang mở → chỉ cho thông báo liên quan bán hàng hiện popup / thông báo hệ thống.
/// Các loại khác (chấm công, thiết bị, tin nhắn nội bộ, nhân sự…) vẫn vào chuông thông báo, không che màn hình bán.
class PosNotifyFocus {
  PosNotifyFocus._();

  static int _n = 0;

  static bool get active => _n > 0;

  static void enter() => _n++;

  static void leave() {
    if (_n > 0) _n--;
  }

  /// Không hiện lúc đang bán: thông tin nền (đơn bán xong của người khác, tồn thấp, hạn dùng).
  static const _quietPosEntities = {'possaleorder', 'posproduct', 'posreportexpiry'};

  /// `true` nếu thông báo cần hiện ngay cả khi đang ở màn thu ngân (đơn QR / online, đặt bàn, thanh toán, cảnh báo in…).
  static bool isRelevant({String? relatedEntityType, String? categoryCode}) {
    final e = (relatedEntityType ?? '').toLowerCase();
    final c = (categoryCode ?? '').toLowerCase();
    if (_quietPosEntities.contains(e)) return false;
    return c == 'pos' || e.startsWith('pos');
  }

  /// Rút gọn nội dung dài (thông báo hệ thống / popup) để không che màn hình.
  static String clip(String s, {int max = 110}) {
    final t = s.replaceAll(RegExp(r'\s+'), ' ').trim();
    return t.length <= max ? t : '${t.substring(0, max - 1).trimRight()}…';
  }
}
