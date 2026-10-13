import 'dart:async';
import 'dart:convert';
import 'dart:io' show Directory, File;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/pos_device_identity.dart';
import 'api_service.dart';
import 'pos_network_monitor.dart';

/// Một đơn bán lúc mất mạng (chờ / đã gửi lên máy chủ).
class OfflineSaleRecord {
  OfflineSaleRecord({
    required this.offlineNo,
    required this.seq,
    required this.createdAt,
    required this.draftOrderId,
    required this.body,
    required this.total,
    this.tableLabel,
    this.cashier,
    this.status = 'pending',
    this.error,
    this.serverOrderNo,
    this.syncedAt,
  });

  final String offlineNo;
  final int seq;
  final DateTime createdAt;
  /// Đơn bàn đã có trên máy chủ → hoàn tất đơn đó; null → tạo đơn mới.
  final String? draftOrderId;
  final Map<String, dynamic> body;
  final double total;
  final String? tableLabel;
  final String? cashier;
  /// pending / synced / error
  String status;
  String? error;
  String? serverOrderNo;
  DateTime? syncedAt;

  Map<String, dynamic> toJson() => {
        'offlineNo': offlineNo,
        'seq': seq,
        'createdAt': createdAt.toUtc().toIso8601String(),
        'draftOrderId': draftOrderId,
        'body': body,
        'total': total,
        'tableLabel': tableLabel,
        'cashier': cashier,
        'status': status,
        'error': error,
        'serverOrderNo': serverOrderNo,
        'syncedAt': syncedAt?.toUtc().toIso8601String(),
      };

  static OfflineSaleRecord? tryParse(dynamic raw) {
    if (raw is! Map) return null;
    final m = Map<String, dynamic>.from(raw);
    final no = m['offlineNo']?.toString() ?? '';
    final body = m['body'];
    if (no.isEmpty || body is! Map) return null;
    return OfflineSaleRecord(
      offlineNo: no,
      seq: (m['seq'] as num?)?.toInt() ?? 0,
      createdAt: DateTime.tryParse(m['createdAt']?.toString() ?? '') ?? DateTime.now(),
      draftOrderId: (m['draftOrderId']?.toString() ?? '').isEmpty ? null : m['draftOrderId'].toString(),
      body: Map<String, dynamic>.from(body),
      total: (m['total'] as num?)?.toDouble() ?? 0,
      tableLabel: m['tableLabel']?.toString(),
      cashier: m['cashier']?.toString(),
      status: m['status']?.toString() ?? 'pending',
      error: m['error']?.toString(),
      serverOrderNo: m['serverOrderNo']?.toString(),
      syncedAt: DateTime.tryParse(m['syncedAt']?.toString() ?? ''),
    );
  }
}

/// Bán offline (mất mạng) + giữ giỏ hàng chưa lưu được — bền qua «Xóa bộ nhớ đệm», có bản sao ngoài app.
///
/// Lưu ở: (1) file trong thư mục dữ liệu app (không bị «Xóa bộ nhớ đệm» xóa), ghi nguyên tử (tmp → đổi tên);
/// (2) bản sao Download/SBOX_POS (Android) — không mất khi «Xóa dữ liệu» app, Android ≤ 10 còn giữ khi gỡ app.
/// Chống gian lận: số hóa đơn offline cấp trước theo dải từ máy chủ + báo lần cài app (mã thiết bị không đổi
/// qua cài lại) → chủ quán thấy số đã dùng mà không về máy chủ / máy cài lại khi còn đơn chưa gửi.
class PosOfflineService {
  PosOfflineService._();
  static final PosOfflineService instance = PosOfflineService._();

  static const _channel = MethodChannel('sbox/offline_vault');
  static const _installKey = 'pos_install_id_v1';
  static const _prefsVaultKey = 'pos_offline_vault_v1_';
  static const _reserveWhenBelow = 15;
  static const _reserveCount = 50;

  final _api = ApiService();
  final ValueNotifier<int> pendingSales = ValueNotifier<int>(0);
  final ValueNotifier<int> errorSales = ValueNotifier<int>(0);
  final ValueNotifier<int> pendingCarts = ValueNotifier<int>(0);
  final ValueNotifier<bool> enabledNotifier = ValueNotifier<bool>(false);

