import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/pos_sale_order.dart';
import '../providers/auth_provider.dart';
import '../providers/permission_provider.dart';
import '../services/api_service.dart';
import '../widgets/pos/pos_cancel_return_reason_dialog.dart';
import '../utils/file_saver.dart' as file_saver;
import '../utils/pos_kiot_time_range.dart';
import '../utils/pos_sale_order_print.dart';
import '../utils/pos_sell_print_settings.dart';
import '../utils/pos_print_store_info.dart';
import '../utils/pos_sell_stock_patch.dart';
import '../utils/pos_mutation_result.dart';
import '../widgets/hrm_page_chrome.dart';
import '../widgets/loading_widget.dart';
import '../screens/main_layout.dart' show ScreenRefreshNotifier;
import '../widgets/notification_overlay.dart';
import '../widgets/pos/pos_kiot_time_filter.dart';
import '../utils/responsive_helper.dart';
import '../widgets/pos/pos_mobile_widgets.dart';
import '../widgets/pos/pos_hub_scope.dart';
import '../widgets/pos/pos_module_toolbar.dart';
import '../widgets/pos/pos_purchase_toolbar.dart';
import '../widgets/pos/pos_sale_order_helpers.dart';
import '../widgets/pos/pos_sale_order_receipt_view.dart';
import '../widgets/pos/pos_theme.dart';
import 'pos_sale_order_editor_screen.dart';
import 'pos_sale_return_screen.dart';
import 'package:sbox_pos/l10n/app_tr.dart';

enum _ListColumn {
  orderNo('Mã đơn'),
  time('Thời gian'),
  customer('Khách hàng'),
  subTotal('Tạm tính'),
  discount('Giảm giá'),
  total('Tổng'),
  paid('Đã trả'),
  balance('Còn lại'),
  delivery('Giao hàng'),
  deliveryStatus('TT giao hàng'),
  status('Trạng thái');

  const _ListColumn(this.label);
  final String label;
}

/// Cột mặc định gọn — tránh bảng quá nhiều cột gây rối (còn lại bật trong Tùy chọn cột).
Set<_ListColumn> _defaultListColumns() => {
      _ListColumn.orderNo,
      _ListColumn.time,
      _ListColumn.customer,
      _ListColumn.total,
      _ListColumn.status,
    };

class PosSaleOrderListScreen extends StatefulWidget {
  const PosSaleOrderListScreen({super.key});

  @override
  State<PosSaleOrderListScreen> createState() => _PosSaleOrderListScreenState();
}

class _PosSaleOrderListScreenState extends State<PosSaleOrderListScreen> {
  final _api = ApiService();
  final _searchCtrl = TextEditingController();
  final _moneyFmt = NumberFormat('#,##0', 'vi_VN');
  final _dateFmt = DateFormat('dd/MM/yyyy HH:mm', 'vi_VN');

  bool _loading = true;
  String? _completingId;
  List<PosSaleOrder> _items = [];
  int _total = 0;
  int _page = 1;
  static const _pageSize = 50;

  final Set<String> _statusFilter = {'Completed', 'Cancelled'};
  String? _paymentMethod;
  bool? _isDeliveryFilter;
  PosKiotTimeFilterState _timeFilter = PosKiotTimeFilterState.thisMonth();
  Set<_ListColumn> _visibleColumns = _defaultListColumns();
  bool _exporting = false;
  double? _periodRevenue;

  String? _expandedId;
  PosSaleOrder? _expandedDetail;
  bool _detailLoading = false;
  int _detailTab = 0;
  List<Map<String, dynamic>> _payments = [];

  static const _paymentMethods = [
    null,
    'Tiền mặt',
    'Chuyển khoản',
    'Thẻ',
  ];

  @override
  void initState() {
    super.initState();
    ScreenRefreshNotifier.posSaleOrders.addListener(_onExternalRefresh);
    _load();
  }

  void _onExternalRefresh() {
    if (mounted) _load(page: _page);
  }

