import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/pos_purchase.dart';
import '../providers/permission_provider.dart';
import '../services/api_service.dart';
import '../utils/pos_doc_status.dart';
import '../utils/pos_mutation_result.dart';
import '../widgets/loading_widget.dart';
import '../widgets/notification_overlay.dart';
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
import 'pos_purchase_return_editor_screen.dart';
import '../screens/main_layout.dart' show ScreenRefreshNotifier;
import 'package:sbox_pos/l10n/app_tr.dart';

const _blue = SboxColors.brand600;

class PosPurchaseReturnListScreen extends StatefulWidget {
  const PosPurchaseReturnListScreen({super.key});

  @override
  State<PosPurchaseReturnListScreen> createState() =>
      _PosPurchaseReturnListScreenState();
}

class _PosPurchaseReturnListScreenState extends State<PosPurchaseReturnListScreen> {
  final _api = ApiService();
  final _searchCtrl = TextEditingController();
  final _createdByCtrl = TextEditingController();
  final _returnedByCtrl = TextEditingController();
  final _moneyFmt = NumberFormat('#,##0', 'vi_VN');
  final _dateFmt = DateFormat('dd/MM/yyyy HH:mm', 'vi_VN');

  bool _loading = true;
  List<PosPurchaseReturn> _items = [];
  List<PosSupplierFull> _suppliers = [];
  int _total = 0;
  int _page = 1;
  static const _pageSize = 50;

  final Set<String> _statusFilter = {'Draft', 'Completed', 'Cancelled'};
  String? _supplierId;
  PosKiotTimeFilterState _timeFilter = PosKiotTimeFilterState.thisMonth();

  String? _expandedId;
  PosPurchaseReturn? _expandedDetail;
  bool _detailLoading = false;

