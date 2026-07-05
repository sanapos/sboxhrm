import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/pos_product.dart';
import '../models/pos_purchase.dart';
import '../providers/auth_provider.dart';
import '../providers/permission_provider.dart';
import '../services/api_service.dart';
import '../utils/pos_purchase_receipt_print.dart';
import '../widgets/hrm_page_chrome.dart';
import '../screens/main_layout.dart' show ScreenRefreshNotifier;
import '../widgets/loading_widget.dart';
import '../widgets/notification_overlay.dart';
import '../widgets/pos/pos_barcode_label_dialog.dart';
import '../utils/pos_kiot_time_range.dart';
import '../widgets/pos/pos_kiot_time_filter.dart';
import '../utils/responsive_helper.dart';
import '../widgets/pos/pos_mobile_widgets.dart';
import '../widgets/pos/pos_module_toolbar.dart';
import '../widgets/pos/pos_purchase_toolbar.dart';
import '../widgets/pos/pos_theme.dart';
import 'pos_purchase_receipt_editor_screen.dart';

const _blue = Color(0xFF2563EB);

class PosPurchaseReceiptListScreen extends StatefulWidget {
  const PosPurchaseReceiptListScreen({super.key});

  @override
  State<PosPurchaseReceiptListScreen> createState() =>
      _PosPurchaseReceiptListScreenState();
}