  String? _storeId;
  Map<String, dynamic> _vault = {};
  bool _ready = false;
  bool _syncing = false;
  Timer? _syncTimer;
  Timer? _mirrorTimer;
  String? installId;
  String? deviceKey;
  String? _deviceName;
  bool restoredFromMirror = false;
  Completer<void>? _initDone;

  /// Màn bán hàng đặt: giỏ của tab đang mở do màn bán tự lưu (tránh tạo đơn tạm trùng).
  bool Function(String key)? isLiveCart;

  List<OfflineSaleRecord> get sales => ((_vault['sales'] as List?) ?? const [])
      .map(OfflineSaleRecord.tryParse)
      .whereType<OfflineSaleRecord>()
      .toList();

  bool get enabled => (_vault['settings'] as Map?)?['enabled'] == true;
  int get maxHours => ((_vault['settings'] as Map?)?['maxHours'] as num?)?.toInt() ?? 8;

  List<Map<String, int>> get _blocks => ((_vault['blocks'] as List?) ?? const [])
      .whereType<Map>()
      .map((b) => {
            'from': (b['from'] as num?)?.toInt() ?? 0,
            'to': (b['to'] as num?)?.toInt() ?? 0,
          })
      .where((b) => b['from']! > 0 && b['to']! >= b['from']!)
      .toList();

  int get _nextSeq => (_vault['nextSeq'] as num?)?.toInt() ?? 0;

  /// Số còn lại trong các dải đã cấp (từ số kế tiếp).
  int get remainingSerials {
    final next = _nextSeq;
    var n = 0;
    for (final b in _blocks) {
      final from = next > b['from']! ? next : b['from']!;
      if (from <= b['to']!) n += b['to']! - from + 1;
    }
    return n;
  }

  /// Lần cuối gọi được máy chủ (bán offline chỉ trong [maxHours] giờ kể từ lúc này).
  DateTime? get lastOnlineAt {
    final m = PosNetworkMonitor.instance.lastOkAt;
    if (m != null) return m;
    return DateTime.tryParse(_vault['lastOnlineAt']?.toString() ?? '');
  }

  /// Lỗi do mạng (không tới được / hết giờ) — khác máy chủ trả lỗi nghiệp vụ.
  static bool isConnectionFailure(Map<String, dynamic> res) {
    if (res['isSuccess'] == true) return false;
    final kind = res['errorKind']?.toString();
    return kind == 'network' || kind == 'timeout' || kind == 'unknown';
  }

  static String format(int seq) => 'OFF-${seq.toString().padLeft(6, '0')}';

  // ── Khởi tạo ───────────────────────────────────────────────────────────────

  Future<void> init(String? storeId) async {
    final sid = (storeId ?? '').trim();
    if (sid.isEmpty) return;
    if (_ready && _storeId == sid) return;
    if (_initDone != null && _storeId == sid) return _initDone!.future;
    _storeId = sid;
    _initDone = Completer<void>();
    try {
      await PosNetworkMonitor.instance.start();
      final prefs = await SharedPreferences.getInstance();
      installId = prefs.getString(_installKey);
      if (installId == null || installId!.isEmpty) {
        installId = _newId();
        await prefs.setString(_installKey, installId!);
      }
      deviceKey = await _readDeviceKey();
      _deviceName = (await PosDeviceIdentity.get()).name;
      _vault = await _load() ?? {};
      if (_vault.isEmpty) {
        // Mới cài / đã xóa dữ liệu app → thử lấy lại đơn offline từ bản sao ngoài app.
        final mirror = await _readMirror();
        if (mirror != null) {
          final pending = ((mirror['sales'] as List?) ?? const [])
              .map(OfflineSaleRecord.tryParse)
              .whereType<OfflineSaleRecord>()
              .where((r) => r.status != 'synced')
              .toList();
          if (pending.isNotEmpty || ((mirror['carts'] as Map?)?.isNotEmpty ?? false)) {
            _vault = {
              'sales': pending.map((e) => e.toJson()).toList(),
              'carts': mirror['carts'] ?? {},
              'restoredFrom': mirror['installId'],
            };
            restoredFromMirror = true;
            await _save();
          }
        }
      }
      _refreshCounters();
      _ready = true;
      PosNetworkMonitor.instance.reachable.addListener(_onReachable);
      _syncTimer ??= Timer.periodic(const Duration(minutes: 1), (_) => unawaited(syncAll()));
      unawaited(syncAll());
    } catch (e) {
      debugPrint('PosOfflineService.init: $e');
    } finally {
      _initDone?.complete();
    }
  }

