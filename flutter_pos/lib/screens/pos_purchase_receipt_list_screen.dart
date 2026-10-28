import 'dart:async';
import '../utils/api_datetime.dart';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/pos_product.dart';
import '../models/pos_purchase.dart';
import '../providers/auth_provider.dart';
import '../providers/permission_provider.dart';
import '../services/api_service.dart';
import '../utils/pos_doc_status.dart';
import '../utils/pos_mutation_result.dart';
import '../utils/pos_purchase_receipt_print.dart';
import '../screens/main_layout.dart' show ScreenRefreshNotifier;
import '../widgets/loading_widget.dart';
import '../widgets/notification_overlay.dart';
import '../widgets/pos/pos_barcode_label_dialog.dart';
import '../utils/pos_barcode_print.dart' show posLabelDetail;
import '../utils/pos_kiot_time_range.dart';
import '../widgets/pos/pos_list_filters.dart';
import '../widgets/sbox/sbox_ui.dart';
import '../utils/pos_list_prefs.dart';
import '../utils/responsive_helper.dart';
import '../widgets/pos/pos_mobile_widgets.dart';
import '../widgets/pos/pos_master_detail_layout.dart';
import '../widgets/pos/pos_module_toolbar.dart';
import '../widgets/pos/pos_purchase_toolbar.dart';
import '../widgets/pos/pos_theme.dart';
import '../widgets/pos/pos_supplier_debt_pay_dialog.dart';
import '../widgets/pos/pos_ai_invoice_import.dart';
import 'pos_purchase_receipt_editor_screen.dart';
import 'package:sbox_pos/l10n/app_tr.dart';

const _blue = SboxColors.brand600;

class PosPurchaseReceiptListScreen extends StatefulWidget {
  const PosPurchaseReceiptListScreen({super.key, this.initialSearch});

