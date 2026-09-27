import 'dart:async';
import 'dart:math';

import 'package:http/http.dart' as http;

/// Mã chống trùng (idempotency key) gửi kèm thao tác quan trọng (tạo đơn, báo bếp,
/// tạo lệnh in). Gửi lại cùng mã khi mạng lỗi → server trả kết quả lần trước,
/// không tạo đơn / phiếu thứ hai.
abstract final class PosRequestId {
  static final Random _rng = Random.secure();

  /// 32 ký tự hex ngẫu nhiên.
  static String newId() {
    final b = StringBuffer();
    for (var i = 0; i < 16; i++) {
      b.write(_rng.nextInt(256).toRadixString(16).padLeft(2, '0'));
    }
    return b.toString();
  }

  /// Lỗi mạng (không nhận được phản hồi) — gửi lại cùng mã là an toàn.
  /// Không import dart:io (bản web): http bọc SocketException thành ClientException.
  static bool isNetworkError(Object e) {
    if (e is TimeoutException || e is http.ClientException) return true;
    final s = e.toString();
    return s.contains('SocketException') ||
        s.contains('Connection reset') ||
        s.contains('Connection closed') ||
        s.contains('Failed host lookup');
  }
}
