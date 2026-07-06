import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/pos_sale_order.dart';
import '../providers/auth_provider.dart';
import '../providers/permission_provider.dart';
import '../services/api_service.dart';
import '../utils/file_saver.dart' as file_saver;
import '../utils/pos_kiot_time_range.dart';
import '../utils/pos_sale_order_print.dart';
import '../utils/pos_sell_print_settings.dart';
import '../utils/pos_sell_stock_patch.dart';
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
import 'pos_sale_return_list_screen.dart';

const _blue = Color(0xFF2563EB);

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

Set<_ListColumn> _defaultListColumns() => {
      _ListColumn.orderNo,
      _ListColumn.time,
      _ListColumn.customer,
      _ListColumn.subTotal,
      _ListColumn.discount,
      _ListColumn.total,
      _ListColumn.paid,
      _ListColumn.balance,
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
  List<PosSaleOrder> _items = [];
  int _total = 0;
  int _page = 1;
  static const _pageSize = 50;

  final Set<String> _statusFilter = {'Draft', 'Completed', 'Cancelled'};
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
    _load();
  }

  @override
  void dispose() {
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
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final printSettings = await PosSellPrintSettings.load();
    await printPosSaleOrder(
      context: context,
      order: order,
      branchName: auth.currentUser?.department,
      mergeSameItems: printSettings.mergeSameItems,
      copies: printSettings.copies,
      templateId: printSettings.templateId,
      skipDedup: true,
    );
  }

  void _patchOrderInList(PosSaleOrder updated) {
    setState(() {
      _items = _items.map((x) => x.id == updated.id ? updated : x).toList();
      if (_expandedId == updated.id) _expandedDetail = updated;
    });
  }

  Future<void> _cancelOrder(PosSaleOrder o) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Hủy đơn (hoàn kho)'),
        content: Text(
            'Hủy đơn ${o.orderNo}, hoàn kho hàng đã bán và chuyển trạng thái «Đã hủy»?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Không')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Hủy đơn'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final res = await _api.cancelPosSale(o.id);
    if (!mounted) return;
    if (res['isSuccess'] == true) {
      if (res['data'] is! Map<String, dynamic>) {
        NotificationOverlayManager().showError(
          title: 'Lỗi',
          message: 'Server không trả về dữ liệu đơn — vui lòng tải lại danh sách',
        );
        await _load(page: _page);
        return;
      }
      final updated = PosSaleOrder.fromJson(res['data'] as Map<String, dynamic>);
      if (updated.status != 'Cancelled') {
        NotificationOverlayManager().showError(
          title: 'Lỗi',
          message:
              'Đơn vẫn ở trạng thái ${posSaleOrderStatusLabel(updated.status)} — chưa hủy được trên server',
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
          message: '${o.orderNo} · trạng thái: Đã hủy');
      await _load(page: _page);
      await _refreshExpandedDetail(o.id);
    } else {
      NotificationOverlayManager().showError(
          title: 'Lỗi', message: res['message']?.toString() ?? 'Không hủy được');
    }
  }

  Future<void> _deleteOrder(PosSaleOrder o) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Xóa khỏi danh sách'),
        content: Text(
            'Xóa hẳn đơn ${o.orderNo} khỏi danh sách? (Không hoàn kho thêm — chỉ ẩn phiếu)'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Không')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Xóa'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final res = await _api.deletePosSale(o.id);
    if (!mounted) return;
    if (res['isSuccess'] == true) {
      NotificationOverlayManager().showSuccess(title: 'Đã xóa', message: o.orderNo);
      _collapseExpanded();
      setState(() => _items = _items.where((x) => x.id != o.id).toList());
      ScreenRefreshNotifier.refreshPosAfterStockChange();
      await _load(page: _page);
    } else {
      NotificationOverlayManager().showError(
          title: 'Lỗi', message: res['message']?.toString() ?? 'Không xóa được');
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
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Hoàn thành đơn'),
        content: Text('Xác nhận hoàn thành đơn ${o.orderNo} và trừ kho?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Không')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: _blue),
            child: const Text('Hoàn thành'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final res = await _api.completePosSale(o.id);
    if (!mounted) return;
    if (res['isSuccess'] == true) {
      NotificationOverlayManager().showSuccess(title: 'Hoàn thành', message: o.orderNo);
      await _load(page: _page);
      await _refreshExpandedDetail(o.id);
    } else {
      NotificationOverlayManager()
          .showError(title: 'Lỗi', message: res['message']?.toString() ?? '');
    }
  }

  void _showColumnPicker() {
    showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          title: const Text('Tùy chọn cột'),
          content: SizedBox(
            width: 280,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: _ListColumn.values.map((c) {
                  return CheckboxListTile(
                    dense: true,
                    activeColor: _blue,
                    title: Text(c.label, style: const TextStyle(fontSize: 13)),
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
              child: const Text('Mặc định'),
            ),
            FilledButton(
              onPressed: () {
                setState(() {});
                Navigator.pop(ctx);
              },
              style: FilledButton.styleFrom(backgroundColor: _blue),
              child: const Text('Áp dụng'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _exportExcel(PermissionProvider perm) async {
    if (!perm.canExport('PosProducts')) return;
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
            .showSuccess(title: 'Xuất file', message: 'Đã xuất Excel đơn hàng');
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
          .showSuccess(title: 'Sao chép', message: 'Đã tạo ${copy.orderNo}');
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
                title: const Text('Đang xử lý', style: TextStyle(fontSize: 13)),
                value: _statusFilter.contains('Draft'),
                activeColor: _blue,
                onChanged: (v) => _toggleStatus('Draft', v),
              ),
              CheckboxListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: const Text('Hoàn thành', style: TextStyle(fontSize: 13)),
                value: _statusFilter.contains('Completed'),
                activeColor: _blue,
                onChanged: (v) => _toggleStatus('Completed', v),
              ),
              CheckboxListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: const Text('Đã hủy', style: TextStyle(fontSize: 13)),
                value: _statusFilter.contains('Cancelled'),
                activeColor: _blue,
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
                title: const Text('Tất cả', style: TextStyle(fontSize: 13)),
                value: null,
                groupValue: _isDeliveryFilter,
                activeColor: _blue,
                onChanged: (v) {
                  setState(() => _isDeliveryFilter = v);
                  _load();
                },
              ),
              RadioListTile<bool?>(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: const Text('Không giao hàng', style: TextStyle(fontSize: 13)),
                value: false,
                groupValue: _isDeliveryFilter,
                activeColor: _blue,
                onChanged: (v) {
                  setState(() => _isDeliveryFilter = v);
                  _load();
                },
              ),
              RadioListTile<bool?>(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: const Text('Giao hàng', style: TextStyle(fontSize: 13)),
                value: true,
                groupValue: _isDeliveryFilter,
                activeColor: _blue,
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
            hint: const Text('Tất cả', style: TextStyle(fontSize: 12)),
            items: _paymentMethods
                .map(
                  (m) => DropdownMenuItem<String?>(
                    value: m,
                    child: Text(m ?? 'Tất cả', style: const TextStyle(fontSize: 12)),
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
          style: FilledButton.styleFrom(backgroundColor: _blue),
          child: const Text('Áp dụng lọc', style: TextStyle(fontSize: 12)),
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
        ..addAll({'Draft', 'Completed', 'Cancelled'});
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
      return const Scaffold(
          body: Center(child: Text('Không có quyền xem đơn hàng')));
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
              activeFilterCount: _activeFilterCount,
              filterChips: Padding(
                padding: const EdgeInsets.only(left: 4),
                child: ActionChip(
                  label: Text(_timeFilter.displayLabel,
                      style: const TextStyle(fontSize: 12)),
                  onPressed: _openFilters,
                ),
              ),
            )
          else
            PosMobileListHeader(
              icon: Icons.receipt_long,
              title: 'Quản lý đơn hàng',
              onRefresh: () => _load(page: _page),
              onOpenFilters: null,
              activeFilterCount: _activeFilterCount,
              trailing: [
                if (perm.canExport('PosProducts'))
                  OutlinedButton.icon(
                    onPressed: _exporting ? null : () => _exportExcel(perm),
                    icon: _exporting
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.download, size: 18),
                    label: const Text('Xuất file'),
                  ),
                IconButton(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const PosSaleReturnListScreen(),
                      ),
                    );
                  },
                  icon: const Icon(Icons.assignment_return_outlined),
                  tooltip: 'Danh sách trả hàng',
                ),
                IconButton(
                  onPressed: _showColumnPicker,
                  icon: const Icon(Icons.view_column_outlined),
                  tooltip: 'Tùy chọn cột',
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
                      decoration: const InputDecoration(
                        hintText: 'Tìm mã đơn, khách hàng…',
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
                            ? const Center(child: Text('Chưa có đơn hàng'))
                            : Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  _buildTableHeader(),
                                  Expanded(
                                      child: _buildList(canEdit)),
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
          Text('Tổng $_total đơn',
              style:
                  const TextStyle(fontSize: 12, color: PosTheme.textSecondary)),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.chevron_left),
            onPressed: _page > 1 ? () => _load(page: _page - 1) : null,
          ),
          Text('Trang $_page / $pages', style: const TextStyle(fontSize: 12)),
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
        child: Text(c.label, style: h, textAlign: align),
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
                  const Text(
                    'Doanh thu thuần',
                    style: TextStyle(
                      fontSize: 13,
                      color: PosTheme.textSecondary,
                    ),
                  ),
                  Text(
                    '$_total hoá đơn${returnedTotal > 0 ? ' · Hoàn trả ${_moneyFmt.format(returnedTotal)}' : ''}',
                    style: const TextStyle(fontSize: 12, color: PosTheme.textSecondary),
                  ),
                ],
              ),
            ),
            Text(
              _moneyFmt.format(totalAmount),
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          _moneyFmt.format(o.total),
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
        ),
        if (o.hasReturns)
          Container(
            margin: const EdgeInsets.only(top: 2),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(
              color: Colors.orange.shade50,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              'Đã trả ${_moneyFmt.format(o.returnedAmount)}',
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
                  label,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: PosTheme.textSecondary,
                    letterSpacing: 0.3,
                  ),
                ),
              ),
              Text(
                dayReturn > 0
                    ? 'Thuần ${_moneyFmt.format(dayNet)} · Trả ${_moneyFmt.format(dayReturn)}'
                    : 'Tổng ngày: ${_moneyFmt.format(dayNet)} đ',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: _blue,
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

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
      children: children,
    );
  }

  Future<void> _showMobileOrderDetail(PosSaleOrder summary, bool canEdit) async {
    PosSaleOrder order = summary;
    if (order.lines.isEmpty) {
      final res = await _api.getPosSale(summary.id);
      if (!mounted) return;
      if (res['isSuccess'] == true && res['data'] is Map<String, dynamic>) {
        order = PosSaleOrder.fromJson(res['data'] as Map<String, dynamic>);
      }
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
                      order.orderNo,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  posSaleOrderStatusChip(order.status),
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
                        label: Text(order.printCount > 0 ? 'In lại' : 'In'),
                        style: FilledButton.styleFrom(backgroundColor: _blue),
                      ),
                    if (canEdit && order.status == 'Draft')
                      FilledButton.icon(
                        onPressed: () {
                          Navigator.pop(ctx);
                          _openEditor(orderId: order.id);
                        },
                        icon: const Icon(Icons.edit, size: 16),
                        label: const Text('Chỉnh sửa'),
                      ),
                    if (canEdit && order.status == 'Completed')
                      OutlinedButton.icon(
                        onPressed: () {
                          Navigator.pop(ctx);
                          _cancelOrder(order);
                        },
                        icon: const Icon(Icons.cancel_outlined, size: 16),
                        label: const Text('Hủy đơn (hoàn kho)'),
                      ),
                    if (canEdit &&
                        (order.status == 'Cancelled' || order.status == 'Draft'))
                      OutlinedButton.icon(
                        onPressed: () {
                          Navigator.pop(ctx);
                          _deleteOrder(order);
                        },
                        icon: const Icon(Icons.delete_outline, size: 16),
                        style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
                        label: const Text('Xóa khỏi DS'),
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

    return Material(
      color: Colors.white,
      child: InkWell(
        onTap: () => _showMobileOrderDetail(o, canEdit),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      o.customerName ?? 'Khách lẻ',
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  _buildOrderTotalColumn(o),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '$timeStr · ${o.orderNo}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: PosTheme.textSecondary,
                      ),
                    ),
                  ),
                  Text(
                    o.paymentMethod,
                    style: const TextStyle(
                      fontSize: 12,
                      color: PosTheme.textSecondary,
                    ),
                  ),
                ],
              ),
              if (firstLine != null) ...[
                const SizedBox(height: 6),
                Text(
                  '${firstLine.productName} x${_qtyFmt(firstLine.qty)}',
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
        status: posSaleOrderStatusChip(o.status),
        accentColor: _blue,
        fields: [
          PosMobileField(
            'Thời gian',
            dt != null ? _dateFmt.format(dt.toLocal()) : '—',
          ),
          PosMobileField('Khách', o.customerName ?? 'Khách lẻ'),
          PosMobileField('Tổng còn', '${_moneyFmt.format(o.total)} đ'),
          if (o.hasReturns)
            PosMobileField('Đã trả', '${_moneyFmt.format(o.returnedAmount)} đ'),
          PosMobileField('Còn lại', '${_moneyFmt.format(_balance(o))} đ'),
        ],
        detail: expanded ? _buildDetailPanel(o, canEdit) : null,
      );
    }
    return Material(
      color: Colors.white,
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: () => _toggleExpand(o),
            hoverColor: const Color(0xFFF1F5F9),
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
                    color: PosTheme.textSecondary,
                  ),
                  const SizedBox(width: 4),
                  if (_visibleColumns.contains(_ListColumn.orderNo))
                    Expanded(
                      flex: 2,
                      child: Text(o.orderNo,
                          style: const TextStyle(
                              color: _blue, fontWeight: FontWeight.w600, fontSize: 12)),
                    ),
                  if (_visibleColumns.contains(_ListColumn.time))
                    Expanded(
                      flex: 2,
                      child: Text(
                        dt != null ? _dateFmt.format(dt.toLocal()) : '—',
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                  if (_visibleColumns.contains(_ListColumn.customer))
                    Expanded(
                      flex: 2,
                      child: Text(o.customerName ?? 'Khách lẻ',
                          style: const TextStyle(fontSize: 12),
                          overflow: TextOverflow.ellipsis),
                    ),
                  if (_visibleColumns.contains(_ListColumn.subTotal))
                    Expanded(
                      flex: 2,
                      child: Text('${_moneyFmt.format(o.subTotal)} đ',
                          style: const TextStyle(fontSize: 12),
                          textAlign: TextAlign.right),
                    ),
                  if (_visibleColumns.contains(_ListColumn.discount))
                    Expanded(
                      flex: 2,
                      child: Text('${_moneyFmt.format(o.discount)} đ',
                          style: const TextStyle(fontSize: 12),
                          textAlign: TextAlign.right),
                    ),
                  if (_visibleColumns.contains(_ListColumn.total))
                    Expanded(
                      flex: 2,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text('${_moneyFmt.format(o.total)} đ',
                              style: const TextStyle(
                                  fontSize: 12, fontWeight: FontWeight.w600),
                              textAlign: TextAlign.right),
                          if (o.hasReturns)
                            Text(
                              'Đã trả ${_moneyFmt.format(o.returnedAmount)}',
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
                      child: Text('${_moneyFmt.format(o.paidAmount)} đ',
                          style: const TextStyle(fontSize: 12),
                          textAlign: TextAlign.right),
                    ),
                  if (_visibleColumns.contains(_ListColumn.balance))
                    Expanded(
                      flex: 2,
                      child: Text('${_moneyFmt.format(_balance(o))} đ',
                          style: const TextStyle(fontSize: 12),
                          textAlign: TextAlign.right),
                    ),
                  if (_visibleColumns.contains(_ListColumn.delivery))
                    Expanded(
                      flex: 1,
                      child: Text(o.isDelivery ? 'Có' : '—',
                          style: const TextStyle(fontSize: 12)),
                    ),
                  if (_visibleColumns.contains(_ListColumn.deliveryStatus))
                    Expanded(
                      flex: 2,
                      child: Text(o.deliveryStatus ?? '—',
                          style: const TextStyle(fontSize: 12),
                          overflow: TextOverflow.ellipsis),
                    ),
                  if (_visibleColumns.contains(_ListColumn.status))
                    SizedBox(
                      width: 90,
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: posSaleOrderStatusChip(o.status),
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
              posSaleOrderStatusChip(o.status),
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
                  label: const Text('Chỉnh sửa'),
                  style: FilledButton.styleFrom(backgroundColor: _blue),
                ),
                OutlinedButton.icon(
                  onPressed: () => _completeOrder(o),
                  icon: const Icon(Icons.check_circle_outline, size: 16),
                  label: const Text('Hoàn thành'),
                ),
                OutlinedButton.icon(
                  onPressed: () => _deleteOrder(o),
                  icon: const Icon(Icons.delete_outline, size: 16),
                  label: const Text('Xóa khỏi DS'),
                ),
              ],
              if (canEdit && o.status == 'Completed') ...[
                OutlinedButton.icon(
                  onPressed: () => _cancelOrder(o),
                  icon: const Icon(Icons.cancel_outlined, size: 16),
                  label: const Text('Hủy đơn (hoàn kho)'),
                ),
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
                  label: const Text('Trả hàng'),
                ),
                OutlinedButton.icon(
                  onPressed: () => _printOrder(o),
                  icon: const Icon(Icons.print, size: 16),
                  label: Text(o.printCount > 0 ? 'In lại' : 'In'),
                ),
              ],
              if (canEdit && o.status == 'Completed')
                OutlinedButton.icon(
                  onPressed: () => _copyOrder(o),
                  icon: const Icon(Icons.copy, size: 16),
                  label: const Text('Sao chép'),
                ),
              if (canEdit && (o.status == 'Cancelled' || o.status == 'Draft'))
                OutlinedButton.icon(
                  onPressed: () => _deleteOrder(o),
                  icon: const Icon(Icons.delete_outline, size: 16),
                  label: const Text('Xóa khỏi DS'),
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
        foregroundColor: active ? _blue : PosTheme.textSecondary,
        textStyle: TextStyle(
            fontWeight: active ? FontWeight.w600 : FontWeight.normal,
            fontSize: 13),
      ),
      child: Text(label),
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
                text: '$label: ',
                style: const TextStyle(color: PosTheme.textSecondary)),
            TextSpan(text: value),
          ],
        ),
      );

  Widget _buildPaymentsTab(PosSaleOrder o) {
    if (_payments.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Text('Chưa có thanh toán',
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
              '${p['paymentNo'] ?? p['PaymentNo']} — ${_moneyFmt.format((p['amount'] ?? p['Amount'] as num?)?.toDouble() ?? 0)} đ',
              style: const TextStyle(fontSize: 12)),
          subtitle: Text(
            [
              if (dt != null) _dateFmt.format(dt.toLocal()),
              p['paymentMethod'] ?? p['PaymentMethod'],
              if (p['note'] ?? p['Note'] != null) p['note'] ?? p['Note'],
            ].whereType<String>().join(' · '),
            style: const TextStyle(fontSize: 11),
          ),
        );
      }).toList(),
    );
  }
}