  final String? initialSearch;

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
    if (widget.initialSearch != null &&
        widget.initialSearch!.trim().isNotEmpty) {
      _searchCtrl.text = widget.initialSearch!.trim();
    }
    ScreenRefreshNotifier.posPurchaseReceipts.addListener(_onExternalRefresh);
    _loadSuppliers();
    _load();
    _restoreSort();
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
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _loadSuppliers() async {
    final res = await _api.getPosPurchaseSuppliers(pageSize: 200);
    if (!mounted || res['isSuccess'] != true) return;
    final raw = res['data'];
    final list = raw is Map
        ? ((raw['items'] as List?) ?? [])
        : (raw is List ? raw : <dynamic>[]);
    setState(() {
      _suppliers = list
          .map((e) => PosSupplierFull.fromJson(
                Map<String, dynamic>.from(e as Map),
              ))
          .toList();
    });
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
      sort: _sort,
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

  /// Chụp hóa đơn NCC → AI đọc → phiếu nhập. Phiếu tạm thì mở luôn để kiểm / nhập kho.
  Future<void> _openAiInvoice() async {
    final result = await showPosAiInvoiceImport(context);
    if (result == null || !mounted) return;
    if (result.isDraft) {
      NotificationOverlayManager().showSuccess(
        title: tr('Đã tạo phiếu tạm ${result.receiptNo}'),
        message: tr('Kiểm lại rồi bấm «Nhập hàng vào kho».'),
      );
      await _openEditor(receiptId: result.receiptId);
      return;
    }
    ScreenRefreshNotifier.refreshPosAfterStockChange();
    NotificationOverlayManager().showSuccess(
      title: tr('Đã nhập kho phiếu ${result.receiptNo}'),
      message: tr('Tồn kho và công nợ NCC đã được cập nhật.'),
    );
    await _load(page: 1);
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

  /// In tem theo phiếu nhập: mỗi dòng in đúng số lượng nhập (quy đổi về đơn vị cơ bản, vd 2 Thùng × 24
  /// = 48 tem lon), kèm lô / HSD của dòng. Trước đây in mỗi mặt hàng 1 tem (× số bản chung) và gọi API
  /// lần lượt từng dòng.
  Future<void> _printLabels(PosPurchaseReceipt r) async {
    final ids = {for (final l in r.lines) l.productId};
    final fetched = await Future.wait(ids.map((id) async {
      final res = await _api.getPosProduct(id);
      return MapEntry(id, res['isSuccess'] == true && res['data'] is Map
          ? Map<String, dynamic>.from(res['data'] as Map)
          : null);
    }));
    final byId = {for (final e in fetched) if (e.value != null) e.key: e.value!};
    final products = <PosProduct>[];
    final quantities = <int>[];
    final dateFmt = DateFormat('dd/MM/yyyy');
    for (final line in r.lines) {
      final json = byId[line.productId];
      if (json == null || line.qty <= 0) continue;
      // Mỗi dòng một đối tượng riêng: cùng mặt hàng nhưng khác lô / HSD vẫn in đúng thông tin dòng.
      final p = PosProduct.fromJson(json);
      final unit = (line.unitName ?? '').trim().toLowerCase();
      final rate = unit.isEmpty
          ? 1.0
          : (p.units ?? const [])
                  .where((u) => u.unitName.trim().toLowerCase() == unit)
                  .map((u) => u.conversionRate)
                  .firstOrNull ??
              1.0;
      final count = (line.qty * (rate <= 0 ? 1 : rate)).ceil().clamp(1, 2000);
      final detail = [
        if ((line.lotNo ?? '').trim().isNotEmpty) 'Lô ${line.lotNo!.trim()}',
        if (line.manufactureDate != null) 'NSX ${dateFmt.format(line.manufactureDate!)}',
        if (line.expiryDate != null) 'HSD ${dateFmt.format(line.expiryDate!)}',
      ].join(' · ');
      if (detail.isNotEmpty) posLabelDetail[p] = detail;
      products.add(p);
      quantities.add(count);
    }
    if (!mounted) return;
    if (products.isEmpty) {
      NotificationOverlayManager()
          .showWarning(title: 'In tem', message: tr('Không có hàng để in tem'));
      return;
    }
    await showPosBarcodeLabelDialog(context, products, quantities: quantities);
  }

  Future<void> _completeReceipt(PosPurchaseReceipt r) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Nhập hàng vào kho')),
        content: Text(tr('Hoàn thành phiếu ${r.receiptNo} và cập nhật tồn kho?')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Hủy'))),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: _blue),
            child: Text(tr('Xác nhận')),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final res = await _api.completePosPurchaseReceipt(r.id);
    if (!mounted) return;
    final result = PosDocMutationResult.parse(
      Map<String, dynamic>.from(res),
      expectedStatus: 'Completed',
      completedLabel: 'Đã nhập hàng',
    );
    if (result.ok) {
      NotificationOverlayManager().showSuccess(
        title: 'Thành công',
        message: result.successMessage(r.receiptNo, completedLabel: 'Đã nhập hàng'),
      );
      ScreenRefreshNotifier.refreshPosAfterStockChange();
      await _load(page: _page);
      await _refreshExpandedDetail(r.id);
    } else {
      NotificationOverlayManager().showError(
        title: 'Lỗi',
        message: result.errorMessage ?? res['message']?.toString() ?? 'Không thể hoàn thành',
      );
      await _load(page: _page);
    }
  }

  Future<void> _copyReceipt(PosPurchaseReceipt r) async {
    final res = await _api.copyPosPurchaseReceipt(r.id);
    if (!mounted) return;
    if (res['isSuccess'] == true && res['data'] != null) {
      final copy = PosPurchaseReceipt.fromJson(res['data'] as Map<String, dynamic>);
      NotificationOverlayManager()
          .showSuccess(title: 'Sao chép', message: tr('Đã tạo ${copy.receiptNo}'));
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
        title: Text(tr('Xóa phiếu')),
        content: Text(tr('Xóa hẳn phiếu ${r.receiptNo}? Thao tác không thể hoàn tác.')),
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
    final res = await _api.deletePosPurchaseReceipt(r.id);
    if (!mounted) return;
    final deleteResult = PosDocMutationResult.parseDelete(
      Map<String, dynamic>.from(res),
    );
    if (deleteResult.ok) {
      NotificationOverlayManager().showSuccess(title: 'Đã xóa', message: r.receiptNo);
      _collapseExpanded();
      setState(() {
        _items = _items.where((x) => x.id != r.id).toList();
        if (_total > 0) _total -= 1;
      });
      ScreenRefreshNotifier.refreshPosPurchaseReceipts();
      await _load(page: _page);
    } else {
      NotificationOverlayManager().showError(
        title: 'Lỗi',
        message: deleteResult.errorMessage ?? res['message']?.toString() ?? 'Không xóa được',
      );
      await _load(page: _page);
    }
  }

  Future<void> _voidCompletedReceipt(PosPurchaseReceipt r) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Hủy phiếu nhập')),
        content: Text(tr('Hủy phiếu ${r.receiptNo} và trừ lại hàng đã nhập kho?')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Không'))),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: Text(tr('Hủy phiếu')),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final res = await _api.cancelPosPurchaseReceipt(r.id);
    if (!mounted) return;
    final result = PosDocMutationResult.parse(
      Map<String, dynamic>.from(res),
      expectedStatus: 'Cancelled',
      completedLabel: 'Đã nhập hàng',
    );
    if (result.ok) {
      NotificationOverlayManager().showSuccess(
        title: 'Đã hủy',
        message: result.successMessage(r.receiptNo,
            stockNote: 'Đã hoàn kho', completedLabel: 'Đã nhập hàng'),
      );
      ScreenRefreshNotifier.refreshPosAfterStockChange();
      await _load(page: _page);
      await _refreshExpandedDetail(r.id);
    } else {
      NotificationOverlayManager().showError(
        title: 'Lỗi',
        message: result.errorMessage ?? res['message']?.toString() ?? 'Không hủy được',
      );
      await _load(page: _page);
    }
  }

  double _balanceDue(PosPurchaseReceipt r) {
    if (r.balanceDue != 0) return r.balanceDue;
    final gt = r.grandTotal != 0
        ? r.grandTotal
        : r.totalCost + r.totalVat - r.discountAmount;
    return gt - r.paidAmount;
  }

  Timer? _debounce;

  void _onSearchChanged(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () => _load());
  }

  void _clearMoreFilters() {
    _createdByCtrl.clear();
    _importedByCtrl.clear();
    _invoiceNoCtrl.clear();
    _load();
  }

  int get _moreFilterCount => [_createdByCtrl, _importedByCtrl, _invoiceNoCtrl]
      .where((c) => c.text.trim().isNotEmpty)
      .length;

  /// Số bộ lọc khác mặc định (đủ trạng thái, mọi NCC) — hiện trên nút «Bộ lọc (n)».
  int get _activeFilterCount =>
      (_statusFilter.length < 3 ? 1 : 0) + _moreFilterCount + (_supplierId != null ? 1 : 0);

  Widget _buildFilterBar(bool canEdit) {
    return SboxFilterBar(
      collapseFilters: _md,
      activeFilterCount: _activeFilterCount,
      searchHint: 'Tìm mã phiếu nhập, tên hàng, ghi chú…',
      searchController: _searchCtrl,
      onSearch: _onSearchChanged,
      filters: [
        PosMultiChip(
          label: 'Trạng thái',
          options: const {'Draft': 'Phiếu tạm', 'Completed': 'Đã nhập hàng', 'Cancelled': 'Đã hủy'},
          selected: _statusFilter,
          onChanged: (v) {
            setState(() => _statusFilter
              ..clear()
              ..addAll(v));
            _load();
          },
        ),
        PosTimeRangeChip(state: _timeFilter, onChanged: _onTimeFilterChanged),
        PosPickChip(
          label: 'NCC',
          value: _supplierId,
          options: {for (final s in _suppliers) s.id: s.name},
          onChanged: (v) {
            setState(() => _supplierId = v);
            _load();
          },
        ),
        PosMoreFiltersButton(
          activeCount: _moreFilterCount,
          onApply: () => _load(),
          onClear: _clearMoreFilters,
          fields: () => [
            PosFilterField(label: 'Người tạo', controller: _createdByCtrl, hint: 'Tên người tạo'),
            PosFilterField(label: 'Người nhập', controller: _importedByCtrl, hint: 'Tên người nhập'),
            PosFilterField(label: 'Số hóa đơn đầu vào', controller: _invoiceNoCtrl, hint: 'Số HĐ đầu vào'),
          ],
        ),
      ],
      actions: [
        if (canEdit)
          SboxButton.secondary(
              label: 'Chụp hóa đơn (AI)', icon: Icons.document_scanner_outlined, onPressed: _openAiInvoice),
        if (canEdit) SboxButton(label: 'Tạo phiếu nhập', icon: Icons.add, onPressed: () => _openEditor()),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final perm = Provider.of<PermissionProvider>(context);
    if (!perm.canView('PosPurchaseReceipts') && !perm.canView('PosProducts')) {
      return Scaffold(
          body: Center(child: Text(tr('Không có quyền xem nhập hàng'))));
    }
    final canEdit = perm.canEdit('PosPurchaseReceipts');
    final mobile = posUseMobileList(context);
    _md = !mobile && MediaQuery.sizeOf(context).width >= 1100;

    return Scaffold(
      backgroundColor: SboxColors.page,
      body: posMobileSafeBody(
        context,
        Column(
          children: [
            const PosModuleToolbar(activeModule: 'PosPurchaseReceipts'),
            Padding(
              padding: EdgeInsets.fromLTRB(mobile ? 12 : 24, mobile ? 12 : 20, mobile ? 12 : 24, 0),
              child: _buildFilterBar(canEdit),
            ),
            Expanded(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: mobile ? 0 : 12),
                child: _loading
                    ? const LoadingWidget()
                    : _items.isEmpty
                        ? const SboxEmptyState(
                            icon: Icons.inventory_2_outlined,
                            title: 'Chưa có phiếu nhập hàng',
                            message: 'Đổi bộ lọc thời gian / trạng thái, hoặc tạo phiếu nhập mới.')
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              if (!_md) _buildTableHeader(),
                              Expanded(
                                  child: _md
                                      ? _buildMdSplit(canEdit)
                                      : _buildList(canEdit)),
                            ],
                          ),
              ),
            ),
            if (!_md) _buildPager(),
          ],
        ),
      ),
    );
  }

