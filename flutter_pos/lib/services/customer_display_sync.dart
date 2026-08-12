import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/customer_display_models.dart';
import 'api_service.dart';
import 'customer_display_bridge_stub.dart'
    if (dart.library.html) 'customer_display_bridge_web.dart'
    if (dart.library.io) 'customer_display_bridge_io.dart' as bridge;

/// Đồng bộ trạng thái màn hình phụ giữa máy thu ngân ↔ màn khách.
///
/// POS và màn phụ chạy **2 FlutterEngine riêng** — EventChannel chỉ gắn
/// MainActivity nên màn phụ phải **poll** SharedPreferences để nhận hóa đơn.
class CustomerDisplaySync extends ChangeNotifier {
  CustomerDisplaySync._();
  static final CustomerDisplaySync instance = CustomerDisplaySync._();

  static const _prefsKey = 'sbox_customer_display_state_v1';
  static const _viewerCodePrefsKey = 'sbox_customer_display_viewer_code_v1';

  CustomerDisplayState _state = CustomerDisplayState.idle;
  CustomerDisplayConfig _config = const CustomerDisplayConfig();
  StreamSubscription<String>? _nativeSub;
  Timer? _pollTimer;
  bool _listening = false;
  bool _pollBusy = false;
  String? _localViewerCode;

  CustomerDisplayState get state => _state;
  CustomerDisplayConfig get config => _config;
  bool get enabled => _config.enabled;

  /// Link mở trên trình duyệt máy khác (không cần đăng nhập).
  /// Dùng path `/customer-display` (không dùng `/#/...`) vì `/` phục vụ home.html SEO.
  String get viewerBrowserLink {
    final code = ensureViewerCode();
    if (kIsWeb) {
      try {
        final origin = Uri.base.origin;
        if (origin.isNotEmpty) return '$origin/customer-display?v=$code';
      } catch (_) {}
    }
    return 'https://sboxhrm.com/customer-display?v=$code';
  }

  /// Đảm bảo có mã ≥4 ký tự (ổn định qua prefs / config server).
  String ensureViewerCode() {
    final fromCfg = _config.viewerCode.trim();
    if (fromCfg.length >= 4) {
      _localViewerCode = fromCfg;
      return fromCfg;
    }
    final local = (_localViewerCode ?? '').trim();
    if (local.length >= 4) {
      _config = _config.copyWith(viewerCode: local);
      return local;
    }
    final generated = CustomerDisplayConfig.newViewerCode();
    _localViewerCode = generated;
    _config = _config.copyWith(viewerCode: generated);
    unawaited(_persistViewerCode(generated));
    return generated;
  }

  void applyConfig(CustomerDisplayConfig config) {
    final incoming = config.viewerCode.trim();
    String code;
    if (incoming.length >= 4) {
      code = incoming;
      _localViewerCode = incoming;
      unawaited(_persistViewerCode(incoming));
    } else {
      final local = (_localViewerCode ?? _config.viewerCode).trim();
      code = local.length >= 4 ? local : CustomerDisplayConfig.newViewerCode();
      _localViewerCode = code;
      unawaited(_persistViewerCode(code));
    }
    _config = config.copyWith(viewerCode: code);
    notifyListeners();
  }

