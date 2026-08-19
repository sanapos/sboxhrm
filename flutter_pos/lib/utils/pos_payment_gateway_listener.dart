import 'dart:async';

import '../services/api_service.dart';
import '../services/customer_display_sync.dart';
import '../services/signalr_service.dart';

/// Lắng nghe webhook Tingee qua SignalR → màn phụ + callback UI.
class PosPaymentGatewayListener {
  PosPaymentGatewayListener._();
  static final PosPaymentGatewayListener instance =
      PosPaymentGatewayListener._();

  StreamSubscription<Map<String, dynamic>>? _sub;
  final _callbacks = <void Function(Map<String, dynamic> event)>{};

  /// Bật subscription SignalR (gọi một lần từ main hoặc POS).
  void start() => _ensureSub();

  void addListener(void Function(Map<String, dynamic> event) cb) {
    _callbacks.add(cb);
    _ensureSub();
  }

  void removeListener(void Function(Map<String, dynamic> event) cb) {
    _callbacks.remove(cb);
  }

  void stop() {
    _callbacks.clear();
    _sub?.cancel();
    _sub = null;
  }

  void _ensureSub() {
    _sub ??= SignalRService().onPosFloorChanged.listen(_onFloor);
  }

  void _onFloor(Map<String, dynamic> event) {
    final reason =
        (event['reason'] ?? event['Reason'] ?? '').toString().toLowerCase();
    if (reason != 'tingeepaymentconfirmed') return;

    final message =
        (event['message'] ?? event['Message'] ?? '').toString().trim();
    final orderNo = (event['orderNo'] ?? event['OrderNo'] ?? '').toString();

    unawaited(CustomerDisplaySync.instance.publishPaymentConfirmed(
      message: message.isNotEmpty
          ? message
          : 'Đã nhận chuyển khoản thành công',
      orderNo: orderNo.isEmpty ? null : orderNo,
    ));

    for (final cb in _callbacks.toList()) {
      cb(event);
    }
  }
}

class PosPaymentGatewayApi {
  PosPaymentGatewayApi(this._api);
  final ApiService _api;

  Future<Map<String, dynamic>?> getSettings() async {
    final res = await _api.getPosPaymentGatewaySettings();
    if (res['isSuccess'] == true && res['data'] is Map) {
      return Map<String, dynamic>.from(res['data'] as Map);
    }
    return null;
  }

  Future<Map<String, dynamic>?> getCredits() async {
    final res = await _api.getPosNotificationCredits();
    if (res['isSuccess'] == true && res['data'] is Map) {
      return Map<String, dynamic>.from(res['data'] as Map);
    }
    return null;
  }

  Future<List<Map<String, dynamic>>> listIntents({String? status}) async {
    final res = await _api.listPosTransferPaymentIntents(status: status);
    if (res['isSuccess'] != true || res['data'] is! List) return const [];
    return (res['data'] as List)
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  Future<Map<String, dynamic>?> createIntent({
    required String externalOrderId,
    String? orderNo,
    required double amountExpected,
    String? tableName,
    String? saleOrderId,
    String provider = 'Tingee',
  }) async {
    final res = await _api.createPosTransferPaymentIntent(
      externalOrderId: externalOrderId,
      orderNo: orderNo,
      amountExpected: amountExpected,
      tableName: tableName,
      saleOrderId: saleOrderId,
      provider: provider,
    );
    if (res['isSuccess'] == true && res['data'] is Map) {
      return Map<String, dynamic>.from(res['data'] as Map);
    }
    return null;
  }

  static bool isTingeeEnabled(Map<String, dynamic>? settings) =>
      settings?['tingeeEnabled'] == true;

  static bool preferTingee(Map<String, dynamic>? settings) =>
      (settings?['defaultTransferProvider']?.toString() ?? 'VietQr')
          .toLowerCase()
          .contains('tingee');
}
