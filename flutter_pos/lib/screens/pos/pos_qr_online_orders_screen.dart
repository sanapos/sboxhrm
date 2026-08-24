import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/pos_sale_order.dart';
import '../../models/qr_order_lock_config.dart';
import '../../services/api_service.dart';
import '../../utils/navigation_notifier.dart';
import '../../utils/pos_sale_order_print.dart';
import '../../utils/pos_sell_print_settings.dart';
import '../../utils/pos_sell_store_settings.dart';
import '../../widgets/notification_overlay.dart';
import '../../widgets/pos/pos_hub_scope.dart';
import '../../widgets/pos/pos_shipping_compare_sheet.dart';
import '../../widgets/pos/pos_theme.dart';
import 'package:sbox_pos/l10n/app_tr.dart';

/// Theo dõi / đổi trạng thái đơn QR đặt online.
class PosQrOnlineOrdersScreen extends StatefulWidget {
  const PosQrOnlineOrdersScreen({super.key, this.highlightOrderId});

  /// Ưu tiên hơn [NavigationNotifier.notificationHighlightId] khi mở từ hub.
  final String? highlightOrderId;

  @override
  State<PosQrOnlineOrdersScreen> createState() =>
      _PosQrOnlineOrdersScreenState();
}

class _PosQrOnlineOrdersScreenState extends State<PosQrOnlineOrdersScreen> {
  final _api = ApiService();
  final _money = NumberFormat('#,##0', 'vi_VN');

  bool _loading = true;
  bool _busy = false;
  String? _error;
  String? _filter;
  String _search = '';
  DateTime _from = DateTime.now().subtract(const Duration(days: 7));
  DateTime _to = DateTime.now();
  String? _productFilterId;
  Timer? _searchDebounce;
  List<_OnlineOrder> _orders = [];
  List<_StatusOpt> _statuses = const [];
  List<_ProductFilter> _productFilters = const [];
  String? _highlightId;
  QrOrderLockConfig _onlineCfg = const QrOrderLockConfig();
  List<MapEntry<String, String>> _shippingCarriers = const [];
  PosSellPrintSettings _printSettings = PosSellPrintSettings();
  PosSellStoreSettings _storeSettings = const PosSellStoreSettings();

  static const _flow = [
    'pending',
    'confirmed',
    'preparing',
    'shipping',
    'delivered',
  ];

  @override
  void dispose() {
    _searchDebounce?.cancel();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _highlightId = widget.highlightOrderId ??
        NavigationNotifier.notificationHighlightId.value;
    NavigationNotifier.notificationHighlightId.value = null;
    _load();
  }

  List<String> _forwardActions(String status) {
    final s = status.toLowerCase();
    if (s == 'cancelled' || s == 'delivered') return const [];
    switch (s) {
      case 'pending':
        // Xác nhận đơn → thẳng Đang chuẩn bị
        return const ['preparing', 'cancelled'];
      case 'confirmed':
        return const ['preparing', 'cancelled'];
      case 'preparing':
        return const ['shipping', 'cancelled'];
      case 'shipping':
        return const ['delivered'];
      default:
        return const ['preparing'];
    }
  }

  String _actionLabel(String code, List<_StatusOpt> opts, {String? fromStatus}) {
    switch (code) {
      case 'confirmed':
        return tr('Xác nhận đơn');
      case 'preparing':
        return (fromStatus == 'pending')
            ? tr('Xác nhận đơn')
            : tr('Bắt đầu chuẩn bị');
      case 'shipping':
        return tr('Đang giao hàng');
      case 'delivered':
        return tr('Giao thành công');
      case 'cancelled':
        return tr('Hủy đơn');
      default:
        return opts
            .firstWhere((o) => o.code == code,
                orElse: () => _StatusOpt(code: code, label: code))
            .label;
    }
  }