class _PosPurchaseReceiptListScreenState
    extends State<PosPurchaseReceiptListScreen> {
  final _api = ApiService();
  final _searchCtrl = TextEditingController();
  final _createdByCtrl = TextEditingController();
  final _importedByCtrl = TextEditingController();
  final _invoiceNoCtrl = TextEditingController();
  final _moneyFmt = NumberFormat('#,##0', 'vi_VN');
  final _dateFmt = DateFormat('dd/MM/yyyy HH:mm', 'vi_VN');

  bool _loading = true;
  List<PosPurchaseReceipt> _items = [];
  List<PosSupplierFull> _suppliers = [];
  int _total = 0;
  int _page = 1;
  static const _pageSize = 50;

  final Set<String> _statusFilter = {'Draft', 'Completed', 'Cancelled'};
  String? _supplierId;
  PosKiotTimeFilterState _timeFilter = PosKiotTimeFilterState.thisMonth();

  String? _expandedId;
  PosPurchaseReceipt? _expandedDetail;
  bool _detailLoading = false;
  int _detailTab = 0;
  List<Map<String, dynamic>> _payments = [];

  @override
  void initState() {
    super.initState();
    ScreenRefreshNotifier.posPurchaseReceipts.addListener(_onExternalRefresh);
    _loadSuppliers();
    _load();
  }

  void _onExternalRefresh() {
    if (!mounted) return;
    _load(page: _page);
  }

  @override
  void dispose() {
    ScreenRefreshNotifier.posPurchaseReceipts.removeListener(_onExternalRefresh);
    _searchCtrl.dispose();
    _createdByCtrl.dispose();
    _importedByCtrl.dispose();
    _invoiceNoCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadSuppliers() async {
    final res = await _api.getPosSuppliers();
    if (!mounted || res['isSuccess'] != true) return;
    final list = (res['data'] as List?)
            ?.map((e) => PosSupplierFull.fromJson(e as Map<String, dynamic>))
            .toList() ??
        [];
    setState(() => _suppliers = list);
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

    final res = await _api.getPosPurchaseReceipts(
      search: _searchCtrl.text.trim().isEmpty ? null : _searchCtrl.text.trim(),
      statuses: _statusFilter.toList(),
      supplierId: _supplierId,
      createdBy: _createdByCtrl.text.trim().isEmpty
          ? null
          : _createdByCtrl.text.trim(),
      importedBy: _importedByCtrl.text.trim().isEmpty
          ? null
          : _importedByCtrl.text.trim(),
      inputInvoiceNo:
          _invoiceNoCtrl.text.trim().isEmpty ? null : _invoiceNoCtrl.text.trim(),
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
            .map((e) => PosPurchaseReceipt.fromJson(e as Map<String, dynamic>))
            .toList();
      });
    } else {
      setState(() => _loading = false);
    }
  }

  Future<void> _toggleExpand(PosPurchaseReceipt summary) async {
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

    final res = await _api.getPosPurchaseReceipt(summary.id);
    if (!mounted || _expandedId != summary.id) return;
    if (res['isSuccess'] == true) {
      setState(() {
        _expandedDetail =
            PosPurchaseReceipt.fromJson(res['data'] as Map<String, dynamic>);
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
    final res = await _api.getPosPurchaseReceipt(id);
    if (!mounted || _expandedId != id) return;
    if (res['isSuccess'] == true && res['data'] is Map<String, dynamic>) {
      setState(() {
        _expandedDetail = PosPurchaseReceipt.fromJson(
            res['data'] as Map<String, dynamic>);
      });
    } else {
      _collapseExpanded();
    }
  }

  Future<void> _loadPayments(String id) async {
    final res = await _api.getPosPurchaseReceiptPayments(id);
    if (!mounted) return;
    if (res['isSuccess'] == true && res['data'] is List) {
      setState(() {
        _payments = (res['data'] as List).cast<Map<String, dynamic>>();
      });
    }
  }

  Future<void> _openEditor({String? receiptId}) async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => PosPurchaseReceiptEditorScreen(receiptId: receiptId),
      ),
    );
    if (mounted) _load(page: _page);
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

  Future<void> _printReceipt(PosPurchaseReceipt r) async {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    await printPosPurchaseReceipt(
      context: context,
      receiptNo: r.receiptNo,
      importDate: r.importDate?.toLocal() ?? r.createdAt?.toLocal() ?? DateTime.now(),
      branchName: auth.currentUser?.department,
      createdBy: r.createdBy ?? auth.currentUser?.fullName,
      supplierName: r.supplierName,
      inputInvoiceNo: r.inputInvoiceNo,
      note: r.note,
      status: r.status,
      linesTotal: r.totalCost,
      totalVat: r.totalVat,
      discountAmount: r.discountAmount,
      discountIsPercent: r.discountIsPercent,
      discountInput: r.discountInput,
      paidAmount: r.paidAmount,
      grandTotal: r.grandTotal != 0 ? r.grandTotal : r.totalCost + r.totalVat - r.discountAmount,
      lines: r.lines,
    );
  }

  Future<void> _printLabels(PosPurchaseReceipt r) async {
    final products = <PosProduct>[];
    for (final line in r.lines) {
      final res = await _api.getPosProduct(line.productId);
      if (res['isSuccess'] == true && res['data'] != null) {
        products.add(PosProduct.fromJson(res['data'] as Map<String, dynamic>));
      }
    }
    if (!mounted) return;
    if (products.isEmpty) {
      NotificationOverlayManager()
          .showWarning(title: 'In tem', message: 'Không có hàng để in tem');
      return;
    }
    await showPosBarcodeLabelDialog(context, products);
  }

  Future<void> _completeReceipt(PosPurchaseReceipt r) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Nhập hàng vào kho'),
        content: Text(
            'Hoàn thành phiếu ${r.receiptNo} và cập nhật tồn kho?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Hủy')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: _blue),
            child: const Text('Xác nhận'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final res = await _api.completePosPurchaseReceipt(r.id);
    if (!mounted) return;
    if (res['isSuccess'] == true) {
      NotificationOverlayManager().showSuccess(
          title: 'Thành công', message: 'Đã nhập hàng vào kho');
      await _load(page: _page);
      await _refreshExpandedDetail(r.id);
    } else {
      NotificationOverlayManager().showError(
          title: 'Lỗi', message: res['message']?.toString() ?? 'Không thể hoàn thành');
    }
  }

  Future<void> _copyReceipt(PosPurchaseReceipt r) async {
    final res = await _api.copyPosPurchaseReceipt(r.id);
    if (!mounted) return;
    if (res['isSuccess'] == true && res['data'] != null) {
      final copy = PosPurchaseReceipt.fromJson(res['data'] as Map<String, dynamic>);
      NotificationOverlayManager()
          .showSuccess(title: 'Sao chép', message: 'Đã tạo ${copy.receiptNo}');
      _load(page: _page);
      _openEditor(receiptId: copy.id);
    } else {
      NotificationOverlayManager().showError(
          title: 'Lỗi', message: res['message']?.toString() ?? 'Không sao chép được');
    }
  }

  Future<void> _deleteReceipt(PosPurchaseReceipt r) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Xóa phiếu'),
        content: Text('Xóa hẳn phiếu ${r.receiptNo}? Thao tác không thể hoàn tác.'),
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
    final res = await _api.deletePosPurchaseReceipt(r.id);
    if (!mounted) return;
    if (res['isSuccess'] == true) {
      NotificationOverlayManager().showSuccess(title: 'Đã xóa', message: r.receiptNo);
      _collapseExpanded();
      await _load(page: _page);
    } else {
      NotificationOverlayManager().showError(
          title: 'Lỗi', message: res['message']?.toString() ?? 'Không xóa được');
    }
  }

  Future<void> _voidCompletedReceipt(PosPurchaseReceipt r) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Hủy phiếu nhập'),
        content: Text(
            'Hủy phiếu ${r.receiptNo} và trừ lại hàng đã nhập kho?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Không')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Hủy phiếu'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final res = await _api.cancelPosPurchaseReceipt(r.id);
    if (!mounted) return;
    if (res['isSuccess'] == true) {
      NotificationOverlayManager().showSuccess(
          title: 'Đã hủy', message: 'Đã hoàn kho · ${r.receiptNo}');
      await _load(page: _page);
      await _refreshExpandedDetail(r.id);
    } else {
      NotificationOverlayManager().showError(
          title: 'Lỗi', message: res['message']?.toString() ?? 'Không hủy được');
    }
  }

  double _balanceDue(PosPurchaseReceipt r) {
    if (r.balanceDue != 0) return r.balanceDue;
    final gt = r.grandTotal != 0
        ? r.grandTotal
        : r.totalCost + r.totalVat - r.discountAmount;
    return gt - r.paidAmount;
  }

  int get _activeFilterCount {
    var n = 0;
    if (_supplierId != null) n++;
    if (_createdByCtrl.text.trim().isNotEmpty) n++;
    if (_importedByCtrl.text.trim().isNotEmpty) n++;
    if (_invoiceNoCtrl.text.trim().isNotEmpty) n++;
    if (_statusFilter.length < 3) n++;
    return n;
  }

  Widget _buildFilterPanel() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        purchaseFilterSection(
          'Trạng thái',
          Column(
            children: [
              CheckboxListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: const Text('Phiếu tạm', style: TextStyle(fontSize: 13)),
                value: _statusFilter.contains('Draft'),
                activeColor: _blue,
                onChanged: (v) => _toggleStatus('Draft', v),
              ),
              CheckboxListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: const Text('Đã nhập hàng', style: TextStyle(fontSize: 13)),
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
        purchaseFilterSection(
          'Thời gian',
          PosKiotTimeFilter(
            state: _timeFilter,
            onChanged: _onTimeFilterChanged,
          ),
        ),
        purchaseFilterSection(
          'Nhà cung cấp',
          DropdownButtonFormField<String?>(
            isDense: true,
            value: _supplierId,
            decoration: const InputDecoration(
              isDense: true,
              border: OutlineInputBorder(),
              contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            ),
            hint: const Text('Tất cả NCC', style: TextStyle(fontSize: 12)),
            items: [
              const DropdownMenuItem<String?>(
                value: null,
                child: Text('Tất cả NCC', style: TextStyle(fontSize: 12)),
              ),
              ..._suppliers.map(
                (s) => DropdownMenuItem<String?>(
                  value: s.id,
                  child: Text(s.name,
                      style: const TextStyle(fontSize: 12),
                      overflow: TextOverflow.ellipsis),
                ),
              ),
            ],
            onChanged: (v) {
              setState(() => _supplierId = v);
              _load();
            },
          ),
        ),
        purchaseFilterSection(
          'Người tạo',
          TextField(
            controller: _createdByCtrl,
            decoration: const InputDecoration(
              hintText: 'Chọn người tạo…',
              isDense: true,
              border: OutlineInputBorder(),
              contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            ),
            style: const TextStyle(fontSize: 12),
            onSubmitted: (_) => _load(),
          ),
        ),
        purchaseFilterSection(
          'Số hóa đơn đầu vào',
          TextField(
            controller: _invoiceNoCtrl,
            decoration: const InputDecoration(
              hintText: 'Số HĐ đầu vào…',
              isDense: true,
              border: OutlineInputBorder(),
              contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            ),
            style: const TextStyle(fontSize: 12),
            onSubmitted: (_) => _load(),
          ),
        ),
        purchaseFilterSection(
          'Người nhập',
          TextField(
            controller: _importedByCtrl,
            decoration: const InputDecoration(
              hintText: 'Chọn người nhập…',
              isDense: true,
              border: OutlineInputBorder(),
              contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            ),
            style: const TextStyle(fontSize: 12),
            onSubmitted: (_) => _load(),
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

  void _openFilters() {
    showPosMobileFilterSheet(context, child: _buildFilterPanel());
  }

  @override
  Widget build(BuildContext context) {
    final perm = Provider.of<PermissionProvider>(context);
    if (!perm.canView('PosProducts')) {
      return const Scaffold(
          body: Center(child: Text('Không có quyền xem nhập hàng')));
    }
    final canEdit = perm.canEdit('PosPurchaseReceipts');

    return Scaffold(
      backgroundColor: HrmPageChrome.background,
      body: posMobileSafeBody(
        context,
        Column(
        children: [
          const PosModuleToolbar(activeModule: 'PosPurchaseReceipts'),
          PosMobileListHeader(
            icon: Icons.shopping_cart,
            title: 'Nhập hàng NCC',
            onCreate: canEdit ? () => _openEditor() : null,
            createLabel: 'Tạo phiếu nhập',
            onRefresh: () => _load(page: _page),
            onOpenFilters: posUseMobileList(context) ? _openFilters : null,
            activeFilterCount: _activeFilterCount,
          ),
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
                        hintText: 'Tìm mã phiếu nhập, ghi chú…',
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
                            ? const Center(
                                child: Text('Chưa có phiếu nhập hàng'))
                            : Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
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
      ),
    );
  }

  Widget _buildPager() {
    if (posUseMobileList(context)) {
      return PosMobilePager(
        total: _total,
        page: _page,
        pageSize: _pageSize,
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
          Text('Tổng $_total phiếu',
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
        fontSize: 12, fontWeight: FontWeight.w600, color: PosTheme.textSecondary);
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
          Expanded(flex: 2, child: Text('Mã PN', style: h)),
          Expanded(flex: 2, child: Text('Thời gian', style: h)),
          Expanded(flex: 2, child: Text('Mã NCC', style: h)),
          Expanded(flex: 3, child: Text('NCC', style: h)),
          Expanded(
              flex: 2,
              child: Text('Cần trả NCC', style: h, textAlign: TextAlign.right)),
          SizedBox(width: 100, child: Text('Trạng thái', style: h, textAlign: TextAlign.right)),
        ],
      ),
    );
  }

  Widget _buildList(bool canEdit) {
    final mobile = posUseMobileList(context);
    return ListView.builder(
      padding: Responsive.fabListInsets(
        context,
        base: EdgeInsets.fromLTRB(12, mobile ? 8 : 0, 12, 12),
        enabled: mobile && canEdit,
      ),
      itemCount: _items.length,
      itemBuilder: (ctx, i) => _buildReceiptBlock(_items[i], canEdit),
    );
  }

  Widget _buildReceiptBlock(PosPurchaseReceipt r, bool canEdit) {
    final expanded = _expandedId == r.id;
    final dt = r.importDate ?? r.createdAt;
    if (posUseMobileList(context)) {
      return PosMobileExpandableDocCard(
        expanded: expanded,
        onTap: () => _toggleExpand(r),
        code: r.receiptNo,
        status: purchaseStatusChip(r.status),
        accentColor: _blue,
        fields: [
          PosMobileField(
            'Thời gian',
            dt != null ? _dateFmt.format(dt.toLocal()) : '—',
          ),
          PosMobileField('NCC', r.supplierName ?? '—'),
          PosMobileField(
            'Cần trả',
            '${_moneyFmt.format(_balanceDue(r))} đ',
          ),
        ],
        detail: expanded ? _buildDetailPanel(r, canEdit) : null,
      );
    }
    return Material(
      color: Colors.white,
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: () => _toggleExpand(r),
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
                  Expanded(
                    flex: 2,
                    child: Text(r.receiptNo,
                        style: const TextStyle(
                            color: _blue, fontWeight: FontWeight.w600, fontSize: 13)),
                  ),
                  Expanded(
                    flex: 2,
                    child: Text(
                      dt != null ? _dateFmt.format(dt.toLocal()) : '—',
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: Text(r.supplierCode ?? '—',
                        style: const TextStyle(fontSize: 13)),
                  ),
                  Expanded(
                    flex: 3,
                    child: Text(r.supplierName ?? '—',
                        style: const TextStyle(fontSize: 13),
                        overflow: TextOverflow.ellipsis),
                  ),
                  Expanded(
                    flex: 2,
                    child: Text('${_moneyFmt.format(_balanceDue(r))} đ',
                        style: const TextStyle(fontSize: 13),
                        textAlign: TextAlign.right),
                  ),
                  SizedBox(
                    width: 100,
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: purchaseStatusChip(r.status),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (expanded) _buildDetailPanel(r, canEdit),
        ],
      ),
    );
  }

  Widget _buildDetailPanel(PosPurchaseReceipt summary, bool canEdit) {
    if (_detailLoading) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    final r = _expandedDetail ?? summary;

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
              purchaseStatusChip(r.status),
            ],
          ),
          const SizedBox(height: 8),
          if (_detailTab == 0) _buildInfoTab(r) else _buildPaymentsTab(r),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (canEdit && r.status == 'Draft')
                FilledButton(
                  onPressed: () => _openEditor(receiptId: r.id),
                  style: FilledButton.styleFrom(backgroundColor: _blue),
                  child: const Text('Mở phiếu'),
                ),
              OutlinedButton.icon(
                onPressed: () => _printReceipt(r),
                icon: const Icon(Icons.print, size: 16),
                label: const Text('In phiếu'),
              ),
              OutlinedButton.icon(
                onPressed: r.lines.isEmpty && _expandedDetail == null
                    ? null
                    : () async {
                        if (_expandedDetail == null) {
                          final res = await _api.getPosPurchaseReceipt(r.id);
                          if (res['isSuccess'] == true && mounted) {
                            await _printLabels(PosPurchaseReceipt.fromJson(
                                res['data'] as Map<String, dynamic>));
                          }
                        } else {
                          await _printLabels(r);
                        }
                      },
                icon: const Icon(Icons.qr_code, size: 16),
                label: const Text('In tem mã'),
              ),
              if (canEdit && r.status == 'Draft')
                OutlinedButton.icon(
                  onPressed: () => _completeReceipt(r),
                  icon: const Icon(Icons.inventory_2_outlined, size: 16),
                  label: const Text('Nhập hàng vào kho'),
                ),
              if (canEdit)
                OutlinedButton.icon(
                  onPressed: () => _copyReceipt(r),
                  icon: const Icon(Icons.copy, size: 16),
                  label: const Text('Sao chép'),
                ),
              if (canEdit && r.status == 'Draft')
                OutlinedButton.icon(
                  onPressed: () => _deleteReceipt(r),
                  icon: const Icon(Icons.delete_outline, size: 16),
                  label: const Text('Xóa'),
                ),
              if (canEdit && r.status == 'Completed')
                OutlinedButton.icon(
                  onPressed: () => _voidCompletedReceipt(r),
                  icon: const Icon(Icons.cancel_outlined, size: 16),
                  label: const Text('Hủy'),
                ),
              if (canEdit && r.status == 'Cancelled')
                OutlinedButton.icon(
                  onPressed: () => _deleteReceipt(r),
                  icon: const Icon(Icons.delete_outline, size: 16),
                  label: const Text('Xóa'),
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

  Widget _buildInfoTab(PosPurchaseReceipt r) {
    final dt = r.importDate ?? r.createdAt;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 24,
          runSpacing: 6,
          children: [
            _meta('Người tạo', r.createdBy ?? '—'),
            _meta('Người nhập', r.importedBy ?? '—'),
            _meta('NCC', r.supplierName ?? '—'),
            _meta('Ngày nhập',
                dt != null ? _dateFmt.format(dt.toLocal()) : '—'),
            _meta('Số HĐ đầu vào', r.inputInvoiceNo ?? '—'),
          ],
        ),
        if (r.note != null && r.note!.isNotEmpty) ...[
          const SizedBox(height: 8),
          _meta('Ghi chú', r.note!),
        ],
        const SizedBox(height: 10),
        if (r.lines.isNotEmpty)
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              headingRowHeight: 36,
              dataRowMinHeight: 32,
              dataRowMaxHeight: 40,
              columnSpacing: 16,
              headingRowColor:
                  WidgetStateProperty.all(Colors.white),
              columns: const [
                DataColumn(label: Text('Mã hàng', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600))),
                DataColumn(label: Text('Tên hàng', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600))),
                DataColumn(label: Text('SL', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600))),
                DataColumn(label: Text('Đơn giá', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600))),
                DataColumn(label: Text('VAT', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600))),
                DataColumn(label: Text('Thành tiền', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600))),
              ],
              rows: r.lines.map((l) {
                final vatLabel = l.vatExempt
                    ? 'KCT'
                    : l.vatRate <= 0
                        ? '—'
                        : '${l.vatRate.toStringAsFixed(0)}%';
                return DataRow(cells: [
                  DataCell(Text(l.productCode, style: const TextStyle(fontSize: 12))),
                  DataCell(Text(l.productName, style: const TextStyle(fontSize: 12))),
                  DataCell(Text(l.qty.toStringAsFixed(0), style: const TextStyle(fontSize: 12))),
                  DataCell(Text('${_moneyFmt.format(l.costPrice)} đ', style: const TextStyle(fontSize: 12))),
                  DataCell(Text(vatLabel, style: const TextStyle(fontSize: 12))),
                  DataCell(Text('${_moneyFmt.format(l.lineTotal + l.vatAmount)} đ',
                      style: const TextStyle(fontSize: 12))),
                ]);
              }).toList(),
            ),
          ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerRight,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('Tổng tiền hàng: ${_moneyFmt.format(r.totalCost)} đ',
                  style: const TextStyle(fontSize: 12)),
              Text('Tổng VAT: ${_moneyFmt.format(r.totalVat)} đ',
                  style: const TextStyle(fontSize: 12)),
              Text('Giảm giá: ${_moneyFmt.format(r.discountAmount)} đ',
                  style: const TextStyle(fontSize: 12)),
              Text(
                  'Tổng cộng: ${_moneyFmt.format(r.grandTotal != 0 ? r.grandTotal : r.totalCost + r.totalVat - r.discountAmount)} đ',
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              Text('Đã trả NCC: ${_moneyFmt.format(r.paidAmount)} đ',
                  style: const TextStyle(fontSize: 12)),
            ],
          ),
        ),
      ],
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

  Widget _buildPaymentsTab(PosPurchaseReceipt r) {
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
            ].whereType<String>().join(' · '),
            style: const TextStyle(fontSize: 11),
          ),
        );
      }).toList(),
    );
  }
}
