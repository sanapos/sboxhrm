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

  /// `what` nhận: resync, users, clock, resetmark, reboot, factory_reset.
  /// `factory_reset` xóa WiFi/IP máy chấm công, đặt gateway về AP mode
  /// (sóng SBOX-Gateway-XXXX, mật khẩu cấu hình sbox12345) và reboot.
  /// Sau khi reset cần cấu hình WiFi lại qua web 192.168.4.1.
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

  // ------------------------------------------------------------------
  // Device API — nói chuyện với máy ZK qua gateway (LAN)
  // ------------------------------------------------------------------

  static const _deviceTimeout = Duration(seconds: 45);

  String _deviceErrorBody(http.Response res) {
    final body = utf8.decode(res.bodyBytes, allowMalformed: true).trim();
    if (body.isNotEmpty && body.length < 200) return body;
    return 'Thiết bị trả về mã ${res.statusCode}';
  }

  Future<List<ZkDeviceUser>> fetchDeviceUsers(String ip) async {
    final res = await http
        .get(_uri(ip, '/api/device/users'), headers: await _authHeaders(ip))
        .timeout(_deviceTimeout);
    _throwIfUnauthorized(res);
    if (res.statusCode != 200) {
      throw ZkGatewayException(_deviceErrorBody(res));
    }
    final decoded = jsonDecode(utf8.decode(res.bodyBytes));
    if (decoded is! List) {
      throw const ZkGatewayException('Danh sách nhân viên không đúng định dạng');
    }
    return [
      for (final e in decoded)
        if (e is Map)
          ZkDeviceUser.fromJson(e.cast<String, dynamic>()),
    ];
  }

  Future<void> saveDeviceUser(
    String ip, {
    required String pin,
    required String name,
    int privilege = 0,
    int card = 0,
  }) async {
    final res = await http
        .post(
          _uri(ip, '/api/device/users'),
          headers: await _authHeaders(ip, extra: {'Content-Type': 'application/json'}),
          body: jsonEncode({
            'pin': pin,
            'name': name,
            'privilege': privilege,
            'card': card,
          }),
        )
        .timeout(_deviceTimeout);
    _throwIfUnauthorized(res);
    if (res.statusCode != 200) {
      throw ZkGatewayException(_deviceErrorBody(res));
    }
  }

  Future<void> deleteDeviceUser(String ip, String pin) async {
    final res = await http
        .delete(
          _uri(ip, '/api/device/users', {'pin': pin}),
          headers: await _authHeaders(ip),
        )
        .timeout(_deviceTimeout);
    _throwIfUnauthorized(res);
    if (res.statusCode != 200) {
      throw ZkGatewayException(_deviceErrorBody(res));
    }
  }

  Future<ZkDeviceAttlogPage> fetchDeviceAttlog(String ip) async {
    final res = await http
        .get(_uri(ip, '/api/device/attlog'), headers: await _authHeaders(ip))
        .timeout(const Duration(seconds: 60));
    _throwIfUnauthorized(res);
    if (res.statusCode != 200) {
      throw ZkGatewayException(_deviceErrorBody(res));
    }
    final decoded = jsonDecode(utf8.decode(res.bodyBytes));
    if (decoded is! Map) {
      throw const ZkGatewayException('Dữ liệu chấm công không đúng định dạng');
    }
    return ZkDeviceAttlogPage.fromJson(decoded.cast<String, dynamic>());
  }

  Future<List<int>> downloadDeviceAttlogCsv(String ip) async {
    final res = await http
        .get(
          _uri(ip, '/api/device/attlog.csv'),
          headers: await _authHeaders(ip),
        )
        .timeout(const Duration(seconds: 90));
    _throwIfUnauthorized(res);
    if (res.statusCode != 200) {
      throw ZkGatewayException(_deviceErrorBody(res));
    }
    return res.bodyBytes;
  }

  Future<void> startDeviceEnroll(
    String ip, {
    required String pin,
    int fid = 0,
    bool overwrite = true,
  }) async {
    final res = await http
        .post(
          _uri(ip, '/api/device/enroll'),
          headers: await _authHeaders(ip, extra: {'Content-Type': 'application/json'}),
          body: jsonEncode({
            'pin': pin,
            'fid': fid,
            'overwrite': overwrite,
          }),
        )
        .timeout(timeout);
    _throwIfUnauthorized(res);
    if (res.statusCode != 200) {
      throw ZkGatewayException(_deviceErrorBody(res));
    }
  }

  Future<ZkDeviceEnrollStatus> fetchDeviceEnrollStatus(String ip) async {
    final json = await _getJson(ip, '/api/device/enroll');
    return ZkDeviceEnrollStatus.fromJson(json);
  }

  Future<void> deleteDeviceFinger(
    String ip, {
    required String pin,
    int? fid,
  }) async {
    final q = <String, String>{'pin': pin};
    if (fid != null) q['fid'] = '$fid';
    final res = await http
        .delete(
          _uri(ip, '/api/device/finger', q),
          headers: await _authHeaders(ip),
        )
        .timeout(_deviceTimeout);
    _throwIfUnauthorized(res);
    if (res.statusCode != 200) {
      throw ZkGatewayException(_deviceErrorBody(res));
    }
  }

  /// `action`: unlock | refresh | restart | clear_attlog | factory_reset
  ///
  /// - unlock: mở cửa khoảng `seconds` (mặc định 5).
  /// - refresh: REFRESHDATA trên máy ZK.
  /// - restart: RESTART máy chấm công.
  /// - clear_attlog: xóa toàn bộ log chấm công (giữ user + vân tay).
  /// - factory_reset: xóa SẠCH log + user + vân tay + face + thẻ
  ///   trên máy ZK (gọi CLEAR_DATA). Khác với reset ESP — WiFi/IP máy
  ///   không bị ảnh hưởng. Trả về thông báo từ gateway (text).
  Future<String> deviceControl(
    String ip, {
    required String action,
    int seconds = 5,
  }) async {
    final res = await http
        .post(
          _uri(ip, '/api/device/control'),
          headers: await _authHeaders(ip, extra: {'Content-Type': 'application/json'}),
          body: jsonEncode({
            'action': action,
            if (action == 'unlock') 'seconds': seconds,
          }),
        )
        .timeout(_deviceTimeout);
    _throwIfUnauthorized(res);
    if (res.statusCode != 200) {
      throw ZkGatewayException(_deviceErrorBody(res));
    }
    try {
      final decoded = jsonDecode(utf8.decode(res.bodyBytes));
      if (decoded is Map && decoded['message'] != null) {
        return decoded['message'].toString();
      }
    } catch (_) {}
    return 'OK';
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

    // Gộp an toàn khi nhiều mạch:
    // - Cùng IP LAN → cùng một mạch (mDNS stub + UDP/HTTP).
    // - Cùng serial nhưng IP LAN khác → GIỮ CẢ HAI (hai mạch cấu hình nhầm cùng máy).
    // - Serial chỉ dùng để nâng stub thiếu IP, không nuốt mạch thứ hai.
    void merge(ZkGatewayInfo info) {
      if (info.ip.isEmpty && info.host.isEmpty && info.serial.isEmpty) return;

      String? matchKey;
      for (final e in byKey.entries) {
        final prev = e.value;
        final sameIp = info.ip.isNotEmpty &&
            prev.ip.isNotEmpty &&
            info.ip == prev.ip;
        if (sameIp) {
          matchKey = e.key;
          break;
        }

        final sameSerial = info.serial.isNotEmpty &&
            prev.serial.isNotEmpty &&
            info.serial == prev.serial;
        if (!sameSerial) continue;

        final infoLan = _usableLanIp(info.ip);
        final prevLan = _usableLanIp(prev.ip);
        // Một bên chưa có IP LAN (stub) → gộp để bổ sung serial/status.
        if (!infoLan || !prevLan) {
          matchKey = e.key;
          break;
        }
        // Hai IP LAN khác + cùng serial → xung đột cấu hình, không gộp.
      }

      ZkGatewayInfo next = info;
      if (matchKey != null) {
        next = _richerGateway(byKey.remove(matchKey)!, info);
      }

      // Khóa theo IP khi có LAN; serial chỉ khi chưa biết IP (tránh che mạch khác).
      final key = _usableLanIp(next.ip)
          ? 'ip:${next.ip}'
          : (next.serial.isNotEmpty
              ? 's:${next.serial}'
              : (next.ip.isNotEmpty ? 'ip:${next.ip}' : 'h:${next.host}'));
      byKey[key] = next;
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
      if (info.ip.isNotEmpty && info.serial.isNotEmpty && !_isSoftApIp(info.ip)) {
        await rememberHost(info.ip);
      }
    }

    var list = byKey.values.toList();
    // SoftAP 192.168.4.1 chỉ dùng lúc cấu hình. Khi đã có gateway LAN thì bỏ thẻ AP.
    final hasLan = list.any((g) => !_isSoftApIp(g.ip) && g.ip.isNotEmpty);
    if (hasLan) {
      list = list.where((g) => !_isSoftApIp(g.ip)).toList();
    }
    list.sort((a, b) => a.displayName.compareTo(b.displayName));
    return list;
  }

  /// Phát hiện cấu hình xung đột khi nhiều mạch cùng chỗ.
  static List<String> conflictMessages(List<ZkGatewayInfo> list) {
    final msgs = <String>[];
    final bySerial = <String, List<ZkGatewayInfo>>{};
    final byDeviceIp = <String, List<ZkGatewayInfo>>{};

    for (final g in list) {
      if (_isSoftApIp(g.ip)) continue;
      if (g.serial.isNotEmpty) {
        bySerial.putIfAbsent(g.serial, () => []).add(g);
      }
      if (g.deviceIp.isNotEmpty) {
        byDeviceIp.putIfAbsent(g.deviceIp, () => []).add(g);
      }
    }

    for (final e in bySerial.entries) {
      final ips = e.value.map((g) => g.ip).where((ip) => ip.isNotEmpty).toSet();
      if (ips.length > 1) {
        msgs.add(
          'Cùng số seri máy ${e.key} trên ${ips.length} gateway '
          '(${ips.join(", ")}). Mỗi máy ZK chỉ nên gắn một mạch.',
        );
      }
    }
    for (final e in byDeviceIp.entries) {
      final gateways = e.value;
      if (gateways.length < 2) continue;
      // Tránh trùng message nếu đã báo cùng serial.
      final serials = gateways.map((g) => g.serial).where((s) => s.isNotEmpty).toSet();
      if (serials.length == 1 &&
          msgs.any((m) => m.contains('số seri máy ${serials.first}'))) {
        continue;
      }
      msgs.add(
        'Cùng IP máy chấm công ${e.key} trên ${gateways.length} gateway. '
        'Kiểm tra lại cấu hình IP máy.',
      );
    }
    return msgs;
  }

  /// IP SoftAP cấu hình — không phải địa chỉ quản lý trên WiFi nhà.
  static bool _isSoftApIp(String ip) {
    final t = ip.trim();
    return t == apAddress || t.startsWith('192.168.4.');
  }

  static bool _usableLanIp(String ip) {
    if (ip.isEmpty || _isSoftApIp(ip)) return false;
    if (ip == '0.0.0.0') return false;
    return true;
  }

  /// Chọn bản giàu thông tin hơn khi gộp kết quả dò tìm trùng thiết bị.
  static ZkGatewayInfo _richerGateway(ZkGatewayInfo a, ZkGatewayInfo b) {
    final aScore = (a.serial.isNotEmpty ? 4 : 0) +
        (a.version.isNotEmpty ? 2 : 0) +
        (a.name.isNotEmpty ? 1 : 0) +
        (_usableLanIp(a.ip) ? 2 : 0) +
        (a.apSsid.isNotEmpty ? 1 : 0) +
        (a.host.isNotEmpty ? 1 : 0);
    final bScore = (b.serial.isNotEmpty ? 4 : 0) +
        (b.version.isNotEmpty ? 2 : 0) +
        (b.name.isNotEmpty ? 1 : 0) +
        (_usableLanIp(b.ip) ? 2 : 0) +
        (b.apSsid.isNotEmpty ? 1 : 0) +
        (b.host.isNotEmpty ? 1 : 0);
    final rich = bScore >= aScore ? b : a;
    final other = identical(rich, b) ? a : b;
    final preferredIp = _usableLanIp(rich.ip)
        ? rich.ip
        : (_usableLanIp(other.ip) ? other.ip : (rich.ip.isNotEmpty ? rich.ip : other.ip));
    return ZkGatewayInfo(
      ip: preferredIp,
      host: rich.host.isNotEmpty ? rich.host : other.host,
      name: rich.name.isNotEmpty ? rich.name : other.name,
      serial: rich.serial.isNotEmpty ? rich.serial : other.serial,
      deviceIp: rich.deviceIp.isNotEmpty ? rich.deviceIp : other.deviceIp,
      version: rich.version.isNotEmpty ? rich.version : other.version,
      appSha: rich.appSha.isNotEmpty ? rich.appSha : other.appSha,
      apSsid: rich.apSsid.isNotEmpty ? rich.apSsid : other.apSsid,
      provisioned: rich.provisioned || other.provisioned,
      wifiConnected: rich.wifiConnected || other.wifiConnected,
      deviceOnline: rich.deviceOnline || other.deviceOnline,
      serverOnline: rich.serverOnline || other.serverOnline,
      locked: rich.locked || other.locked,
    );
  }

  Future<List<ZkGatewayInfo>> _discoverViaKnownHttpHosts({
    required Duration scanFor,
  }) async {
    // Không luôn dò SoftAP: chỉ khi chưa nhớ host LAN (lúc đang cấu hình).
    // Không phụ thuộc sboxadms.local (trùng khi nhiều mạch) — chỉ fallback cuối.
    final remembered = await loadRememberedHosts();
    final hosts = <String>{
      ...remembered.where((h) => !_isSoftApIp(h)),
      if (remembered.isEmpty) apAddress,
    };

    // Chỉ resolve legacy sboxadms.local khi chưa nhớ IP nào (máy cũ / một mạch).
    // Nhiều mạch cùng LAN làm sboxadms.local không xác định.
    if (!kIsWeb && remembered.isEmpty) {
      try {
        final resolved = await resolveMdnsHost(
          portalHost,
          timeout: Duration(
            milliseconds: (scanFor.inMilliseconds * 0.6).round().clamp(2000, 5000),
          ),
        );
        hosts.addAll(resolved);
      } catch (_) {}
      hosts.add(portalHost);
    }

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
      final raw = prefs.getStringList(_knownHostsKey) ?? const <String>[];
      return raw
          .where((h) => h.trim().isNotEmpty && !_isSoftApIp(h) && h != '0.0.0.0')
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Future<void> rememberHost(String host) async {
    final h = host.trim();
    if (h.isEmpty || h == portalHost || _isSoftApIp(h) || h == '0.0.0.0') return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = (prefs.getStringList(_knownHostsKey) ?? <String>[])
          .where((e) => !_isSoftApIp(e) && e != '0.0.0.0')
          .toList();
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
      // Ưu tiên UDP/mDNS service — không phụ thuộc hostname trùng sboxadms.local.
      final list = await discover(duration: const Duration(seconds: 4));
      for (final info in list) {
        final matches =
            serial == null || serial.isEmpty || info.serial == serial;
        if (matches && info.wifiConnected && info.ip.isNotEmpty) {
          await rememberHost(info.ip);
          return info;
        }
      }

      // Fallback: host đã nhớ + SoftAP.
      for (final host in [...await loadRememberedHosts(), apAddress]) {
        try {
          final viaHost =
              await fetchInfo(host).timeout(const Duration(seconds: 2));
          final matches =
              serial == null || serial.isEmpty || viaHost.serial == serial;
          if (matches && viaHost.wifiConnected) {
            if (viaHost.ip.isNotEmpty) await rememberHost(viaHost.ip);
            return viaHost;
          }
        } catch (_) {}
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