  Color _statusColor(String code) {
    switch (code) {
      case 'delivered':
        return const Color(0xFF3F6F54);
      case 'cancelled':
        return const Color(0xFFB91C1C);
      case 'shipping':
        return const Color(0xFF2563EB);
      case 'preparing':
        return const Color(0xFF9333EA);
      case 'confirmed':
        return const Color(0xFFEA580C);
      default:
        return const Color(0xFF78716C);
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final tablesFut = _api.getPosQrOrderTables();
    final shipFut = _api.getPosShippingEnabled();
    final printFut = PosSellPrintSettings.load();
    final storeFut = PosSellStoreSettings.load(peekServer: true);
    final res = await _api.getPosQrOnlineOrders(
      status: _filter,
      from: _from,
      to: _to,
      search: _search,
      productId: _productFilterId,
    );
    final tablesRes = await tablesFut;
    final shipRes = await shipFut;
    final printS = await printFut;
    final storeS = await storeFut;
    if (!mounted) return;
    if (tablesRes['isSuccess'] == true && tablesRes['data'] is Map) {
      final td = Map<String, dynamic>.from(tablesRes['data'] as Map);
      _onlineCfg = QrOrderLockConfig(
        onlineAutoConfirm: td['onlineAutoConfirm'] == true,
        onlineAutoPrintKitchen: td['onlineAutoPrintKitchen'] == true,
        onlineAutoPay: td['onlineAutoPay'] == true,
        onlineAutoPrintProvisional: td['onlineAutoPrintProvisional'] == true,
        onlineAutoCreateShipment: td['onlineAutoCreateShipment'] == true,
        onlineDefaultCarrierCode:
            (td['onlineDefaultCarrierCode'] ?? '').toString().trim().isEmpty
                ? null
                : (td['onlineDefaultCarrierCode'] ?? '').toString().trim(),
        storeZalo: (td['storeZalo'] ?? '').toString(),
      );
    }
    _shippingCarriers = _parseCarriers(shipRes);
    _printSettings = printS;
    _storeSettings = storeS;
    if (res['isSuccess'] != true || res['data'] is! Map) {
      setState(() {
        _loading = false;
        _error = res['message']?.toString() ?? 'Không tải được đơn online';
      });
      return;
    }
    final data = Map<String, dynamic>.from(res['data'] as Map);
    final statuses = <_StatusOpt>[];
    final rawSt = data['statuses'] ?? data['Statuses'];
    if (rawSt is List) {
      for (final e in rawSt) {
        if (e is! Map) continue;
        statuses.add(_StatusOpt.fromJson(Map<String, dynamic>.from(e)));
      }
    }
    final orders = <_OnlineOrder>[];
    final raw = data['orders'] ?? data['Orders'];
    if (raw is List) {
      for (final e in raw) {
        if (e is! Map) continue;
        orders.add(_OnlineOrder.fromJson(Map<String, dynamic>.from(e)));
      }
    }
    final productFilters = <_ProductFilter>[];
    final rawPf = data['productFilters'] ?? data['ProductFilters'];
    if (rawPf is List) {
      for (final e in rawPf) {
        if (e is! Map) continue;
        productFilters.add(_ProductFilter.fromJson(Map<String, dynamic>.from(e)));
      }
    }
    setState(() {
      _statuses = statuses;
      _orders = orders;
      _productFilters = productFilters;
      _loading = false;
    });
    _openHighlightIfAny();
  }

  void _openHighlightIfAny() {
    final id = _highlightId;
    if (id == null || id.isEmpty) return;
    _highlightId = null;
    _OnlineOrder? hit;
    for (final o in _orders) {
      if (o.id == id) {
        hit = o;
        break;
      }
    }
    if (hit == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _openDetail(hit!);
    });
  }

  List<MapEntry<String, String>> _parseCarriers(Map<String, dynamic> res) {
    final out = <MapEntry<String, String>>[
      const MapEntry('Internal', 'Giao hàng nội bộ'),
    ];
    if (res['isSuccess'] == true && res['data'] is List) {
      for (final e in res['data'] as List) {
        if (e is! Map) continue;
        final m = Map<String, dynamic>.from(e);
        final code = (m['code'] ?? m['Code'] ?? '').toString().trim();
        if (code.isEmpty) continue;
        final name = (m['name'] ?? m['Name'] ?? code).toString();
        out.add(MapEntry(code, name));
      }
    }
    return out;
  }

