/// Cân điện tử nối trực tiếp máy bán hàng (RS232 / USB-COM): đọc khối lượng cho «Cân & in tem» và màn Bán hàng.
///
/// - App Windows: cổng COM (Win32) — cân RS232 qua cáp USB-Serial cũng hiện thành COMx.
/// - Trình duyệt Chrome / Edge (máy tính): Web Serial — lần đầu bấm «Chọn cổng cân» để cấp quyền.
/// - Điện thoại / máy Android: chưa hỗ trợ (dùng mã vạch cân).
///
/// Cấu hình lưu riêng từng máy (SharedPreferences) — mỗi quầy một cân.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'pos_scale_transport.dart';
import 'pos_scale_transport_stub.dart'
    if (dart.library.html) 'pos_scale_transport_web.dart'
    if (dart.library.ffi) 'pos_scale_transport_win.dart';

/// Một lần đọc cân: khối lượng (kg) + ổn định (số không nhảy).
class PosScaleReading {
  const PosScaleReading({required this.kg, required this.stable, this.raw = ''});
  final double kg;
  final bool stable;
  final String raw;
}

/// Lệnh hỏi khối lượng gửi định kỳ (cân không tự gửi liên tục).
enum PosScalePoll {
  none('', 'Không — cân tự gửi liên tục'),
  w('W', 'Gửi «W» (CAS, Toledo, nhiều cân Trung Quốc)'),
  p('P', 'Gửi «P»'),
  r('R', 'Gửi «R»'),
  enq('\x05', 'Gửi ENQ (0x05) — DIGI, một số cân Nhật');

  const PosScalePoll(this.command, this.label);
  final String command;
  final String label;

  static PosScalePoll parse(String? v) =>
      PosScalePoll.values.firstWhere((e) => e.name == v, orElse: () => PosScalePoll.none);
}

/// Cấu hình cân của máy này.
class PosScaleDeviceSettings {
  const PosScaleDeviceSettings({
    this.enabled = false,
    this.port = '',
    this.baudRate = 9600,
    this.dataBits = 8,
    this.parity = 'none',
    this.stopBits = 1,
    this.poll = PosScalePoll.none,
    this.unitWhenMissing = 'kg',
    this.autoWeighOnSell = true,
    this.webUsbVendorId,
    this.webUsbProductId,
  });

  final bool enabled;
  /// Windows: tên cổng (COM3). Web: bỏ trống (dùng cổng đã cấp quyền).
  final String port;
  final int baudRate;
  final int dataBits;
  /// none / even / odd
  final String parity;
  final int stopBits;
  final PosScalePoll poll;
  /// Đơn vị khi dữ liệu cân không ghi đơn vị (kg / g).
  final String unitWhenMissing;
  /// Màn bán: chọn hàng bán theo kg / gram / lạng → lấy luôn khối lượng đang ổn định trên cân.
  final bool autoWeighOnSell;
  final int? webUsbVendorId;
  final int? webUsbProductId;

  static const _key = 'pos_scale_device_v1';

  PosScaleDeviceSettings copyWith({
    bool? enabled,
    String? port,
    int? baudRate,
    int? dataBits,
    String? parity,
    int? stopBits,
    PosScalePoll? poll,
    String? unitWhenMissing,
    bool? autoWeighOnSell,
    int? webUsbVendorId,
    int? webUsbProductId,
  }) =>
      PosScaleDeviceSettings(
        enabled: enabled ?? this.enabled,
        port: port ?? this.port,
        baudRate: baudRate ?? this.baudRate,
        dataBits: dataBits ?? this.dataBits,
        parity: parity ?? this.parity,
        stopBits: stopBits ?? this.stopBits,
        poll: poll ?? this.poll,
        unitWhenMissing: unitWhenMissing ?? this.unitWhenMissing,
        autoWeighOnSell: autoWeighOnSell ?? this.autoWeighOnSell,
        webUsbVendorId: webUsbVendorId ?? this.webUsbVendorId,
        webUsbProductId: webUsbProductId ?? this.webUsbProductId,
      );

  Map<String, dynamic> toJson() => {
        'enabled': enabled,
        'port': port,
        'baudRate': baudRate,
        'dataBits': dataBits,
        'parity': parity,
        'stopBits': stopBits,
        'poll': poll.name,
        'unitWhenMissing': unitWhenMissing,
        'autoWeighOnSell': autoWeighOnSell,
        if (webUsbVendorId != null) 'webUsbVendorId': webUsbVendorId,
        if (webUsbProductId != null) 'webUsbProductId': webUsbProductId,
      };

