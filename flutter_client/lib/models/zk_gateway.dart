int _toInt(dynamic v) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse(v?.toString() ?? '') ?? 0;
}

/// Thẻ tên của một gateway ESP32, dựng được từ gói dò tìm UDP hoặc `/api/info`.
///
/// Cả hai nguồn trả cùng bộ khoá nên chỉ cần một lớp: gói UDP đủ để vẽ danh
/// sách ngay mà chưa phải gọi HTTP tới từng thiết bị.
class ZkGatewayInfo {
  const ZkGatewayInfo({
    required this.ip,
    this.host = '',
    this.name = '',
    this.serial = '',
    this.deviceIp = '',
    this.version = '',
    this.appSha = '',
    this.apSsid = '',
    this.provisioned = false,
    this.wifiConnected = true,
    this.deviceOnline = false,
    this.serverOnline = false,
    this.locked = false,
  });

  final String ip;
  final String host;

  /// Tên gợi nhớ người dùng đặt; rỗng thì hiển thị theo số seri hoặc IP.
  final String name;

  /// Số seri của máy chấm công mà gateway này đang phục vụ.
  final String serial;
  final String deviceIp;
  final String version;

  /// 16 hex đầu SHA app partition (từ `/api/info`).
  final String appSha;
  final String apSsid;

  final bool provisioned;
  final bool wifiConnected;
  final bool deviceOnline;
  final bool serverOnline;
  final bool locked;

  static const productId = 'sbox-zk-gateway';

  bool get isHealthy => provisioned && deviceOnline && serverOnline;

  /// Nhãn hiển thị: ưu tiên tên tự đặt, rồi số seri, cuối cùng là IP.
  String get displayName {
    if (name.trim().isNotEmpty) return name.trim();
    if (serial.isNotEmpty) return 'Gateway $serial';
    return 'Gateway $ip';
  }

  factory ZkGatewayInfo.fromJson(Map<String, dynamic> json, {String? fallbackIp}) {
    return ZkGatewayInfo(
      ip: (json['ip']?.toString().isNotEmpty ?? false)
          ? json['ip'].toString()
          : (fallbackIp ?? ''),
      host: json['host']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      serial: json['serial']?.toString() ?? '',
      deviceIp: json['deviceIp']?.toString() ?? '',
      version: json['version']?.toString() ?? '',
      appSha: json['appSha']?.toString() ?? '',
      apSsid: json['apSsid']?.toString() ?? '',
      provisioned: json['provisioned'] == true,
      wifiConnected: json['wifiConnected'] != false,
      deviceOnline: json['deviceOnline'] == true,
      serverOnline: json['serverOnline'] == true,
      locked: json['locked'] == true,
    );
  }

  ZkGatewayInfo copyWith({String? ip, String? name, bool? locked, String? version, String? appSha}) =>
      ZkGatewayInfo(
        ip: ip ?? this.ip,
        host: host,
        name: name ?? this.name,
        serial: serial,
        deviceIp: deviceIp,
        version: version ?? this.version,
        appSha: appSha ?? this.appSha,
        apSsid: apSsid,
        provisioned: provisioned,
        wifiConnected: wifiConnected,
        deviceOnline: deviceOnline,
        serverOnline: serverOnline,
        locked: locked ?? this.locked,
      );
}

/// Trạng thái đầy đủ từ `/api/status`.
class ZkGatewayStatus {
  const ZkGatewayStatus({
    required this.wifiConnected,
    required this.wifiIp,
    required this.rssi,
    required this.apActive,
    required this.apSsid,
    required this.deviceOnline,
    required this.serial,
    required this.deviceFirmware,
    required this.devicePlatform,
    required this.users,
    required this.fingers,
    required this.records,
    required this.serverOnline,
    required this.uploadedTotal,
    required this.uploadedLast,
    required this.commands,
    required this.error,
    required this.uptimeSeconds,
    required this.freeHeap,
    required this.version,
    this.lastAutoClearYm = 0,
  });

  final bool wifiConnected;
  final String wifiIp;
  final int rssi;
  final bool apActive;
  final String apSsid;

  final bool deviceOnline;
  final String serial;
  final String deviceFirmware;
  final String devicePlatform;
  final int users;
  final int fingers;
  final int records;

  final bool serverOnline;
  final int uploadedTotal;
  final int uploadedLast;
  final int commands;
  final int lastAutoClearYm;

  final String error;
  final int uptimeSeconds;
  final int freeHeap;
  final String version;

  factory ZkGatewayStatus.fromJson(Map<String, dynamic> json) {
    final wifi = (json['wifi'] as Map?)?.cast<String, dynamic>() ?? {};
    final device = (json['device'] as Map?)?.cast<String, dynamic>() ?? {};
    final server = (json['server'] as Map?)?.cast<String, dynamic>() ?? {};
    final sync = (json['sync'] as Map?)?.cast<String, dynamic>() ?? {};

    return ZkGatewayStatus(
      wifiConnected: wifi['connected'] == true,
      wifiIp: wifi['ip']?.toString() ?? '',
      rssi: _toInt(wifi['rssi']),
      apActive: wifi['ap'] == true,
      apSsid: wifi['apSsid']?.toString() ?? '',
      deviceOnline: device['online'] == true,
      serial: device['serial']?.toString() ?? '',
      deviceFirmware: device['firmware']?.toString() ?? '',
      devicePlatform: device['platform']?.toString() ?? '',
      users: _toInt(device['users']),
      fingers: _toInt(device['fingers']),
      records: _toInt(device['records']),
      serverOnline: server['online'] == true,
      uploadedTotal: _toInt(sync['uploadedTotal']),
      uploadedLast: _toInt(sync['uploadedLast']),
      commands: _toInt(sync['commands']),
      lastAutoClearYm: _toInt(sync['lastAutoClearYm']),
      error: json['error']?.toString() ?? '',
      uptimeSeconds: _toInt(json['uptime']),
      freeHeap: _toInt(json['heap']),
      version: json['version']?.toString() ?? '',
    );
  }
}

