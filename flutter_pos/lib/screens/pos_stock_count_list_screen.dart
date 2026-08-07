import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/pos_stock_count.dart';
import '../providers/permission_provider.dart';
import '../providers/auth_provider.dart';
import '../services/api_service.dart';
import '../utils/pos_doc_status.dart';
import '../utils/pos_mutation_result.dart';
import '../utils/pos_stock_count_print.dart';
import '../widgets/hrm_page_chrome.dart';
import '../widgets/loading_widget.dart';
import '../widgets/notification_overlay.dart';
import '../utils/pos_kiot_time_range.dart';
import '../widgets/pos/pos_kiot_time_filter.dart';
import '../utils/responsive_helper.dart';
import '../widgets/pos/pos_mobile_widgets.dart';
import '../widgets/pos/pos_module_toolbar.dart';
import '../widgets/pos/pos_purchase_toolbar.dart';
import '../widgets/pos/pos_stock_count_helpers.dart';
import '../widgets/pos/pos_theme.dart';
import 'pos_stock_count_editor_screen.dart';
import '../screens/main_layout.dart' show ScreenRefreshNotifier;
import 'package:sbox_pos/l10n/app_tr.dart';

const _blue = Color(0xFF2563EB);

class PosStockCountListScreen extends StatefulWidget {
  const PosStockCountListScreen({super.key});

  @override
  State<PosStockCountListScreen> createState() =>
      _PosStockCountListScreenState();
}

class _PosStockCountListScreenState extends State<PosStockCountListScreen> {
  final _api = ApiService();
  final _searchCtrl = TextEditingController();
  final _createdByCtrl = TextEditingController();
  final _moneyFmt = NumberFormat('#,##0', 'vi_VN');
  final _qtyFmt = NumberFormat('#,##0.##', 'vi_VN');
  final _dateFmt = DateFormat('dd/MM/yyyy HH:mm', 'vi_VN');

  bool _loading = true;
  List<PosStockCount> _items = [];
  int _total = 0;
  int _page = 1;
  static const _pageSize = 50;

  final Set<String> _statusFilter = {'InProgress', 'Completed', 'Cancelled'};
  PosKiotTimeFilterState _timeFilter = PosKiotTimeFilterState.thisMonth();

  String? _expandedId;
  PosStockCount? _expandedDetail;
  bool _detailLoading = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _createdByCtrl.dispose();
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

