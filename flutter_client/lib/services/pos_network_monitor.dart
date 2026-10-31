import 'dart:async';
import 'dart:convert';
import 'dart:io' show Socket;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/pos_device_identity.dart';
import '../utils/pos_local_printers_store.dart';
import '../utils/pos_thermal_printer_settings.dart';
import 'api_service.dart';
import 'pos_print_agent_service.dart';
import 'signalr_service.dart';

/// Đo mạng cửa hàng trên thiết bị POS → báo cáo «Mạng cửa hàng».
///
/// Hai phần tách riêng:
/// • Nhận biết mất mạng (thanh báo, bán offline) — luôn chạy nhưng KHÔNG tự hỏi máy chủ: dựa vào lệnh app
///   đang gọi sẵn và kết nối tức thời (realtime). Chỉ ping khi cả hai im lặng / realtime rớt, hoặc khi đang
///   mất mạng (để biết lúc có lại: 10s, sau 1 phút giãn 30s).
/// • Ghi theo dõi mạng cho báo cáo — mặc định TẮT; chỉ chạy khi bấm «Theo dõi mạng» (30 phút – 8 giờ, tự
///   tắt): ping 30s, đếm lệnh gọi lỗi, rớt realtime, thử cổng máy in LAN 2 phút / lần, sóng Wi-Fi. Gom khung
///   5 phút, gửi 5 phút / lần. Trước đây mọi máy mở màn bán hàng đều chạy cả ngày → hàng trăm máy hỏi máy chủ
///   liên tục dù không ai xem báo cáo.
class PosNetworkMonitor {
  PosNetworkMonitor._();
  static final PosNetworkMonitor instance = PosNetworkMonitor._();

  static const _pendingKey = 'pos_net_pending_v1';
  static const _recordKey = 'pos_net_record_until_v1';
  static const _maxPending = 864; // 3 ngày × 288 khung
  static const _pingEvery = Duration(seconds: 30);
  static const _printerEvery = Duration(minutes: 2);
  static const _wifiEvery = Duration(minutes: 1);
  static const _flushEvery = Duration(minutes: 5);
  /// Nhịp tự kiểm «còn nối máy chủ không» khi không ghi theo dõi (không gửi gì nếu app vẫn đang gọi được).
  static const _idleCheckEvery = Duration(seconds: 30);
  static const _idleQuietFor = Duration(seconds: 60);
  static const _probe = MethodChannel('sbox/network_probe');

  /// Ghi theo dõi mạng tới lúc này (null = tắt). Giữ qua lần mở lại app, tự hết hạn.
  final ValueNotifier<DateTime?> recordUntil = ValueNotifier<DateTime?>(null);
  bool get recording {
    final u = recordUntil.value;
    return u != null && DateTime.now().isBefore(u);
  }

  final _api = ApiService();
  final Map<int, _Bucket> _open = {};

  /// Còn gọi được máy chủ không (thanh báo mất mạng, bán offline). Ping lỗi hoặc 2 lệnh gọi lỗi kết nối
  /// liên tiếp → false; bất kỳ trả lời nào từ máy chủ → true.
  final ValueNotifier<bool> reachable = ValueNotifier<bool>(true);
  DateTime? lastOkAt;
  DateTime? offlineSince;
  int _connFails = 0;
  Timer? _fastPing;
  bool _fastPingSlow = false;

  /// Giả lập mất mạng (chủ quán thử quy trình bán offline) — tự tắt sau 30 phút.
  DateTime? _simulateUntil;
  bool get simulateOffline =>
      _simulateUntil != null && DateTime.now().isBefore(_simulateUntil!);
  static const _simulateKey = 'pos_net_simulate_until_v1';
  void setSimulateOffline(bool on) {
    _simulateUntil = on ? DateTime.now().add(const Duration(minutes: 30)) : null;
    // Giữ qua lần mở lại app (thử «tắt app lúc mất mạng») — vẫn tự hết sau 30 phút.
    unawaited(SharedPreferences.getInstance().then((p) => on
        ? p.setString(_simulateKey, _simulateUntil!.toIso8601String())
        : p.remove(_simulateKey)));
    if (on) {
      _markFail(force: true);
    } else {
      unawaited(_pingOnce());
    }
  }