  void _onReachable() {
    if (PosNetworkMonitor.instance.reachable.value) unawaited(syncAll());
  }

  static String _newId() {
    final r = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    final h = Object().hashCode.toRadixString(36);
    return 'i$r$h';
  }

  Future<String> _readDeviceKey() async {
    if (!kIsWeb) {
      try {
        final k = await _channel.invokeMethod<String>('deviceKey');
        if (k != null && k.trim().isNotEmpty) return 'a:${k.trim()}';
      } catch (_) {}
    }
    return 'd:${(await PosDeviceIdentity.get()).id}';
  }

  // ── Lưu trữ ────────────────────────────────────────────────────────────────

  String get _fileName => 'sbox-offline-${_storeId!.replaceAll('-', '').substring(0, 12)}.json';

  Future<File?> _file() async {
    if (kIsWeb) return null;
    final dir = await getApplicationSupportDirectory();
    final d = Directory('${dir.path}/sbox_offline');
    if (!await d.exists()) await d.create(recursive: true);
    return File('${d.path}/$_fileName');
  }

  Future<Map<String, dynamic>?> _load() async {
    try {
      if (kIsWeb) {
        final raw = (await SharedPreferences.getInstance()).getString(_prefsVaultKey + _storeId!);
        return raw == null ? null : Map<String, dynamic>.from(jsonDecode(raw) as Map);
      }
      final f = await _file();
      if (f == null || !await f.exists()) return null;
      return Map<String, dynamic>.from(jsonDecode(await f.readAsString()) as Map);
    } catch (e) {
      debugPrint('PosOfflineService load: $e');
      return null;
    }
  }

  /// Ghi nguyên tử. Trả false nếu không ghi được (đơn offline KHÔNG được bán khi không lưu được).
  Future<bool> _save() async {
    _vault['installId'] = installId;
    _vault['deviceKey'] = deviceKey;
    _vault['savedAt'] = DateTime.now().toUtc().toIso8601String();
    final text = jsonEncode(_vault);
    try {
      if (kIsWeb) {
        await (await SharedPreferences.getInstance()).setString(_prefsVaultKey + _storeId!, text);
      } else {
        final f = (await _file())!;
        final tmp = File('${f.path}.tmp');
        await tmp.writeAsString(text, flush: true);
        await tmp.rename(f.path);
      }
    } catch (e) {
      debugPrint('PosOfflineService save: $e');
      return false;
    }
    _refreshCounters();
    _scheduleMirror();
    return true;
  }

  void _scheduleMirror({bool now = false}) {
    if (kIsWeb) return;
    _mirrorTimer?.cancel();
    _mirrorTimer = Timer(now ? Duration.zero : const Duration(seconds: 2), () async {
      try {
        await _channel.invokeMethod<bool>('write', {'name': _fileName, 'content': jsonEncode(_vault)});
      } catch (_) {}
    });
  }

  Future<Map<String, dynamic>?> _readMirror() async {
    if (kIsWeb) return null;
    try {
      final txt = await _channel.invokeMethod<String>('read', {'name': _fileName});
      if (txt == null || txt.isEmpty) return null;
      return Map<String, dynamic>.from(jsonDecode(txt) as Map);
    } catch (_) {
      return null;
    }
  }

  void _refreshCounters() {
    final list = sales;
    pendingSales.value = list.where((r) => r.status == 'pending').length;
    errorSales.value = list.where((r) => r.status == 'error').length;
    pendingCarts.value = ((_vault['carts'] as Map?) ?? const {}).length;
    enabledNotifier.value = enabled;
  }

  // ── Máy chủ: lần cài app, cài đặt, dải số ──────────────────────────────────