  factory PosScaleDeviceSettings.fromJson(Map<String, dynamic> j) => PosScaleDeviceSettings(
        enabled: j['enabled'] == true,
        port: '${j['port'] ?? ''}',
        baudRate: (j['baudRate'] as num?)?.toInt() ?? 9600,
        dataBits: (j['dataBits'] as num?)?.toInt() ?? 8,
        parity: '${j['parity'] ?? 'none'}',
        stopBits: (j['stopBits'] as num?)?.toInt() ?? 1,
        poll: PosScalePoll.parse(j['poll']?.toString()),
        unitWhenMissing: j['unitWhenMissing'] == 'g' ? 'g' : 'kg',
        autoWeighOnSell: j['autoWeighOnSell'] != false,
        webUsbVendorId: (j['webUsbVendorId'] as num?)?.toInt(),
        webUsbProductId: (j['webUsbProductId'] as num?)?.toInt(),
      );

  static Future<PosScaleDeviceSettings> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw == null || raw.isEmpty) return const PosScaleDeviceSettings();
      return PosScaleDeviceSettings.fromJson(Map<String, dynamic>.from(jsonDecode(raw) as Map));
    } catch (_) {
      return const PosScaleDeviceSettings();
    }
  }

  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(toJson()));
  }
}

/// Tách khung dữ liệu cân thành số kg. Hỗ trợ các dạng phổ biến:
/// «ST,GS,+  0.456kg» (CAS / A&D / nhiều cân TQ), «US,GS,…» (chưa ổn định), «   0.456 kg», «456 g»,
/// «=654.0000» (Yaohua XK3190 gửi liên tục, số đảo ngược), «OL» (quá tải → bỏ).
class PosScaleFrameParser {
  PosScaleFrameParser({this.unitWhenMissing = 'kg'});

  final String unitWhenMissing;
  final _pending = StringBuffer();

  static final _num = RegExp(r'([-+]?)\s*(\d+(?:[.,]\d+)?)\s*(KG|LB|G)?', caseSensitive: false);

  /// Nạp byte mới, trả về các lần đọc tách được (khung kết thúc bằng CR / LF / ETX / '=' mới).
  List<PosScaleReading> feed(List<int> bytes) {
    final out = <PosScaleReading>[];
    for (final b in bytes) {
      final isEnd = b == 0x0D || b == 0x0A || b == 0x03;
      final isYaohuaStart = b == 0x3D; // '=': đầu khung Yaohua
      if (isEnd || (isYaohuaStart && _pending.isNotEmpty)) {
        final r = parseLine(_pending.toString(), unitWhenMissing: unitWhenMissing);
        if (r != null) out.add(r);
        _pending.clear();
        if (isEnd) continue;
      }
      if (b == 0x02) continue; // STX
      if (b >= 0x20 && b < 0x7F) _pending.writeCharCode(b);
      // Khung không có ký tự kết thúc: chặn đệm phình vô hạn.
      if (_pending.length > 64) {
        final r = parseLine(_pending.toString(), unitWhenMissing: unitWhenMissing);
        if (r != null) out.add(r);
        _pending.clear();
      }
    }
    // Yaohua «=xxxx.xxx» không có ký tự kết thúc: khung đủ 8 ký tự thì đọc luôn.
    final p = _pending.toString();
    if (p.startsWith('=') && p.length >= 8) {
      final r = parseLine(p, unitWhenMissing: unitWhenMissing);
      if (r != null) out.add(r);
      _pending.clear();
    }
    return out;
  }

  static PosScaleReading? parseLine(String line, {String unitWhenMissing = 'kg'}) {
    var s = line.trim();
    if (s.isEmpty) return null;
    final up = s.toUpperCase();
    if (up.contains('OL') && !RegExp(r'\d').hasMatch(up)) return null;
    if (up.startsWith('=')) {
      // Yaohua: «=654.0000» → đảo ngược «0000.456» → 0,456 kg.
      final rev = s.substring(1).split('').reversed.join().trim();
      final v = double.tryParse(rev.replaceAll(',', '.'));
      if (v == null) return null;
      return PosScaleReading(kg: _round(unitWhenMissing == 'g' ? v / 1000 : v), stable: true, raw: s);
    }
    // US = Unstable, MOTION / M = đang dao động.
    final unstable = up.startsWith('US') || up.contains(',US') || up.contains('MOTION') || up.startsWith('M ');
    final matches = _num.allMatches(s).where((m) => m.group(2) != null).toList();
    if (matches.isEmpty) return null;
    // Ưu tiên số có đơn vị, rồi số có phần thập phân, rồi số cuối dòng.
    final m = matches.lastWhere((x) => x.group(3) != null,
        orElse: () => matches.lastWhere((x) => x.group(2)!.contains(RegExp(r'[.,]')), orElse: () => matches.last));
    var v = double.parse(m.group(2)!.replaceAll(',', '.'));
    if (m.group(1) == '-') v = -v;
    final unit = (m.group(3) ?? unitWhenMissing).toUpperCase();
    final kg = switch (unit) {
      'G' => v / 1000,
      'LB' => v * 0.45359237,
      _ => v,
    };
    return PosScaleReading(kg: _round(kg), stable: !unstable, raw: s);
  }

  static double _round(double v) => (v * 100000).round() / 100000;
}