  void _markOk() {
    if (simulateOffline) return;
    _connFails = 0;
    lastOkAt = DateTime.now();
    if (!reachable.value) {
      reachable.value = true;
      offlineSince = null;
      _fastPing?.cancel();
      _fastPing = null;
      _fastPingSlow = false;
    }
  }

  void _markFail({bool force = false}) {
    _connFails++;
    if (!force && _connFails < 2) return;
    if (reachable.value) {
      reachable.value = false;
      offlineSince ??= DateTime.now();
      // Mất mạng: ping dày hơn để biết có mạng lại sớm.
      _fastPing ??= Timer.periodic(const Duration(seconds: 10), (_) => unawaited(_pingOnce()));
    } else if (!_fastPingSlow &&
        offlineSince != null &&
        DateTime.now().difference(offlineSince!) > const Duration(minutes: 1)) {
      // Mất lâu (máy chủ bảo trì / đứt mạng): giãn 30s — hàng trăm máy ping 10s/lần dồn vào lúc máy chủ
      // vừa lên lại.
      _fastPingSlow = true;
      _fastPing?.cancel();
      _fastPing = Timer.periodic(const Duration(seconds: 30), (_) => unawaited(_pingOnce()));
    }
  }

  /// Bật ghi theo dõi mạng trên máy này trong [d] (bấm «Theo dõi mạng»).
  Future<void> startRecording(Duration d) async {
    recordUntil.value = DateTime.now().add(d);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_recordKey, recordUntil.value!.toIso8601String());
    } catch (_) {}
    // Mở báo cáo từ Thiết lập mà chưa vào màn bán hàng → chưa start.
    if (_started) {
      _startRecordTimers();
    } else {
      await start();
    }
  }

  /// Dừng ghi (bấm «Dừng» hoặc hết giờ) — gửi nốt số liệu đã đo.
  Future<void> stopRecording() async {
    recordUntil.value = null;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_recordKey);
    } catch (_) {}
    _stopRecordTimers();
    await flush();
  }

  void _startRecordTimers() {
    if (_pingTimer != null) return;
    _rtEverConnected = SignalRService().isConnected;
    _pingTimer = Timer.periodic(_pingEvery, (_) {
      if (!recording) {
        unawaited(stopRecording());
        return;
      }
      unawaited(_pingOnce());
    });
    unawaited(_pingOnce());
    if (!kIsWeb) {
      _printerTimer = Timer.periodic(_printerEvery, (_) => unawaited(_checkPrinters()));
      _wifiTimer = Timer.periodic(_wifiEvery, (_) => unawaited(_readWifi()));
      unawaited(_readWifi());
    }
    _flushTimer = Timer.periodic(_flushEvery, (_) => unawaited(flush()));
  }

  void _stopRecordTimers() {
    for (final t in [_pingTimer, _printerTimer, _wifiTimer, _flushTimer]) {
      t?.cancel();
    }
    _pingTimer = _printerTimer = _wifiTimer = _flushTimer = null;
    _rtDownSince = null;
  }

  /// Không ghi theo dõi: chỉ hỏi máy chủ khi app im lặng quá lâu mà realtime cũng không nối.
  void _idleCheck() {
    if (recording || simulateOffline || !reachable.value) return;
    final ok = lastOkAt;
    if (ok != null && DateTime.now().difference(ok) < _idleQuietFor) return;
    if (SignalRService().isConnected) {
      // Realtime đang nối = máy chủ còn trả lời — không cần gửi thêm yêu cầu.
      _markOk();
      return;
    }
    unawaited(_pingOnce());
  }

  static bool _isConnError(Object e) {
    final s = e.toString();
    return e is TimeoutException ||
        s.contains('SocketException') ||
        s.contains('ClientException') ||
        s.contains('Failed host lookup') ||
        s.contains('Connection') ||
        s.contains('XMLHttpRequest');
  }
  List<Map<String, dynamic>> _pending = [];
  bool _started = false;
  bool _flushing = false;
  Timer? _pingTimer;
  Timer? _printerTimer;
  Timer? _wifiTimer;
  Timer? _flushTimer;
  Timer? _idleTimer;
  StreamSubscription<bool>? _rtSub;
  DateTime? _rtDownSince;
  bool _rtEverConnected = false;
  String? _appVersion;

  static int _bucketKey(DateTime t) {
    final u = t.toUtc();
    return DateTime.utc(u.year, u.month, u.day, u.hour, u.minute ~/ 5 * 5)
            .millisecondsSinceEpoch ~/
        1000;
  }

  _Bucket get _cur => _open.putIfAbsent(_bucketKey(DateTime.now()), _Bucket.new);

  /// Gọi khi vào màn bán hàng (gọi nhiều lần không sao).
  Future<void> start() async {
    if (_started) return;
    _started = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final sim = DateTime.tryParse(prefs.getString(_simulateKey) ?? '');
      if (sim != null && DateTime.now().isBefore(sim)) {
        _simulateUntil = sim;
        _markFail(force: true);
      }
      final raw = prefs.getString(_pendingKey);
      if (raw != null && raw.isNotEmpty) {
        _pending = (jsonDecode(raw) as List)
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      }
      final rec = DateTime.tryParse(prefs.getString(_recordKey) ?? '');
      if (rec != null && DateTime.now().isBefore(rec)) {
        recordUntil.value = rec;
      } else if (rec != null) {
        await prefs.remove(_recordKey);
      }
    } catch (_) {}
    try {
      _appVersion = (await PackageInfo.fromPlatform()).version;
    } catch (_) {}

    ApiService.onApiResponse = (status) {
      if (recording) {
        final b = _cur;
        b.apiCalls++;
        if (status >= 500 || status == 0) b.apiErrors++;
      }
      if (status > 0 && status < 500) _markOk();
    };
    ApiService.onApiFailure = (e) {
      if (recording) {
        final b = _cur;
        b.apiCalls++;
        b.apiErrors++;
        if (e is TimeoutException) b.apiTimeouts++;
      }
      if (_isConnError(e)) _markFail();
    };
    _rtSub = SignalRService().onConnectionStateChanged.listen(_onRealtime);
    // Mới mở app chưa kịp nối realtime không tính là rớt — chỉ đếm sau khi đã nối được.
    _rtEverConnected = SignalRService().isConnected;

    _idleTimer = Timer.periodic(_idleCheckEvery, (_) => _idleCheck());
    // Mở app: biết ngay còn nối máy chủ không (1 lần).
    unawaited(_pingOnce());
    if (recording) _startRecordTimers();
    // Số liệu ghi dở lần trước (tắt app giữa chừng) — gửi nốt.
    if (_pending.isNotEmpty) unawaited(flush());
  }

  /// Dừng đo (đăng xuất). Khung chưa gửi giữ trong máy, lần sau gửi tiếp.
  Future<void> stop() async {
    if (!_started) return;
    _started = false;
    _stopRecordTimers();
    _idleTimer?.cancel();
    _fastPing?.cancel();
    _idleTimer = null;
    _fastPing = null;
    _fastPingSlow = false;
    await _rtSub?.cancel();
    _rtSub = null;
    ApiService.onApiResponse = null;
    ApiService.onApiFailure = null;
    _closeOldBuckets();
    await _savePending();
  }

  void _onRealtime(bool connected) {
    final now = DateTime.now();
    if (connected) {
      _rtEverConnected = true;
      _markOk();
    } else if (_rtEverConnected && reachable.value && !recording) {
      // Realtime vừa rớt: hỏi máy chủ 1 lần để thanh báo / bán offline biết sớm.
      unawaited(_pingOnce());
    }
    if (!recording) return;
    if (!connected && !_rtEverConnected) return;
    if (!connected) {
      _cur.rtDisconnects++;
      _rtDownSince ??= now;
    } else if (_rtDownSince != null) {
      final sec = now.difference(_rtDownSince!).inSeconds;
      _cur.rtDownSec = (_cur.rtDownSec + sec).clamp(0, 300);
      _rtDownSince = null;
    }
  }

  Future<void> _pingOnce() async {
    if (simulateOffline) {
      _markFail(force: true);
      return;
    }
    final ms = await _api.pingNetwork();
    if (!recording) {
      if (ms == null) {
        _markFail(force: true);
      } else {
        _markOk();
      }
      return;
    }
    final b = _cur;
    b.pingSent++;
    if (ms == null) {
      b.pingFailed++;
      b.offlineSec = (b.offlineSec + _pingEvery.inSeconds).clamp(0, 300);
      _markFail(force: true);
    } else {
      b.pings.add(ms);
      _markOk();
    }
    // Realtime đang rớt: cộng dồn mỗi lượt (cả khi chưa nối lại).
    if (_rtDownSince != null) {
      b.rtDownSec = (b.rtDownSec + _pingEvery.inSeconds).clamp(0, 300);
    }
    _closeOldBuckets();
  }

  Future<void> _checkPrinters() async {
    List<PosLocalPrinterProfile> list;
    try {
      list = (await PosLocalPrintersStore.instance.loadAll())
          .where((p) =>
              p.enabled &&
              p.connectionType == PosThermalConnectionType.lan &&
              (p.lanHost ?? '').trim().isNotEmpty)
          .toList();
    } catch (_) {
      return;
    }
    for (final p in list) {
      final sw = Stopwatch()..start();
      final b = _cur;
      b.printerChecks++;
      try {
        final s = await Socket.connect(p.lanHost!.trim(), p.lanPort,
            timeout: const Duration(seconds: 3));
        s.destroy();
        b.printerMs.add(sw.elapsedMilliseconds);
      } catch (_) {
        b.printerFailed++;
      }
    }
  }

  Future<void> _readWifi() async {
    try {
      final m = await _probe.invokeMapMethod<String, dynamic>('info');
      if (m == null) return;
      final b = _cur;
      b.connType = m['transport']?.toString();
      final rssi = (m['rssi'] as num?)?.toInt();
      if (rssi != null) b.rssi.add(rssi);
    } catch (_) {}
  }

  void _closeOldBuckets() {
    final curKey = _bucketKey(DateTime.now());
    final old = _open.keys.where((k) => k < curKey).toList()..sort();
    for (final k in old) {
      final b = _open.remove(k)!;
      _pending.add(b.toJson(k));
    }
    if (_pending.length > _maxPending) {
      _pending = _pending.sublist(_pending.length - _maxPending);
    }
    if (old.isNotEmpty) unawaited(_savePending());
  }

  Future<void> _savePending() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_pendingKey, jsonEncode(_pending));
    } catch (_) {}
  }

  /// Gửi các khung đã đóng (gửi lại cùng khung = ghi đè trên server, không nhân đôi).
  Future<void> flush() async {
    _closeOldBuckets();
    if (_flushing || _pending.isEmpty) return;
    _flushing = true;
    try {
      final dev = await PosDeviceIdentity.get();
      while (_pending.isNotEmpty) {
        final batch = _pending.take(200).toList();
        final res = await _api.postNetworkSamples({
          'deviceId': dev.id,
          'deviceName': dev.name,
          'platform': kIsWeb ? 'web' : defaultTargetPlatform.name,
          'appVersion': _appVersion,
          'isAgent': !kIsWeb && PosPrintAgentService.instance.isRunning,
          'samples': batch,
        });
        if (res['isSuccess'] != true) break;
        _pending.removeRange(0, batch.length);
      }
      await _savePending();
    } catch (e) {
      debugPrint('PosNetworkMonitor flush: $e');
    } finally {
      _flushing = false;
    }
  }

  /// «Kiểm tra mạng ngay» (~30–60s): ping liên tục, tải lên / về, gọi đồng thời (giả lập giờ đông),
  /// realtime, máy in LAN. [onProgress] nhận 0..1 + mô tả bước.
  Future<NetworkQuickTestResult> runQuickTest({
    void Function(double progress, String step)? onProgress,
    int pings = 20,
    int burst = 12,
  }) async {
    final lat = <int>[];
    var failed = 0;
    for (var i = 0; i < pings; i++) {
      onProgress?.call(i / (pings + 4), 'Đo độ trễ ($i/$pings)');
      final ms = await _api.pingNetwork(timeout: const Duration(seconds: 6));
      if (ms == null) {
        failed++;
      } else {
        lat.add(ms);
      }
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    onProgress?.call((pings + 1) / (pings + 4), 'Đo tốc độ tải về');
    final down = await _api.networkDownloadKbps();
    onProgress?.call((pings + 2) / (pings + 4), 'Đo tốc độ tải lên');
    final up = await _api.networkUploadKbps();
    onProgress?.call((pings + 3) / (pings + 4), 'Giả lập giờ đông ($burst yêu cầu cùng lúc)');
    final burstRes = await Future.wait(
        List.generate(burst, (_) => _api.pingNetwork(timeout: const Duration(seconds: 10))));
    final burstOk = burstRes.whereType<int>().toList();
    final printers = <({String name, int? ms})>[];
    if (!kIsWeb) {
      try {
        for (final p in (await PosLocalPrintersStore.instance.loadAll()).where((p) =>
            p.enabled &&
            p.connectionType == PosThermalConnectionType.lan &&
            (p.lanHost ?? '').trim().isNotEmpty)) {
          final sw = Stopwatch()..start();
          int? ms;
          try {
            final s = await Socket.connect(p.lanHost!.trim(), p.lanPort,
                timeout: const Duration(seconds: 3));
            s.destroy();
            ms = sw.elapsedMilliseconds;
          } catch (_) {}
          printers.add((name: p.name, ms: ms));
        }
      } catch (_) {}
    }
    Map<String, dynamic>? wifi;
    if (!kIsWeb) {
      try {
        wifi = await _probe.invokeMapMethod<String, dynamic>('info');
      } catch (_) {}
    }
    onProgress?.call(1, 'Xong');
    return NetworkQuickTestResult(
      pingSent: pings,
      pingFailed: failed,
      latencies: lat,
      downKbps: down,
      upKbps: up,
      burstSent: burst,
      burstOk: burstOk.length,
      burstLatencies: burstOk,
      realtimeConnected: SignalRService().isConnected,
      printers: printers,
      connType: wifi?['transport']?.toString(),
      wifiRssi: (wifi?['rssi'] as num?)?.toInt(),
    );
  }
}