/// Cấu hình đọc/ghi qua `/api/config`.
class ZkGatewayConfig {
  ZkGatewayConfig({
    this.gwName = '',
    this.wifiSsid = '',
    this.hasWifiPass = false,
    this.deviceIp = '',
    this.devicePort = 4370,
    this.commKey = 0,
    this.serverUrl = 'https://sboxhrm.com',
    this.snOverride = '',
    this.pollInterval = 10,
    this.attlogInterval = 30,
    this.backfillDays = 30,
    this.tzOffset = 7,
    this.syncClock = true,
    this.autoClearAttlog = false,
    this.autoClearDay = 1,
    this.autoClearHour = 2,
    this.autoClearMin = 0,
    this.lastAutoClearYm = 0,
  });

  String gwName;
  String wifiSsid;
  final bool hasWifiPass;
  String deviceIp;
  int devicePort;
  int commKey;
  String serverUrl;
  String snOverride;
  int pollInterval;
  int attlogInterval;
  int backfillDays;
  int tzOffset;
  bool syncClock;
  bool autoClearAttlog;
  int autoClearDay;
  int autoClearHour;
  int autoClearMin;
  final int lastAutoClearYm;

  factory ZkGatewayConfig.fromJson(Map<String, dynamic> json) {
    return ZkGatewayConfig(
      gwName: json['gwName']?.toString() ?? '',
      wifiSsid: json['wifiSsid']?.toString() ?? '',
      hasWifiPass: json['hasWifiPass'] == true,
      deviceIp: json['deviceIp']?.toString() ?? '',
      devicePort: _toInt(json['devicePort']) == 0 ? 4370 : _toInt(json['devicePort']),
      commKey: _toInt(json['commKey']),
      serverUrl: json['serverUrl']?.toString() ?? 'https://sboxhrm.com',
      snOverride: json['snOverride']?.toString() ?? '',
      pollInterval: _toInt(json['pollInterval']),
      attlogInterval: _toInt(json['attlogInterval']),
      backfillDays: _toInt(json['backfillDays']),
      tzOffset: _toInt(json['tzOffset']),
      syncClock: json['syncClock'] != false,
      autoClearAttlog: json['autoClearAttlog'] == true,
      autoClearDay: () {
        final d = _toInt(json['autoClearDay']);
        if (d < 1 || d > 28) return 1;
        return d;
      }(),
      autoClearHour: () {
        final h = _toInt(json['autoClearHour']);
        if (h < 0 || h > 23) return 2;
        return h;
      }(),
      autoClearMin: () {
        final m = _toInt(json['autoClearMin']);
        if (m < 0 || m > 59) return 0;
        return m;
      }(),
      lastAutoClearYm: _toInt(json['lastAutoClearYm']),
    );
  }

  /// Chỉ gửi những khoá cần đổi: firmware giữ nguyên các khoá không xuất hiện,
  /// nhờ vậy để trống mật khẩu WiFi sẽ không xoá mật khẩu đã lưu.
  Map<String, dynamic> toPayload({String? wifiPass}) {
    return {
      'gwName': gwName,
      'wifiSsid': wifiSsid,
      if (wifiPass != null && wifiPass.isNotEmpty) 'wifiPass': wifiPass,
      'deviceIp': deviceIp,
      'devicePort': devicePort,
      'commKey': commKey,
      // serverUrl cố định trong firmware — không gửi để tránh hiểu nhầm có thể đổi.
      'snOverride': snOverride,
      'pollInterval': pollInterval,
      'attlogInterval': attlogInterval,
      'backfillDays': backfillDays,
      'tzOffset': tzOffset,
      'syncClock': syncClock,
    };
  }

  Map<String, dynamic> toAutoClearPayload() {
    return {
      'autoClearAttlog': autoClearAttlog,
      'autoClearDay': autoClearDay.clamp(1, 28),
      'autoClearHour': autoClearHour.clamp(0, 23),
      'autoClearMin': autoClearMin.clamp(0, 59),
    };
  }
}

/// Một mạng WiFi mà gateway quét được (`/api/scan`).
class ZkWifiAp {
  const ZkWifiAp({required this.ssid, required this.rssi, required this.secure});

  final String ssid;
  final int rssi;
  final bool secure;

  /// 1..4 vạch, dùng vẽ cột tín hiệu.
  int get bars {
    if (rssi >= -55) return 4;
    if (rssi >= -67) return 3;
    if (rssi >= -78) return 2;
    return 1;
  }

  factory ZkWifiAp.fromJson(Map<String, dynamic> json) => ZkWifiAp(
        ssid: json['ssid']?.toString() ?? '',
        rssi: _toInt(json['rssi']),
        secure: json['secure'] != false,
      );
}