  // ── Màn ngang rộng (T1, tablet, web): danh sách phiếu bên trái · chi tiết bên phải ──
  bool _md = false;
  PosPurchaseReceipt? _mdSelected;

  Future<void> _mdSelect(PosPurchaseReceipt r) async {
    if (_expandedId == r.id) return;
    _mdSelected = r;
    await _toggleExpand(r);
  }

  /// Sắp xếp danh sách (server): time_desc | time_asc | value_desc | value_asc | no_asc.
  String _sort = 'time_desc';

  static const _sortLabels = {
    'time_desc': 'Mới nhất',
    'time_asc': 'Cũ nhất',
    'value_desc': 'Giá trị cao → thấp',
    'value_asc': 'Giá trị thấp → cao',
    'no_asc': 'Theo mã phiếu',
  };

  String get _sortPrefsKey => 'purchase_receipts';

  /// Lấy lại cách sắp xếp đã chọn lần trước trên máy này.
  Future<void> _restoreSort() async {
    final v = await PosListPrefs.loadSort(_sortPrefsKey);
    if (!mounted || v == null || v == _sort || !_sortLabels.containsKey(v)) return;
    setState(() => _sort = v);
    _load();
  }

  Widget _buildSortButton() {
    final on = _sort != 'time_desc';
    return PopupMenuButton<String>(
      tooltip: tr('Sắp xếp'),
      onSelected: (v) {
        if (v == _sort) return;
        setState(() => _sort = v);
        PosListPrefs.saveSort(_sortPrefsKey, v);
        _load();
      },
      itemBuilder: (_) => [
        for (final e in _sortLabels.entries)
          PopupMenuItem(
            value: e.key,
            child: Row(
              children: [
                Expanded(child: Text(tr(e.value))),
                if (e.key == _sort)
                  const Icon(Icons.check, size: 18, color: PosTheme.kiotBlue),
              ],
            ),
          ),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.sort, size: 18, color: on ? PosTheme.kiotBlue : PosTheme.textSecondary),
            const SizedBox(width: 4),
            Text(
              tr(_sortLabels[_sort] ?? ''),
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: on ? PosTheme.kiotBlue : PosTheme.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMdSplit(bool canEdit) {
    return PosMasterDetailLayout(
      prefsKey: 'purchase_receipts',
      initialFraction: 0.36,
      minMasterWidth: 380,
      master: Material(
        color: Colors.white,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(16, 4, 8, 4),
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: PosTheme.border)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      tr('$_total phiếu'),
                      style: const TextStyle(
                          fontSize: 12.5, color: PosTheme.textSecondary),
                    ),
                  ),
                  _buildSortButton(),
                ],
              ),
            ),
            Expanded(
              child: ListView.builder(
                itemCount: _items.length,
                itemBuilder: (_, i) => _buildMdRow(_items[i]),
              ),
            ),
            _buildPager(),
          ],
        ),
      ),
      detail: _buildMdDetail(canEdit),
    );
  }

  Widget _buildMdRow(PosPurchaseReceipt r) {
    final selected = _expandedId == r.id;
    final cancelled = r.status == 'Cancelled';
    final dt = r.importDate ?? r.createdAt;
    return Material(
      color: selected ? PosTheme.kiotBlueLight : Colors.white,
      child: InkWell(
        onTap: () => _mdSelect(r),
        child: Container(
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(
                color: selected ? PosTheme.kiotBlue : Colors.transparent,
                width: 3,
              ),
              bottom: const BorderSide(color: PosTheme.border),
            ),
          ),
          padding: const EdgeInsets.fromLTRB(13, 10, 12, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      tr(r.receiptNo),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                        color: cancelled ? Colors.red.shade700 : PosTheme.textPrimary,
                        decoration: cancelled ? TextDecoration.lineThrough : null,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  purchaseStatusChip(r.status),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      tr([if (dt != null) _dateFmt.format(dt.toLocal()), r.supplierName ?? ''].where((e) => e.isNotEmpty).join(' · ')),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 12.5, color: PosTheme.textSecondary),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    tr('${_moneyFmt.format(_balanceDue(r))} đ'),
                    style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMdDetail(bool canEdit) {
    final sel = _mdSelected;
    if (_expandedId == null || sel == null) {
      return ColoredBox(
        color: SboxColors.slate50,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.inventory_2_outlined,
                  size: 56, color: SboxColors.slate400),
              const SizedBox(height: 12),
              Text(
                tr('Chọn phiếu nhập bên trái'),
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 6),
              Text(
                tr('Chi tiết hàng trong phiếu và thao tác (mở, hoàn thành, sao chép, hủy…) hiện ở đây'),
                style: const TextStyle(fontSize: 13, color: PosTheme.textSecondary),
              ),
            ],
          ),
        ),
      );
    }
    final r = _expandedDetail ?? sel;
    final dt = r.importDate ?? r.createdAt;
    return ColoredBox(
      color: SboxColors.slate50,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Thanh đầu: mã phiếu + trạng thái / ngày · NCC — giá trị chính bên phải.
          Material(
            color: Colors.white,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 8, 10),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                tr(r.receiptNo),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 19,
                                  fontWeight: FontWeight.w700,
                                  color: PosTheme.kiotBlue,
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            purchaseStatusChip(r.status),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          tr([if (dt != null) _dateFmt.format(dt.toLocal()), r.supplierName ?? ''].where((e) => e.isNotEmpty).join(' · ')),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 13, color: PosTheme.textSecondary),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        tr('Cần trả NCC'),
                        style: const TextStyle(
                            fontSize: 12, color: PosTheme.textSecondary),
                      ),
                      Text(
                        tr('${_moneyFmt.format(_balanceDue(r))} đ'),
                        style: const TextStyle(
                            fontSize: 18, fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                  const SizedBox(width: 4),
                  IconButton(
                    tooltip: tr('Đóng'),
                    icon: const Icon(Icons.close),
                    onPressed: () {
                      _mdSelected = null;
                      _collapseExpanded();
                    },
                  ),
                ],
              ),
            ),
          ),
          const Divider(height: 1, color: PosTheme.border),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 12),
              child: _buildDetailPanel(sel, canEdit),
            ),
          ),
          // Nút thao tác ghim đáy — không phải cuộn hết bảng hàng mới thấy.
          if (!_detailLoading)
            Material(
              color: Colors.white,
              child: Container(
                decoration: const BoxDecoration(
                  border: Border(top: BorderSide(color: PosTheme.border)),
                ),
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                child: _buildDetailActions(r, canEdit),
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
          Text(tr('Tổng $_total phiếu'),
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
        fontSize: 12, fontWeight: FontWeight.w600, color: PosTheme.textSecondary);
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: SboxColors.slate50,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
        border: Border.all(color: SboxColors.slate200),
      ),
      child: Row(
        children: [
          const SizedBox(width: 24),
          Expanded(flex: 2, child: Text(tr('Mã PN'), style: h)),
          Expanded(flex: 2, child: Text(tr('Thời gian'), style: h)),
          Expanded(flex: 2, child: Text(tr('Mã NCC'), style: h)),
          Expanded(flex: 3, child: Text(tr('NCC'), style: h)),
          Expanded(
              flex: 2,
              child: Text(tr('Cần trả NCC'), style: h, textAlign: TextAlign.right)),
          SizedBox(width: 136, child: Text(tr('Trạng thái'), style: h, textAlign: TextAlign.right)),
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
            hoverColor: r.status == 'Cancelled'
                ? Colors.red.shade50
                : SboxColors.slate100,
            child: Container(

              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: posDocRowBackground(r.status),
                border: Border(
                  bottom: BorderSide(
                      color: expanded ? SboxColors.slate200 : Colors.transparent),
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
                    child: Text(tr(r.receiptNo),
                        style: posDocNoTextStyle(r.status, activeColor: _blue)),
                  ),
                  Expanded(
                    flex: 2,
                    child: Text(
                      tr(dt != null ? _dateFmt.format(dt.toLocal()) : '—'),
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: Text(tr(r.supplierCode ?? '—'),
                        style: const TextStyle(fontSize: 13)),
                  ),
                  Expanded(
                    flex: 3,
                    child: Text(tr(r.supplierName ?? '—'),
                        style: const TextStyle(fontSize: 13),
                        overflow: TextOverflow.ellipsis),
                  ),
                  Expanded(
                    flex: 2,
                    child: Text(tr('${_moneyFmt.format(_balanceDue(r))} đ'),
                        style: const TextStyle(fontSize: 13),
                        textAlign: TextAlign.right),
                  ),
                  SizedBox(
                    width: 136,
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
      color: SboxColors.slate50,
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              _detailTabBtn(0, 'Thông tin'),
              _detailTabBtn(1, 'Lịch sử thanh toán'),
            ],
          ),
          const SizedBox(height: 8),
          if (_detailTab == 0) _buildInfoTab(r) else _buildPaymentsTab(r),
          if (!_md) ...[
            const SizedBox(height: 10),
            _buildDetailActions(r, canEdit),
          ],
        ],
      ),
    );
  }

  Widget _buildDetailActions(PosPurchaseReceipt r, bool canEdit) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        if (canEdit && r.status == 'Draft')
          FilledButton(
            onPressed: () => _openEditor(receiptId: r.id),
            style: FilledButton.styleFrom(backgroundColor: _blue),
            child: Text(tr('Mở phiếu')),
          ),
        OutlinedButton.icon(
          onPressed: () => _printReceipt(r),
          icon: const Icon(Icons.print, size: 16),
          label: Text(tr('In phiếu')),
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
          label: Text(tr('In tem mã')),
        ),
        if (canEdit && r.status == 'Draft')
          OutlinedButton.icon(
            onPressed: () => _completeReceipt(r),
            icon: const Icon(Icons.inventory_2_outlined, size: 16),
            label: Text(tr('Nhập hàng vào kho')),
          ),
        if (canEdit)
          OutlinedButton.icon(
            onPressed: () => _copyReceipt(r),
            icon: const Icon(Icons.copy, size: 16),
            label: Text(tr('Sao chép')),
          ),
        if (canEdit && r.status == 'Draft')
          OutlinedButton.icon(
            onPressed: () => _deleteReceipt(r),
            icon: const Icon(Icons.delete_outline, size: 16),
            label: Text(tr('Xóa')),
          ),
        if (canEdit && r.status == 'Completed' && _balanceDue(r) > 0)
          OutlinedButton.icon(
            onPressed: () async {
              final ok = await showPosSupplierDebtPayDialog(
                context,
                receipt: r,
              );
              if (ok == true && mounted) {
                await _load(page: _page);
                await _refreshExpandedDetail(r.id);
              }
            },
            icon: const Icon(Icons.payments_outlined, size: 16),
            label: Text(tr('Thanh toán NCC')),
          ),
        if (canEdit && r.status == 'Completed')
          OutlinedButton.icon(
            onPressed: () => _voidCompletedReceipt(r),
            icon: const Icon(Icons.cancel_outlined, size: 16),
            label: Text(tr('Hủy')),
          ),
        if (canEdit && r.status == 'Cancelled')
          OutlinedButton.icon(
            onPressed: () => _deleteReceipt(r),
            icon: const Icon(Icons.delete_outline, size: 16),
            label: Text(tr('Xóa')),
          ),
      ],
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
      child: Text(tr(label)),
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
              columns: [
                DataColumn(label: Text(tr('Mã hàng'), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600))),
                DataColumn(label: Text(tr('Tên hàng'), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600))),
                DataColumn(label: Text(tr('SL'), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600))),
                DataColumn(label: Text(tr('Đơn giá'), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600))),
                DataColumn(label: Text(tr('VAT'), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600))),
                DataColumn(label: Text(tr('Thành tiền'), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600))),
              ],
              rows: r.lines.map((l) {
                final vatLabel = l.vatExempt
                    ? 'KCT'
                    : l.vatRate <= 0
                        ? '—'
                        : '${l.vatRate.toStringAsFixed(0)}%';
                return DataRow(cells: [
                  DataCell(Text(tr(l.productCode), style: const TextStyle(fontSize: 12))),
                  DataCell(Text(tr(l.productName), style: const TextStyle(fontSize: 12))),
                  DataCell(Text(tr(l.qty.toStringAsFixed(0)), style: const TextStyle(fontSize: 12))),
                  DataCell(Text(tr('${_moneyFmt.format(l.costPrice)} đ'), style: const TextStyle(fontSize: 12))),
                  DataCell(Text(tr(vatLabel), style: const TextStyle(fontSize: 12))),
                  DataCell(Text(tr('${_moneyFmt.format(l.lineTotal + l.vatAmount)} đ'),
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
              Text(tr('Tổng tiền hàng: ${_moneyFmt.format(r.totalCost)} đ'),
                  style: const TextStyle(fontSize: 12)),
              Text(tr('Tổng VAT: ${_moneyFmt.format(r.totalVat)} đ'),
                  style: const TextStyle(fontSize: 12)),
              Text(tr('Giảm giá: ${_moneyFmt.format(r.discountAmount)} đ'),
                  style: const TextStyle(fontSize: 12)),
              Text(tr('Tổng cộng: ${_moneyFmt.format(r.grandTotal != 0 ? r.grandTotal : r.totalCost + r.totalVat - r.discountAmount)} đ'),
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              Text(tr('Đã trả NCC: ${_moneyFmt.format(r.paidAmount)} đ'),
                  style: const TextStyle(fontSize: 12)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _meta(String label, String value) => RichText(
        text: TextSpan(
          style: const TextStyle(fontSize: 12, color: SboxColors.text),
          children: [
            TextSpan(
                text: tr('$label: '),
                style: const TextStyle(color: PosTheme.textSecondary)),
            TextSpan(text: tr(value)),
          ],
        ),
      );

  Widget _buildPaymentsTab(PosPurchaseReceipt r) {
    final due = _balanceDue(r);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (r.status == 'Completed' && due > 0)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () async {
                final ok = await showPosSupplierDebtPayDialog(
                  context,
                  receipt: r,
                );
                if (ok == true && mounted) {
                  await _load(page: _page);
                  await _refreshExpandedDetail(r.id);
                }
              },
              icon: const Icon(Icons.payments_outlined, size: 18),
              label: Text(tr('Thanh toán còn lại (${_moneyFmt.format(due)} đ)')),
            ),
          ),
        if (_payments.isEmpty)
          Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Text(tr('Chưa có thanh toán'),
                style: TextStyle(fontSize: 12, color: PosTheme.textSecondary)),
          )
        else
          ..._payments.map((p) {
            final paidAt = p['paidAt'] ?? p['PaidAt'];
            final dt =
                paidAt != null ? parseApiUtcDateTime(paidAt.toString()) : null;
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
                ].whereType<String>().join(' · ')),
                style: const TextStyle(fontSize: 11),
              ),
            );
          }),
      ],
    );
  }
}