class _Bucket {
  int apiCalls = 0, apiErrors = 0, apiTimeouts = 0;
  int pingSent = 0, pingFailed = 0, offlineSec = 0;
  int rtDisconnects = 0, rtDownSec = 0;
  int printerChecks = 0, printerFailed = 0;
  final pings = <int>[];
  final printerMs = <int>[];
  final rssi = <int>[];
  String? connType;

  static int? _pct(List<int> v, double p) {
    if (v.isEmpty) return null;
    final a = [...v]..sort();
    final i = ((p * a.length).ceil() - 1).clamp(0, a.length - 1);
    return a[i];
  }

  Map<String, dynamic> toJson(int key) => {
        'bucketStart': DateTime.fromMillisecondsSinceEpoch(key * 1000, isUtc: true).toIso8601String(),
        'connType': connType ?? (kIsWeb ? 'web' : null),
        'wifiRssi': rssi.isEmpty ? null : (rssi.reduce((a, b) => a + b) / rssi.length).round(),
        'apiCalls': apiCalls,
        'apiErrors': apiErrors,
        'apiTimeouts': apiTimeouts,
        'pingSent': pingSent,
        'pingFailed': pingFailed,
        'pingP50Ms': _pct(pings, 0.5),
        'pingP95Ms': _pct(pings, 0.95),
        'pingMaxMs': pings.isEmpty ? null : pings.reduce((a, b) => a > b ? a : b),
        'offlineSec': offlineSec,
        'realtimeDisconnects': rtDisconnects,
        'realtimeDownSec': rtDownSec,
        'printerChecks': printerChecks,
        'printerFailed': printerFailed,
        'printerAvgMs': printerMs.isEmpty
            ? null
            : (printerMs.reduce((a, b) => a + b) / printerMs.length).round(),
      };
}

