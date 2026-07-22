import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/customer_display_models.dart';
import 'customer_display_bridge_stub.dart'
    if (dart.library.html) 'customer_display_bridge_web.dart'
    if (dart.library.io) 'customer_display_bridge_io.dart' as bridge;

/// Đồng bộ trạng thái màn hình phụ giữa máy thu ngân ↔ màn khách.
class CustomerDisplaySync extends ChangeNotifier {
  CustomerDisplaySync._();
  static final CustomerDisplaySync instance = CustomerDisplaySync._();

  static const _prefsKey = 'sbox_customer_display_state_v1';

  CustomerDisplayState _state = CustomerDisplayState.idle;
  CustomerDisplayConfig _config = const CustomerDisplayConfig();
  StreamSubscription<String>? _nativeSub;
  bool _listening = false;

  CustomerDisplayState get state => _state;
  CustomerDisplayConfig get config => _config;
  bool get enabled => _config.enabled;

  void applyConfig(CustomerDisplayConfig config) {
    _config = config;
    notifyListeners();
  }

  Future<void> startListening() async {
    if (_listening) return;
    _listening = true;
    final cached = await bridge.CustomerDisplayPlatformBridge.readNative();
    final fromBridge = CustomerDisplayState.tryDecode(cached);
    if (fromBridge != null) {
      _state = fromBridge;
    } else {
      final prefs = await SharedPreferences.getInstance();
      final local = CustomerDisplayState.tryDecode(prefs.getString(_prefsKey));
      if (local != null) _state = local;
    }
    notifyListeners();

    _nativeSub?.cancel();
    final stream = bridge.CustomerDisplayPlatformBridge.nativeStateStream();
    if (stream != null) {
      _nativeSub = stream.listen((raw) {
        final s = CustomerDisplayState.tryDecode(raw);
        if (s == null) return;
        if (s.updatedAtMs < _state.updatedAtMs) return;
        _state = s;
        notifyListeners();
      });
    }
  }

  Future<void> publish(CustomerDisplayState next) async {
    if (!_config.enabled) {
      // Chỉ publish idle tối thiểu khi tắt — không đẩy hóa đơn.
      if (next.mode == CustomerDisplayMode.active) return;
    }
    final stamped = next.copyWith(
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    );
    _state = stamped;
    notifyListeners();
    final json = stamped.encode();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, json);
    } catch (_) {}
    await bridge.CustomerDisplayPlatformBridge.publishNative(json);
  }

  Future<void> publishIdle({
    List<CustomerDisplayPromoItem>? promoItems,
    String? storeName,
  }) {
    return publish(CustomerDisplayState(
      mode: CustomerDisplayMode.idle,
      promoItems: promoItems ?? _state.promoItems,
      storeName: storeName ?? _state.storeName,
    ));
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
  }) {
    return publish(CustomerDisplayState(
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
    ));
  }

  Future<bool> openSecondary() =>
      bridge.CustomerDisplayPlatformBridge.openSecondary();

  Future<bool> closeSecondary() =>
      bridge.CustomerDisplayPlatformBridge.closeSecondary();

  Future<List<Map<String, dynamic>>> listDisplays() =>
      bridge.CustomerDisplayPlatformBridge.listDisplays();

  @override
  void dispose() {
    _nativeSub?.cancel();
    super.dispose();
  }
}