  @override
  void initState() {
    super.initState();
    _loadSuppliers();
    _load();
    _restoreSort();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    _createdByCtrl.dispose();
    _returnedByCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadSuppliers() async {
    final res = await _api.getPosPurchaseSuppliers(pageSize: 200);
    if (!mounted || res['isSuccess'] != true || res['data'] is! Map) return;
    final items = (res['data'] as Map)['items'] as List? ?? [];
    setState(() {
      _suppliers = items
          .map((e) => PosSupplierFull.fromJson(e as Map<String, dynamic>))
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

    final res = await _api.getPosPurchaseReturns(
      search: _searchCtrl.text.trim().isEmpty ? null : _searchCtrl.text.trim(),
      statuses: _statusFilter.toList(),
      supplierId: _supplierId,
      createdBy: _createdByCtrl.text.trim().isEmpty
          ? null
          : _createdByCtrl.text.trim(),
      returnedBy: _returnedByCtrl.text.trim().isEmpty
          ? null
          : _returnedByCtrl.text.trim(),
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
            .map((e) => PosPurchaseReturn.fromJson(e as Map<String, dynamic>))
            .toList();
      });
    } else {
      setState(() => _loading = false);
    }
  }

  Future<void> _toggleExpand(PosPurchaseReturn summary) async {
    if (_expandedId == summary.id) {
      setState(() {
        _expandedId = null;
        _expandedDetail = null;
      });
      return;
    }
    setState(() {
      _expandedId = summary.id;
      _expandedDetail = null;
      _detailLoading = true;
    });

    final res = await _api.getPosPurchaseReturn(summary.id);
    if (!mounted || _expandedId != summary.id) return;
    if (res['isSuccess'] == true) {
      setState(() {
        _expandedDetail =
            PosPurchaseReturn.fromJson(res['data'] as Map<String, dynamic>);
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
    });
  }

  Future<void> _refreshExpandedDetail(String id) async {
    if (_expandedId != id) return;
    final res = await _api.getPosPurchaseReturn(id);
    if (!mounted || _expandedId != id) return;
    if (res['isSuccess'] == true && res['data'] is Map<String, dynamic>) {
      setState(() {
        _expandedDetail = PosPurchaseReturn.fromJson(
            res['data'] as Map<String, dynamic>);
      });
    } else {
      _collapseExpanded();
    }
  }

  Future<void> _openEditor({String? returnId, String? sourceReceiptId}) async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => PosPurchaseReturnEditorScreen(
          returnId: returnId,
          sourceReceiptId: sourceReceiptId,
        ),
      ),
    );
    if (mounted) _load(page: _page);
  }

  void _onTimeFilterChanged(PosKiotTimeFilterState s) {
    setState(() => _timeFilter = s);
    _load();
  }

  Future<void> _completeReturn(PosPurchaseReturn r) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Hoàn thành trả hàng')),
        content: Text(tr('Xác nhận trả hàng phiếu ${r.returnNo}?')),
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
    final res = await _api.completePosPurchaseReturn(r.id);
    if (!mounted) return;
    final result = PosDocMutationResult.parse(
      Map<String, dynamic>.from(res),
      expectedStatus: 'Completed',
      completedLabel: 'Đã trả hàng',
    );
    if (result.ok) {
      NotificationOverlayManager().showSuccess(
        title: 'Thành công',
        message: result.successMessage(r.returnNo, completedLabel: 'Đã trả hàng'),
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

  Future<void> _copyReturn(PosPurchaseReturn r) async {
    final res = await _api.copyPosPurchaseReturn(r.id);
    if (!mounted) return;
    if (res['isSuccess'] == true && res['data'] != null) {
      final copy = PosPurchaseReturn.fromJson(res['data'] as Map<String, dynamic>);
      NotificationOverlayManager()
          .showSuccess(title: 'Sao chép', message: tr('Đã tạo ${copy.returnNo}'));
      _load(page: _page);
      _openEditor(returnId: copy.id);
    } else {
      NotificationOverlayManager().showError(
          title: 'Lỗi', message: res['message']?.toString() ?? 'Không sao chép được');
    }
  }

  Future<void> _deleteReturn(PosPurchaseReturn r) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Xóa phiếu')),
        content: Text(tr('Xóa hẳn phiếu ${r.returnNo}? Thao tác không thể hoàn tác.')),
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
    final res = await _api.deletePosPurchaseReturn(r.id);
    if (!mounted) return;
    final deleteResult = PosDocMutationResult.parseDelete(
      Map<String, dynamic>.from(res),
    );
    if (deleteResult.ok) {
      NotificationOverlayManager().showSuccess(title: 'Đã xóa', message: r.returnNo);
      _collapseExpanded();
      setState(() {
        _items = _items.where((x) => x.id != r.id).toList();
        if (_total > 0) _total -= 1;
      });
      await _load(page: _page);
    } else {
      NotificationOverlayManager().showError(
        title: 'Lỗi',
        message: deleteResult.errorMessage ?? res['message']?.toString() ?? 'Không xóa được',
      );
      await _load(page: _page);
    }
  }

  Future<void> _voidCompletedReturn(PosPurchaseReturn r) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Hủy phiếu trả hàng')),
        content: Text(tr('Hủy phiếu ${r.returnNo} và hoàn hàng về kho?')),
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
    final res = await _api.cancelPosPurchaseReturn(r.id);
    if (!mounted) return;
    final result = PosDocMutationResult.parse(
      Map<String, dynamic>.from(res),
      expectedStatus: 'Cancelled',
      completedLabel: 'Đã trả hàng',
    );
    if (result.ok) {
      NotificationOverlayManager().showSuccess(
        title: 'Đã hủy',
        message: result.successMessage(r.returnNo,
            stockNote: 'Đã hoàn kho', completedLabel: 'Đã trả hàng'),
      );
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

  double _supplierOwed(PosPurchaseReturn r) {
    if (r.supplierRefundAmount > 0) return r.supplierRefundAmount;
    return r.totalAmount - r.discountAmount;
  }

  Timer? _debounce;

  void _onSearchChanged(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () => _load());
  }

  int get _moreFilterCount => [_createdByCtrl, _returnedByCtrl].where((c) => c.text.trim().isNotEmpty).length;

  /// Số bộ lọc khác mặc định (đủ trạng thái, mọi NCC) — hiện trên nút «Bộ lọc (n)».
  int get _activeFilterCount =>
      (_statusFilter.length < 3 ? 1 : 0) + _moreFilterCount + (_supplierId != null ? 1 : 0);

  Widget _buildFilterBar(bool canEdit) {
    return SboxFilterBar(
      collapseFilters: _md,
      activeFilterCount: _activeFilterCount,
      searchHint: 'Tìm mã phiếu trả, tên hàng…',
      searchController: _searchCtrl,
      onSearch: _onSearchChanged,
      filters: [
        PosMultiChip(
          label: 'Trạng thái',
          options: const {'Draft': 'Phiếu tạm', 'Completed': 'Đã trả hàng', 'Cancelled': 'Đã hủy'},
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
          onClear: () {
            _createdByCtrl.clear();
            _returnedByCtrl.clear();
            _load();
          },
          fields: () => [
            PosFilterField(label: 'Người tạo', controller: _createdByCtrl, hint: 'Tên người tạo'),
            PosFilterField(label: 'Người trả', controller: _returnedByCtrl, hint: 'Tên người trả'),
          ],
        ),
      ],
      actions: [
        if (canEdit) SboxButton(label: 'Tạo phiếu trả', icon: Icons.add, onPressed: () => _openEditor()),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final perm = Provider.of<PermissionProvider>(context);
    if (!perm.canView('PosPurchaseReturns') && !perm.canView('PosProducts')) {
      return Scaffold(body: Center(child: Text(tr('Không có quyền xem trả hàng nhập'))));
    }
    final canEdit = perm.canEdit('PosPurchaseReturns');
    final mobile = posUseMobileList(context);
    _md = !mobile && MediaQuery.sizeOf(context).width >= 1100;

    return Scaffold(
      backgroundColor: SboxColors.page,
      body: posMobileSafeBody(
        context,
        Column(
          children: [
            const PosModuleToolbar(activeModule: 'PosPurchaseReturns'),
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
                        ? SboxEmptyState(
                            icon: Icons.inventory_2_outlined,
                            title: 'Chưa có phiếu trả hàng nhập',
                            message: 'Đổi bộ lọc thời gian / trạng thái, hoặc tạo phiếu mới.')
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
  PosPurchaseReturn? _mdSelected;

  Future<void> _mdSelect(PosPurchaseReturn r) async {
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

  String get _sortPrefsKey => 'purchase_returns';

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
      prefsKey: 'purchase_returns',
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

  Widget _buildMdRow(PosPurchaseReturn r) {
    final selected = _expandedId == r.id;
    final cancelled = r.status == 'Cancelled';
    final dt = r.returnDate;
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
                      tr(r.returnNo),
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
                  purchaseStatusChip(r.status, completedLabel: 'Đã trả hàng'),
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
                    tr('${_moneyFmt.format(_supplierOwed(r))} đ'),
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
                tr('Chọn phiếu trả hàng bên trái'),
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
    final dt = r.returnDate;
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
                                tr(r.returnNo),
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
                            purchaseStatusChip(r.status, completedLabel: 'Đã trả hàng'),
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
                        tr('NCC cần trả'),
                        style: const TextStyle(
                            fontSize: 12, color: PosTheme.textSecondary),
                      ),
                      Text(
                        tr('${_moneyFmt.format(_supplierOwed(r))} đ'),
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
    const h = TextStyle(
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
          Expanded(flex: 2, child: Text(tr('Mã THN'), style: h)),
          Expanded(flex: 2, child: Text(tr('Thời gian'), style: h)),
          Expanded(flex: 3, child: Text(tr('NCC'), style: h)),
          Expanded(flex: 2, child: Text(tr('Tổng tiền'), style: h, textAlign: TextAlign.right)),
          Expanded(flex: 2, child: Text(tr('Giảm giá'), style: h, textAlign: TextAlign.right)),
          Expanded(flex: 2, child: Text(tr('NCC cần trả'), style: h, textAlign: TextAlign.right)),
          Expanded(flex: 2, child: Text(tr('NCC đã trả'), style: h, textAlign: TextAlign.right)),
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
      itemBuilder: (ctx, i) => _buildReturnBlock(_items[i], canEdit),
    );
  }

  Widget _buildReturnBlock(PosPurchaseReturn r, bool canEdit) {
    final expanded = _expandedId == r.id;
    if (posUseMobileList(context)) {
      return PosMobileExpandableDocCard(
        expanded: expanded,
        onTap: () => _toggleExpand(r),
        code: r.returnNo,
        status: purchaseStatusChip(r.status, completedLabel: 'Đã trả hàng'),
        accentColor: _blue,
        fields: [
          PosMobileField(
            'Ngày trả',
            r.returnDate != null
                ? _dateFmt.format(r.returnDate!.toLocal())
                : '—',
          ),
          PosMobileField('NCC', r.supplierName ?? '—'),
          PosMobileField(
            'NCC đã trả',
            '${_moneyFmt.format(_supplierOwed(r))} đ',
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
                    child: Text(tr(r.returnNo),
                        style: posDocNoTextStyle(r.status, activeColor: _blue)),
                  ),
                  Expanded(
                    flex: 2,
                    child: Text(
                      tr(r.returnDate != null
                          ? _dateFmt.format(r.returnDate!.toLocal())
                          : '—'),
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                  Expanded(
                    flex: 3,
                    child: Padding(
                      padding: const EdgeInsets.only(right: 12),
                      child: Text(tr(r.supplierName ?? '—'),
                          style: const TextStyle(fontSize: 13),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: Text(tr('${_moneyFmt.format(r.totalAmount)} đ'),
                        textAlign: TextAlign.right,
                        style: const TextStyle(fontSize: 13)),
                  ),
                  Expanded(
                    flex: 2,
                    child: Text(tr('${_moneyFmt.format(r.discountAmount)} đ'),
                        textAlign: TextAlign.right,
                        style: const TextStyle(fontSize: 13)),
                  ),
                  Expanded(
                    flex: 2,
                    child: Text(tr('${_moneyFmt.format(_supplierOwed(r))} đ'),
                        textAlign: TextAlign.right,
                        style: const TextStyle(fontSize: 13)),
                  ),
                  Expanded(
                    flex: 2,
                    child: Text(tr('${_moneyFmt.format(r.refundReceived)} đ'),
                        textAlign: TextAlign.right,
                        style: const TextStyle(fontSize: 13)),
                  ),
                  SizedBox(
                    width: 136,
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: purchaseStatusChip(r.status, completedLabel: 'Đã trả hàng'),
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

  Widget _buildDetailPanel(PosPurchaseReturn summary, bool canEdit) {
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
          if (!_md)
            Row(
            children: [
              Text(tr('Thông tin'),
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: _blue)),
              const Spacer(),
              purchaseStatusChip(r.status, completedLabel: 'Đã trả hàng'),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 24,
            runSpacing: 6,
            children: [
              _meta('Người tạo', r.createdBy ?? '—'),
              _meta('Người trả', r.returnedBy ?? '—'),
              _meta('NCC', r.supplierName ?? '—'),
              _meta(
                  'Ngày trả',
                  r.returnDate != null
                      ? _dateFmt.format(r.returnDate!.toLocal())
                      : '—'),
              if (r.sourceReceiptNo != null)
                _meta('Phiếu nhập gốc', r.sourceReceiptNo!),
            ],
          ),
          if (r.note != null && r.note!.isNotEmpty) ...[
            const SizedBox(height: 6),
            _meta('Ghi chú', r.note!),
          ],
          const SizedBox(height: 10),
          if (r.lines.isNotEmpty)
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                headingRowHeight: 36,
                dataRowMinHeight: 32,
                columnSpacing: 16,
                headingRowColor: WidgetStateProperty.all(Colors.white),
                columns: [
                  DataColumn(label: Text(tr('Mã hàng'), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600))),
                  DataColumn(label: Text(tr('Tên hàng'), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600))),
                  DataColumn(label: Text(tr('SL'), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600))),
                  DataColumn(label: Text(tr('Giá trả lại'), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600))),
                  DataColumn(label: Text(tr('Giảm giá'), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600))),
                  DataColumn(label: Text(tr('Thành tiền'), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600))),
                ],
                rows: r.lines.map((l) {
                  return DataRow(cells: [
                    DataCell(Text(tr(l.productCode), style: const TextStyle(fontSize: 12))),
                    DataCell(Text(tr(l.productName), style: const TextStyle(fontSize: 12))),
                    DataCell(Text(tr(l.qty.toStringAsFixed(0)), style: const TextStyle(fontSize: 12))),
                    DataCell(Text(tr('${_moneyFmt.format(l.costPrice)} đ'), style: const TextStyle(fontSize: 12))),
                    DataCell(Text(tr('${_moneyFmt.format(l.discountAmount)} đ'), style: const TextStyle(fontSize: 12))),
                    DataCell(Text(tr('${_moneyFmt.format(l.lineTotal)} đ'), style: const TextStyle(fontSize: 12))),
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
                Text(tr('Tổng tiền hàng: ${_moneyFmt.format(r.totalAmount)} đ'),
                    style: const TextStyle(fontSize: 12)),
                Text(tr('Giảm giá: ${_moneyFmt.format(r.discountAmount)} đ'),
                    style: const TextStyle(fontSize: 12)),
                Text(tr('NCC cần trả: ${_moneyFmt.format(_supplierOwed(r))} đ'),
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                Text(tr('NCC đã trả: ${_moneyFmt.format(r.refundReceived)} đ'),
                    style: const TextStyle(fontSize: 12)),
              ],
            ),
          ),
          if (!_md) ...[
            const SizedBox(height: 10),
            _buildDetailActions(r, canEdit),
          ],
        ],
      ),
    );
  }

  Widget _buildDetailActions(PosPurchaseReturn r, bool canEdit) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        if (canEdit && r.status == 'Draft')
          FilledButton(
            onPressed: () => _openEditor(returnId: r.id),
            style: FilledButton.styleFrom(backgroundColor: _blue),
            child: Text(tr('Mở phiếu')),
          ),
        if (canEdit && r.status == 'Draft')
          OutlinedButton.icon(
            onPressed: () => _completeReturn(r),
            icon: const Icon(Icons.check_circle_outline, size: 16),
            label: Text(tr('Hoàn thành trả hàng')),
          ),
        if (canEdit)
          OutlinedButton.icon(
            onPressed: () => _copyReturn(r),
            icon: const Icon(Icons.copy, size: 16),
            label: Text(tr('Sao chép')),
          ),
        if (canEdit && r.status == 'Draft')
          OutlinedButton.icon(
            onPressed: () => _deleteReturn(r),
            icon: const Icon(Icons.delete_outline, size: 16),
            label: Text(tr('Xóa')),
          ),
        if (canEdit && r.status == 'Completed')
          OutlinedButton.icon(
            onPressed: () => _voidCompletedReturn(r),
            icon: const Icon(Icons.cancel_outlined, size: 16),
            label: Text(tr('Hủy')),
          ),
        if (canEdit && r.status == 'Cancelled')
          OutlinedButton.icon(
            onPressed: () => _deleteReturn(r),
            icon: const Icon(Icons.delete_outline, size: 16),
            label: Text(tr('Xóa')),
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
}
