import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/zk_gateway.dart';
import 'zk_gateway_discovery.dart';

/// Nói chuyện trực tiếp với gateway ESP32 trong mạng nội bộ.
///
/// Không đi qua sboxhrm.com: lúc cài đặt lần đầu điện thoại đang nối vào điểm
/// phát của chính ESP (192.168.4.1) nên chưa có đường ra Internet, và khi quản
/// lý thì gọi thẳng IP LAN vẫn nhanh hơn.
class ZkGatewayClient {
  ZkGatewayClient({this.timeout = const Duration(seconds: 6)});

  final Duration timeout;

  /// Địa chỉ mặc định của ESP khi đang ở chế độ điểm phát cấu hình.
  static const apAddress = '192.168.4.1';

  /// Cổng và chuỗi hỏi phải khớp `discovery.h` trong firmware.
  static const _discoveryPort = 51820;
  static const _discoveryProbe = 'SBOX_DISCOVER';

  Uri _uri(String ip, String path, [Map<String, String>? query]) =>
      Uri.http(ip, path, query);

  Future<Map<String, dynamic>> _getJson(String ip, String path) async {
    final res = await http.get(_uri(ip, path)).timeout(timeout);
    if (res.statusCode != 200) {
      throw ZkGatewayException('Thiết bị trả về mã ${res.statusCode}');
    }
    final decoded = jsonDecode(utf8.decode(res.bodyBytes));
    if (decoded is! Map) {
      throw const ZkGatewayException('Dữ liệu trả về không đúng định dạng');
    }
    return decoded.cast<String, dynamic>();
  }

  /// Xác nhận đầu bên kia đúng là gateway SBOX chứ không phải thiết bị khác
  /// tình cờ mở cổng 80.
  Future<ZkGatewayInfo> fetchInfo(String ip) async {
    final json = await _getJson(ip, '/api/info');
    if (json['product'] != ZkGatewayInfo.productId) {
      throw const ZkGatewayException('Địa chỉ này không phải gateway SBOX');
    }
    return ZkGatewayInfo.fromJson(json, fallbackIp: ip);
  }

  Future<ZkGatewayStatus> fetchStatus(String ip) async =>
      ZkGatewayStatus.fromJson(await _getJson(ip, '/api/status'));

  Future<ZkGatewayConfig> fetchConfig(String ip) async =>
      ZkGatewayConfig.fromJson(await _getJson(ip, '/api/config'));

  /// Quét WiFi bằng chính sóng của ESP: danh sách này mới phản ánh đúng những
  /// mạng 2.4GHz mà nó bắt được, khác với danh sách điện thoại nhìn thấy.
  Future<List<ZkWifiAp>> scanWifi(String ip) async {
    final res = await http
        .get(_uri(ip, '/api/scan'))
        .timeout(const Duration(seconds: 20));
    if (res.statusCode != 200) {
      throw ZkGatewayException('Quét WiFi thất bại (mã ${res.statusCode})');
    }
    final decoded = jsonDecode(utf8.decode(res.bodyBytes));
    if (decoded is! List) return const [];

    final seen = <String>{};
    final list = <ZkWifiAp>[];
    for (final item in decoded) {
      if (item is! Map) continue;
      final ap = ZkWifiAp.fromJson(item.cast<String, dynamic>());
      if (ap.ssid.isEmpty || !seen.add(ap.ssid)) continue;
      list.add(ap);
    }
    list.sort((a, b) => b.rssi.compareTo(a.rssi));
    return list;
  }

  Future<void> saveConfig(String ip, Map<String, dynamic> payload) async {
    final res = await http
        .post(
          _uri(ip, '/api/config'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(payload),
        )
        .timeout(timeout);
    if (res.statusCode != 200) {
      throw ZkGatewayException('Lưu cấu hình thất bại (mã ${res.statusCode})');
    }
  }

  /// `what` nhận: resync, users, clock, resetmark, reboot.
  Future<void> runAction(String ip, String what) async {
    final res = await http
        .post(_uri(ip, '/api/action', {'do': what}))
        .timeout(timeout);
    if (res.statusCode != 200) {
      throw ZkGatewayException('Không thực hiện được (mã ${res.statusCode})');
    }
  }

  Future<void> uploadFirmware(String ip, List<int> bytes) async {
    final res = await http
        .post(
          _uri(ip, '/api/ota'),
          headers: {'Content-Type': 'application/octet-stream'},
          body: bytes,
        )
        .timeout(const Duration(minutes: 3));
    if (res.statusCode != 200) {
      throw ZkGatewayException('Nạp firmware thất bại (mã ${res.statusCode})');
    }
  }

  /// Dò mọi gateway trong cùng lớp mạng bằng quảng bá UDP.
  ///
  /// Dùng UDP thay vì mDNS vì rất nhiều router chặn multicast giữa các client
  /// (tính năng "AP isolation"), lúc đó mDNS im lặng còn broadcast vẫn tới.
  Future<List<ZkGatewayInfo>> discover({
    Duration duration = const Duration(seconds: 4),
  }) {
    return discoverGateways(
      duration: duration,
      probe: _discoveryProbe,
      port: _discoveryPort,
    );
  }

  /// Chờ tới khi gateway nối được WiFi nhà và đăng ký xong với máy chủ.
  ///
  /// Dùng sau khi lưu cấu hình: ESP rời điểm phát nên phải hỏi lại qua IP mới,
  /// và IP đó chỉ biết được nhờ dò tìm.
  Future<ZkGatewayInfo?> waitUntilOnline({
    String? serial,
    Duration duration = const Duration(seconds: 75),
  }) async {
    final deadline = DateTime.now().add(duration);
    while (DateTime.now().isBefore(deadline)) {
      final list = await discover(duration: const Duration(seconds: 3));
      for (final info in list) {
        final matches = serial == null || serial.isEmpty || info.serial == serial;
        if (matches && info.wifiConnected && info.ip.isNotEmpty) {
          return info;
        }
      }
      await Future.delayed(const Duration(seconds: 2));
    }
    return null;
  }
}

class ZkGatewayException implements Exception {
  const ZkGatewayException(this.message);
  final String message;

  @override
  String toString() => message;
}