/// Bộ đọc cân của máy (một kết nối cho cả ứng dụng).
class PosScaleReader extends ChangeNotifier {
  PosScaleReader._();
  static final instance = PosScaleReader._();

  final PosScaleTransport _transport = createPosScaleTransport();
  PosScaleDeviceSettings settings = const PosScaleDeviceSettings();
  bool connected = false;
  bool connecting = false;
  String? error;
  PosScaleReading? _last;
  DateTime? _lastAt;
  final _recent = <double>[];
  PosScaleFrameParser _parser = PosScaleFrameParser();
  Timer? _pollTimer;
  bool _loaded = false;
  final _stream = StreamController<PosScaleReading>.broadcast();

  bool get supported => _transport.supported;
  String get unsupportedReason => _transport.unsupportedReason;
  bool get isWeb => _transport.isWeb;
  String get kind => _transport.kind;
  Stream<PosScaleReading> get readings => _stream.stream;

  /// Lần đọc còn mới (≤ 2 giây) — cân mất tín hiệu thì null.
  PosScaleReading? get current {
    final at = _lastAt;
    if (_last == null || at == null || DateTime.now().difference(at) > const Duration(seconds: 2)) return null;
    return _last;
  }

  /// Khối lượng đang ổn định và > 0 (kg).
  double? get stableKg {
    final c = current;
    return c != null && c.stable && c.kg > 0.0005 ? c.kg : null;
  }

  /// Nạp cấu hình, tự kết nối nếu đã bật (gọi khi mở màn bán / hộp cân).
  Future<void> ensureStarted() async {
    if (!_loaded) {
      _loaded = true;
      settings = await PosScaleDeviceSettings.load();
    }
    if (settings.enabled && supported && !connected && !connecting) {
      await connect(silent: true);
    }
  }

  Future<List<String>> listPorts() => _transport.listPorts();

  /// Web: hộp chọn cổng của trình duyệt (phải gọi từ thao tác bấm nút).
  Future<({int? vendorId, int? productId})?> requestWebPort() => _transport.requestPort();

  Future<void> updateSettings(PosScaleDeviceSettings next, {bool reconnect = true}) async {
    settings = next;
    _loaded = true;
    await next.save();
    if (reconnect) {
      await disconnect();
      if (next.enabled) await connect();
    }
    notifyListeners();
  }

  Future<bool> connect({bool silent = false}) async {
    if (!supported) {
      error = unsupportedReason;
      notifyListeners();
      return false;
    }
    connecting = true;
    error = null;
    notifyListeners();
    _parser = PosScaleFrameParser(unitWhenMissing: settings.unitWhenMissing);
    try {
      await _transport.open(settings, _onBytes, (e) {
        error = e;
        connected = false;
        _pollTimer?.cancel();
        notifyListeners();
      });
      connected = true;
      _startPolling();
    } catch (e) {
      connected = false;
      error = '$e'.replaceFirst('Exception: ', '');
      if (!silent) debugPrint('PosScaleReader.connect: $e');
    }
    connecting = false;
    notifyListeners();
    return connected;
  }

  Future<void> disconnect() async {
    _pollTimer?.cancel();
    _pollTimer = null;
    try {
      await _transport.close();
    } catch (_) {}
    connected = false;
    _last = null;
    _recent.clear();
    notifyListeners();
  }

  void _startPolling() {
    _pollTimer?.cancel();
    final cmd = settings.poll.command;
    if (cmd.isEmpty) return;
    _pollTimer = Timer.periodic(const Duration(milliseconds: 400), (_) {
      if (!connected) return;
      unawaited(_transport.write([...ascii.encode(cmd), if (cmd.length == 1 && cmd != '\x05') 0x0D, if (cmd.length == 1 && cmd != '\x05') 0x0A]));
    });
  }

  void _onBytes(List<int> bytes) {
    for (final r in _parser.feed(bytes)) {
      // Cân gửi liên tục không có cờ ổn định: 3 lần liên tiếp cùng số (±1 g) = ổn định.
      _recent.add(r.kg);
      if (_recent.length > 3) _recent.removeAt(0);
      final steady = _recent.length == 3 &&
          _recent.map((v) => (v - r.kg).abs()).reduce(math.max) <= 0.001;
      final reading = PosScaleReading(kg: r.kg, stable: r.stable && steady, raw: r.raw);
      final changed = _last == null || _last!.kg != reading.kg || _last!.stable != reading.stable;
      _last = reading;
      _lastAt = DateTime.now();
      _stream.add(reading);
      if (changed) notifyListeners();
    }
  }

  /// Chờ khối lượng ổn định > 0 (tối đa [timeout]). Null nếu không có cân / không ổn định.
  Future<double?> waitStableKg({Duration timeout = const Duration(seconds: 3)}) async {
    final now = stableKg;
    if (now != null) return now;
    if (!connected) return null;
    try {
      final r = await readings.firstWhere((r) => r.stable && r.kg > 0.0005).timeout(timeout);
      return r.kg;
    } catch (_) {
      return null;
    }
  }
}
