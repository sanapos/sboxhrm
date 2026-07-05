import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/pos_stock_issue_doc.dart';
import '../providers/permission_provider.dart';
import '../services/api_service.dart';
import '../widgets/hrm_page_chrome.dart';
import '../widgets/loading_widget.dart';
import '../widgets/notification_overlay.dart';
import '../utils/pos_kiot_time_range.dart';
import '../widgets/pos/pos_kiot_time_filter.dart';
import '../utils/responsive_helper.dart';
import '../widgets/pos/pos_mobile_widgets.dart';
import '../widgets/pos/pos_module_toolbar.dart';
import '../widgets/pos/pos_purchase_toolbar.dart';
import '../widgets/pos/pos_stock_issue_config.dart';
import '../widgets/pos/pos_stock_issue_helpers.dart';
import '../widgets/pos/pos_theme.dart';
import 'pos_stock_issue_editor_screen.dart';

const _blue = Color(0xFF2563EB);

class PosStockIssueListScreen extends StatefulWidget {
  const PosStockIssueListScreen({super.key, required this.config});

  final PosStockIssueConfig config;

  @override
  State<PosStockIssueListScreen> createState() =>
      _PosStockIssueListScreenState();
}

class _PosStockIssueListScreenState extends State<PosStockIssueListScreen> {
  final _api = ApiService();
  final _searchCtrl = TextEditingController();
  final _createdByCtrl = TextEditingController();
  final _moneyFmt = NumberFormat('#,##0', 'vi_VN');
  final _qtyFmt = NumberFormat('#,##0.##', 'vi_VN');
  final _dateFmt = DateFormat('dd/MM/yyyy HH:mm', 'vi_VN');

  bool _loading = true;
  List<PosStockIssueDoc> _items = [];
  int _total = 0;
  int _page = 1;
  static const _pageSize = 50;

  final Set<String> _statusFilter = {'Draft', 'Completed', 'Cancelled'};
  PosKiotTimeFilterState _timeFilter = PosKiotTimeFilterState.thisMonth();

  String? _expandedId;
  PosStockIssueDoc? _expandedDetail;
  bool _detailLoading = false;

  PosStockIssueConfig get _config => widget.config;

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