  Future<void> _registerInstall() async {
    int? osInstall;
    if (!kIsWeb) {
      try {
        osInstall = await _channel.invokeMethod<int>('firstInstallTime');
      } catch (_) {}
    }
    String? version;
    try {
      version = (await PackageInfo.fromPlatform()).version;
    } catch (_) {}
    final usedSeq = sales.map((r) => r.seq).fold<int>(0, (a, b) => b > a ? b : a);
    final res = await _api.offlineRegisterInstall({
      'deviceKey': deviceKey,
      'installId': installId,
      'deviceName': _deviceName,
      'platform': kIsWeb ? 'web' : defaultTargetPlatform.name,
      'appVersion': version,
      if (osInstall != null)
        'osFirstInstallAt': DateTime.fromMillisecondsSinceEpoch(osInstall, isUtc: true).toIso8601String(),
      'pendingOfflineSales': pendingSales.value + errorSales.value,
      if (usedSeq > 0) 'lastOfflineSeq': usedSeq,
    });
    if (res['isSuccess'] != true || res['data'] is! Map) return;
    final d = Map<String, dynamic>.from(res['data'] as Map);
    _vault['settings'] = {
      'enabled': d['offlineEnabled'] == true,
      'maxHours': (d['maxHours'] as num?)?.toInt() ?? 8,
    };
    _vault['lastOnlineAt'] = DateTime.now().toUtc().toIso8601String();
    // Dải số của lần cài này (máy chủ là nguồn chuẩn — app mất dữ liệu vẫn biết dải đang dùng).
    final serverBlocks = ((d['blocks'] as List?) ?? const [])
        .whereType<Map>()
        .map((b) => {'from': (b['fromSeq'] as num?)?.toInt() ?? 0, 'to': (b['toSeq'] as num?)?.toInt() ?? 0})
        .toList();
    if (serverBlocks.isNotEmpty) _vault['blocks'] = serverBlocks;
    await _save();
    if (enabled && remainingSerials < _reserveWhenBelow) {
      final r = await _api.offlineReserveSerials({
        'deviceKey': deviceKey,
        'installId': installId,
        'deviceName': _deviceName,
        'count': _reserveCount,
      });
      if (r['isSuccess'] == true && r['data'] is Map) {
        final b = Map<String, dynamic>.from(r['data'] as Map);
        final blocks = [..._blocks, {'from': (b['fromSeq'] as num).toInt(), 'to': (b['toSeq'] as num).toInt()}];
        _vault['blocks'] = blocks;
        await _save();
      }
    }
  }

  // ── Bán offline ────────────────────────────────────────────────────────────

  /// Lý do không bán offline được (null = được).
  String? offlineSaleBlockedReason() {
    if (!_ready) return 'Chưa sẵn sàng bán offline';
    if (!enabled) return 'Cửa hàng chưa bật «Cho bán offline» (Thiết lập → Ngành hàng & cách bán)';
    if (remainingSerials <= 0) {
      return 'Máy chưa được cấp số hóa đơn offline — cần có mạng ít nhất 1 lần sau khi bật bán offline';
    }
    final last = lastOnlineAt;
    if (last != null && DateTime.now().difference(last).inHours >= maxHours) {
      return 'Đã mất mạng quá $maxHours giờ — không bán offline thêm (giới hạn của cửa hàng)';
    }
    return null;
  }

  /// Lấy số hóa đơn offline kế tiếp (ghi bền ngay — không cấp trùng kể cả khi app văng).
  Future<({String no, int seq})?> takeOfflineNo() async {
    var next = _nextSeq;
    for (final b in _blocks..sort((a, b) => a['from']!.compareTo(b['from']!))) {
      if (next < b['from']!) next = b['from']!;
      if (next <= b['to']!) {
        _vault['nextSeq'] = next + 1;
        if (!await _save()) return null;
        return (no: format(next), seq: next);
      }
    }
    return null;
  }

  /// Lưu đơn offline — PHẢI thành công trước khi in hóa đơn / xóa giỏ.
  Future<bool> addSale(OfflineSaleRecord r) async {
    final list = ((_vault['sales'] as List?) ?? []).toList()..add(r.toJson());
    _vault['sales'] = list;
    final ok = await _save();
    _scheduleMirror(now: true);
    return ok;
  }

  // ── Giỏ hàng chưa lưu được lên máy chủ ─────────────────────────────────────

  Future<void> saveCart(String key, Map<String, dynamic> data) async {
    if (!_ready) return;
    final carts = Map<String, dynamic>.from((_vault['carts'] as Map?) ?? {});
    carts[key] = {...data, 'savedAt': DateTime.now().toUtc().toIso8601String()};
    _vault['carts'] = carts;
    await _save();
  }