/// Kết quả «Kiểm tra mạng ngay» + kết luận / lời khuyên ngay trên máy.
class NetworkQuickTestResult {
  NetworkQuickTestResult({
    required this.pingSent,
    required this.pingFailed,
    required this.latencies,
    required this.downKbps,
    required this.upKbps,
    required this.burstSent,
    required this.burstOk,
    required this.burstLatencies,
    required this.realtimeConnected,
    required this.printers,
    this.connType,
    this.wifiRssi,
  });

  final int pingSent;
  final int pingFailed;
  final List<int> latencies;
  final double? downKbps;
  final double? upKbps;
  final int burstSent;
  final int burstOk;
  final List<int> burstLatencies;
  final bool realtimeConnected;
  final List<({String name, int? ms})> printers;
  final String? connType;
  final int? wifiRssi;

  static int? _pct(List<int> v, double p) => _Bucket._pct(v, p);

  int? get p50 => _pct(latencies, 0.5);
  int? get p95 => _pct(latencies, 0.95);
  int? get burstP95 => _pct(burstLatencies, 0.95);
  double get failPct => pingSent == 0 ? 0 : 100 * pingFailed / pingSent;

  /// green / yellow / red
  String get verdict {
    if (failPct > 5 || burstOk < burstSent || (p95 ?? 99999) > 2000 || !realtimeConnected) return 'red';
    if (failPct > 0 ||
        (p95 ?? 0) > 800 ||
        (burstP95 ?? 0) > 2000 ||
        (wifiRssi != null && wifiRssi! <= -70) ||
        printers.any((p) => p.ms == null)) {
      return 'yellow';
    }
    return 'green';
  }

