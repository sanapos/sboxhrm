import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/zk_gateway.dart';
import 'zk_gateway_discovery.dart';
import 'zk_gateway_mdns.dart';

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

  /// Hostname mDNS cố định của trang web cấu hình (sau khi gateway đã vào WiFi nhà).
  static const portalHost = 'sboxadms.local';

  /// URL trang web cấu hình khi đã cùng WiFi với gateway.
  static String get portalUrl => 'http://$portalHost';

  /// URL trang web khi điện thoại đang nối sóng AP của gateway.
  static String get apPortalUrl => 'http://$apAddress';

  /// URL trang web theo IP LAN (khi biết địa chỉ cụ thể).
  static String portalUrlForIp(String ip) => 'http://$ip';

  /// Cổng và chuỗi hỏi phải khớp `discovery.h` trong firmware.
  static const _discoveryPort = 51820;
  static const _discoveryProbe = 'SBOX_DISCOVER';
  static const _knownHostsKey = 'zk_gw_known_hosts';

  static final Map<String, String> _passByKey = {};

  Uri _uri(String ip, String path, [Map<String, String>? query]) =>
      Uri.http(ip, path, query);

  String _passKey(String ipOrSerial) => 'zk_gw_pass_$ipOrSerial';

  Future<String?> getSavedPassword({String? serial, String? ip}) async {
    if (serial != null && serial.isNotEmpty && _passByKey.containsKey(serial)) {
      return _passByKey[serial];
    }
    if (ip != null && ip.isNotEmpty && _passByKey.containsKey(ip)) {
      return _passByKey[ip];
    }
    final prefs = await SharedPreferences.getInstance();
    if (serial != null && serial.isNotEmpty) {
      final p = prefs.getString(_passKey(serial));
      if (p != null && p.isNotEmpty) {
        _passByKey[serial] = p;
        return p;
      }
    }
    if (ip != null && ip.isNotEmpty) {
      final p = prefs.getString(_passKey(ip));
      if (p != null && p.isNotEmpty) {
        _passByKey[ip] = p;
        return p;
      }
    }
    return null;
  }

  Future<void> rememberPassword(String password, {String? serial, String? ip}) async {
    final prefs = await SharedPreferences.getInstance();
    if (serial != null && serial.isNotEmpty) {
      _passByKey[serial] = password;
      await prefs.setString(_passKey(serial), password);
    }
    if (ip != null && ip.isNotEmpty) {
      _passByKey[ip] = password;
      await prefs.setString(_passKey(ip), password);
    }
  }

  Future<void> forgetPassword({String? serial, String? ip}) async {
    final prefs = await SharedPreferences.getInstance();
    if (serial != null && serial.isNotEmpty) {
      _passByKey.remove(serial);
      await prefs.remove(_passKey(serial));
    }
    if (ip != null && ip.isNotEmpty) {
      _passByKey.remove(ip);
      await prefs.remove(_passKey(ip));
    }
  }

  Future<Map<String, String>> _authHeaders(String ip, {Map<String, String>? extra}) async {
    final headers = <String, String>{...?extra};
    final pass = await getSavedPassword(ip: ip);
    if (pass != null && pass.isNotEmpty) {
      final token = base64Encode(utf8.encode('admin:$pass'));
      headers['Authorization'] = 'Basic $token';
    }
    return headers;
  }

  void _throwIfUnauthorized(http.Response res) {
    if (res.statusCode == 401) {
      throw const ZkGatewayAuthException();
    }
  }

  Future<Map<String, dynamic>> _getJson(String ip, String path) async {
    final res = await http
        .get(_uri(ip, path), headers: await _authHeaders(ip))
        .timeout(timeout);
    _throwIfUnauthorized(res);
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
    // /api/info không yêu cầu mật khẩu.
    final res = await http.get(_uri(ip, '/api/info')).timeout(timeout);
    if (res.statusCode != 200) {
      throw ZkGatewayException('Thiết bị trả về mã ${res.statusCode}');
    }
    final decoded = jsonDecode(utf8.decode(res.bodyBytes));
    if (decoded is! Map) {
      throw const ZkGatewayException('Dữ liệu trả về không đúng định dạng');
    }
    final json = decoded.cast<String, dynamic>();
    if (json['product'] != ZkGatewayInfo.productId) {
      throw const ZkGatewayException('Địa chỉ này không phải gateway SBOX');
    }
    return ZkGatewayInfo.fromJson(json, fallbackIp: ip);
  }

  Future<ZkGatewayStatus> fetchStatus(String ip) async =>
      ZkGatewayStatus.fromJson(await _getJson(ip, '/api/status'));

  Future<ZkGatewayConfig> fetchConfig(String ip) async =>
      ZkGatewayConfig.fromJson(await _getJson(ip, '/api/config'));

  Future<Map<String, dynamic>> fetchAuthStatus(String ip) async {
    final res = await http.get(_uri(ip, '/api/auth/status')).timeout(timeout);
    if (res.statusCode != 200) {
      throw ZkGatewayException('Không đọc được trạng thái khóa');
    }
    final decoded = jsonDecode(utf8.decode(res.bodyBytes));
    if (decoded is! Map) {
      throw const ZkGatewayException('Dữ liệu trả về không đúng định dạng');
    }
    return decoded.cast<String, dynamic>();
  }

  Future<void> verifyPassword(String ip, String password) async {
    final token = base64Encode(utf8.encode('admin:$password'));
    final res = await http
        .get(
          _uri(ip, '/api/auth/check'),
          headers: {'Authorization': 'Basic $token'},
        )
        .timeout(timeout);
    if (res.statusCode == 401) {
      throw const ZkGatewayAuthException();
    }
    if (res.statusCode != 200) {
      throw ZkGatewayException('Xác thực thất bại (mã ${res.statusCode})');
    }
  }

  Future<void> setPortalPassword(
    String ip,
    String password, {
    String? oldPassword,
  }) async {
    final headers = await _authHeaders(ip, extra: {'Content-Type': 'application/json'});
    if (oldPassword != null && oldPassword.isNotEmpty) {
      headers['Authorization'] =
          'Basic ${base64Encode(utf8.encode('admin:$oldPassword'))}';
    }
    final res = await http
        .post(
          _uri(ip, '/api/auth/set'),
          headers: headers,
          body: jsonEncode({
            'password': password,
            if (oldPassword != null) 'oldPassword': oldPassword,
          }),
        )
        .timeout(timeout);
    _throwIfUnauthorized(res);
    if (res.statusCode != 200) {
      throw ZkGatewayException('Đặt mật khẩu thất bại (mã ${res.statusCode})');
    }
  }

  /// Xóa mật khẩu. Khi ESP đang phát AP cấu hình thì không cần mật khẩu cũ.
  Future<void> clearPortalPassword(String ip, {String? password}) async {
    final headers = <String, String>{'Content-Type': 'application/json'};
    if (password != null && password.isNotEmpty) {
      headers['Authorization'] =
          'Basic ${base64Encode(utf8.encode('admin:$password'))}';
    }
    final res = await http
        .post(_uri(ip, '/api/auth/clear'), headers: headers)
        .timeout(timeout);
    _throwIfUnauthorized(res);
    if (res.statusCode != 200) {
      throw ZkGatewayException('Xóa mật khẩu thất bại (mã ${res.statusCode})');
    }
  }

  /// Quét WiFi bằng chính sóng của ESP: danh sách này mới phản ánh đúng những
  /// mạng 2.4GHz mà nó bắt được, khác với danh sách điện thoại nhìn thấy.
  Future<List<ZkWifiAp>> scanWifi(String ip) async {
    final res = await http
        .get(_uri(ip, '/api/scan'), headers: await _authHeaders(ip))
        .timeout(const Duration(seconds: 20));
    _throwIfUnauthorized(res);
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
          headers: await _authHeaders(ip, extra: {'Content-Type': 'application/json'}),
          body: jsonEncode(payload),
        )
        .timeout(timeout);
    _throwIfUnauthorized(res);
    if (res.statusCode != 200) {
      throw ZkGatewayException('Lưu cấu hình thất bại (mã ${res.statusCode})');
    }
  }

  /// `what` nhận: resync, users, clock, resetmark, reboot.
  Future<void> runAction(String ip, String what) async {
    final res = await http
        .post(
          _uri(ip, '/api/action', {'do': what}),
          headers: await _authHeaders(ip),
        )
        .timeout(timeout);
    _throwIfUnauthorized(res);
    if (res.statusCode != 200) {
      throw ZkGatewayException('Không thực hiện được (mã ${res.statusCode})');
    }
  }

  Future<void> uploadFirmware(String ip, List<int> bytes) async {
    final res = await http
        .post(
          _uri(ip, '/api/ota'),
          headers: await _authHeaders(ip, extra: {'Content-Type': 'application/octet-stream'}),
          body: bytes,
        )
        .timeout(const Duration(minutes: 3));
    _throwIfUnauthorized(res);
    if (res.statusCode != 200) {
      throw ZkGatewayException('Nạp firmware thất bại (mã ${res.statusCode})');
    }
  }

  /// Dò gateway trong cùng WiFi: Bonjour/mDNS + HTTP host quen thuộc + UDP.
  ///
  /// Trên iPhone, mDNS là đường chính (cùng cơ chế Safari dùng cho
  /// `http://sboxadms.local`). UDP broadcast thường bị chặn; HTTP trực tiếp tới
  /// `.local` cũng hay fail vì Dart không resolve Bonjour ổn.
  Future<List<ZkGatewayInfo>> discover({
    Duration? duration,
  }) async {
    final scanFor = duration ??
        (defaultTargetPlatform == TargetPlatform.iOS
            ? const Duration(seconds: 7)
            : const Duration(seconds: 5));

    final byKey = <String, ZkGatewayInfo>{};

    void merge(ZkGatewayInfo info) {
      if (info.ip.isEmpty && info.host.isEmpty && info.serial.isEmpty) return;
      final key = info.serial.isNotEmpty
          ? 's:${info.serial}'
          : (info.ip.isNotEmpty ? 'ip:${info.ip}' : 'h:${info.host}');
      final prev = byKey[key];
      // Ưu tiên bản có đủ IP + serial.
      if (prev == null ||
          (info.ip.isNotEmpty && prev.ip.isEmpty) ||
          (info.serial.isNotEmpty && prev.serial.isEmpty)) {
        byKey[key] = info;
      }
    }

    final mdnsFuture = discoverGatewaysViaMdns(duration: scanFor);
    final httpFuture = _discoverViaKnownHttpHosts(scanFor: scanFor);
    final udpFuture = discoverGateways(
      duration: scanFor,
      probe: _discoveryProbe,
      port: _discoveryPort,
    );

    final parts = await Future.wait([mdnsFuture, httpFuture, udpFuture]);
    for (final list in parts) {
      for (final info in list) {
        merge(info);
      }
    }

    // mDNS có thể chỉ trả IP trần — xác nhận bằng /api/info và lưu lại.
    final bareIps = [
      for (final info in byKey.values)
        if (info.ip.isNotEmpty && info.serial.isEmpty && info.version.isEmpty)
          info.ip,
    ];
    if (bareIps.isNotEmpty) {
      await Future.wait(bareIps.map((ip) async {
        try {
          final full = await fetchInfo(ip).timeout(const Duration(seconds: 2));
          merge(full);
          await rememberHost(full.ip.isNotEmpty ? full.ip : ip);
        } catch (_) {}
      }));
    }

    for (final info in byKey.values) {
      if (info.ip.isNotEmpty && info.serial.isNotEmpty) {
        await rememberHost(info.ip);
      }
    }

    final list = byKey.values.toList();
    list.sort((a, b) => a.displayName.compareTo(b.displayName));
    return list;
  }

  Future<List<ZkGatewayInfo>> _discoverViaKnownHttpHosts({
    required Duration scanFor,
  }) async {
    final hosts = <String>{
      apAddress,
      ...await loadRememberedHosts(),
    };

    // Trên iOS: resolve sboxadms.local bằng Bonjour trước, rồi HTTP theo IP.
    // Gọi thẳng hostname `.local` qua package:http thường thất bại.
    if (!kIsWeb) {
      try {
        final resolved = await resolveMdnsHost(
          portalHost,
          timeout: Duration(
            milliseconds: (scanFor.inMilliseconds * 0.6).round().clamp(2000, 5000),
          ),
        );
        hosts.addAll(resolved);
      } catch (_) {}
    }

    // Vẫn thử hostname (Android / desktop đôi khi resolve được).
    hosts.add(portalHost);

    final found = <ZkGatewayInfo>[];
    await Future.wait(hosts.map((host) async {
      try {
        final info = await fetchInfo(host).timeout(const Duration(seconds: 2));
        found.add(info);
        if (info.ip.isNotEmpty) await rememberHost(info.ip);
      } catch (_) {}
    }));
    return found;
  }

  Future<List<String>> loadRememberedHosts() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getStringList(_knownHostsKey) ?? const [];
    } catch (_) {
      return const [];
    }
  }

  Future<void> rememberHost(String host) async {
    final h = host.trim();
    if (h.isEmpty || h == portalHost) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = prefs.getStringList(_knownHostsKey) ?? <String>[];
      if (list.contains(h)) {
        list.remove(h);
      }
      list.insert(0, h);
      while (list.length > 8) {
        list.removeLast();
      }
      await prefs.setStringList(_knownHostsKey, list);
    } catch (_) {}
  }

  Future<ZkGatewayInfo?> waitUntilOnline({
    String? serial,
    Duration duration = const Duration(seconds: 75),
  }) async {
    final deadline = DateTime.now().add(duration);
    while (DateTime.now().isBefore(deadline)) {
      try {
        final resolved = await resolveMdnsHost(
          portalHost,
          timeout: const Duration(seconds: 2),
        );
        for (final ip in [...resolved, portalHost]) {
          try {
            final viaHost =
                await fetchInfo(ip).timeout(const Duration(seconds: 2));
            final matches =
                serial == null || serial.isEmpty || viaHost.serial == serial;
            if (matches && viaHost.wifiConnected) {
              if (viaHost.ip.isNotEmpty) await rememberHost(viaHost.ip);
              return viaHost;
            }
          } catch (_) {}
        }
      } catch (_) {}

      final list = await discover(duration: const Duration(seconds: 4));
      for (final info in list) {
        final matches =
            serial == null || serial.isEmpty || info.serial == serial;
        if (matches && info.wifiConnected && info.ip.isNotEmpty) {
          await rememberHost(info.ip);
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

class ZkGatewayAuthException extends ZkGatewayException {
  const ZkGatewayAuthException()
      : super('Gateway đang khóa — cần mật khẩu quản trị');
}
