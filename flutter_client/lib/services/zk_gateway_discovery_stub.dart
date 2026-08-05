import '../models/zk_gateway.dart';

/// Bản thay thế cho web: trình duyệt không cho mở socket UDP nên không thể dò
/// tìm. Giao diện tự chuyển sang hướng dẫn dùng app điện thoại.
Future<List<ZkGatewayInfo>> discoverGateways({
  required Duration duration,
  required String probe,
  required int port,
}) async =>
    const [];
