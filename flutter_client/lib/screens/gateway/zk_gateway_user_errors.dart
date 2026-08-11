import '../../models/zk_gateway.dart';
import '../../services/zk_gateway_client.dart';

/// Thông báo lỗi gateway kèm hướng dẫn xử lý cho người dùng cửa hàng.
class ZkGatewayUserError {
  const ZkGatewayUserError({required this.title, required this.message});

  final String title;
  final String message;

  /// Map exception → tiêu đề + hướng dẫn ngắn (tiếng Việt).
  static ZkGatewayUserError from(
    Object error, {
    String fallbackTitle = 'Không kết nối được gateway',
  }) {
    if (error is ZkGatewayAuthException) {
      return const ZkGatewayUserError(
        title: 'Gateway đang khóa',
        message:
            'Cần mật khẩu quản trị.\n\n'
            '• Nhập mật khẩu đã đặt khi khóa cấu hình.\n'
            '• Quên mật khẩu: nối điện thoại vào sóng SBOX-Gateway-XXXX '
            '(mật khẩu sbox12345), mở lại app và chọn Đặt lại mật khẩu.',
      );
    }

    final raw = error is ZkGatewayException
        ? error.message
        : error.toString().replaceFirst('Exception: ', '');
    final lower = raw.toLowerCase();

    if (lower.contains('timeout') ||
        lower.contains('timed out') ||
        lower.contains('time out')) {
      return ZkGatewayUserError(
        title: fallbackTitle,
        message:
            'Gateway không trả lời kịp.\n\n'
            '$connectionChecklist\n\n'
            'Chi tiết: $raw',
      );
    }

    if (lower.contains('socket') ||
        lower.contains('connection refused') ||
        lower.contains('connection reset') ||
        lower.contains('network is unreachable') ||
        lower.contains('failed host lookup') ||
        lower.contains('no address') ||
        lower.contains('clientexception') ||
        lower.contains('không kết nối') ||
        lower.contains('os error')) {
      return ZkGatewayUserError(
        title: fallbackTitle,
        message:
            'Điện thoại không tới được địa chỉ gateway.\n\n'
            '$connectionChecklist\n\n'
            'Chi tiết: $raw',
      );
    }

    if (lower.contains('không phải gateway') ||
        lower.contains('product')) {
      return ZkGatewayUserError(
        title: 'Sai thiết bị',
        message:
            'Địa chỉ này không phải gateway SBOX.\n\n'
            '• Quay lại danh sách và bấm Dò tìm lại.\n'
            '• Kiểm tra IP trên nhãn / trang web sboxadms.local.',
      );
    }

    return ZkGatewayUserError(
      title: fallbackTitle,
      message: '$raw\n\n$connectionChecklist',
    );
  }

  static const connectionChecklist =
      'Cách xử lý:\n'
      '1. Điện thoại cùng WiFi với gateway (không dùng 4G).\n'
      '2. Gateway còn điện, đèn mạng bình thường.\n'
      '3. Quay lại danh sách → Dò tìm lại (IP có thể đã đổi).\n'
      '4. Thử mở http://sboxadms.local hoặc IP gateway trên trình duyệt cùng WiFi.\n'
      '5. Vẫn lỗi: nhờ kỹ thuật mở trang cấu hình web trên máy tính cùng mạng.';

  /// Gợi ý khi status đã có nhưng một nhánh offline.
  static String? statusHint(ZkGatewayStatus s) {
    if (!s.wifiConnected) {
      return 'Mất WiFi: cấu hình lại WiFi nhà trên gateway, '
          'hoặc nối điện thoại vào sóng SBOX-Gateway để cài lại.';
    }
    if (!s.deviceOnline) {
      return 'Mất máy chấm công: kiểm tra máy còn điện, cùng mạng LAN, '
          'đúng IP trong «Cấu hình WiFi / máy». Comm Key phải khớp máy.';
    }
    if (!s.serverOnline) {
      return 'Mất máy chủ: gateway cần Internet tới sboxhrm.com. '
          'Kiểm tra WiFi nhà có mạng ra ngoài; thử Đồng bộ lại sau vài phút.';
    }
    return null;
  }
}