  List<String> get advice {
    final out = <String>[];
    if (failPct > 0) {
      out.add('Có $pingFailed/$pingSent lần không gọi được máy chủ — kiểm tra router / đường truyền Internet.');
    }
    if ((p95 ?? 0) > 800) out.add('Độ trễ cao ($p95 ms) — order / báo bếp sẽ chậm. Kiểm tra gói Internet, khởi động lại router.');
    if (burstOk < burstSent || (burstP95 ?? 0) > 2000) {
      out.add('Nhiều yêu cầu cùng lúc bị chậm / lỗi — router dễ quá tải giờ đông. Tách Wi-Fi riêng cho máy POS, giới hạn Wi-Fi khách.');
    }
    if (wifiRssi != null && wifiRssi! <= -70) {
      out.add('Sóng Wi-Fi yếu ($wifiRssi dBm) — đặt máy gần router / bộ phát hoặc cắm dây LAN.');
    }
    for (final p in printers.where((p) => p.ms == null)) {
      out.add('Không kết nối được máy in «${p.name}» — kiểm tra nguồn / dây mạng; đặt IP cố định cho máy in (router hay đổi IP).');
    }
    if (!realtimeConnected) out.add('Mất kết nối tức thời (realtime) — bàn / phiếu cập nhật chậm. Thoát vào lại app.');
    if (connType == 'mobile') out.add('Máy đang dùng 4G — nên dùng Wi-Fi / dây LAN của quán cho ổn định.');
    if (out.isEmpty) out.add('Mạng tốt — dùng order / in qua mạng được.');
    return out;
  }
}