  Future<void> removeCart(String key) async {
    if (!_ready) return;
    final carts = Map<String, dynamic>.from((_vault['carts'] as Map?) ?? {});
    if (carts.remove(key) == null) return;
    _vault['carts'] = carts;
    await _save();
  }

  // ── Đồng bộ khi có mạng ────────────────────────────────────────────────────

  /// Gửi đơn offline theo thứ tự số, rồi giỏ hàng chưa lưu, rồi báo lần cài app (số đã dùng / còn chờ).
  Future<void> syncAll() async {
    if (!_ready || _syncing) return;
    if (!PosNetworkMonitor.instance.reachable.value) return;
    _syncing = true;
    try {
      var changed = false;
      final list = sales..sort((a, b) => a.seq.compareTo(b.seq));
      for (final r in list.where((r) => r.status == 'pending')) {
        final body = {
          ...r.body,
          'offlineNo': r.offlineNo,
          'offlineAt': r.createdAt.toUtc().toIso8601String(),
          'offlineDeviceKey': deviceKey,
        }..remove('expectedLockVersion');
        final res = r.draftOrderId != null
            ? await _api.updatePosSale(r.draftOrderId!, body)
            : await _api.createPosSale(body);
        if (res['isSuccess'] == true) {
          r.status = 'synced';
          r.error = null;
          r.syncedAt = DateTime.now();
          final d = res['data'];
          r.serverOrderNo = d is Map ? d['orderNo']?.toString() : null;
          changed = true;
        } else if (isConnectionFailure(res)) {
          // Mất mạng / hết giờ giữa chừng (máy chủ có thể đã nhận — gửi lại cùng số offline không tạo đơn đôi)
          // → lần sau gửi tiếp đúng thứ tự.
          break;
        } else {
          r.status = 'error';
          r.error = res['message']?.toString() ?? 'Máy chủ từ chối';
          changed = true;
        }
        _vault['sales'] = list.map((e) => e.toJson()).toList();
        await _save();
      }
      // Dọn đơn đã đồng bộ quá 7 ngày (máy chủ đã có, báo cáo kiểm soát giữ lịch sử).
      final keep = sales.where((r) =>
          r.status != 'synced' ||
          r.syncedAt == null ||
          DateTime.now().difference(r.syncedAt!).inDays < 7);
      if (keep.length != sales.length) {
        _vault['sales'] = keep.map((e) => e.toJson()).toList();
        changed = true;
      }
      await _pushCarts();
      if (changed) await _save();
      await _registerInstall();
    } catch (e) {
      debugPrint('PosOfflineService.syncAll: $e');
    } finally {
      _syncing = false;
    }
  }

  Future<void> _pushCarts() async {
    final carts = Map<String, dynamic>.from((_vault['carts'] as Map?) ?? {});
    for (final e in carts.entries.toList()) {
      if (isLiveCart?.call(e.key) == true) continue;
      final m = e.value is Map ? Map<String, dynamic>.from(e.value as Map) : null;
      final body = m?['body'] is Map ? Map<String, dynamic>.from(m!['body'] as Map) : null;
      if (body == null) {
        carts.remove(e.key);
        continue;
      }
      body.remove('expectedLockVersion');
      final draftId = m!['draftOrderId']?.toString();
      final res = (draftId != null && draftId.isNotEmpty)
          ? await _api.updatePosSale(draftId, body)
          : await _api.createPosSale({...body, 'complete': false});
      if (res['isSuccess'] == true) {
        carts.remove(e.key);
      } else if (isConnectionFailure(res)) {
        break;
      } else {
        // Máy chủ từ chối (đơn đã thanh toán ở máy khác…) — giữ lại 3 ngày để quản lý xem, rồi bỏ.
        final saved = DateTime.tryParse(m['savedAt']?.toString() ?? '');
        if (saved != null && DateTime.now().difference(saved).inDays >= 3) carts.remove(e.key);
      }
    }
    _vault['carts'] = carts;
  }

  /// Gửi lại đơn lỗi (quản lý đã xử lý nguyên nhân, vd mở lại ca / thêm hàng).
  Future<void> retryErrors() async {
    final list = sales;
    for (final r in list.where((r) => r.status == 'error')) {
      r.status = 'pending';
      r.error = null;
    }
    _vault['sales'] = list.map((e) => e.toJson()).toList();
    await _save();
    await syncAll();
  }
}