  Future<void> _setStatus(_OnlineOrder order, String status,
      {bool internalDelivery = false}) async {
    setState(() => _busy = true);
    final res = await _api.setPosQrOnlineOrderStatus(
      order.id,
      status,
      internalDelivery: internalDelivery,
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (res['isSuccess'] != true) {
      NotificationOverlayManager().showError(
        title: 'Không cập nhật được',
        message: res['message']?.toString() ?? 'Thử lại',
      );
      return;
    }
    NotificationOverlayManager().showSuccess(
      title: 'Đã cập nhật',
      message: order.orderNo,
    );
    if (status == 'confirmed' && _onlineCfg.onlineAutoPrintProvisional) {
      await _printProvisional(order);
    }
    await _load();
  }

  Future<void> _deleteCancelled(_OnlineOrder order) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Xóa đơn đã hủy?')),
        content: Text(
          tr('Đơn ${order.orderNo} sẽ biến khỏi danh sách. '
              'Không ảnh hưởng kho / doanh thu.'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(tr('Huỷ')),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(tr('Xóa')),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    final res = await _api.deletePosQrOnlineOrder(order.id);
    if (!mounted) return;
    setState(() => _busy = false);
    if (res['isSuccess'] != true) {
      NotificationOverlayManager().showError(
        title: tr('Không xóa được'),
        message: res['message']?.toString() ?? tr('Thử lại'),
      );
      return;
    }
    NotificationOverlayManager().showSuccess(
      title: tr('Đã xóa'),
      message: order.orderNo,
    );
    await _load();
  }

  void _openPayment(_OnlineOrder o) {
    NavigationNotifier.pendingOpenQrOnlineDraftId.value = o.id;
    NavigationNotifier.pendingOpenQrOnlinePay.value = true;
    NavigationNotifier.posHubTab.value = 2;
    final nav = Navigator.of(context);
    if (nav.canPop()) {
      nav.popUntil((route) => route.isFirst);
    }
    NotificationOverlayManager().showInfo(
      title: tr('Thanh toán'),
      message: tr('Mở màn bán hàng — đơn ${o.orderNo}'),
    );
  }

  Future<void> _printProvisional(_OnlineOrder o) async {
    setState(() => _busy = true);
    try {
      final res = await _api.getPosSale(o.id);
      if (!mounted) return;
      if (res['isSuccess'] != true || res['data'] is! Map) {
        NotificationOverlayManager().showError(
          title: 'Không in tạm tính',
          message: res['message']?.toString() ?? 'Không tải được đơn',
        );
        return;
      }
      final map = Map<String, dynamic>.from(res['data'] as Map);
      final order = PosSaleOrder.fromJson(map);
      final ok = await printPosSaleOrder(
        context: context,
        order: order,
        branchName: _storeSettings.storeName.isNotEmpty
            ? _storeSettings.storeName
            : null,
        storeAddress: _storeSettings.address.isNotEmpty
            ? _storeSettings.address
            : null,
        storePhone:
            _storeSettings.phone.isNotEmpty ? _storeSettings.phone : null,
        mergeSameItems: _printSettings.mergeSameItems,
        copies: _printSettings.copies,
        templateId: _printSettings.templateId,
        skipDedup: true,
        preferDevicePrintOnly: true,
        documentTitle: 'HÓA ĐƠN TẠM TÍNH',
      );
      if (!mounted) return;
      if (ok) {
        NotificationOverlayManager().showSuccess(
          title: 'Tạm tính',
          message: tr('Đã gửi in hóa đơn tạm tính'),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _toastResult(String title, String message, {bool success = true}) {
    if (success) {
      NotificationOverlayManager().showSuccess(
        title: title,
        message: message,
        duration: const Duration(seconds: 6),
      );
    } else {
      NotificationOverlayManager().showError(
        title: title,
        message: message,
        duration: const Duration(seconds: 6),
      );
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$title — $message'),
        backgroundColor: success ? Colors.green.shade700 : Colors.red.shade700,
        duration: const Duration(seconds: 5),
      ),
    );
  }

  Future<void> _pickShipment(_OnlineOrder o) async {
    if (_shippingCarriers.isEmpty) {
      _toastResult(
        'Chưa cấu hình',
        tr('Bật hãng vận chuyển trong Cài đặt POS'),
        success: false,
      );
      return;
    }
    final pick = await showShippingCompareDialog(
      context: context,
      orderId: o.id,
      orderNo: o.orderNo,
      codAmount: o.isPaid ? 0 : o.total,
    );
    if (pick == null || !mounted) return;
    setState(() => _busy = true);
    _toastResult('Đang tạo vận đơn', '${pick.carrierName} · ${o.orderNo}');
    try {
      final res = await _api.createPosQrOnlineShipment(
        o.id,
        pick.carrierCode,
        weightGrams: pick.weightGrams,
        lengthCm: pick.lengthCm,
        widthCm: pick.widthCm,
        heightCm: pick.heightCm,
        serviceCode: pick.serviceCode,
        shipFeePayer: pick.shipFeePayer,
        fixedShipFee: pick.fixedShipFee,
      );
      if (!mounted) return;
      if (res['isSuccess'] != true) {
        final msg = res['message']?.toString() ?? 'Thử lại';
        await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Không tạo được vận đơn'),
            content: Text(msg),
            actions: [
              FilledButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(tr('Đóng')),
              ),
            ],
          ),
        );
        _toastResult('Không tạo được vận đơn', msg, success: false);
        return;
      }
      final data =
          res['data'] is Map ? Map<String, dynamic>.from(res['data'] as Map) : null;
      final orderMap = data?['order'] is Map
          ? Map<String, dynamic>.from(data!['order'] as Map)
          : null;
      final tracking = (data?['trackingCode'] ??
              data?['TrackingCode'] ??
              orderMap?['trackingCode'] ??
              orderMap?['TrackingCode'] ??
              '')
          .toString()
          .trim();
      final apiMsg = (data?['message'] ?? res['message'] ?? '').toString().trim();
      if (tracking.isEmpty) {
        final msg = apiMsg.isNotEmpty
            ? apiMsg
            : tr('Kiểm tra Viettel Post — tắt Sandbox nếu dùng token production');
        await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Chưa có mã vận đơn'),
            content: Text(msg),
            actions: [
              FilledButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(tr('Đóng')),
              ),
            ],
          ),
        );
        _toastResult('Chưa có mã vận đơn', msg, success: false);
      } else {
        final msg = apiMsg.isNotEmpty ? apiMsg : 'Mã: $tracking';
        await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Đã tạo vận đơn'),
            content: SelectableText(msg),
            actions: [
              FilledButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(tr('OK')),
              ),
            ],
          ),
        );
        _toastResult('Đã tạo vận đơn', msg);
      }
      await _load();
    } catch (e) {
      if (!mounted) return;
      _toastResult('Lỗi mạng', '$e', success: false);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  bool _isViettelCarrier(String partner) {
    final p = partner.toLowerCase();
    return p.contains('viettel') || p == 'viettelpost' || p == 'vtp';
  }

  Future<void> _openShipmentLabel(_OnlineOrder o) async {
    setState(() => _busy = true);
    try {
      final res = await _api.getPosShipmentLabel(o.id);
      if (!mounted) return;
      final data = res['data'] is Map
          ? Map<String, dynamic>.from(res['data'] as Map)
          : <String, dynamic>{};
      final ok = res['isSuccess'] == true &&
          (data['success'] == true || data['Success'] == true);
      final url = (data['labelUrl'] ?? data['LabelUrl'] ?? '').toString();
      if (ok && url.isNotEmpty) {
        final uri = Uri.parse(url);
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
          _toastResult('Mở nhãn vận đơn', o.orderNo);
        } else {
          _toastResult('Không mở được link in', url, success: false);
        }
      } else {
        _toastResult(
          'Không lấy được nhãn in',
          (data['message'] ?? data['Message'] ?? res['message'] ?? '')
              .toString(),
          success: false,
        );
      }
    } catch (e) {
      if (mounted) _toastResult('Lỗi mạng', '$e', success: false);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _syncShipmentTracking(_OnlineOrder o) async {
    setState(() => _busy = true);
    try {
      final res = await _api.syncPosShipmentTracking(o.id);
      if (!mounted) return;
      final data = res['data'] is Map
          ? Map<String, dynamic>.from(res['data'] as Map)
          : <String, dynamic>{};
      final ok = res['isSuccess'] == true &&
          (data['success'] == true || data['Success'] == true);
      if (ok) {
        final name =
            (data['statusName'] ?? data['StatusName'] ?? '').toString();
        _toastResult('Đã đồng bộ VTP', name.isEmpty ? o.orderNo : name);
        await _load();
      } else {
        _toastResult(
          'Đồng bộ thất bại',
          (data['message'] ?? data['Message'] ?? res['message'] ?? '')
              .toString(),
          success: false,
        );
      }
    } catch (e) {
      if (mounted) _toastResult('Lỗi mạng', '$e', success: false);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _cancelShipment(_OnlineOrder o) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Hủy vận đơn Viettel Post?')),
        content: Text(tr('Mã ${o.trackingCode} — chỉ hủy khi VTP chưa nhận hàng (<200).')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Không'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Hủy VTP'))),
        ],
      ),
    );
    if (yes != true || !mounted) return;
    setState(() => _busy = true);
    try {
      final res = await _api.cancelPosShipment(o.id, note: 'Hủy từ SBOX POS');
      if (!mounted) return;
      final data = res['data'] is Map
          ? Map<String, dynamic>.from(res['data'] as Map)
          : <String, dynamic>{};
      final ok = res['isSuccess'] == true &&
          (data['success'] == true || data['Success'] == true);
      if (ok) {
        _toastResult('Đã yêu cầu hủy VTP', o.trackingCode);
        await _load();
      } else {
        _toastResult(
          'Hủy thất bại',
          (data['message'] ?? data['Message'] ?? res['message'] ?? '')
              .toString(),
          success: false,
        );
      }
    } catch (e) {
      if (mounted) _toastResult('Lỗi mạng', '$e', success: false);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _orderFulfillmentActions(_OnlineOrder o, {VoidCallback? onClose}) {
    if (o.status == 'cancelled') return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 10),
        Text(
          tr('Thanh toán & giao hàng'),
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w800,
            color: Colors.grey.shade600,
          ),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            if (o.canPrintProvisional)
              OutlinedButton.icon(
                onPressed: _busy
                    ? null
                    : () {
                        onClose?.call();
                        _printProvisional(o);
                      },
                icon: const Icon(Icons.receipt_long_outlined, size: 18),
                label: Text(tr('In tạm tính')),
              ),
            if (o.canPay)
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: PosTheme.kiotBlue,
                ),
                onPressed: _busy
                    ? null
                    : () {
                        onClose?.call();
                        _openPayment(o);
                      },
                icon: const Icon(Icons.point_of_sale, size: 18),
                label: Text(tr('Thanh toán')),
              )
            else if (o.isPaid)
              Chip(
                avatar: const Icon(Icons.check_circle, size: 18),
                label: Text(tr('Đã thanh toán')),
              ),
            if (o.trackingCode.isEmpty &&
                o.status != 'cancelled' &&
                o.status != 'pending')
              OutlinedButton.icon(
                onPressed: _busy
                    ? null
                    : () {
                        onClose?.call();
                        _pickShipment(o);
                      },
                icon: const Icon(Icons.local_shipping_outlined, size: 18),
                label: Text(tr('Tạo vận đơn')),
              ),
          ],
        ),
        if (o.trackingCode.isNotEmpty || o.deliveryPartner.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            '🚚 ${o.deliveryPartner.isNotEmpty ? o.deliveryPartner : tr('Vận chuyển')}'
            '${o.trackingCode.isNotEmpty ? ' · ${o.trackingCode}' : ''}',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
          ),
          if (o.trackingCode.isNotEmpty && _isViettelCarrier(o.deliveryPartner)) ...[
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                OutlinedButton.icon(
                  onPressed: _busy
                      ? null
                      : () {
                          onClose?.call();
                          _openShipmentLabel(o);
                        },
                  icon: const Icon(Icons.print_outlined, size: 18),
                  label: Text(tr('In vận đơn')),
                ),
                OutlinedButton.icon(
                  onPressed: _busy
                      ? null
                      : () {
                          onClose?.call();
                          _syncShipmentTracking(o);
                        },
                  icon: const Icon(Icons.sync, size: 18),
                  label: Text(tr('Đồng bộ VTP')),
                ),
                if (o.status != 'cancelled' && o.status != 'delivered')
                  OutlinedButton.icon(
                    onPressed: _busy
                        ? null
                        : () {
                            onClose?.call();
                            _cancelShipment(o);
                          },
                    icon: const Icon(Icons.cancel_outlined, size: 18),
                    label: Text(tr('Hủy VTP')),
                  ),
              ],
            ),
          ],
        ],
      ],
    );
  }

  Widget _quickStatusActions(_OnlineOrder o) {
    final actions = _forwardActions(o.status);
    if (actions.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 10),
        Text(
          tr('Cập nhật nhanh'),
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w800,
            color: Colors.grey.shade600,
          ),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final code in actions)
              if (code == 'cancelled')
                OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.red.shade700,
                    side: BorderSide(color: Colors.red.shade300),
                    visualDensity: VisualDensity.compact,
                  ),
                  onPressed: _busy ? null : () => _setStatus(o, code),
                  child: Text(_actionLabel(code, _statuses, fromStatus: o.status)),
                )
              else
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: _statusColor(code),
                    visualDensity: VisualDensity.compact,
                  ),
                  onPressed: _busy ? null : () => _setStatus(o, code),
                  child: Text(_actionLabel(code, _statuses, fromStatus: o.status)),
                ),
          ],
        ),
        _orderFulfillmentActions(o),
      ],
    );
  }

  Future<void> _call(String phone) async {
    final digits = phone.replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) return;
    final uri = Uri(scheme: 'tel', path: digits);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  Future<void> _openZalo(String phone) async {
    final digits = phone.replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) return;
    final uri = Uri.parse('https://zalo.me/$digits');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _pickFromDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _from,
      firstDate: DateTime(2020),
      lastDate: _to,
    );
    if (picked == null) return;
    setState(() => _from = picked);
    await _load();
  }

  Future<void> _pickToDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _to,
      firstDate: _from,
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (picked == null) return;
    setState(() => _to = picked);
    await _load();
  }

  void _onSearchChanged(String v) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 400), () {
      if (_search == v) return;
      setState(() => _search = v);
      _load();
    });
  }

  Widget _contactActions(_OnlineOrder o, {bool compact = false}) {
    if (compact) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: tr('Gọi'),
            onPressed: () => _call(o.phone),
            icon: const Icon(Icons.phone_outlined),
          ),
          IconButton(
            tooltip: 'Zalo',
            onPressed: () => _openZalo(o.phone),
            icon: const Icon(Icons.chat_bubble_outline),
          ),
        ],
      );
    }
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () => _call(o.phone),
            icon: const Icon(Icons.phone, size: 18),
            label: Text(tr('Gọi điện')),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () => _openZalo(o.phone),
            icon: const Icon(Icons.chat_bubble_outline, size: 18),
            label: const Text('Zalo'),
          ),
        ),
      ],
    );
  }

  Widget _statusStepper(String current) {
    if (current == 'cancelled') {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFFFEE2E2),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Icon(Icons.cancel_outlined, color: Colors.red.shade800, size: 18),
            const SizedBox(width: 6),
            Text(tr('Đã hủy'),
                style: TextStyle(
                    fontWeight: FontWeight.w800, color: Colors.red.shade900)),
          ],
        ),
      );
    }
    final idx = _flow.indexOf(current);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          for (var i = 0; i < _flow.length; i++) ...[
            if (i > 0)
              Expanded(
                child: Container(
                  height: 2,
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                  color: i <= idx
                      ? _statusColor(_flow[i])
                      : const Color(0xFFE7E5E4),
                ),
              ),
            Tooltip(
              message: _statuses
                  .firstWhere((s) => s.code == _flow[i],
                      orElse: () =>
                          _StatusOpt(code: _flow[i], label: _flow[i]))
                  .label,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: i == idx ? 20 : 14,
                    height: i == idx ? 20 : 14,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: i <= idx
                          ? _statusColor(_flow[i])
                          : const Color(0xFFE7E5E4),
                    ),
                    child: i < idx
                        ? const Icon(Icons.check, size: 10, color: Colors.white)
                        : null,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _shortStatusLabel(_flow[i]),
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: i == idx ? FontWeight.w800 : FontWeight.w500,
                      color: i <= idx
                          ? const Color(0xFF1C1917)
                          : Colors.grey.shade500,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _shortStatusLabel(String code) {
    switch (code) {
      case 'pending':
        return tr('Chờ');
      case 'confirmed':
        return tr('Xác nhận');
      case 'preparing':
        return tr('Chuẩn bị');
      case 'shipping':
        return tr('Giao');
      case 'delivered':
        return tr('Xong');
      default:
        return code;
    }
  }

  Future<void> _openMaps(_OnlineOrder o) async {
    Uri? uri;
    if (o.hasGps) {
      uri = Uri.parse(
          'https://www.google.com/maps/search/?api=1&query=${o.lat},${o.lng}');
    } else if (o.address.trim().isNotEmpty) {
      uri = Uri.parse(
          'https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(o.address.trim())}');
    }
    if (uri == null) return;
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && mounted) {
      NotificationOverlayManager().showError(
        title: tr('Không mở được bản đồ'),
        message: tr('Cài Google Maps hoặc trình duyệt'),
      );
    }
  }

  void _openDetail(_OnlineOrder o) {
    final nextActions = _forwardActions(o.status);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        var orderOpen = true;
        var customerOpen = false;
        var actionsOpen = true;
        return SafeArea(
          child: StatefulBuilder(
            builder: (ctx, setLocal) {
              return Padding(
                padding: EdgeInsets.fromLTRB(
                  12,
                  0,
                  12,
                  12 + MediaQuery.viewInsetsOf(ctx).bottom,
                ),
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              '${tr('Đơn')} ${o.orderNo}',
                              style: const TextStyle(
                                  fontWeight: FontWeight.w900, fontSize: 17),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: _statusColor(o.status).withOpacity(0.12),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              o.statusLabel,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                color: _statusColor(o.status),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '${_money.format(o.total)}₫ · ${o.lines.length} món · ${o.customerName}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 12, color: Colors.grey.shade700),
                      ),
                      const SizedBox(height: 8),
                      _statusStepper(o.status),
                      const SizedBox(height: 10),
                      _expandBlock(
                        title: tr('Đơn hàng'),
                        icon: Icons.receipt_long_outlined,
                        expanded: orderOpen,
                        summary:
                            '${o.lines.length} món · ${_money.format(o.total)}₫',
                        onToggle: () =>
                            setLocal(() => orderOpen = !orderOpen),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            for (final l in o.lines)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 4),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        '${l.name} × ${_fmtQty(l.qty)}',
                                        style: const TextStyle(fontSize: 13),
                                      ),
                                    ),
                                    Text(
                                      '${_money.format(l.lineTotal)}₫',
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w700,
                                          fontSize: 13),
                                    ),
                                  ],
                                ),
                              ),
                            const Divider(height: 14),
                            Row(
                              children: [
                                Text(tr('Tổng'),
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w800)),
                                const Spacer(),
                                Text('${_money.format(o.total)}₫',
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w900,
                                        color: Color(0xFFC2410C))),
                              ],
                            ),
                            if (o.note.trim().isNotEmpty) ...[
                              const SizedBox(height: 6),
                              Text(
                                o.note,
                                style: TextStyle(
                                    color: Colors.grey.shade700, fontSize: 12),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      _expandBlock(
                        title: tr('Khách hàng'),
                        icon: Icons.person_outline,
                        expanded: customerOpen,
                        summary: o.customerName,
                        onToggle: () =>
                            setLocal(() => customerOpen = !customerOpen),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(o.customerName,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w800)),
                            const SizedBox(height: 4),
                            Text('☎ ${o.phone}'),
                            if (o.address.trim().isNotEmpty) ...[
                              const SizedBox(height: 6),
                              InkWell(
                                onTap: () => _openMaps(o),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Icon(
                                      o.hasGps
                                          ? Icons.location_on
                                          : Icons.place_outlined,
                                      size: 18,
                                      color: PosTheme.kiotBlue,
                                    ),
                                    const SizedBox(width: 4),
                                    Expanded(
                                      child: Text(
                                        o.address,
                                        style: TextStyle(
                                          color: PosTheme.kiotBlue,
                                          decoration:
                                              TextDecoration.underline,
                                          decorationColor: PosTheme.kiotBlue
                                              .withOpacity(0.4),
                                        ),
                                      ),
                                    ),
                                    if (o.hasGps)
                                      Text(
                                        tr('Maps'),
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w800,
                                          color: PosTheme.kiotBlue,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ] else if (o.hasGps) ...[
                              const SizedBox(height: 6),
                              TextButton.icon(
                                onPressed: () => _openMaps(o),
                                icon: const Icon(Icons.map_outlined, size: 18),
                                label: Text(tr('Mở Google Maps')),
                              ),
                            ],
                            const SizedBox(height: 8),
                            _contactActions(o),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      _expandBlock(
                        title: tr('Thao tác'),
                        icon: Icons.tune,
                        expanded: actionsOpen,
                        summary: o.status == 'cancelled'
                            ? tr('Xóa khỏi danh sách')
                            : nextActions.isEmpty
                                ? tr('In / giao hàng')
                                : _actionLabel(nextActions.first, _statuses,
                                    fromStatus: o.status),
                        onToggle: () =>
                            setLocal(() => actionsOpen = !actionsOpen),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _orderFulfillmentActions(o,
                                onClose: () => Navigator.pop(ctx)),
                            if (nextActions.isNotEmpty) ...[
                              const SizedBox(height: 8),
                              Text(tr('Bước tiếp theo'),
                                  style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w800,
                                      color: Colors.grey.shade700)),
                              const SizedBox(height: 6),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  for (final code in nextActions)
                                    if (code == 'cancelled')
                                      OutlinedButton(
                                        style: OutlinedButton.styleFrom(
                                          foregroundColor: Colors.red.shade700,
                                          side: BorderSide(
                                              color: Colors.red.shade300),
                                        ),
                                        onPressed: _busy
                                            ? null
                                            : () {
                                                Navigator.pop(ctx);
                                                _setStatus(o, code);
                                              },
                                        child: Text(
                                            _actionLabel(code, _statuses,
                                                fromStatus: o.status)),
                                      )
                                    else
                                      FilledButton(
                                        style: FilledButton.styleFrom(
                                          backgroundColor: _statusColor(code),
                                        ),
                                        onPressed: _busy
                                            ? null
                                            : () {
                                                Navigator.pop(ctx);
                                                _setStatus(o, code);
                                              },
                                        child: Text(
                                            _actionLabel(code, _statuses,
                                                fromStatus: o.status)),
                                      ),
                                ],
                              ),
                            ] else if (o.status == 'delivered') ...[
                              const SizedBox(height: 6),
                              Text(tr('Giao thành công'),
                                  style: TextStyle(
                                      fontWeight: FontWeight.w800,
                                      color: _statusColor('delivered'))),
                            ] else if (o.status == 'cancelled') ...[
                              const SizedBox(height: 8),
                              OutlinedButton.icon(
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: Colors.red.shade800,
                                  side: BorderSide(color: Colors.red.shade300),
                                ),
                                onPressed: _busy
                                    ? null
                                    : () {
                                        Navigator.pop(ctx);
                                        _deleteCancelled(o);
                                      },
                                icon: const Icon(Icons.delete_outline, size: 18),
                                label: Text(tr('Xóa đơn đã hủy')),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }

  Widget _expandBlock({
    required String title,
    required IconData icon,
    required bool expanded,
    required String summary,
    required VoidCallback onToggle,
    required Widget child,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE7E5E4)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          InkWell(
            onTap: onToggle,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  Icon(icon, size: 18, color: PosTheme.kiotBlue),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(title,
                        style: const TextStyle(
                            fontWeight: FontWeight.w800, fontSize: 13)),
                  ),
                  if (!expanded)
                    Flexible(
                      child: Text(
                        summary,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.right,
                        style: TextStyle(
                            fontSize: 11, color: Colors.grey.shade600),
                      ),
                    ),
                  Icon(
                    expanded
                        ? Icons.expand_less
                        : Icons.expand_more,
                    color: Colors.grey.shade600,
                  ),
                ],
              ),
            ),
          ),
          if (expanded) ...[
            Divider(height: 1, color: Colors.grey.shade200),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
              child: child,
            ),
          ],
        ],
      ),
    );
  }

  String _fmtQty(double q) =>
      q == q.roundToDouble() ? q.toInt().toString() : q.toString();

  @override
  Widget build(BuildContext context) {
    final pushed = PosHubScope.pushedSubPageOf(context);
    return Scaffold(
      backgroundColor: const Color(0xFFF3F4F6),
      appBar: AppBar(
        backgroundColor: PosTheme.kiotBlue,
        foregroundColor: Colors.white,
        automaticallyImplyLeading: pushed,
        title: Text(tr('Đơn online')),
        actions: [
          IconButton(
            tooltip: tr('Tải lại'),
            onPressed: _loading || _busy ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Column(
        children: [
          Material(
            color: Colors.white,
            elevation: 1,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 6, 10, 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: TextField(
                          decoration: InputDecoration(
                            hintText: tr('Tìm đơn, SĐT…'),
                            prefixIcon: const Icon(Icons.search, size: 18),
                            isDense: true,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 8,
                            ),
                          ),
                          onChanged: _busy ? null : _onSearchChanged,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _busy ? null : _pickFromDate,
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            visualDensity: VisualDensity.compact,
                            minimumSize: const Size(0, 36),
                          ),
                          child: Text(DateFormat('dd/MM').format(_from),
                              style: const TextStyle(fontSize: 11)),
                        ),
                      ),
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 2),
                        child: Text('–', style: TextStyle(fontSize: 12)),
                      ),
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _busy ? null : _pickToDate,
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            visualDensity: VisualDensity.compact,
                            minimumSize: const Size(0, 36),
                          ),
                          child: Text(DateFormat('dd/MM').format(_to),
                              style: const TextStyle(fontSize: 11)),
                        ),
                      ),
                    ],
                  ),
                  if (_productFilters.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    DropdownButtonFormField<String?>(
                      value: _productFilterId,
                      isExpanded: true,
                      isDense: true,
                      decoration: InputDecoration(
                        hintText: tr('Sản phẩm'),
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 6),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      items: [
                        DropdownMenuItem<String?>(
                          value: null,
                          child: Text(tr('Tất cả SP'),
                              style: const TextStyle(fontSize: 12)),
                        ),
                        for (final p in _productFilters)
                          DropdownMenuItem<String?>(
                            value: p.id,
                            child: Text(p.name,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 12)),
                          ),
                      ],
                      onChanged: _busy
                          ? null
                          : (v) {
                              setState(() => _productFilterId = v);
                              _load();
                            },
                    ),
                  ],
                ],
              ),
            ),
          ),
          SizedBox(
            height: 48,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              children: [
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: FilterChip(
                    label: Text(tr('Tất cả')),
                    selected: _filter == null,
                    onSelected: _busy
                        ? null
                        : (_) {
                            setState(() => _filter = null);
                            _load();
                          },
                  ),
                ),
                for (final s in _statuses)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: FilterChip(
                      label: Text(s.label),
                      selected: _filter == s.code,
                      onSelected: _busy
                          ? null
                          : (_) {
                              setState(() => _filter = s.code);
                              _load();
                            },
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : RefreshIndicator(
                    onRefresh: _load,
                    child: _error != null
                        ? ListView(
                            children: [
                              Padding(
                                padding: const EdgeInsets.all(24),
                                child: Text(_error!,
                                    style:
                                        TextStyle(color: Colors.red.shade700)),
                              ),
                            ],
                          )
                        : _orders.isEmpty
                            ? ListView(
                                children: [
                                  Padding(
                                    padding: const EdgeInsets.all(32),
                                    child: Text(
                                      tr('Chưa có đơn online'),
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                          color: Colors.grey.shade700),
                                    ),
                                  ),
                                ],
                              )
                            : ListView.separated(
                                padding: const EdgeInsets.fromLTRB(
                                    12, 8, 12, 24),
                                itemCount: _orders.length,
                                separatorBuilder: (_, __) =>
                                    const SizedBox(height: 6),
                                itemBuilder: (_, i) {
                                  final o = _orders[i];
                                  return Material(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(10),
                                    child: InkWell(
                                      borderRadius: BorderRadius.circular(10),
                                      onTap: () => _openDetail(o),
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 12, vertical: 10),
                                        child: Row(
                                          children: [
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Row(
                                                    children: [
                                                      Expanded(
                                                        child: Text(
                                                          o.orderNo,
                                                          maxLines: 1,
                                                          overflow: TextOverflow
                                                              .ellipsis,
                                                          style:
                                                              const TextStyle(
                                                            fontWeight:
                                                                FontWeight
                                                                    .w800,
                                                            fontSize: 14,
                                                          ),
                                                        ),
                                                      ),
                                                      Container(
                                                        padding:
                                                            const EdgeInsets
                                                                .symmetric(
                                                          horizontal: 8,
                                                          vertical: 2,
                                                        ),
                                                        decoration:
                                                            BoxDecoration(
                                                          color: _statusColor(
                                                                  o.status)
                                                              .withOpacity(
                                                                  0.12),
                                                          borderRadius:
                                                              BorderRadius
                                                                  .circular(
                                                                      999),
                                                        ),
                                                        child: Text(
                                                          o.statusLabel,
                                                          style: TextStyle(
                                                            fontSize: 11,
                                                            fontWeight:
                                                                FontWeight
                                                                    .w700,
                                                            color:
                                                                _statusColor(
                                                                    o.status),
                                                          ),
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                  const SizedBox(height: 4),
                                                  Text(
                                                    '${o.customerName} · ${o.phone}',
                                                    maxLines: 1,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    style: TextStyle(
                                                      fontSize: 12,
                                                      color: Colors
                                                          .grey.shade700,
                                                    ),
                                                  ),
                                                  const SizedBox(height: 2),
                                                  Text(
                                                    '${_money.format(o.total)}₫ · ${o.lines.length} món',
                                                    style: const TextStyle(
                                                      fontWeight:
                                                          FontWeight.w800,
                                                      fontSize: 13,
                                                      color: Color(0xFFC2410C),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                            const SizedBox(width: 6),
                                            Icon(Icons.chevron_right,
                                                color: Colors.grey.shade400),
                                          ],
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _ProductFilter {
  const _ProductFilter({required this.id, required this.name});
  final String id;
  final String name;
  factory _ProductFilter.fromJson(Map<String, dynamic> j) => _ProductFilter(
        id: (j['id'] ?? j['Id'] ?? '').toString(),
        name: (j['name'] ?? j['Name'] ?? '').toString(),
      );
}

class _StatusOpt {
  const _StatusOpt({required this.code, required this.label});
  final String code;
  final String label;
  factory _StatusOpt.fromJson(Map<String, dynamic> j) => _StatusOpt(
        code: (j['code'] ?? j['Code'] ?? '').toString(),
        label: (j['label'] ?? j['Label'] ?? '').toString(),
      );
}

class _OnlineOrder {
  const _OnlineOrder({
    required this.id,
    required this.orderNo,
    required this.status,
    required this.statusLabel,
    required this.customerName,
    required this.phone,
    required this.address,
    required this.note,
    required this.total,
    required this.lines,
    this.isPaid = false,
    this.canPay = false,
    this.canPrintProvisional = false,
    this.trackingCode = '',
    this.deliveryPartner = '',
    this.lat,
    this.lng,
  });

  final String id;
  final String orderNo;
  final String status;
  final String statusLabel;
  final String customerName;
  final String phone;
  final String address;
  final String note;
  final double total;
  final List<_OnlineLine> lines;
  final bool isPaid;
  final bool canPay;
  final bool canPrintProvisional;
  final String trackingCode;
  final String deliveryPartner;
  final double? lat;
  final double? lng;

  bool get hasGps => lat != null && lng != null;

  factory _OnlineOrder.fromJson(Map<String, dynamic> j) {
    final lines = <_OnlineLine>[];
    final raw = j['lines'] ?? j['Lines'];
    if (raw is List) {
      for (final e in raw) {
        if (e is! Map) continue;
        lines.add(_OnlineLine.fromJson(Map<String, dynamic>.from(e)));
      }
    }
    final note = (j['note'] ?? j['Note'] ?? '').toString();
    final address = (j['address'] ?? j['Address'] ?? '').toString();
    final gps = _parseGps(note) ??
        _parseGps(address) ??
        _parseGpsPair(j['lat'] ?? j['Lat'], j['lng'] ?? j['Lng']);
    return _OnlineOrder(
      id: (j['id'] ?? j['Id'] ?? '').toString(),
      orderNo: (j['orderNo'] ?? j['OrderNo'] ?? '').toString(),
      status: (j['status'] ?? j['Status'] ?? 'pending').toString(),
      statusLabel:
          (j['statusLabel'] ?? j['StatusLabel'] ?? '').toString(),
      customerName:
          (j['customerName'] ?? j['CustomerName'] ?? '').toString(),
      phone: (j['phone'] ?? j['Phone'] ?? '').toString(),
      address: address,
      note: note,
      total: (j['total'] as num?)?.toDouble() ??
          (j['Total'] as num?)?.toDouble() ??
          0,
      lines: lines,
      isPaid: j['isPaid'] == true || j['IsPaid'] == true,
      canPay: j['canPay'] == true || j['CanPay'] == true,
      canPrintProvisional:
          j['canPrintProvisional'] == true || j['CanPrintProvisional'] == true,
      trackingCode:
          (j['trackingCode'] ?? j['TrackingCode'] ?? '').toString(),
      deliveryPartner:
          (j['deliveryPartner'] ?? j['DeliveryPartner'] ?? '').toString(),
      lat: gps?.$1,
      lng: gps?.$2,
    );
  }
}

(double, double)? _parseGps(String text) {
  final m = RegExp(r'GPS\s*(-?\d+(?:\.\d+)?)\s*,\s*(-?\d+(?:\.\d+)?)',
          caseSensitive: false)
      .firstMatch(text);
  if (m == null) return null;
  final la = double.tryParse(m.group(1)!);
  final ln = double.tryParse(m.group(2)!);
  if (la == null || ln == null) return null;
  if (la < -90 || la > 90 || ln < -180 || ln > 180) return null;
  return (la, ln);
}

(double, double)? _parseGpsPair(dynamic lat, dynamic lng) {
  final la = lat is num ? lat.toDouble() : double.tryParse('$lat');
  final ln = lng is num ? lng.toDouble() : double.tryParse('$lng');
  if (la == null || ln == null) return null;
  if (la < -90 || la > 90 || ln < -180 || ln > 180) return null;
  return (la, ln);
}

class _OnlineLine {
  const _OnlineLine({
    required this.name,
    required this.qty,
    required this.lineTotal,
  });
  final String name;
  final double qty;
  final double lineTotal;
  factory _OnlineLine.fromJson(Map<String, dynamic> j) => _OnlineLine(
        name: (j['name'] ?? j['Name'] ?? '').toString(),
        qty: (j['qty'] as num?)?.toDouble() ??
            (j['Qty'] as num?)?.toDouble() ??
            0,
        lineTotal: (j['lineTotal'] as num?)?.toDouble() ??
            (j['LineTotal'] as num?)?.toDouble() ??
            0,
      );
}