  Future<void> _persistViewerCode(String code) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_viewerCodePrefsKey, code);
    } catch (_) {}
  }

  Future<void> _loadLocalViewerCode() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final c = (prefs.getString(_viewerCodePrefsKey) ?? '').trim();
      if (c.length >= 4) _localViewerCode = c;
    } catch (_) {}
  }

  Future<void> startListening() async {
    if (_listening) return;
    _listening = true;
    await _loadLocalViewerCode();
    ensureViewerCode();
    await _pullLatestFromStorage();
    notifyListeners();

    _nativeSub?.cancel();
    final stream = bridge.CustomerDisplayPlatformBridge.nativeStateStream();
    if (stream != null) {
      _nativeSub = stream.listen(
        (raw) {
          final s = CustomerDisplayState.tryDecode(raw);
          if (s == null) return;
          _applyIfNewer(s);
        },
        onError: (Object e) {
          debugPrint('CustomerDisplay events: $e');
        },
        cancelOnError: false,
      );
    }

    // Engine màn phụ không nhận EventChannel từ MainActivity → poll.
    _pollTimer?.cancel();
    // 2.5s đủ mượt cho màn phụ; 800ms gây I/O prefs liên tục trên Sunmi.
    _pollTimer = Timer.periodic(const Duration(milliseconds: 2500), (_) {
      unawaited(_pollStorage());
    });
  }

  Future<void> _pollStorage() async {
    if (_pollBusy) return;
    _pollBusy = true;
    try {
      await _pullLatestFromStorage();
    } finally {
      _pollBusy = false;
    }
  }

  Future<void> _pullLatestFromStorage() async {
    try {
      final cached = await bridge.CustomerDisplayPlatformBridge.readNative();
      final fromBridge = CustomerDisplayState.tryDecode(cached);
      if (fromBridge != null) {
        _applyIfNewer(fromBridge);
      }
    } catch (_) {}
    try {
      final prefs = await SharedPreferences.getInstance();
      final local = CustomerDisplayState.tryDecode(prefs.getString(_prefsKey));
      if (local != null) {
        _applyIfNewer(local);
      }
    } catch (_) {}
  }

  void _applyIfNewer(CustomerDisplayState s) {
    if (s.updatedAtMs < _state.updatedAtMs) return;
    if (s.updatedAtMs == _state.updatedAtMs && identical(s, _state)) {
      return;
    }
    if (s.updatedAtMs == _state.updatedAtMs &&
        s.mode == _state.mode &&
        s.lines.length == _state.lines.length &&
        s.total == _state.total &&
        s.tableLabel == _state.tableLabel &&
        s.subtotal == _state.subtotal) {
      return;
    }
    _state = s;
    notifyListeners();
  }

  /// [stillValid]: nếu trả false sau await I/O → bỏ publishNative
  /// (tránh idle sơ đồ ghi đè bill khi đã vào bàn).
  Future<void> publish(
    CustomerDisplayState next, {
    bool Function()? stillValid,
  }) async {
    // Local T1/native luôn nhận bill; `enabled` chỉ chặn sync viewer từ xa.
    final stamped = next.copyWith(
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
      idleSeconds: _config.idleSeconds,
    );
    if (stillValid != null && !stillValid()) return;
    _state = stamped;
    notifyListeners();

    final json = stamped.encode();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, json);
    } catch (_) {}
    if (stillValid != null && !stillValid()) return;
    await bridge.CustomerDisplayPlatformBridge.publishNative(json);

    if (!_config.enabled) return;
    if (stillValid != null && !stillValid()) return;

    final code = ensureViewerCode();
    if (code.length >= 4) {
      unawaited(ApiService().putPosCustomerDisplayState(
        stateJson: json,
        viewerCode: code,
      ));
    }
  }

  /// Áp state từ API (máy xem từ xa).
  void applyRemoteStateJson(String? raw) {
    final s = CustomerDisplayState.tryDecode(raw);
    if (s == null) return;
    _applyIfNewer(s);
  }

  Future<void> publishIdle({
    List<CustomerDisplayPromoItem>? promoItems,
    String? storeName,
    bool Function()? stillValid,
  }) {
    return publish(
      CustomerDisplayState(
        mode: CustomerDisplayMode.idle,
        promoItems: promoItems ?? _state.promoItems,
        storeName: storeName ?? _state.storeName,
        idleSeconds: _config.idleSeconds,
      ),
      stillValid: stillValid,
    );
  }

  Future<void> publishActive({
    required String? tableLabel,
    String? areaName,
    String? orderNo,
    int guestCount = 0,
    required List<CustomerDisplayLine> lines,
    required double subtotal,
    required double discount,
    required double total,
    String? storeName,
    List<CustomerDisplayPromoItem>? promoItems,
    String? paymentQrUrl,
    bool Function()? stillValid,
  }) {
    return publish(
      CustomerDisplayState(
        mode: CustomerDisplayMode.active,
        tableLabel: tableLabel,
        areaName: areaName,
        orderNo: orderNo,
        guestCount: guestCount,
        lines: lines,
        subtotal: subtotal,
        discount: discount,
        total: total,
        storeName: storeName ?? _state.storeName,
        promoItems: promoItems ?? _state.promoItems,
        idleSeconds: _config.idleSeconds,
        paymentQrUrl: paymentQrUrl,
      ),
      stillValid: stillValid,
    );
  }

  Future<bool> hasSecondaryDisplay() =>
      bridge.CustomerDisplayPlatformBridge.hasSecondaryDisplay();

  Future<bool> openSecondary() {
    final mode = _config.target.wire;
    if (_config.target == CustomerDisplayTarget.window) {
      // Window: chỉ cần sync JSON/API — Kotlin no-op / web mở popup.
      return bridge.CustomerDisplayPlatformBridge.openSecondary(mode: mode);
    }
    return bridge.CustomerDisplayPlatformBridge.openSecondary(mode: mode);
  }

  Future<bool> closeSecondary() =>
      bridge.CustomerDisplayPlatformBridge.closeSecondary();

  Future<List<Map<String, dynamic>>> listDisplays() =>
      bridge.CustomerDisplayPlatformBridge.listDisplays();

  @override
  void dispose() {
    _pollTimer?.cancel();
    _nativeSub?.cancel();
    super.dispose();
  }
}