    final res = await _api.getPosStockIssueDocs(
      _config.kind,
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
            .map((e) => PosStockIssueDoc.fromJson(e as Map<String, dynamic>))
            .toList();
      });
    } else {
      setState(() => _loading = false);
    }
  }

  Future<void> _toggleExpand(PosStockIssueDoc summary) async {
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

    final res = await _api.getPosStockIssueDoc(_config.kind, summary.id);
    if (!mounted || _expandedId != summary.id) return;
    if (res['isSuccess'] == true) {
      setState(() {
        _expandedDetail =
            PosStockIssueDoc.fromJson(res['data'] as Map<String, dynamic>);
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
    final res = await _api.getPosStockIssueDoc(_config.kind, id);
    if (!mounted || _expandedId != id) return;
    if (res['isSuccess'] == true && res['data'] is Map<String, dynamic>) {
      setState(() {
        _expandedDetail = PosStockIssueDoc.fromJson(
            res['data'] as Map<String, dynamic>);
      });
    } else {
      _collapseExpanded();
    }
  }

  Future<void> _openEditor({String? issueId}) async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => PosStockIssueEditorScreen(
          config: _config,
          issueId: issueId,
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

  Future<void> _completeIssue(PosStockIssueDoc doc) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(_config.completeDialogTitle),
        content: Text(
            '${_config.completeDialogMessage.replaceAll('?', '')} ${doc.issueNo}?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Hủy')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: _blue),
            child: const Text('Xác nhận'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final res = await _api.completePosStockIssueDoc(_config.kind, doc.id);
    if (!mounted) return;
    if (res['isSuccess'] == true) {
      NotificationOverlayManager().showSuccess(
          title: 'Thành công', message: 'Đã hoàn thành ${doc.issueNo}');
      await _load(page: _page);
      await _refreshExpandedDetail(doc.id);
    } else {
      NotificationOverlayManager().showError(
          title: 'Lỗi',
          message: res['message']?.toString() ?? 'Không thể hoàn thành');
    }
  }

  Future<void> _copyIssue(PosStockIssueDoc doc) async {
    final res = await _api.copyPosStockIssueDoc(_config.kind, doc.id);
    if (!mounted) return;
    if (res['isSuccess'] == true && res['data'] != null) {
      final copy =
          PosStockIssueDoc.fromJson(res['data'] as Map<String, dynamic>);
      NotificationOverlayManager()
          .showSuccess(title: 'Sao chép', message: 'Đã tạo ${copy.issueNo}');
      _load(page: _page);
      _openEditor(issueId: copy.id);
    } else {
      NotificationOverlayManager().showError(
          title: 'Lỗi',
          message: res['message']?.toString() ?? 'Không sao chép được');
    }
  }

  Future<void> _deleteIssue(PosStockIssueDoc doc) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Xóa phiếu'),
        content: Text(
            'Xóa hẳn phiếu ${doc.issueNo}? Thao tác không thể hoàn tác.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Không')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Xóa'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final res = await _api.deletePosStockIssueDoc(_config.kind, doc.id);
    if (!mounted) return;
    if (res['isSuccess'] == true) {
      NotificationOverlayManager()
          .showSuccess(title: 'Đã xóa', message: doc.issueNo);
      _collapseExpanded();
      await _load(page: _page);
    } else {
      NotificationOverlayManager().showError(
          title: 'Lỗi', message: res['message']?.toString() ?? 'Không xóa được');
    }
  }

  Future<void> _voidCompletedIssue(PosStockIssueDoc doc) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(_config.voidDialogTitle),
        content: Text('${_config.voidDialogMessage} ${doc.issueNo}'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Không')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Hủy phiếu'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final res = await _api.cancelPosStockIssueDoc(_config.kind, doc.id);
    if (!mounted) return;
    if (res['isSuccess'] == true) {
      NotificationOverlayManager().showSuccess(
          title: 'Đã hủy', message: 'Đã hoàn tồn kho · ${doc.issueNo}');
      await _load(page: _page);
      await _refreshExpandedDetail(doc.id);
    } else {
      NotificationOverlayManager().showError(
          title: 'Lỗi', message: res['message']?.toString() ?? 'Không hủy được');
    }
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
                title: const Text('Phiếu tạm', style: TextStyle(fontSize: 13)),
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
        purchaseFilterSection(
          'Thời gian',
          PosKiotTimeFilter(state: _timeFilter, onChanged: _onTimeFilterChanged),
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
      return Scaffold(
          body: Center(child: Text('Không có quyền xem ${_config.title}')));
    }
    final canEdit = perm.canEdit(_config.moduleCode);

    return Scaffold(
      backgroundColor: HrmPageChrome.background,
      body: posMobileSafeBody(
        context,
        Column(
        children: [
          PosModuleToolbar(activeModule: _config.activeModule),
          PosMobileListHeader(
            icon: _config.icon,
            title: _config.title,
            onCreate: canEdit ? () => _openEditor() : null,
            createLabel: _config.createButtonLabel,
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
                        hintText: _config.searchHint,
                        prefixIcon: const Icon(Icons.search, size: 20),
                        border: const OutlineInputBorder(),
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
                                child: Text('Chưa có phiếu ${_config.title}'))
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
          const Expanded(flex: 2, child: Text('Mã phiếu', style: h)),
          const Expanded(flex: 2, child: Text('Thời gian', style: h)),
          if (_config.showInternalFields)
            const Expanded(flex: 2, child: Text('Loại xuất', style: h)),
          const Expanded(
              flex: 2,
              child: Text('Tổng SL', style: h, textAlign: TextAlign.right)),
          const Expanded(
              flex: 2,
              child: Text('Tổng giá trị', style: h, textAlign: TextAlign.right)),
          SizedBox(
              width: 110,
              child: Text('Trạng thái', style: h, textAlign: TextAlign.right)),
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
      itemBuilder: (ctx, i) => _buildIssueBlock(_items[i], canEdit),
    );
  }

  Widget _buildIssueBlock(PosStockIssueDoc doc, bool canEdit) {
    final expanded = _expandedId == doc.id;
    final created = doc.issuedAt ?? doc.createdAt;
    if (posUseMobileList(context)) {
      return PosMobileExpandableDocCard(
        expanded: expanded,
        onTap: () => _toggleExpand(doc),
        code: doc.issueNo,
        status: stockIssueStatusChip(doc.status),
        accentColor: _blue,
        fields: [
          PosMobileField(
            'Thời gian',
            created != null ? _dateFmt.format(created.toLocal()) : '—',
          ),
          if (_config.showInternalFields)
            PosMobileField('Loại xuất', doc.categoryName ?? '—'),
          PosMobileField('Tổng SL', _fmtQty(doc.totalQty)),
          PosMobileField(
            'Giá trị',
            '${_moneyFmt.format(doc.totalValue)} đ',
          ),
        ],
        detail: expanded ? _buildDetailPanel(doc, canEdit) : null,
      );
    }
    return Material(
      color: Colors.white,
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: () => _toggleExpand(doc),
            hoverColor: const Color(0xFFF1F5F9),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                      color: expanded
                          ? Colors.grey.shade200
                          : Colors.transparent),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    expanded
                        ? Icons.keyboard_arrow_down
                        : Icons.keyboard_arrow_right,
                    size: 20,
                    color: PosTheme.textSecondary,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    flex: 2,
                    child: Text(doc.issueNo,
                        style: const TextStyle(
                            color: _blue,
                            fontWeight: FontWeight.w600,
                            fontSize: 13)),
                  ),
                  Expanded(
                    flex: 2,
                    child: Text(
                      created != null
                          ? _dateFmt.format(created.toLocal())
                          : '—',
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                  if (_config.showInternalFields)
                    Expanded(
                      flex: 2,
                      child: Text(doc.categoryName ?? '—',
                          style: const TextStyle(fontSize: 13)),
                    ),
                  Expanded(
                    flex: 2,
                    child: Text(_fmtQty(doc.totalQty),
                        style: const TextStyle(fontSize: 13),
                        textAlign: TextAlign.right),
                  ),
                  Expanded(
                    flex: 2,
                    child: Text('${_moneyFmt.format(doc.totalValue)} đ',
                        style: const TextStyle(fontSize: 13),
                        textAlign: TextAlign.right),
                  ),
                  SizedBox(
                    width: 110,
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: stockIssueStatusChip(doc.status),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (expanded) _buildDetailPanel(doc, canEdit),
        ],
      ),
    );
  }

  Widget _buildDetailPanel(PosStockIssueDoc summary, bool canEdit) {
    if (_detailLoading) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    final doc = _expandedDetail ?? summary;

    return Container(
      color: const Color(0xFFF8FAFC),
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Text('Chi tiết phiếu',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              const Spacer(),
              stockIssueStatusChip(doc.status),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 24,
            runSpacing: 6,
            children: [
              _meta('Người tạo', doc.createdBy ?? '—'),
              if (doc.issuedBy != null) _meta('Người xuất', doc.issuedBy!),
              _meta(
                  'Thời gian tạo',
                  doc.createdAt != null
                      ? _dateFmt.format(doc.createdAt!.toLocal())
                      : '—'),
              if (doc.completedAt != null)
                _meta('Ngày hoàn thành',
                    _dateFmt.format(doc.completedAt!.toLocal())),
              if (_config.showInternalFields) ...[
                _meta('Loại xuất', doc.categoryName ?? '—'),
                _meta('Người nhận', doc.recipientName ?? '—'),
              ],
              _meta('Số dòng', '${doc.lines.length}'),
            ],
          ),
          if (doc.note != null && doc.note!.isNotEmpty) ...[
            const SizedBox(height: 8),
            _meta('Ghi chú', doc.note!),
          ],
          const SizedBox(height: 10),
          if (doc.lines.isNotEmpty)
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                headingRowHeight: 36,
                dataRowMinHeight: 32,
                dataRowMaxHeight: 40,
                columnSpacing: 16,
                headingRowColor: WidgetStateProperty.all(Colors.white),
                columns: [
                  const DataColumn(
                      label: Text('Mã hàng',
                          style: TextStyle(
                              fontSize: 12, fontWeight: FontWeight.w600))),
                  const DataColumn(
                      label: Text('Tên hàng',
                          style: TextStyle(
                              fontSize: 12, fontWeight: FontWeight.w600))),
                  DataColumn(
                      label: Text(_config.qtyColumnLabel,
                          style: const TextStyle(
                              fontSize: 12, fontWeight: FontWeight.w600))),
                  const DataColumn(
                      label: Text('Giá vốn',
                          style: TextStyle(
                              fontSize: 12, fontWeight: FontWeight.w600))),
                  const DataColumn(
                      label: Text('Thành tiền',
                          style: TextStyle(
                              fontSize: 12, fontWeight: FontWeight.w600))),
                ],
                rows: doc.lines.map((l) {
                  return DataRow(cells: [
                    DataCell(Text(l.productCode,
                        style: const TextStyle(fontSize: 12))),
                    DataCell(Text(l.productName,
                        style: const TextStyle(fontSize: 12))),
                    DataCell(Text(_fmtQty(l.qty),
                        style: const TextStyle(fontSize: 12))),
                    DataCell(Text('${_moneyFmt.format(l.costPrice)} đ',
                        style: const TextStyle(fontSize: 12))),
                    DataCell(Text('${_moneyFmt.format(l.lineTotal)} đ',
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
                Text('Tổng SL: ${_fmtQty(doc.totalQty)}',
                    style: const TextStyle(fontSize: 12)),
                Text('Tổng giá trị: ${_moneyFmt.format(doc.totalValue)} đ',
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (canEdit && doc.status == 'Draft')
                FilledButton(
                  onPressed: () => _openEditor(issueId: doc.id),
                  style: FilledButton.styleFrom(backgroundColor: _blue),
                  child: const Text('Mở phiếu'),
                ),
              if (canEdit && doc.status == 'Draft')
                OutlinedButton.icon(
                  onPressed: () => _completeIssue(doc),
                  icon: const Icon(Icons.check_circle_outline, size: 16),
                  label: Text(_config.completeActionLabel),
                ),
              if (canEdit)
                OutlinedButton.icon(
                  onPressed: () => _copyIssue(doc),
                  icon: const Icon(Icons.copy, size: 16),
                  label: const Text('Sao chép'),
                ),
              if (canEdit && doc.status == 'Draft')
                OutlinedButton.icon(
                  onPressed: () => _deleteIssue(doc),
                  icon: const Icon(Icons.delete_outline, size: 16),
                  label: const Text('Xóa'),
                ),
              if (canEdit && doc.status == 'Completed')
                OutlinedButton.icon(
                  onPressed: () => _voidCompletedIssue(doc),
                  icon: const Icon(Icons.cancel_outlined, size: 16),
                  label: const Text('Hủy'),
                ),
              if (canEdit && doc.status == 'Cancelled')
                OutlinedButton.icon(
                  onPressed: () => _deleteIssue(doc),
                  icon: const Icon(Icons.delete_outline, size: 16),
                  label: const Text('Xóa'),
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
                text: '$label: ',
                style: const TextStyle(color: PosTheme.textSecondary)),
            TextSpan(text: value),
          ],
        ),
      );
}