    final res = await _api.getPosStockCounts(
      search: _searchCtrl.text.trim().isEmpty ? null : _searchCtrl.text.trim(),
      statuses: _statusFilter.toList(),
      createdBy: _createdByCtrl.text.trim().isEmpty
          ? null
          : _createdByCtrl.text.trim(),
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
            .map((e) => PosStockCount.fromJson(e as Map<String, dynamic>))
            .toList();
      });
    } else {
      setState(() => _loading = false);
    }
  }

  Future<void> _toggleExpand(PosStockCount summary) async {
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

    final res = await _api.getPosStockCount(summary.id);
    if (!mounted || _expandedId != summary.id) return;
    if (res['isSuccess'] == true) {
      setState(() {
        _expandedDetail =
            PosStockCount.fromJson(res['data'] as Map<String, dynamic>);
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
    final res = await _api.getPosStockCount(id);
    if (!mounted || _expandedId != id) return;
    if (res['isSuccess'] == true && res['data'] is Map<String, dynamic>) {
      setState(() {
        _expandedDetail =
            PosStockCount.fromJson(res['data'] as Map<String, dynamic>);
      });
    } else {
      _collapseExpanded();
    }
  }

  Future<void> _openEditor({String? countId}) async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => PosStockCountEditorScreen(countId: countId),
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

  Future<void> _completeCount(PosStockCount c) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Cân bằng kho')),
        content: Text(tr('Hoàn thành phiếu ${c.countNo} và cập nhật tồn kho?')),
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
    final res = await _api.completePosStockCount(c.id);
    if (!mounted) return;
    final result = PosDocMutationResult.parse(
      Map<String, dynamic>.from(res),
      expectedStatus: 'Completed',
      statusFallback: 'InProgress',
      completedLabel: 'Đã cân bằng kho',
    );
    if (result.ok) {
      NotificationOverlayManager().showSuccess(
        title: 'Thành công',
        message: result.successMessage(c.countNo, completedLabel: 'Đã cân bằng kho'),
      );
      ScreenRefreshNotifier.refreshPosAfterStockChange();
      await _load(page: _page);
      await _refreshExpandedDetail(c.id);
    } else {
      NotificationOverlayManager().showError(
        title: 'Lỗi',
        message: result.errorMessage ?? res['message']?.toString() ?? 'Không thể hoàn thành',
      );
      await _load(page: _page);
    }
  }

  Future<void> _copyCount(PosStockCount c) async {
    final res = await _api.copyPosStockCount(c.id);
    if (!mounted) return;
    if (res['isSuccess'] == true && res['data'] != null) {
      final copy =
          PosStockCount.fromJson(res['data'] as Map<String, dynamic>);
      NotificationOverlayManager()
          .showSuccess(title: 'Sao chép', message: tr('Đã tạo ${copy.countNo}'));
      _load(page: _page);
      _openEditor(countId: copy.id);
    } else {
      NotificationOverlayManager().showError(
          title: 'Lỗi', message: res['message']?.toString() ?? 'Không sao chép được');
    }
  }

  Future<void> _deleteCount(PosStockCount c) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Xóa phiếu')),
        content: Text(tr('Xóa hẳn phiếu ${c.countNo}? Thao tác không thể hoàn tác.')),
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
    final res = await _api.deletePosStockCount(c.id);
    if (!mounted) return;
    final deleteResult = PosDocMutationResult.parseDelete(
      Map<String, dynamic>.from(res),
    );
    if (deleteResult.ok) {
      NotificationOverlayManager().showSuccess(title: 'Đã xóa', message: c.countNo);
      _collapseExpanded();
      setState(() {
        _items = _items.where((x) => x.id != c.id).toList();
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

  Future<void> _voidCompletedCount(PosStockCount c) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Hủy phiếu kiểm kê')),
        content: Text(tr('Hủy phiếu ${c.countNo} và hoàn tồn kho về trước khi cân bằng?')),
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
    final res = await _api.cancelPosStockCount(c.id);
    if (!mounted) return;
    final result = PosDocMutationResult.parse(
      Map<String, dynamic>.from(res),
      expectedStatus: 'Cancelled',
      statusFallback: 'InProgress',
      completedLabel: 'Đã cân bằng kho',
    );
    if (result.ok) {
      NotificationOverlayManager().showSuccess(
        title: 'Đã hủy',
        message: result.successMessage(c.countNo,
            stockNote: 'Đã hoàn tồn kho', completedLabel: 'Đã cân bằng kho'),
      );
      await _load(page: _page);
      await _refreshExpandedDetail(c.id);
    } else {
      NotificationOverlayManager().showError(
        title: 'Lỗi',
        message: result.errorMessage ?? res['message']?.toString() ?? 'Không hủy được',
      );
      await _load(page: _page);
    }
  }

  Future<void> _printCount(PosStockCount summary) async {
    PosStockCount count = _expandedDetail ?? summary;
    if (count.lines.isEmpty || _expandedId != summary.id) {
      final res = await _api.getPosStockCount(summary.id);
      if (!mounted) return;
      if (res['isSuccess'] != true || res['data'] == null) {
        NotificationOverlayManager().showError(
            title: 'Lỗi', message: tr('Không tải được phiếu để in'));
        return;
      }
      count = PosStockCount.fromJson(res['data'] as Map<String, dynamic>);
    }
    final auth = Provider.of<AuthProvider>(context, listen: false);
    await printPosStockCount(
      context: context,
      count: count,
      branchName: auth.currentUser?.department,
    );
  }

  String _fmtQty(double v) => _qtyFmt.format(v);

  int get _activeFilterCount {
    var n = 0;
    if (_createdByCtrl.text.trim().isNotEmpty) n++;
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
                value: _statusFilter.contains('InProgress'),
                activeColor: _blue,
                onChanged: (v) => _toggleStatus('InProgress', v),
              ),
              CheckboxListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(tr('Đã cân bằng kho'), style: TextStyle(fontSize: 13)),
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
          body: Center(child: Text(tr('Không có quyền xem kiểm kê kho'))));
    }
    final canEdit = perm.canEdit('PosStockCounts');

    return Scaffold(
      backgroundColor: HrmPageChrome.background,
      body: posMobileSafeBody(
        context,
        Column(
        children: [
          const PosModuleToolbar(activeModule: 'PosStockCounts'),
          PosMobileListHeader(
            icon: Icons.inventory_outlined,
            title: 'Kiểm kê kho',
            onCreate: canEdit ? () => _openEditor() : null,
            createLabel: 'Tạo phiếu KK',
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
                        hintText: tr('Tìm mã KK, ghi chú…'),
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
                            ? Center(child: Text(tr('Chưa có phiếu kiểm kê')))
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
          Expanded(flex: 2, child: Text(tr('Mã KK'), style: h)),
          Expanded(flex: 2, child: Text(tr('Thời gian'), style: h)),
          Expanded(flex: 2, child: Text(tr('Ngày cân bằng'), style: h)),
          Expanded(
              flex: 2,
              child: Text(tr('SL thực tế'), style: h, textAlign: TextAlign.right)),
          Expanded(
              flex: 2,
              child: Text(tr('Tổng thực tế'), style: h, textAlign: TextAlign.right)),
          Expanded(
              flex: 2,
              child: Text(tr('Tổng chênh lệch'), style: h, textAlign: TextAlign.right)),
          SizedBox(width: 110, child: Text(tr('Trạng thái'), style: h, textAlign: TextAlign.right)),
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
      itemBuilder: (ctx, i) => _buildCountBlock(_items[i], canEdit),
    );
  }

  Widget _buildCountBlock(PosStockCount c, bool canEdit) {
    final expanded = _expandedId == c.id;
    final created = c.createdAt;
    final completed = c.completedAt;
    if (posUseMobileList(context)) {
      return PosMobileExpandableDocCard(
        expanded: expanded,
        onTap: () => _toggleExpand(c),
        code: c.countNo,
        status: stockCountStatusChip(c.status),
        accentColor: _blue,
        fields: [
          PosMobileField(
            'Tạo lúc',
            created != null ? _dateFmt.format(created.toLocal()) : '—',
          ),
          PosMobileField(
            'Cân bằng',
            completed != null ? _dateFmt.format(completed.toLocal()) : '—',
          ),
          PosMobileField('SL thực tế', _fmtQty(c.totalActualQty)),
        ],
        detail: expanded ? _buildDetailPanel(c, canEdit) : null,
      );
    }
    return Material(
      color: Colors.white,
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: () => _toggleExpand(c),
            hoverColor: c.status == 'Cancelled'
                ? Colors.red.shade50
                : const Color(0xFFF1F5F9),
            child: Container(
              color: posDocRowBackground(
                  c.status == 'InProgress' ? 'InProgress' : c.status),
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
                    child: Text(tr(c.countNo),
                        style: posDocNoTextStyle(
                          c.status == 'InProgress' ? 'InProgress' : c.status,
                          activeColor: _blue,
                        )),
                  ),
                  Expanded(
                    flex: 2,
                    child: Text(
                      tr(created != null ? _dateFmt.format(created.toLocal()) : '—'),
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: Text(
                      tr(completed != null ? _dateFmt.format(completed.toLocal()) : '—'),
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: Text(tr(_fmtQty(c.totalActualQty)),
                        style: const TextStyle(fontSize: 13),
                        textAlign: TextAlign.right),
                  ),
                  Expanded(
                    flex: 2,
                    child: Text(tr('${_moneyFmt.format(c.totalActualValue)} đ'),
                        style: const TextStyle(fontSize: 13),
                        textAlign: TextAlign.right),
                  ),
                  Expanded(
                    flex: 2,
                    child: Text(
                      tr('${c.totalDiffQty >= 0 ? '+' : ''}${_fmtQty(c.totalDiffQty)}'),
                      style: TextStyle(
                        fontSize: 13,
                        color: c.totalDiffQty == 0
                            ? PosTheme.textSecondary
                            : c.totalDiffQty > 0
                                ? Colors.green.shade700
                                : Colors.red.shade700,
                      ),
                      textAlign: TextAlign.right,
                    ),
                  ),
                  SizedBox(
                    width: 110,
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: stockCountStatusChip(c.status),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (expanded) _buildDetailPanel(c, canEdit),
        ],
      ),
    );
  }

  Widget _buildDetailPanel(PosStockCount summary, bool canEdit) {
    if (_detailLoading) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    final c = _expandedDetail ?? summary;

    return Container(
      color: const Color(0xFFF8FAFC),
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(tr('Chi tiết phiếu'),
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              const Spacer(),
              stockCountStatusChip(c.status),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 24,
            runSpacing: 6,
            children: [
              _meta('Người tạo', c.createdBy ?? '—'),
              _meta('Người cân bằng', c.balancedBy ?? '—'),
              _meta('Thời gian tạo',
                  c.createdAt != null ? _dateFmt.format(c.createdAt!.toLocal()) : '—'),
              _meta('Ngày cân bằng',
                  c.completedAt != null ? _dateFmt.format(c.completedAt!.toLocal()) : '—'),
              _meta('Đã kiểm', '${c.checkedCount}/${c.lineCount}'),
            ],
          ),
          if (c.note != null && c.note!.isNotEmpty) ...[
            const SizedBox(height: 8),
            _meta('Ghi chú', c.note!),
          ],
          const SizedBox(height: 10),
          if (c.lines.isNotEmpty)
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                headingRowHeight: 36,
                dataRowMinHeight: 32,
                dataRowMaxHeight: 40,
                columnSpacing: 16,
                headingRowColor: WidgetStateProperty.all(Colors.white),
                columns: [
                  DataColumn(
                      label: Text(tr('Mã hàng'),
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600))),
                  DataColumn(
                      label: Text(tr('Tên hàng'),
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600))),
                  DataColumn(
                      label: Text(tr('Tồn kho'),
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600))),
                  DataColumn(
                      label: Text(tr('Thực tế'),
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600))),
                  DataColumn(
                      label: Text(tr('SL lệch'),
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600))),
                  DataColumn(
                      label: Text(tr('Giá trị lệch'),
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600))),
                ],
                rows: c.lines.map((l) {
                  return DataRow(cells: [
                    DataCell(Text(tr(l.productCode), style: const TextStyle(fontSize: 12))),
                    DataCell(Text(tr(l.productName), style: const TextStyle(fontSize: 12))),
                    DataCell(Text(tr(_fmtQty(l.systemQty)), style: const TextStyle(fontSize: 12))),
                    DataCell(Text(
                        tr(l.countedQty != null ? _fmtQty(l.countedQty!) : '—'),
                        style: const TextStyle(fontSize: 12))),
                    DataCell(Text(
                        tr(l.countedQty != null ? _fmtQty(l.diffQty) : '—'),
                        style: const TextStyle(fontSize: 12))),
                    DataCell(Text(
                        tr(l.countedQty != null ? '${_moneyFmt.format(l.diffValue)} đ' : '—'),
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
                Text(tr('Tổng SL thực tế: ${_fmtQty(c.totalActualQty)}'),
                    style: const TextStyle(fontSize: 12)),
                Text(tr('Tổng giá trị thực tế: ${_moneyFmt.format(c.totalActualValue)} đ'),
                    style: const TextStyle(fontSize: 12)),
                Text(tr('${tr('Tổng chênh lệch: ')}${c.totalDiffQty >= 0 ? '+' : ''}${_fmtQty(c.totalDiffQty)} (${_moneyFmt.format(c.totalDiffValue)} đ)'),
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (canEdit && c.status == 'InProgress')
                FilledButton(
                  onPressed: () => _openEditor(countId: c.id),
                  style: FilledButton.styleFrom(backgroundColor: _blue),
                  child: Text(tr('Mở phiếu')),
                ),
              if (canEdit && c.status == 'InProgress')
                OutlinedButton.icon(
                  onPressed: () => _completeCount(c),
                  icon: const Icon(Icons.inventory_2_outlined, size: 16),
                  label: Text(tr('Cân bằng kho')),
                ),
              if (canEdit)
                OutlinedButton.icon(
                  onPressed: () => _copyCount(c),
                  icon: const Icon(Icons.copy, size: 16),
                  label: Text(tr('Sao chép')),
                ),
              if (canEdit && c.status == 'InProgress')
                OutlinedButton.icon(
                  onPressed: () => _deleteCount(c),
                  icon: const Icon(Icons.delete_outline, size: 16),
                  label: Text(tr('Xóa')),
                ),
              if (canEdit && c.status == 'Completed')
                OutlinedButton.icon(
                  onPressed: () => _voidCompletedCount(c),
                  icon: const Icon(Icons.cancel_outlined, size: 16),
                  label: Text(tr('Hủy')),
                ),
              if (canEdit && c.status == 'Cancelled')
                OutlinedButton.icon(
                  onPressed: () => _deleteCount(c),
                  icon: const Icon(Icons.delete_outline, size: 16),
                  label: Text(tr('Xóa')),
                ),
              OutlinedButton.icon(
                onPressed: () => _printCount(c),
                icon: const Icon(Icons.print, size: 16),
                label: Text(tr('In')),
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