  @override
  void dispose() {
    ScreenRefreshNotifier.posSaleOrders.removeListener(_onExternalRefresh);
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load({int page = 1}) async {
    setState(() => _loading = true);
    if (_statusFilter.isEmpty) {
      if (mounted) {
        setState(() {
          _loading = false;
          _items = [];
          _total = 0;
        });
      }
      return;
    }

    final res = await _api.getPosSales(
      search: _searchCtrl.text.trim().isEmpty ? null : _searchCtrl.text.trim(),
      statuses: _statusFilter.toList(),
      paymentMethod: _paymentMethod,
      isDelivery: _isDeliveryFilter,
      from: _timeFilter.from,
      to: _timeFilter.to,
      page: page,
      pageSize: _pageSize,
    );

    if (!mounted) return;
    if (res['isSuccess'] == true && res['data'] is Map) {
      final data = res['data'] as Map;
      setState(() {
        _loading = false;
        _page = page;
        _total = (data['total'] as num?)?.toInt() ?? 0;
        _items = ((data['items'] as List?) ?? [])
            .map((e) => PosSaleOrder.fromJson(e as Map<String, dynamic>))
            // Slot bán hàng (TMP…) không hiện trong DS đơn — chỉ dùng tab Bán hàng.
            .where((o) => !(o.status == 'Draft' &&
                o.orderNo.toUpperCase().startsWith('TMP')))
            .toList();
      });
      await _loadPeriodSummary();
    } else {
      setState(() => _loading = false);
    }
  }

  Future<void> _toggleExpand(PosSaleOrder summary) async {
    if (_expandedId == summary.id) {
      setState(() {
        _expandedId = null;
        _expandedDetail = null;
        _payments = [];
      });
      return;
    }
    setState(() {
      _expandedId = summary.id;
      _expandedDetail = null;
      _detailLoading = true;
      _detailTab = 0;
      _payments = [];
    });

    final res = await _api.getPosSale(summary.id);
    if (!mounted || _expandedId != summary.id) return;
    if (res['isSuccess'] == true) {
      setState(() {
        _expandedDetail =
            PosSaleOrder.fromJson(res['data'] as Map<String, dynamic>);
        _detailLoading = false;
      });
    } else {
      setState(() => _detailLoading = false);
    }
  }

  void _collapseExpanded() {
    setState(() {
      _expandedId = null;
      _expandedDetail = null;
      _payments = [];
    });
  }

  Future<void> _refreshExpandedDetail(String id) async {
    if (_expandedId != id) return;
    final res = await _api.getPosSale(id);
    if (!mounted || _expandedId != id) return;
    if (res['isSuccess'] == true && res['data'] is Map<String, dynamic>) {
      setState(() {
        _expandedDetail =
            PosSaleOrder.fromJson(res['data'] as Map<String, dynamic>);
      });
    } else {
      _collapseExpanded();
    }
  }

  Future<void> _loadPayments(String id) async {
    final res = await _api.getPosSalePayments(id);
    if (!mounted) return;
    if (res['isSuccess'] == true && res['data'] is List) {
      setState(() {
        _payments = (res['data'] as List).cast<Map<String, dynamic>>();
      });
    }
  }

  void _toggleStatus(String status, bool? v) {
    setState(() {
      if (v == true) {
        _statusFilter.add(status);
      } else {
        _statusFilter.remove(status);
      }
    });
    _load();
  }

  void _onTimeFilterChanged(PosKiotTimeFilterState s) {
    setState(() => _timeFilter = s);
    _load();
  }

  Future<void> _printOrder(PosSaleOrder o) async {
    PosSaleOrder order = o;
    if (order.lines.isEmpty) {
      final res = await _api.getPosSale(o.id);
      if (res['isSuccess'] == true && mounted) {
        order = PosSaleOrder.fromJson(res['data'] as Map<String, dynamic>);
      }
    }
    if (!mounted) return;
    final printSettings = await PosSellPrintSettings.load();
    final store = await PosPrintStoreInfo.load();
    if (!mounted) return;
    await printPosSaleOrder(
      context: context,
      order: order,
      branchName: store.storeName,
      storeAddress: store.address,
      storePhone: store.phone,
      mergeSameItems: printSettings.mergeSameItems,
      copies: printSettings.copies,
      templateId: printSettings.templateId,
      skipDedup: true,
      preferDevicePrintOnly: true,
      showFeedback: true,
      openCashDrawer: false,
    );
    // Làm mới printCount trên danh sách sau khi ghi nhận in.
    if (!mounted) return;
    final refreshed = await _api.getPosSale(o.id);
    if (refreshed['isSuccess'] == true && refreshed['data'] is Map) {
      _patchOrderInList(
        PosSaleOrder.fromJson(refreshed['data'] as Map<String, dynamic>),
      );
    }
  }

  void _patchOrderInList(PosSaleOrder updated) {
    setState(() {
      _items = _items.map((x) => x.id == updated.id ? updated : x).toList();
      if (_expandedId == updated.id) _expandedDetail = updated;
    });
  }

  /// Giữ trạng thái từ API mutation (hủy/hoàn thành) nếu reload danh sách trả dữ liệu cũ.
  void _reconcileOrderAfterLoad(PosSaleOrder authoritative) {
    if (!mounted) return;
    final idx = _items.indexWhere((x) => x.id == authoritative.id);
    if (idx < 0) return;
    if (_items[idx].status != authoritative.status ||
        _items[idx].returnStatus != authoritative.returnStatus) {
      _patchOrderInList(authoritative);
    } else if (_expandedId == authoritative.id) {
      setState(() => _expandedDetail = authoritative);
    }
  }

  Future<void> _cancelOrder(PosSaleOrder o) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Hủy đơn (hoàn kho)')),
        content: Text(tr('${tr('Hủy đơn ')}${o.orderNo}?\n\n'
            '• Hoàn kho hàng đã bán\n'
            '• Hoàn công nợ / điểm / voucher (nếu có)\n'
            '• Đơn chuyển sang «Đã hủy» (vẫn thấy trong danh sách)\n\n'
            'Chỉ dùng khi đơn đã hoàn thành và chưa trả hàng.')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Không'))),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: Text(tr('Hủy đơn')),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final reasonCfg = await fetchCancelReturnReasonConfig(_api);
    if (!mounted) return;
    final reasonResult = await showPosCancelReturnReasonDialog(
      context,
      config: reasonCfg,
      title: 'Lý do hủy đơn',
    );
    if (reasonResult == null || !mounted) return;
    final res = await _api.cancelPosSale(
      o.id,
      reason: reasonResult.reason.isEmpty ? null : reasonResult.reason,
      detailNote: reasonResult.detailNote,
    );
    if (!mounted) return;
    if (res['isSuccess'] == true) {
      if (res['data'] is! Map<String, dynamic>) {
        NotificationOverlayManager().showError(
          title: 'Lỗi',
          message: tr('Server không trả về dữ liệu đơn — vui lòng tải lại danh sách'),
        );
        await _load(page: _page);
        return;
      }
      final updated = PosSaleOrder.fromJson(res['data'] as Map<String, dynamic>);
      if (updated.status != 'Cancelled') {
        NotificationOverlayManager().showError(
          title: 'Lỗi',
          message: tr('Đơn vẫn ở trạng thái ${posSaleOrderStatusLabel(updated.status)} — chưa hủy được trên server'),
        );
        await _load(page: _page);
        return;
      }
      _patchOrderInList(updated);
      final stockLines = updated.lines
          .where((line) => line.productId.isNotEmpty && line.qty > 0)
          .map(
            (line) => PosSellStockLineDelta(
              productId: line.productId,
              variantId: line.variantId,
              qty: line.qty,
              addBack: true,
            ),
          )
          .toList();
      ScreenRefreshNotifier.refreshPosAfterStockChange(sellStockLines: stockLines);
      NotificationOverlayManager().showSuccess(
          title: 'Đã hủy đơn',
          message: tr('${o.orderNo} · trạng thái: Đã hủy'));
      await _load(page: _page);
      _reconcileOrderAfterLoad(updated);
      if (mounted) setState(() {});
    } else {
      NotificationOverlayManager().showError(
          title: 'Lỗi', message: res['message']?.toString() ?? 'Không hủy được');
    }
  }

  Future<void> _deleteOrder(PosSaleOrder o) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Xóa khỏi danh sách')),
        content: Text(tr('${tr('Ẩn đơn ')}${o.orderNo} khỏi danh sách?\n\n'
            '• Không hoàn kho thêm (kho đã xử lý trước đó)\n'
            '• Chỉ xóa khỏi màn hình — dữ liệu vẫn lưu trên server\n\n'
            'Dùng cho đơn đã hủy, đơn tạm, hoặc đơn đã trả hết 100%.')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Không'))),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: Text(tr('Xóa')),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final res = await _api.deletePosSale(o.id);
    if (!mounted) return;
    final deleteResult = PosDocMutationResult.parseDelete(
      Map<String, dynamic>.from(res),
    );
    if (deleteResult.ok) {
      NotificationOverlayManager().showSuccess(title: 'Đã xóa', message: o.orderNo);
      _collapseExpanded();
      setState(() {
        _items = _items.where((x) => x.id != o.id).toList();
        if (_total > 0) _total -= 1;
      });
      ScreenRefreshNotifier.refreshPosAfterStockChange();
      await _loadPeriodSummary();
    } else {
      NotificationOverlayManager().showError(
        title: 'Lỗi',
        message: deleteResult.errorMessage ?? res['message']?.toString() ?? 'Không xóa được',
      );
    }
  }

  Future<void> _openEditor({String? orderId}) async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => PosSaleOrderEditorScreen(orderId: orderId),
      ),
    );
    if (mounted) _load(page: _page);
  }

  Future<void> _completeOrder(PosSaleOrder o) async {
    if (_completingId != null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Hoàn thành đơn')),
        content: Text(tr('Xác nhận hoàn thành đơn ${o.orderNo} và trừ kho?')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Không'))),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: PosTheme.kiotBlue),
            child: Text(tr('Hoàn thành')),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _completingId = o.id);
    try {
    var res = await _api.completePosSale(o.id);
    final msg = (res['message'] ?? '').toString().toLowerCase();
    if (res['isSuccess'] != true &&
        res['statusCode'] == 409 &&
        (msg.contains('xung đột') ||
            msg.contains('trùng mã') ||
            msg.contains('đồng thời'))) {
      await Future<void>.delayed(const Duration(milliseconds: 350));
      if (!mounted) return;
      res = await _api.completePosSale(o.id);
    }
    if (!mounted) return;
    if (res['isSuccess'] == true) {
      PosSaleOrder? updated;
      if (res['data'] is Map<String, dynamic>) {
        updated = PosSaleOrder.fromJson(res['data'] as Map<String, dynamic>);
        _patchOrderInList(updated);
      }
      final stockLines = (updated?.lines ?? o.lines)
          .where((line) => line.productId.isNotEmpty && line.qty > 0)
          .map(
            (line) => PosSellStockLineDelta(
              productId: line.productId,
              variantId: line.variantId,
              qty: line.qty,
              addBack: false,
            ),
          )
          .toList();
      ScreenRefreshNotifier.refreshPosAfterStockChange(sellStockLines: stockLines);
      NotificationOverlayManager().showSuccess(title: 'Hoàn thành', message: o.orderNo);
      await _load(page: _page);
      if (updated != null) _reconcileOrderAfterLoad(updated);
      await _refreshExpandedDetail(o.id);
      if (mounted) setState(() {});
    } else {
      NotificationOverlayManager()
          .showError(title: 'Lỗi', message: res['message']?.toString() ?? '');
    }
    } finally {
      if (mounted) setState(() => _completingId = null);
    }
  }

  void _showColumnPicker() {
    showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          title: Text(tr('Tùy chọn cột')),
          content: SizedBox(
            width: 280,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: _ListColumn.values.map((c) {
                  return CheckboxListTile(
                    dense: true,
                    activeColor: PosTheme.kiotBlue,
                    title: Text(tr(c.label), style: const TextStyle(fontSize: 13)),
                    value: _visibleColumns.contains(c),
                    onChanged: (v) {
                      setDlg(() {
                        if (v == true) {
                          _visibleColumns.add(c);
                        } else if (_visibleColumns.length > 1) {
                          _visibleColumns.remove(c);
                        }
                      });
                    },
                  );
                }).toList(),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => setDlg(() => _visibleColumns = _defaultListColumns()),
              child: Text(tr('Mặc định')),
            ),
            FilledButton(
              onPressed: () {
                setState(() {});
                Navigator.pop(ctx);
              },
              style: FilledButton.styleFrom(backgroundColor: PosTheme.kiotBlue),
              child: Text(tr('Áp dụng')),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _exportExcel(PermissionProvider perm) async {
    if (!perm.canExport('PosSaleOrders') && !perm.canExport('PosProducts')) return;
    setState(() => _exporting = true);
    try {
      final res = await _api.exportPosSalesExcel(
        search: _searchCtrl.text.trim().isEmpty ? null : _searchCtrl.text.trim(),
        statuses: _statusFilter.toList(),
        paymentMethod: _paymentMethod,
        isDelivery: _isDeliveryFilter,
        from: _timeFilter.from,
        to: _timeFilter.to,
      );
      if (res['isSuccess'] == true) {
        final bytes = Uint8List.fromList(List<int>.from(res['data']));
        await file_saver.saveFileBytes(
          bytes,
          'don_hang_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.xlsx',
          'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        );
        NotificationOverlayManager()
            .showSuccess(title: 'Xuất file', message: tr('Đã xuất Excel đơn hàng'));
      } else {
        NotificationOverlayManager().showError(
            title: 'Lỗi', message: res['message']?.toString() ?? 'Export thất bại');
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _copyOrder(PosSaleOrder o) async {
    final res = await _api.copyPosSale(o.id);
    if (!mounted) return;
    if (res['isSuccess'] == true && res['data'] != null) {
      final copy = PosSaleOrder.fromJson(res['data'] as Map<String, dynamic>);
      NotificationOverlayManager()
          .showSuccess(title: 'Sao chép', message: tr('Đã tạo ${copy.orderNo}'));
      await _openEditor(orderId: copy.id);
    } else {
      NotificationOverlayManager().showError(
          title: 'Lỗi', message: res['message']?.toString() ?? 'Không sao chép được');
    }
  }

  double _balance(PosSaleOrder o) =>
      o.balanceDue != 0 ? o.balanceDue : o.total - o.paidAmount;

  int get _activeFilterCount {
    var n = 0;
    if (_paymentMethod != null) n++;
    if (_isDeliveryFilter != null) n++;
    if (_statusFilter.length < 3) n++;
    return n;
  }

  Widget _buildFilterPanel() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        saleFilterSection(
          'Trạng thái',
          Column(
            children: [
              CheckboxListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(tr('Đang xử lý'), style: TextStyle(fontSize: 13)),
                value: _statusFilter.contains('Draft'),
                activeColor: PosTheme.kiotBlue,
                onChanged: (v) => _toggleStatus('Draft', v),
              ),
              CheckboxListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(tr('Hoàn thành'), style: TextStyle(fontSize: 13)),
                value: _statusFilter.contains('Completed'),
                activeColor: PosTheme.kiotBlue,
                onChanged: (v) => _toggleStatus('Completed', v),
              ),
              CheckboxListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(tr('Đã hủy'), style: TextStyle(fontSize: 13)),
                value: _statusFilter.contains('Cancelled'),
                activeColor: PosTheme.kiotBlue,
                onChanged: (v) => _toggleStatus('Cancelled', v),
              ),
            ],
          ),
        ),
        saleFilterSection(
          'Thời gian',
          PosKiotTimeFilter(state: _timeFilter, onChanged: _onTimeFilterChanged),
        ),
        saleFilterSection(
          'Loại đơn',
          Column(
            children: [
              RadioListTile<bool?>(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(tr('Tất cả'), style: TextStyle(fontSize: 13)),
                value: null,
                groupValue: _isDeliveryFilter,
                activeColor: PosTheme.kiotBlue,
                onChanged: (v) {
                  setState(() => _isDeliveryFilter = v);
                  _load();
                },
              ),
              RadioListTile<bool?>(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(tr('Không giao hàng'), style: TextStyle(fontSize: 13)),
                value: false,
                groupValue: _isDeliveryFilter,
                activeColor: PosTheme.kiotBlue,
                onChanged: (v) {
                  setState(() => _isDeliveryFilter = v);
                  _load();
                },
              ),
              RadioListTile<bool?>(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(tr('Giao hàng'), style: TextStyle(fontSize: 13)),
                value: true,
                groupValue: _isDeliveryFilter,
                activeColor: PosTheme.kiotBlue,
                onChanged: (v) {
                  setState(() => _isDeliveryFilter = v);
                  _load();
                },
              ),
            ],
          ),
        ),
        saleFilterSection(
          'Thanh toán',
          DropdownButtonFormField<String?>(
            isDense: true,
            value: _paymentMethod,
            decoration: const InputDecoration(
              isDense: true,
              border: OutlineInputBorder(),
              contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            ),
            hint: Text(tr('Tất cả'), style: TextStyle(fontSize: 12)),
            items: _paymentMethods
                .map(
                  (m) => DropdownMenuItem<String?>(
                    value: m,
                    child: Text(tr(m ?? 'Tất cả'), style: const TextStyle(fontSize: 12)),
                  ),
                )
                .toList(),
            onChanged: (v) {
              setState(() => _paymentMethod = v);
              _load();
            },
          ),
        ),
        FilledButton(
          onPressed: () => _load(),
          style: FilledButton.styleFrom(backgroundColor: PosTheme.kiotBlue),
          child: Text(tr('Áp dụng lọc'), style: TextStyle(fontSize: 12)),
        ),
      ],
    );
  }

  Future<void> _loadPeriodSummary() async {
    final res = await _api.getPosSalesReportSummary(
      from: _timeFilter.from,
      to: _timeFilter.to,
    );
    if (!mounted) return;
    if (res['isSuccess'] == true && res['data'] is Map) {
      final d = res['data'] as Map;
      setState(() {
        _periodRevenue = (d['totalRevenue'] as num?)?.toDouble();
      });
    }
  }

  Future<void> _resetFilters() async {
    setState(() {
      _statusFilter
        ..clear()
        ..addAll({'Completed', 'Cancelled'});
      _paymentMethod = null;
      _isDeliveryFilter = null;
      _timeFilter = PosKiotTimeFilterState.thisMonth();
    });
    await _load();
  }

  void _openFilters() {
    showPosMobileFilterSheet(
      context,
      child: _buildFilterPanel(),
      onReset: _resetFilters,
      onApply: () => _load(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final perm = Provider.of<PermissionProvider>(context);
    if (!perm.canView('PosProducts')) {
      return Scaffold(
          body: Center(child: Text(tr('Không có quyền xem đơn hàng'))));
    }
    final canEdit =
        perm.canEdit('PosSaleOrders') || perm.canEdit('PosProducts');
    final mobile = posUseMobileList(context);
    final inHub = PosHubScope.of(context);

    return Scaffold(
      backgroundColor: HrmPageChrome.background,
      body: Column(
        children: [
          if (!inHub) const PosModuleToolbar(activeModule: 'PosSaleOrders'),
          if (mobile)
            PosMobileKiotHeader(
              title: 'Hoá đơn',
              onFilter: _openFilters,
              onRefresh: () => _load(page: _page),
              activeFilterCount: _activeFilterCount,
              filterChips: Padding(
                padding: const EdgeInsets.only(left: 4),
                child: ActionChip(
                  label: Text(tr(_timeFilter.displayLabel),
                      style: const TextStyle(fontSize: 12)),
                  onPressed: _openFilters,
                ),
              ),
            )
          else
            PosMobileListHeader(
              icon: Icons.receipt_long,
              title: 'Hóa đơn',
              onRefresh: () => _load(page: _page),
              onOpenFilters: null,
              activeFilterCount: _activeFilterCount,
              trailing: [
                if (perm.canExport('PosSaleOrders') ||
                    perm.canExport('PosProducts'))
                  IconButton(
                    onPressed: _exporting ? null : () => _exportExcel(perm),
                    icon: _exporting
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.download_outlined),
                    tooltip: tr('Xuất Excel'),
                  ),
                IconButton(
                  onPressed: _showColumnPicker,
                  icon: const Icon(Icons.view_column_outlined),
                  tooltip: tr('Thêm cột'),
                ),
              ],
            ),
          if (mobile) _buildMobileSummaryCard(),
          Expanded(
            child: PosResponsiveFilterLayout(
              filterPanel: PosPurchaseFilterPanel(child: _buildFilterPanel()),
              child: Column(
                children: [
                  Padding(
                    padding: EdgeInsets.fromLTRB(
                        12, posUseMobileList(context) ? 8 : 10, 12, 0),
                    child: TextField(
                      controller: _searchCtrl,
                      decoration: InputDecoration(
                        hintText: tr('Tìm mã đơn, khách hàng…'),
                        prefixIcon: Icon(Icons.search, size: 20),
                        border: OutlineInputBorder(),
                        isDense: true,
                        filled: true,
                        fillColor: Colors.white,
                      ),
                      onSubmitted: (_) => _load(),
                    ),
                  ),
                  Expanded(
                    child: _loading
                        ? const LoadingWidget()
                        : _items.isEmpty
                            ? RefreshIndicator(
                                onRefresh: () => _load(page: _page),
                                child: ListView(
                                  physics:
                                      const AlwaysScrollableScrollPhysics(),
                                  children: [
                                    SizedBox(height: 120),
                                    Center(child: Text(tr('Chưa có đơn hàng'))),
                                  ],
                                ),
                              )
                            : Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.stretch,
                                children: [
                                  _buildTableHeader(),
                                  Expanded(child: _buildList(canEdit)),
                                ],
                              ),
                  ),
                  _buildPager(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPager() {
    if (posUseMobileList(context)) {
      return PosMobilePager(
        total: _total,
        page: _page,
        pageSize: _pageSize,
        label: 'đơn',
        onPageChanged: (p) => _load(page: p),
      );
    }
    if (_total <= _pageSize) return const SizedBox.shrink();
    final pages = (_total / _pageSize).ceil();
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          Text(tr('Tổng $_total đơn'),
              style:
                  const TextStyle(fontSize: 12, color: PosTheme.textSecondary)),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.chevron_left),
            onPressed: _page > 1 ? () => _load(page: _page - 1) : null,
          ),
          Text(tr('Trang $_page / $pages'), style: const TextStyle(fontSize: 12)),
          IconButton(
            icon: const Icon(Icons.chevron_right),
            onPressed: _page < pages ? () => _load(page: _page + 1) : null,
          ),
        ],
      ),
    );
  }

  Widget _buildTableHeader() {
    if (posUseMobileList(context)) return const SizedBox.shrink();
    TextStyle h = const TextStyle(
        fontSize: 11, fontWeight: FontWeight.w600, color: PosTheme.textSecondary);
    Widget col(_ListColumn c, {int flex = 2, TextAlign align = TextAlign.left}) {
      if (!_visibleColumns.contains(c)) return const SizedBox.shrink();
      return Expanded(
        flex: flex,
        child: Text(tr(c.label), style: h, textAlign: align),
      );
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          const SizedBox(width: 24),
          col(_ListColumn.orderNo),
          col(_ListColumn.time),
          col(_ListColumn.customer),
          col(_ListColumn.subTotal, align: TextAlign.right),
          col(_ListColumn.discount, align: TextAlign.right),
          col(_ListColumn.total, align: TextAlign.right),
          col(_ListColumn.paid, align: TextAlign.right),
          col(_ListColumn.balance, align: TextAlign.right),
          col(_ListColumn.delivery, flex: 1),
          col(_ListColumn.deliveryStatus, flex: 2),
          col(_ListColumn.status, flex: 1, align: TextAlign.right),
        ],
      ),
    );
  }

  Widget _buildMobileSummaryCard() {
    final completed = _items.where((o) => o.status == 'Completed');
    final totalAmount = _periodRevenue ??
        completed.fold<double>(0, (s, o) => s + o.total);
    final returnedTotal =
        completed.fold<double>(0, (s, o) => s + o.returnedAmount);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Container(
        decoration: PosTheme.mobileCardDecoration(),
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(tr('Doanh thu thuần'),
                    style: TextStyle(
                      fontSize: 13,
                      color: PosTheme.textSecondary,
                    ),
                  ),
                  Text(
                    tr('$_total hoá đơn${returnedTotal > 0 ? ' · Hoàn trả ${_moneyFmt.format(returnedTotal)}' : ''}'),
                    style: const TextStyle(fontSize: 12, color: PosTheme.textSecondary),
                  ),
                ],
              ),
            ),
            Text(
              tr(_moneyFmt.format(totalAmount)),
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  double _daySalesTotal(List<PosSaleOrder> orders) => orders
      .where((o) => o.status == 'Completed')
      .fold<double>(0, (sum, o) => sum + o.total);

  double _dayReturnTotal(List<PosSaleOrder> orders) => orders
      .where((o) => o.status == 'Completed')
      .fold<double>(0, (sum, o) => sum + o.returnedAmount);

  Widget _buildOrderTotalColumn(PosSaleOrder o) {
    final cancelled = o.status == 'Cancelled';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(tr('${_moneyFmt.format(o.total)} đ'),
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.bold,
            color: cancelled ? Colors.red.shade800 : null,
            decoration: cancelled ? TextDecoration.lineThrough : null,
            decorationColor: cancelled ? Colors.red.shade400 : null,
          ),
        ),
        if (o.hasReturns)
          Container(
            margin: const EdgeInsets.only(top: 2),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(
              color: Colors.orange.shade50,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(tr('Đã trả ${_moneyFmt.format(o.returnedAmount)}'),
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: Colors.orange.shade800,
              ),
            ),
          ),
      ],
    );
  }

  String _dayHeaderLabel(String key) {
    if (key == 'unknown') return 'KHÔNG RÕ NGÀY';
    final d = DateTime.parse(key);
    final dayFmt = DateFormat('dd/MM/yyyy', 'vi_VN');
    final today = DateTime.now();
    final isToday =
        d.year == today.year && d.month == today.month && d.day == today.day;
    return isToday
        ? 'HÔM NAY ${dayFmt.format(d)}'
        : dayFmt.format(d).toUpperCase();
  }

  Widget _buildList(bool canEdit) => _buildGroupedList(canEdit);

  Widget _buildGroupedList(bool canEdit) {
    final groups = <String, List<PosSaleOrder>>{};
    final order = <String>[];
    for (final o in _items) {
      final dt = o.saleDate ?? o.createdAt;
      final key = dt != null
          ? DateFormat('yyyy-MM-dd').format(dt.toLocal())
          : 'unknown';
      if (!groups.containsKey(key)) {
        groups[key] = [];
        order.add(key);
      }
      groups[key]!.add(o);
    }

    final children = <Widget>[];
    for (final key in order) {
      final list = groups[key]!;
      final label = _dayHeaderLabel(key);
      final dayNet = _daySalesTotal(list);
      final dayReturn = _dayReturnTotal(list);
      children.add(
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 12, 4, 6),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  tr(label),
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: PosTheme.textSecondary,
                    letterSpacing: 0.3,
                  ),
                ),
              ),
              Text(
                tr(dayReturn > 0
                    ? 'Thuần ${_moneyFmt.format(dayNet)} · Trả ${_moneyFmt.format(dayReturn)}'
                    : 'Tổng ngày: ${_moneyFmt.format(dayNet)} đ'),
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: PosTheme.kiotBlue,
                ),
              ),
            ],
          ),
        ),
      );
      for (final o in list) {
        if (posUseMobileList(context)) {
          children.add(_buildKiotInvoiceTile(o, canEdit));
        } else {
          children.add(_buildOrderBlock(o, canEdit));
        }
      }
    }

    return RefreshIndicator(
      onRefresh: () => _load(page: _page),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
        children: children,
      ),
    );
  }

  Future<void> _showMobileOrderDetail(PosSaleOrder summary, bool canEdit) async {
    PosSaleOrder order = summary;
    final res = await _api.getPosSale(summary.id);
    if (mounted && res['isSuccess'] == true && res['data'] is Map<String, dynamic>) {
      order = PosSaleOrder.fromJson(res['data'] as Map<String, dynamic>);
      _patchOrderInList(order);
    }
    if (!mounted) return;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.88,
        minChildSize: 0.45,
        maxChildSize: 0.95,
        builder: (_, scrollCtrl) => Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 8, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      tr(order.orderNo),
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  posSaleOrderStatusChip(order.status, returnStatus: order.returnStatus),
                  IconButton(
                    onPressed: () => Navigator.pop(ctx),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: SingleChildScrollView(
                controller: scrollCtrl,
                child: PosSaleOrderReceiptView(order: order),
              ),
            ),
            const Divider(height: 1),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (order.status == 'Completed')
                      FilledButton.icon(
                        onPressed: () {
                          Navigator.pop(ctx);
                          _printOrder(order);
                        },
                        icon: const Icon(Icons.print, size: 16),
                        label: Text(
                          tr(order.printCount > 0
                              ? 'In lại (đã in ${order.printCount} lần)'
                              : 'In'),
                        ),
                        style: FilledButton.styleFrom(backgroundColor: PosTheme.kiotBlue),
                      ),
                    if (canEdit && order.status == 'Draft')
                      FilledButton.icon(
                        onPressed: () {
                          Navigator.pop(ctx);
                          _openEditor(orderId: order.id);
                        },
                        icon: const Icon(Icons.edit, size: 16),
                        label: Text(tr('Chỉnh sửa')),
                      ),
                    if (canEdit && order.canCancelWithStock)
                      OutlinedButton.icon(
                        onPressed: () {
                          Navigator.pop(ctx);
                          _cancelOrder(order);
                        },
                        icon: const Icon(Icons.cancel_outlined, size: 16),
                        label: Text(tr('Hủy đơn (hoàn kho)')),
                      ),
                    if (canEdit &&
                        order.status == 'Completed' &&
                        !order.isFullyReturned)
                      OutlinedButton.icon(
                        onPressed: () async {
                          Navigator.pop(ctx);
                          final ok = await Navigator.of(context).push<bool>(
                            MaterialPageRoute(
                              builder: (_) => PosSaleReturnScreen(orderId: order.id),
                            ),
                          );
                          if (ok == true && mounted) _load();
                        },
                        icon: const Icon(Icons.assignment_return_outlined, size: 16),
                        label: Text(tr('Trả hàng')),
                      ),
                    if (canEdit && order.canDeleteFromList)
                      OutlinedButton.icon(
                        onPressed: () {
                          Navigator.pop(ctx);
                          _deleteOrder(order);
                        },
                        icon: const Icon(Icons.delete_outline, size: 16),
                        style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
                        label: Text(tr(order.status == 'Draft'
                            ? 'Xóa phiếu tạm'
                            : 'Xóa khỏi DS')),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildKiotInvoiceTile(PosSaleOrder o, bool canEdit) {
    final dt = o.saleDate ?? o.createdAt;
    final timeStr =
        dt != null ? DateFormat('dd/MM/yyyy HH:mm', 'vi_VN').format(dt.toLocal()) : '—';
    final firstLine = o.lines.isNotEmpty ? o.lines.first : null;
    final isCancelled = o.status == 'Cancelled';

    return Material(
      color: posSaleOrderRowBackground(o.status),
      child: InkWell(
        onTap: () => _showMobileOrderDetail(o, canEdit),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Dòng 1: khách (cỡ nhỏ hơn để hết 1 hàng) · tổng tiền phải
              Row(
                children: [
                  if (isCancelled) ...[
                    Icon(Icons.cancel, size: 16, color: Colors.red.shade700),
                    const SizedBox(width: 4),
                  ],
                  Expanded(
                    child: Text(
                      tr(o.customerName ?? 'Khách lẻ'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        height: 1.2,
                        color: isCancelled ? Colors.red.shade800 : null,
                        decoration:
                            isCancelled ? TextDecoration.lineThrough : null,
                        decorationColor:
                            isCancelled ? Colors.red.shade400 : null,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  _buildOrderTotalColumn(o),
                ],
              ),
              const SizedBox(height: 4),
              // Dòng 2: mã đơn trái · trạng thái (dưới tổng tiền) phải
              Row(
                children: [
                  Expanded(
                    child: Text(
                      tr(o.orderNo),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: PosTheme.textPrimary,
                      ),
                    ),
                  ),
                  posSaleOrderStatusChip(o.status, returnStatus: o.returnStatus),
                ],
              ),
              const SizedBox(height: 2),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      tr(timeStr),
                      style: const TextStyle(
                        fontSize: 11,
                        color: PosTheme.textSecondary,
                      ),
                    ),
                  ),
                  Text(
                    tr(o.paymentMethod),
                    style: const TextStyle(
                      fontSize: 11,
                      color: PosTheme.textSecondary,
                    ),
                  ),
                ],
              ),
              if (firstLine != null) ...[
                const SizedBox(height: 6),
                Text(
                  tr('${firstLine.productName} x${_qtyFmt(firstLine.qty)}'),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, color: PosTheme.textSecondary),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  String _qtyFmt(double q) {
    return q == q.roundToDouble() ? q.toStringAsFixed(0) : q.toStringAsFixed(1);
  }

  Widget _buildOrderBlock(PosSaleOrder o, bool canEdit) {
    final expanded = _expandedId == o.id;
    final dt = o.saleDate ?? o.createdAt;
    if (posUseMobileList(context)) {
      return PosMobileExpandableDocCard(
        expanded: expanded,
        onTap: () => _toggleExpand(o),
        code: o.orderNo,
        status: posSaleOrderStatusChip(o.status, returnStatus: o.returnStatus),
        accentColor: posSaleOrderAccentColor(o.status, fallback: PosTheme.kiotBlue),
        fields: [
          PosMobileField(
            'Thời gian',
            dt != null ? _dateFmt.format(dt.toLocal()) : '—',
          ),
          PosMobileField('Khách', o.customerName ?? 'Khách lẻ'),
          PosMobileField('Tổng', '${_moneyFmt.format(o.total)} đ'),
          if (o.hasReturns)
            PosMobileField('Đã trả', '${_moneyFmt.format(o.returnedAmount)} đ'),
        ],
        detail: expanded ? _buildDetailPanel(o, canEdit) : null,
      );
    }
    return Material(
      color: posSaleOrderRowBackground(o.status),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: () => _toggleExpand(o),
            hoverColor: o.status == 'Cancelled'
                ? Colors.red.shade100.withOpacity(0.35)
                : const Color(0xFFF1F5F9),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                      color: expanded ? Colors.grey.shade200 : Colors.transparent),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    expanded ? Icons.keyboard_arrow_down : Icons.keyboard_arrow_right,
                    size: 20,
                    color: o.status == 'Cancelled'
                        ? Colors.red.shade700
                        : PosTheme.textSecondary,
                  ),
                  const SizedBox(width: 4),
                  if (_visibleColumns.contains(_ListColumn.orderNo))
                    Expanded(
                      flex: 2,
                      child: Text(
                        tr(o.orderNo),
                        style: TextStyle(
                          color: posSaleOrderAccentColor(o.status, fallback: PosTheme.kiotBlue),
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                          decoration: o.status == 'Cancelled'
                              ? TextDecoration.lineThrough
                              : null,
                        ),
                      ),
                    ),
                  if (_visibleColumns.contains(_ListColumn.time))
                    Expanded(
                      flex: 2,
                      child: Text(
                        tr(dt != null ? _dateFmt.format(dt.toLocal()) : '—'),
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                  if (_visibleColumns.contains(_ListColumn.customer))
                    Expanded(
                      flex: 2,
                      child: Text(
                        tr(o.customerName ?? 'Khách lẻ'),
                        style: posSaleOrderCancelledTextStyle(
                              o.status,
                              base: const TextStyle(fontSize: 12),
                            ) ??
                            const TextStyle(fontSize: 12),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  if (_visibleColumns.contains(_ListColumn.subTotal))
                    Expanded(
                      flex: 2,
                      child: Text(tr('${_moneyFmt.format(o.subTotal)} đ'),
                          style: const TextStyle(fontSize: 12),
                          textAlign: TextAlign.right),
                    ),
                  if (_visibleColumns.contains(_ListColumn.discount))
                    Expanded(
                      flex: 2,
                      child: Text(tr('${_moneyFmt.format(o.discount)} đ'),
                          style: const TextStyle(fontSize: 12),
                          textAlign: TextAlign.right),
                    ),
                  if (_visibleColumns.contains(_ListColumn.total))
                    Expanded(
                      flex: 2,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(tr('${_moneyFmt.format(o.total)} đ'),
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: o.status == 'Cancelled'
                                  ? Colors.red.shade800
                                  : null,
                              decoration: o.status == 'Cancelled'
                                  ? TextDecoration.lineThrough
                                  : null,
                              decorationColor: o.status == 'Cancelled'
                                  ? Colors.red.shade400
                                  : null,
                            ),
                            textAlign: TextAlign.right,
                          ),
                          if (o.hasReturns)
                            Text(tr('Đã trả ${_moneyFmt.format(o.returnedAmount)}'),
                              style: TextStyle(
                                fontSize: 10,
                                color: Colors.orange.shade800,
                              ),
                              textAlign: TextAlign.right,
                            ),
                        ],
                      ),
                    ),
                  if (_visibleColumns.contains(_ListColumn.paid))
                    Expanded(
                      flex: 2,
                      child: Text(tr('${_moneyFmt.format(o.paidAmount)} đ'),
                          style: const TextStyle(fontSize: 12),
                          textAlign: TextAlign.right),
                    ),
                  if (_visibleColumns.contains(_ListColumn.balance))
                    Expanded(
                      flex: 2,
                      child: Text(tr('${_moneyFmt.format(_balance(o))} đ'),
                          style: const TextStyle(fontSize: 12),
                          textAlign: TextAlign.right),
                    ),
                  if (_visibleColumns.contains(_ListColumn.delivery))
                    Expanded(
                      flex: 1,
                      child: Text(tr(o.isDelivery ? 'Có' : '—'),
                          style: const TextStyle(fontSize: 12)),
                    ),
                  if (_visibleColumns.contains(_ListColumn.deliveryStatus))
                    Expanded(
                      flex: 2,
                      child: Text(tr(o.deliveryStatus ?? '—'),
                          style: const TextStyle(fontSize: 12),
                          overflow: TextOverflow.ellipsis),
                    ),
                  if (_visibleColumns.contains(_ListColumn.status))
                    SizedBox(
                      width: 90,
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: posSaleOrderStatusChip(o.status, returnStatus: o.returnStatus),
                      ),
                    ),
                ],
              ),
            ),
          ),
          if (expanded) _buildDetailPanel(o, canEdit),
        ],
      ),
    );
  }

  Widget _buildDetailPanel(PosSaleOrder summary, bool canEdit) {
    if (_detailLoading) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    final o = _expandedDetail ?? summary;

    return Container(
      color: const Color(0xFFF8FAFC),
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              _detailTabBtn(0, 'Thông tin'),
              _detailTabBtn(1, 'Lịch sử thanh toán'),
              const Spacer(),
              posSaleOrderStatusChip(o.status, returnStatus: o.returnStatus),
            ],
          ),
          const SizedBox(height: 8),
          if (_detailTab == 0) _buildInfoTab(o) else _buildPaymentsTab(o),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (canEdit && o.status == 'Draft') ...[
                FilledButton.icon(
                  onPressed: () => _openEditor(orderId: o.id),
                  icon: const Icon(Icons.edit, size: 16),
                  label: Text(tr('Chỉnh sửa')),
                  style: FilledButton.styleFrom(backgroundColor: PosTheme.kiotBlue),
                ),
                OutlinedButton.icon(
                  onPressed: _completingId != null
                      ? null
                      : () => _completeOrder(o),
                  icon: const Icon(Icons.check_circle_outline, size: 16),
                  label: Text(
                    tr(_completingId == o.id ? 'Đang xử lý…' : 'Hoàn thành'),
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: () => _deleteOrder(o),
                  icon: const Icon(Icons.delete_outline, size: 16),
                  label: Text(tr('Xóa khỏi DS')),
                ),
              ],
              if (canEdit && o.status == 'Completed') ...[
                if (o.canCancelWithStock)
                  OutlinedButton.icon(
                    onPressed: () => _cancelOrder(o),
                    icon: const Icon(Icons.cancel_outlined, size: 16),
                    label: Text(tr('Hủy đơn (hoàn kho)')),
                  ),
                if (!o.isFullyReturned)
                  OutlinedButton.icon(
                    onPressed: () async {
                      final ok = await Navigator.of(context).push<bool>(
                        MaterialPageRoute(
                          builder: (_) => PosSaleReturnScreen(orderId: o.id),
                        ),
                      );
                      if (ok == true && mounted) _load();
                    },
                    icon: const Icon(Icons.assignment_return_outlined, size: 16),
                    label: Text(tr('Trả hàng')),
                  ),
                OutlinedButton.icon(
                  onPressed: () => _printOrder(o),
                  icon: const Icon(Icons.print, size: 16),
                  label: Text(
                    tr(o.printCount > 0
                        ? 'In lại (đã in ${o.printCount} lần)'
                        : 'In'),
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: () => _copyOrder(o),
                  icon: const Icon(Icons.copy, size: 16),
                  label: Text(tr('Sao chép')),
                ),
              ],
              if (canEdit && o.canDeleteFromList)
                OutlinedButton.icon(
                  onPressed: () => _deleteOrder(o),
                  icon: const Icon(Icons.delete_outline, size: 16),
                  style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
                  label: Text(tr(o.status == 'Draft' ? 'Xóa phiếu tạm' : 'Xóa khỏi DS')),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _detailTabBtn(int idx, String label) {
    final active = _detailTab == idx;
    return TextButton(
      onPressed: () {
        setState(() => _detailTab = idx);
        if (idx == 1 && _expandedId != null) _loadPayments(_expandedId!);
      },
      style: TextButton.styleFrom(
        foregroundColor: active ? PosTheme.kiotBlue : PosTheme.textSecondary,
        textStyle: TextStyle(
            fontWeight: active ? FontWeight.w600 : FontWeight.normal,
            fontSize: 13),
      ),
      child: Text(tr(label)),
    );
  }

  Widget _buildInfoTab(PosSaleOrder o) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: PosSaleOrderReceiptView(order: o),
    );
  }

  Widget _meta(String label, String value) => RichText(
        text: TextSpan(
          style: const TextStyle(fontSize: 12, color: Colors.black87),
          children: [
            TextSpan(
                text: tr('$label: '),
                style: const TextStyle(color: PosTheme.textSecondary)),
            TextSpan(text: tr(value)),
          ],
        ),
      );

  Widget _buildPaymentsTab(PosSaleOrder o) {
    if (_payments.isEmpty) {
      return Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Text(tr('Chưa có thanh toán'),
            style: TextStyle(fontSize: 12, color: PosTheme.textSecondary)),
      );
    }
    return Column(
      children: _payments.map((p) {
        final paidAt = p['paidAt'] ?? p['PaidAt'];
        final dt = paidAt != null ? DateTime.tryParse(paidAt.toString()) : null;
        return ListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: Text(
              tr('${p['paymentNo'] ?? p['PaymentNo']} — ${_moneyFmt.format((p['amount'] ?? p['Amount'] as num?)?.toDouble() ?? 0)} đ'),
              style: const TextStyle(fontSize: 12)),
          subtitle: Text(
            tr([
              if (dt != null) _dateFmt.format(dt.toLocal()),
              p['paymentMethod'] ?? p['PaymentMethod'],
              if (p['note'] ?? p['Note'] != null) p['note'] ?? p['Note'],
            ].whereType<String>().join(' · ')),
            style: const TextStyle(fontSize: 11),
          ),
        );
      }).toList(),
    );
  }
}
