import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/pos_purchase.dart';
import '../providers/permission_provider.dart';
import '../services/api_service.dart';
import '../utils/pos_doc_status.dart';
import '../utils/pos_mutation_result.dart';
import '../widgets/hrm_page_chrome.dart';
import '../widgets/loading_widget.dart';
import '../widgets/notification_overlay.dart';
import '../utils/pos_kiot_time_range.dart';
import '../widgets/pos/pos_kiot_time_filter.dart';
import '../utils/responsive_helper.dart';
import '../widgets/pos/pos_mobile_widgets.dart';
import '../widgets/pos/pos_module_toolbar.dart';
import '../widgets/pos/pos_purchase_toolbar.dart';
import '../widgets/pos/pos_theme.dart';
import 'pos_purchase_return_editor_screen.dart';
import '../screens/main_layout.dart' show ScreenRefreshNotifier;
import 'package:zkteco_flutter_client/l10n/app_tr.dart';

const _blue = Color(0xFF2563EB);

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
  }

  @override
  void dispose() {
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

  int get _activeFilterCount {
    var n = 0;
    if (_supplierId != null) n++;
    if (_createdByCtrl.text.trim().isNotEmpty) n++;
    if (_returnedByCtrl.text.trim().isNotEmpty) n++;
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
                title: Text(tr('Phiếu tạm'), style: TextStyle(fontSize: 13)),
                value: _statusFilter.contains('Draft'),
                activeColor: _blue,
                onChanged: (v) => _toggleStatus('Draft', v),
              ),
              CheckboxListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(tr('Đã trả hàng'), style: TextStyle(fontSize: 13)),
                value: _statusFilter.contains('Completed'),
                activeColor: _blue,
                onChanged: (v) => _toggleStatus('Completed', v),
              ),
              CheckboxListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(tr('Đã hủy'), style: TextStyle(fontSize: 13)),
                value: _statusFilter.contains('Cancelled'),
                activeColor: _blue,
                onChanged: (v) => _toggleStatus('Cancelled', v),
              ),
            ],
          ),
        ),
        purchaseFilterSection(
          'Thời gian',
          PosKiotTimeFilter(state: _timeFilter, onChanged: _onTimeFilterChanged),
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
            hint: Text(tr('Tất cả NCC'), style: TextStyle(fontSize: 12)),
            items: [
              DropdownMenuItem<String?>(
                value: null,
                child: Text(tr('Tất cả NCC'), style: TextStyle(fontSize: 12)),
              ),
              ..._suppliers.map(
                (s) => DropdownMenuItem<String?>(
                  value: s.id,
                  child: Text(tr(s.name),
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
            decoration: InputDecoration(
              hintText: tr('Chọn người tạo…'),
              isDense: true,
              border: OutlineInputBorder(),
              contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            ),
            style: const TextStyle(fontSize: 12),
            onSubmitted: (_) => _load(),
          ),
        ),
        purchaseFilterSection(
          'Người trả',
          TextField(
            controller: _returnedByCtrl,
            decoration: InputDecoration(
              hintText: tr('Chọn người trả…'),
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
          child: Text(tr('Áp dụng lọc'), style: TextStyle(fontSize: 12)),
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
      return Scaffold(
          body: Center(child: Text(tr('Không có quyền xem trả hàng nhập'))));
    }
    final canEdit = perm.canEdit('PosPurchaseReturns');

    return Scaffold(
      backgroundColor: HrmPageChrome.background,
      body: posMobileSafeBody(
        context,
        Column(
        children: [
          const PosModuleToolbar(activeModule: 'PosPurchaseReturns'),
          PosMobileListHeader(
            icon: Icons.assignment_return,
            title: 'Trả hàng nhập',
            onCreate: canEdit ? () => _openEditor() : null,
            createLabel: 'Trả hàng nhập',
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
                      decoration: InputDecoration(
                        hintText: tr('Theo mã phiếu trả…'),
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
                            ? Center(
                                child: Text(tr('Chưa có phiếu trả hàng')))
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
        color: const Color(0xFFF8FAFC),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          const SizedBox(width: 24),
          Expanded(flex: 2, child: Text(tr('Mã THN'), style: h)),
          Expanded(flex: 2, child: Text(tr('Thời gian'), style: h)),
          Expanded(flex: 3, child: Text(tr('NCC'), style: h)),
          Expanded(flex: 2, child: Text(tr('Tổng tiền'), style: h)),
          Expanded(flex: 2, child: Text(tr('Giảm giá'), style: h)),
          Expanded(flex: 2, child: Text(tr('NCC cần trả'), style: h)),
          Expanded(flex: 2, child: Text(tr('NCC đã trả'), style: h)),
          SizedBox(width: 100, child: Text(tr('Trạng thái'), style: h, textAlign: TextAlign.right)),
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
                : const Color(0xFFF1F5F9),
            child: Container(
              color: posDocRowBackground(r.status),
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
                    child: Text(tr(r.supplierName ?? '—'),
                        style: const TextStyle(fontSize: 13),
                        overflow: TextOverflow.ellipsis),
                  ),
                  Expanded(
                    flex: 2,
                    child: Text(tr('${_moneyFmt.format(r.totalAmount)} đ'),
                        style: const TextStyle(fontSize: 13)),
                  ),
                  Expanded(
                    flex: 2,
                    child: Text(tr('${_moneyFmt.format(r.discountAmount)} đ'),
                        style: const TextStyle(fontSize: 13)),
                  ),
                  Expanded(
                    flex: 2,
                    child: Text(tr('${_moneyFmt.format(_supplierOwed(r))} đ'),
                        style: const TextStyle(fontSize: 13)),
                  ),
                  Expanded(
                    flex: 2,
                    child: Text(tr('${_moneyFmt.format(r.refundReceived)} đ'),
                        style: const TextStyle(fontSize: 13)),
                  ),
                  SizedBox(
                    width: 100,
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
      color: const Color(0xFFF8FAFC),
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
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
          const SizedBox(height: 10),
          Wrap(
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
          ),
        ],
      ),
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
}
